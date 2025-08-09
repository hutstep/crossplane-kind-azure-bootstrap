# Crossplane Kind Scaffold

This repository provides a simple scaffold to work locally with a kind (Kubernetes-in-Docker) cluster for experimenting with Crossplane and GitOps-friendly workflows.

## Prerequisites
- Docker (for kind)
- kind v0.20+ (or latest)
- kubectl v1.28+
- Helm v3.12+
- Optional: Flux CLI (if you plan to bootstrap Flux locally)
- Optional: Crossplane CLI (cx) or rely on Helm for installation

## Usage
- Create local directories used by this repo:
  - scripts/
  - .tmp/ (ephemeral; ignored by git)

Typical flow:
1) Create a local kind cluster
   - A script will be provided under scripts/ to create a cluster using a config in .tmp/ when applicable.
2) Install Crossplane into the cluster (e.g., via Helm)
3) Install providers and compositions as needed
4) When done, delete the kind cluster

You can place your own scripts under scripts/ and keep any generated files (e.g., kind config, kubeconfig copies) under .tmp/.

Note: Ensure all scripts in scripts/ are executable so you can run them directly (chmod +x scripts/*).

## Usage examples
- Non-interactive default install:
  ```
  scripts/bootstrap-crossplane-kind.sh --yes
  ```
- Recreate cluster and override versions:
  ```
  scripts/bootstrap-crossplane-kind.sh --yes --recreate \
    --cluster-name xp-dev --kind-node-image kindest/node:v1.29.4 \
    --crossplane-version v1.20.1 \
    --provider-azure-version v1.13.0 \
    --func-pat-version v0.9.0 \
    --func-envcfg-version v0.4.0
  ```
- Use existing context without creating cluster:
  ```
  scripts/bootstrap-crossplane-kind.sh --yes --skip-cluster
  ```

## CI notes
- Ensure Docker-in-Docker or Docker is available on the runner (kind requires Docker).
- Cache Helm repository data if possible to speed up runs (e.g., cache $HOME/.cache/helm and optionally $HOME/.config/helm/repositories.yaml between jobs).
