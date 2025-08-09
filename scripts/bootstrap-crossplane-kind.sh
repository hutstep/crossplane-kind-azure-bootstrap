#!/usr/bin/env bash
# scripts/bootstrap-crossplane-kind.sh
# Purpose: Bootstrap a local Crossplane environment on a kind cluster with robust, idempotent, non-interactive friendly CLI.
# Behavior: Detects required tools only (does not install). Uses idempotent helm upgrade --install and kubectl apply.
# Exits non-zero on any error; prints actionable diagnostics. Supports dry-run.

set -Eeuo pipefail
IFS=$'\n\t'

# ------------------------------
# Defaults (override with flags)
# ------------------------------
CROSSPLANE_VERSION="v1.20.1"
PROVIDER_AZURE_VERSION="v1.13.0"
FUNC_PAT_VERSION="v0.9.0"
FUNC_ENVCFG_VERSION="v0.4.0"
CLUSTER_NAME="crossplane-kind"
KINDEST_NODE_IMAGE="kindest/node:v1.33.1"
WAIT_TIMEOUT="10m"

YES=false
VERBOSE=false
DRY_RUN=false
RECREATE=false
SKIP_CLUSTER=false
CLEANUP=false
DELETE_CLUSTER=false
FORCE_CLEAN=false

SCRIPT_NAME="$(basename "$0")"

# ------------------------------
# Logging and helpers
# ------------------------------
log() { echo "[INFO ] $*"; }
warn() { echo "[WARN ] $*" 2>&1; }
err() { echo "[ERROR] $*" 2>&1; }
die() { err "$*"; exit 1; }

if [[ ${VERBOSE} == true ]]; then set -x; fi

# Trap for diagnostics: print error line and try to show pods for quick context
trap 'echo "[ERROR] at line $LINENO"; kubectl get pods -A || true' ERR

# Wait for Crossplane packages (Provider/Function) to report Healthy condition.
# Falls back to a JSONPath poll if kubectl wait is flaky. Honors WAIT_TIMEOUT and DRY_RUN.
wait_pkg_healthy() {
  local kind="$1" name="$2" timeout="${3:-$WAIT_TIMEOUT}"
  if DRY_RUN; then
    log "[dry-run] would wait for $kind/$name to become Healthy (timeout ${timeout})"
    return 0
  fi
  local end=$((SECONDS + ${timeout%m}*60))
  while (( SECONDS < end )); do
    if kubectl get "$kind" "$name" -o jsonpath='{.status.conditions[?(@.type=="Healthy")].status}' 2>/dev/null | grep -q True; then
      return 0
    fi
    sleep 3
  done
  kubectl get "$kind" "$name" -o yaml || true
  return 1
}

usage() {
  cat <<EOF
${SCRIPT_NAME} - Bootstrap Crossplane on a local kind cluster

Usage:
  ${SCRIPT_NAME} [flags]

Flags:
  -y, --yes                         Assume yes to prompts (non-interactive)
  -n, --cluster-name NAME           kind cluster name (default: ${CLUSTER_NAME})
  -k, --kind-node-image IMAGE       kindest node image (default: ${KINDEST_NODE_IMAGE})
      --crossplane-version VERSION  Crossplane version (default: ${CROSSPLANE_VERSION})
      --provider-azure-version VER  Provider family Azure version (default: ${PROVIDER_AZURE_VERSION})
      --func-pat-version VERSION    Crossplane function-patch-and-transform version (default: ${FUNC_PAT_VERSION})
      --func-envcfg-version VERSION Crossplane function-environment-configs version (default: ${FUNC_ENVCFG_VERSION})
      --recreate                    Delete existing kind cluster with the same name before creating
      --skip-cluster                Skip cluster creation and use current kubectl context
      --wait-timeout DURATION       Wait timeout for rollouts, e.g. 10m (default: ${WAIT_TIMEOUT})
      --cleanup                     Cleanup Crossplane, providers, and functions from the cluster
      --delete-cluster              When used with --cleanup, also delete the kind cluster named ${CLUSTER_NAME}
      --force-clean                 Also remove Crossplane Function package CRDs (functions/functionrevisions) if leftovers persist
  -v, --verbose                     Enable bash tracing (set -x)
      --dry-run                     Print planned actions without executing
  -h, --help                        Show this help

Examples:
  # Basic run with defaults
  ${SCRIPT_NAME}

  # Custom cluster and Crossplane version
  ${SCRIPT_NAME} -n demo --crossplane-version v1.20.1

  # Dry-run preview
  DRY_RUN=true ${SCRIPT_NAME}
  ${SCRIPT_NAME} --dry-run -n demo

  # Recreate cluster and wait longer
  ${SCRIPT_NAME} --recreate --wait-timeout 15m

  # Cleanup Crossplane resources (keep cluster)
  ${SCRIPT_NAME} --cleanup

  # Cleanup and delete the kind cluster
  ${SCRIPT_NAME} --cleanup --delete-cluster

Behavior:
  - Detects required tools; does not install them.
  - Idempotent operations via 'helm upgrade --install' and 'kubectl apply'.
  - Exits non-zero on any error and prints actionable diagnostics.
EOF
}

confirm() {
  local prompt_msg="$1"
  if [[ ${YES} == true ]]; then
    log "Auto-confirmed: ${prompt_msg}"
    return 0
  fi
  read -r -p "${prompt_msg} [y/N]: " ans || true
  case "${ans}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

require_cmd() {
  local cmd="$1"; shift || true
  local hint="$*"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    err "Missing required tool: ${cmd}"
    if [[ -n "${hint}" ]]; then warn "Hint: ${hint}"; fi
    case "${cmd}" in
      kind)
        warn "Install kind: https://kind.sigs.k8s.io/docs/user/quick-start/"
        ;;
      kubectl)
        warn "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
        ;;
      helm)
        warn "Install Helm: https://helm.sh/docs/intro/install/"
        ;;
    esac
    exit 127
  fi
}

# DRY_RUN predicate and command runner (portable)
DRY_RUN() { [ "${DRY_RUN}" = "true" ]; }
run() {
  if DRY_RUN; then
    echo "+ $*"
  else
    "$@"
  fi
}

print_settings() {
  cat <<EOF
Settings:
  CLUSTER_NAME=${CLUSTER_NAME}
  KINDEST_NODE_IMAGE=${KINDEST_NODE_IMAGE}
  CROSSPLANE_VERSION=${CROSSPLANE_VERSION}
  PROVIDER_AZURE_VERSION=${PROVIDER_AZURE_VERSION}
  FUNC_PAT_VERSION=${FUNC_PAT_VERSION}
  FUNC_ENVCFG_VERSION=${FUNC_ENVCFG_VERSION}
  WAIT_TIMEOUT=${WAIT_TIMEOUT}
  RECREATE=${RECREATE}
  SKIP_CLUSTER=${SKIP_CLUSTER}
  CLEANUP=${CLEANUP}
  DELETE_CLUSTER=${DELETE_CLUSTER}
  FORCE_CLEAN=${FORCE_CLEAN}
  DRY_RUN=${DRY_RUN}
  VERBOSE=${VERBOSE}
EOF
}

# ------------------------------
# Parse arguments
# ------------------------------
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -y|--yes) YES=true; shift ;;
      -n|--cluster-name) CLUSTER_NAME="$2"; shift 2 ;;
      -k|--kind-node-image) KINDEST_NODE_IMAGE="$2"; shift 2 ;;
      --crossplane-version) CROSSPLANE_VERSION="$2"; shift 2 ;;
      --provider-azure-version) PROVIDER_AZURE_VERSION="$2"; shift 2 ;;
      --func-pat-version) FUNC_PAT_VERSION="$2"; shift 2 ;;
      --func-envcfg-version) FUNC_ENVCFG_VERSION="$2"; shift 2 ;;
      --wait-timeout) WAIT_TIMEOUT="$2"; shift 2 ;;
      --recreate) RECREATE=true; shift ;;
      --skip-cluster) SKIP_CLUSTER=true; shift ;;
      --cleanup) CLEANUP=true; shift ;;
      --delete-cluster) DELETE_CLUSTER=true; shift ;;
      --force-clean) FORCE_CLEAN=true; shift ;;
      -v|--verbose) VERBOSE=true; set -x; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; break ;;
      -*) err "Unknown flag: $1"; usage; exit 2 ;;
      *) err "Unexpected arg: $1"; usage; exit 2 ;;
    esac
  done
}

# ------------------------------
# Validations
# ------------------------------
validate_inputs() {
  [[ -n "${CLUSTER_NAME}" ]] || die "--cluster-name cannot be empty"
  [[ -n "${KINDEST_NODE_IMAGE}" ]] || die "--kind-node-image cannot be empty"
  [[ -n "${CROSSPLANE_VERSION}" ]] || die "--crossplane-version cannot be empty"
  [[ -n "${WAIT_TIMEOUT}" ]] || die "--wait-timeout cannot be empty"
}

check_tools() {
  # Only detect; never install
  require_cmd kind
  require_cmd kubectl
  require_cmd helm
}

# ------------------------------
# Cluster operations (idempotent)
# ------------------------------
cluster_exists() {
  kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}" || return 1
}

ensure_cluster() {
  if [[ ${SKIP_CLUSTER} == true ]]; then
    log "Skipping cluster creation. Using current kubectl context."
    return 0
  fi

  if cluster_exists; then
    if [[ ${RECREATE} == true ]]; then
      confirm "Delete existing kind cluster '${CLUSTER_NAME}'?" || die "Aborted by user."
      log "Deleting existing kind cluster '${CLUSTER_NAME}'"
      run kind delete cluster --name "${CLUSTER_NAME}"
    else
      log "kind cluster '${CLUSTER_NAME}' already exists; reusing."
      return 0
    fi
  fi

  log "Creating kind cluster '${CLUSTER_NAME}' with image '${KINDEST_NODE_IMAGE}'"
  run kind create cluster \
    --name "${CLUSTER_NAME}" \
    --image "${KINDEST_NODE_IMAGE}"
}

# ------------------------------
# Crossplane install (idempotent)
# ------------------------------
install_crossplane() {
  log "Adding/Updating crossplane helm repo"
  run helm repo add crossplane-stable https://charts.crossplane.io/stable >/dev/null 2>&1 || true
  run helm repo update >/dev/null 2>&1 || true

  log "Installing/Upgrading Crossplane ${CROSSPLANE_VERSION}"
  run helm upgrade --install crossplane crossplane-stable/crossplane \
    --namespace crossplane-system \
    --create-namespace \
    --version "${CROSSPLANE_VERSION}"

  log "Waiting for Crossplane rollout (timeout ${WAIT_TIMEOUT})"
  run kubectl -n crossplane-system rollout status deploy/crossplane --timeout "${WAIT_TIMEOUT}"
  run kubectl -n crossplane-system rollout status deploy/crossplane-rbac-manager --timeout "${WAIT_TIMEOUT}" || true
}

# ------------------------------
# Providers and Functions (idempotent)
# ------------------------------
apply_providers_and_functions()
{
  # Provider family - Azure
  log "Applying Provider family Azure ${PROVIDER_AZURE_VERSION}"
  run kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-family-azure
spec:
  package: xpkg.crossplane.io/crossplane-contrib/provider-family-azure:${PROVIDER_AZURE_VERSION}
EOF
  log "Waiting for Provider provider-family-azure to become Healthy (timeout ${WAIT_TIMEOUT})"
  wait_pkg_healthy provider.pkg.crossplane.io provider-family-azure "${WAIT_TIMEOUT}"

  # Crossplane Functions
  log "Applying Function: function-patch-and-transform ${FUNC_PAT_VERSION}"
  run kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-patch-and-transform
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-patch-and-transform:${FUNC_PAT_VERSION}
EOF
  log "Waiting for Function function-patch-and-transform to become Healthy (timeout ${WAIT_TIMEOUT})"
  wait_pkg_healthy function.pkg.crossplane.io function-patch-and-transform "${WAIT_TIMEOUT}"

  log "Applying Function: function-environment-configs ${FUNC_ENVCFG_VERSION}"
  run kubectl apply -f - <<EOF
apiVersion: pkg.crossplane.io/v1beta1
kind: Function
metadata:
  name: function-environment-configs
spec:
  package: xpkg.upbound.io/crossplane-contrib/function-environment-configs:${FUNC_ENVCFG_VERSION}
EOF
  log "Waiting for Function function-environment-configs to become Healthy (timeout ${WAIT_TIMEOUT})"
  wait_pkg_healthy function.pkg.crossplane.io function-environment-configs "${WAIT_TIMEOUT}"
}

# ------------------------------
# Cleanup mode
# ------------------------------
cleanup_resources() {
  # Attempt to remove FunctionRevisions to ensure no controllers keep Deployments alive
  log "Deleting FunctionRevisions (clear finalizers if needed)"
  local frs
  frs=$(kubectl get functionrevisions.pkg.crossplane.io -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -n "${frs}" ]]; then
    while read -r fr; do
      [[ -z "$fr" ]] && continue
      run kubectl patch functionrevision.pkg.crossplane.io "$fr" --type=merge -p '{"metadata":{"finalizers":[]}}' || true
      run kubectl delete functionrevision.pkg.crossplane.io "$fr" --wait=false || true
    done <<<"$frs"
  fi
  log "Deleting Crossplane Providers (ignore not found)"
  # Use the names we created during apply for accuracy
  run kubectl delete provider.pkg.crossplane.io provider-family-azure --ignore-not-found

  log "Deleting Crossplane Functions (ignore not found)"
  run kubectl delete function.pkg.crossplane.io function-patch-and-transform function-environment-configs --ignore-not-found

  # Best-effort cleanup of lingering Deployments/Pods created by packages (in case CRs were already removed)
  log "Best-effort cleanup of lingering function/provider deployments in crossplane-system"
  # Try label-based cleanup first
  run kubectl -n crossplane-system delete deploy -l pkg.crossplane.io/revision --ignore-not-found || true
  # Fallback: prefix-based cleanup; loop until nothing remains (max 60s)
  local end=$((SECONDS + 60))
  while (( SECONDS < end )); do
    local dels=0
    local dlist
    dlist=$(kubectl -n crossplane-system get deploy -o name 2>/dev/null | grep -E "^deployment/(function-|provider-family-azure)" || true)
    if [[ -n "$dlist" ]]; then
      run kubectl -n crossplane-system delete $dlist --ignore-not-found || true
      dels=1
    fi
    local plist
    plist=$(kubectl -n crossplane-system get pods -o name 2>/dev/null | grep -E "^pod/(function-|provider-family-azure)" || true)
    if [[ -n "$plist" ]]; then
      run kubectl -n crossplane-system delete $plist --ignore-not-found || true
      dels=1
    fi
    if [[ $dels -eq 0 ]]; then
      break
    fi
    sleep 2
  done

  log "Uninstalling Crossplane Helm release (ignore errors)"
  run helm uninstall crossplane -n crossplane-system || true

  # As a last resort, optionally remove Function CRDs to prevent any lingering reconciliation
  if [[ ${FORCE_CLEAN} == true ]]; then
    log "Force clean requested: deleting Function package CRDs"
    run kubectl delete crd functions.pkg.crossplane.io functionrevisions.pkg.crossplane.io --ignore-not-found || true
  fi

  if [[ ${DELETE_CLUSTER} == true ]]; then
    if confirm "Delete kind cluster '${CLUSTER_NAME}'?"; then
      log "Deleting kind cluster '${CLUSTER_NAME}'"
      run kind delete cluster --name "${CLUSTER_NAME}"
    else
      log "Cluster deletion skipped by user"
    fi
  else
    log "Cluster deletion not requested; keeping kind cluster '${CLUSTER_NAME}'"
  fi
}

main() {
  parse_args "$@"
  validate_inputs
  print_settings

  check_tools

  if [[ ${CLEANUP} == true ]]; then
    cleanup_resources
    log "Cleanup complete."
    exit 0
  fi

  ensure_cluster
  install_crossplane
  apply_providers_and_functions

  log "Bootstrap complete."
}

main "$@"

