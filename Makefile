# Makefile for Crossplane + kind bootstrap convenience

.PHONY: help bootstrap dry-run recreate skip-cluster tools-check

SCRIPT := scripts/bootstrap-crossplane-kind.sh

# Override any of these at call time, e.g.:
# make bootstrap CROSSPLANE_VERSION=v1.20.1 CLUSTER_NAME=my-kind
CROSSPLANE_VERSION ?= v1.20.1
PROVIDER_AZURE_VERSION ?= v1.13.0
FUNC_PAT_VERSION ?= v0.9.0
FUNC_ENVCFG_VERSION ?= v0.4.0
CLUSTER_NAME ?= crossplane-kind
KINDEST_NODE_IMAGE ?= kindest/node:v1.29.4
WAIT_TIMEOUT ?= 10m

help:
	@echo "Targets:"
	@echo "  make bootstrap        - Bootstrap Crossplane onto kind (idempotent)"
	@echo "  make dry-run          - Show planned actions without executing"
	@echo "  make recreate         - Recreate the kind cluster then bootstrap"
	@echo "  make skip-cluster     - Use current kube context; install Crossplane only"
	@echo "  make tools-check      - Check required tools exist (no installs)"
	@echo ""
	@echo "Variables (override as needed):"
	@echo "  CROSSPLANE_VERSION, PROVIDER_AZURE_VERSION"
	@echo "  FUNC_PAT_VERSION, FUNC_ENVCFG_VERSION, CLUSTER_NAME"
	@echo "  KINDEST_NODE_IMAGE, WAIT_TIMEOUT"
	@echo ""
	@echo "Examples:"
	@echo "  make bootstrap CLUSTER_NAME=my-kind"
	@echo "  make recreate KINDEST_NODE_IMAGE=kindest/node:v1.29.4"
	@echo "  make dry-run CROSSPLANE_VERSION=v1.20.1"

bootstrap:
	@bash $(SCRIPT) \
	  --crossplane-version $(CROSSPLANE_VERSION) \
	  --provider-azure-version $(PROVIDER_AZURE_VERSION) \
	  --func-pat-version $(FUNC_PAT_VERSION) \
	  --func-envcfg-version $(FUNC_ENVCFG_VERSION) \
	  --wait-timeout $(WAIT_TIMEOUT) \
	  --kind-node-image $(KINDEST_NODE_IMAGE) \
	  --cluster-name $(CLUSTER_NAME)

dry-run:
	@bash $(SCRIPT) --dry-run \
	  --crossplane-version $(CROSSPLANE_VERSION) \
	  --provider-azure-version $(PROVIDER_AZURE_VERSION) \
	  --func-pat-version $(FUNC_PAT_VERSION) \
	  --func-envcfg-version $(FUNC_ENVCFG_VERSION) \
	  --wait-timeout $(WAIT_TIMEOUT) \
	  --kind-node-image $(KINDEST_NODE_IMAGE) \
	  --cluster-name $(CLUSTER_NAME)

recreate:
	@bash $(SCRIPT) -y --recreate \
	  --crossplane-version $(CROSSPLANE_VERSION) \
	  --provider-azure-version $(PROVIDER_AZURE_VERSION) \
	  --func-pat-version $(FUNC_PAT_VERSION) \
	  --func-envcfg-version $(FUNC_ENVCFG_VERSION) \
	  --wait-timeout $(WAIT_TIMEOUT) \
	  --kind-node-image $(KINDEST_NODE_IMAGE) \
	  --cluster-name $(CLUSTER_NAME)

skip-cluster:
	@bash $(SCRIPT) --skip-cluster \
	  --crossplane-version $(CROSSPLANE_VERSION) \
	  --provider-azure-version $(PROVIDER_AZURE_VERSION) \
	  --func-pat-version $(FUNC_PAT_VERSION) \
	  --func-envcfg-version $(FUNC_ENVCFG_VERSION) \
	  --wait-timeout $(WAIT_TIMEOUT)

tools-check:
	@bash -c 'command -v kind >/dev/null || { echo "missing: kind"; exit 127; }'
	@bash -c 'command -v kubectl >/dev/null || { echo "missing: kubectl"; exit 127; }'
	@bash -c 'command -v helm >/dev/null || { echo "missing: helm"; exit 127; }'
	@echo "All required tools present."

