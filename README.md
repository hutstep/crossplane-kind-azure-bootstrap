# crossplane-kind-azure-bootstrap

Bootstrap a local [kind](https://kind.sigs.k8s.io/) cluster with [Crossplane](https://crossplane.io/), the Crossplane provider family for Azure, and selected Composition Functions. Designed to be robust, idempotent, and non-interactive friendly for both local use and CI.

## Features
- Creates or reuses a kind cluster (or targets current kubectl context)
- Installs Crossplane via Helm chart (chart version controllable)
- Installs provider family for Azure (provider-family-azure)
- Installs Crossplane Composition Functions:
  - function-patch-and-transform
  - function-environment-configs
- Reliable health waits with JSONPath fallback
- Cleanup modes (keep cluster, delete cluster, and force-clean leftovers)
- Makefile with common targets

## Prerequisites
- Docker (required by kind)
- kind ≥ 0.20.0
- kubectl ≥ 1.25
- Helm ≥ 3.11
- Network access to:
  - https://charts.crossplane.io/stable/index.yaml
  - https://xpkg.crossplane.io/

Tip: Ensure all scripts in scripts/ are executable so you can run them directly (chmod +x scripts/*).

## Quick start
- Non-interactive default install (creates kind cluster if missing):
  ```bash
  scripts/bootstrap-crossplane-kind.sh --yes
  ```
- Use existing context (no cluster creation):
  ```bash
  scripts/bootstrap-crossplane-kind.sh --yes --skip-cluster
  ```
- Recreate cluster and override versions:
  ```bash
  scripts/bootstrap-crossplane-kind.sh --yes --recreate \
    --cluster-name xp-dev --kind-node-image kindest/node:v1.29.4 \
    --crossplane-version v1.20.1 \
    --provider-azure-version v1.13.0 \
    --func-pat-version v0.9.0 \
    --func-envcfg-version v0.4.0
  ```

## Makefile targets
- Bootstrap (idempotent):
  ```bash
  make bootstrap
  ```
- Dry-run (print planned actions):
  ```bash
  make dry-run
  ```
- Recreate cluster then bootstrap:
  ```bash
  make recreate
  ```
- Use current context (no cluster creation):
  ```bash
  make skip-cluster
  ```
- Tools check (versions, network reachability):
  ```bash
  make tools-check
  ```
- Cleanup providers/functions/Helm release (keep cluster):
  ```bash
  make clean
  ```
- Cleanup plus remove Function package CRDs (keeps cluster):
  ```bash
  make clean-force
  ```
- Cleanup and delete kind cluster:
  ```bash
  make clean-delete-cluster
  ```

## Script flags (most-used)
- --yes                       Non-interactive assume-yes
- --cluster-name NAME         Kind cluster name (default: crossplane-kind)
- --kind-node-image IMAGE     Node image (default: kindest/node:v1.29.4 or newer)
- --crossplane-version VER    Crossplane Helm chart version (e.g., v1.20.1)
- --provider-azure-version V  provider-family-azure version (e.g., v1.13.0)
- --func-pat-version V        function-patch-and-transform version (e.g., v0.9.0)
- --func-envcfg-version V     function-environment-configs version (e.g., v0.4.0)
- --skip-cluster              Target current kubectl context; do not create kind
- --recreate                  Delete existing kind cluster with the same name first
- --wait-timeout DURATION     e.g., 10m
- --cleanup                   Remove providers/functions and Crossplane Helm release
- --delete-cluster            With --cleanup, delete the kind cluster too
- --force-clean               With --cleanup, also remove Function package CRDs
- --dry-run                   Print planned actions only
- --verbose                   Shell tracing (set -x)

## What gets installed
- Crossplane Helm chart from charts.crossplane.io (chart version you choose)
- Provider family Azure package:
  - xpkg.crossplane.io/crossplane-contrib/provider-family-azure:v1.13.0
- Composition Functions:
  - xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.9.0
  - xpkg.crossplane.io/crossplane-contrib/function-environment-configs:v0.4.0

## Verify installation
```bash
helm list -n crossplane-system
kubectl get providers.pkg.crossplane.io -o wide
kubectl get functions.pkg.crossplane.io -o wide
kubectl get pods -A
```

## Cleanup
- Keep cluster, remove providers/functions and Crossplane Helm release:
  ```bash
  scripts/bootstrap-crossplane-kind.sh --cleanup
  ```
- If function pods linger or are recreated by FunctionRevisions, use force-clean:
  ```bash
  scripts/bootstrap-crossplane-kind.sh --cleanup --force-clean
  ```
- Delete cluster too:
  ```bash
  scripts/bootstrap-crossplane-kind.sh --cleanup --delete-cluster --yes
  ```

## CI notes
- Ensure Docker-in-Docker or Docker is available on the runner (kind requires Docker).
- Cache Helm repository data to speed up runs:
  - $HOME/.cache/helm
  - optionally $HOME/.config/helm/repositories.yaml

## License
This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.
