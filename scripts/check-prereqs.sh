#!/usr/bin/env bash
set -euo pipefail

# check-prereqs.sh
# Performs prerequisite checks for local kind-based Kubernetes workflows.
# - Does not install anything
# - Exits non-zero on hard failures; prints warnings for soft checks
#
# Usage:
#   bash scripts/check-prereqs.sh [--skip-cluster]
#
# Flags:
#   --skip-cluster  Do not create a cluster; instead verify the current context is reachable
#                   and is a kind cluster.

SKIP_CLUSTER=false
if [[ ${1:-} == "--skip-cluster" ]]; then
  SKIP_CLUSTER=true
fi

# Colors (fall back to no color if not a TTY)
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

info()  { printf "%b[INFO]%b %s\n"   "$BLUE"  "$NC" "$*"; }
success(){ printf "%b[OK]%b   %s\n"   "$GREEN" "$NC" "$*"; }
warn()  { printf "%b[WARN]%b %s\n"  "$YELLOW" "$NC" "$*"; }
err()   { printf "%b[ERROR]%b %s\n" "$RED"   "$NC" "$*"; }

need_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    err "Missing required command: $name"
    return 1
  fi
}

# Compare two semver versions: returns 0 if v1 >= v2, else 1
ver_ge() {
  # normalizes like 1.2 to 1.2.0
  local v1="$1" v2="$2"
  local IFS=.
  read -r -a a1 <<<"${v1#v}"
  read -r -a a2 <<<"${v2#v}"
  for i in 0 1 2; do
    a1[$i]="${a1[$i]:-0}"
    a2[$i]="${a2[$i]:-0}"
    if ((10#${a1[$i]} > 10#${a2[$i]})); then return 0; fi
    if ((10#${a1[$i]} < 10#${a2[$i]})); then return 1; fi
  done
  return 0
}

# Extract numeric semver from typical CLI version outputs
extract_kind_version() {
  # kind version output: kind v0.20.0
  kind version 2>/dev/null | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

extract_kubectl_version() {
  # Try multiple formats across kubectl versions
  local v
  # 1) YAML (very stable across versions)
  v=$(kubectl version --client --output=yaml 2>/dev/null | awk -F': ' '/gitVersion:/{print $2; exit}' | sed -E 's/^v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/') || true
  # 2) jsonpath
  if [[ -z "$v" ]]; then
    v=$(kubectl version --client -o jsonpath='{.clientVersion.gitVersion}' 2>/dev/null | sed -E 's/^v?([0-9]+\.[0-9]+\.[0-9]+).*$/\1/') || true
  fi
  # 3) --short format: Client Version: v1.29.4
  if [[ -z "$v" ]]; then
    v=$(kubectl version --client --short 2>/dev/null | sed -E 's/.*v([0-9]+\.[0-9]+\.[0-9]+).*/\1/') || true
  fi
  # 4) JSON output
  if [[ -z "$v" ]]; then
    v=$(kubectl version --client -o json 2>/dev/null | sed -nE 's/.*\"gitVersion\"\s*:\s*\"v?([0-9]+\.[0-9]+\.[0-9]+).*\".*/\1/p') || true
  fi
  printf "%s" "$v"
}

extract_helm_version() {
  # helm version --short -> v3.14.4+g... ; trim metadata
  helm version --short 2>/dev/null | sed -E 's/^v?([0-9]+\.[0-9]+\.[0-9]+).*/\1/'
}

check_required_commands() {
  info "Checking required commands..."
  local missing=0
  for cmd in docker kind kubectl helm; do
    if need_cmd "$cmd"; then
      success "$cmd is installed ($(command -v "$cmd"))"
    else
      missing=1
    fi
  done
  if (( missing )); then
    err "Install the missing command(s) and re-run. Required: docker, kind, kubectl, helm"
    return 1
  fi

  # Optional envsubst
  if command -v envsubst >/dev/null 2>&1; then
    success "envsubst is available"
  else
    warn "envsubst not found; scripts will fall back to printf where applicable"
  fi
}

check_versions() {
  info "Validating CLI versions..."

  local kind_v kubectl_v helm_v
  kind_v=$(extract_kind_version || true)
  kubectl_v=$(extract_kubectl_version || true)
  helm_v=$(extract_helm_version || true)

  if [[ -z "$kind_v" ]]; then err "Unable to determine kind version"; return 1; fi
  if [[ -z "$kubectl_v" ]]; then err "Unable to determine kubectl version"; return 1; fi
  if [[ -z "$helm_v" ]]; then err "Unable to determine helm version"; return 1; fi

  local want_kind=0.20.0 want_kubectl=1.25.0 want_helm=3.11.0

  if ver_ge "$kind_v" "$want_kind"; then
    success "kind $kind_v (>= $want_kind)"
  else
    err "kind $kind_v is too old; please upgrade to >= $want_kind"
    return 1
  fi

  if ver_ge "$kubectl_v" "$want_kubectl"; then
    success "kubectl $kubectl_v (>= $want_kubectl)"
  else
    err "kubectl $kubectl_v is too old; please upgrade to >= $want_kubectl"
    return 1
  fi

  if ver_ge "$helm_v" "$want_helm"; then
    success "helm $helm_v (>= $want_helm)"
  else
    err "helm $helm_v is too old; please upgrade to >= $want_helm"
    return 1
  fi
}

check_docker_daemon() {
  info "Checking Docker daemon health..."
  if docker info >/dev/null 2>&1; then
    success "Docker daemon is running"
  else
    err "Unable to communicate with Docker daemon. Ensure Docker Desktop (macOS/Windows) or the Docker service (Linux) is running, then re-run."
    return 1
  fi
}

_httph() {
  # Perform a HEAD/GET with curl or wget. Non-fatal; returns 0/1
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSIL --max-time 10 "$url" >/dev/null 2>&1
    return $?
  elif command -v wget >/dev/null 2>&1; then
    wget --spider -q --timeout=10 "$url" >/dev/null 2>&1
    return $?
  else
    return 2
  fi
}

check_network() {
  info "Checking network reachability (best-effort)..."
  local urls=(
    "https://charts.crossplane.io/stable/index.yaml"
    "https://xpkg.crossplane.io/"
  )
  local any_tool=0
  for u in "${urls[@]}"; do
    if _httph "$u"; then
      success "Reachable: $u"
      any_tool=1
    else
      if [[ $? -eq 2 ]]; then
        warn "Neither curl nor wget found; skipping network checks for $u"
      else
        warn "Could not reach $u. If you are in an air-gapped environment, you may need to pre-download artifacts or configure proxies."
        any_tool=1
      fi
    fi
  done
  if (( any_tool == 0 )); then
    warn "Network checks skipped due to missing curl/wget."
  fi
}

is_kind_context_by_name() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || true)
  [[ "$ctx" =~ ^kind- ]]
}

is_kind_cluster_via_nodes() {
  # Try a few heuristics that are typical for kind clusters
  # - Node names often contain 'kind-' and '-control-plane'
  # - ProviderID may start with 'kind://'
  # - Annotations/labels include keys with 'kind.x-k8s.io'
  local nodes_json
  nodes_json=$(kubectl get nodes -o json 2>/dev/null || true)
  [[ -z "$nodes_json" ]] && return 1
  echo "$nodes_json" | grep -q '"kind.x-k8s.io' && return 0
  echo "$nodes_json" | grep -q '"providerID"\s*:\s*"kind://' && return 0
  echo "$nodes_json" | grep -q '"name"\s*:\s*"kind-.*control-plane"' && return 0
  return 1
}

check_skip_cluster_target() {
  info "--skip-cluster set: validating current Kubernetes context..."
  if ! kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
    err "Current Kubernetes context is not reachable. Ensure your kubeconfig is valid and the cluster is online."
    return 1
  fi
  if is_kind_context_by_name || is_kind_cluster_via_nodes; then
    success "Detected kind cluster in current context"
  else
    err "The current context does not appear to be a kind cluster. Please switch to a kind-* context or use a kind cluster."
    return 1
  fi
}

main() {
  check_required_commands
  check_versions
  check_docker_daemon
  check_network
  if $SKIP_CLUSTER; then
    check_skip_cluster_target
  fi
  success "All prerequisite checks passed."
}

main "$@"

