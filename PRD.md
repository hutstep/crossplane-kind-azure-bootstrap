# Crossplane kind scaffold script

A bash script should be created which will scaffold a local kind cluster with latest version of Crossplane and provider-upjet-azure family provider installed.

# Requirements

## General

- follow best practices for the bash script
- all tools that are needed like crossplane cli, helm, etc. are installed. So check first and don't install any tools without asking.

## kind cluster

- create a kind cluster with `kind create cluster`
- if there is already a kind cluster, ask if it should be deleted. if yes, delete the cluster with `kind delete cluster`. Then proceed with creating a new one

## Crossplane

- follow this guide for Crossplane installation: https://docs.crossplane.io/v1.20/getting-started/provider-azure/
  - install crossplane 1.20.1
  - instead of the azure network provider install, install this provider: xpkg.crossplane.io/crossplane-contrib/provider-family-azure:v1.13.0
  - stop after the provider install
- use crossplane cli for installation of providers and functions: https://docs.crossplane.io/latest/cli/command-reference/
- install these crossplane functions:
  - xpkg.crossplane.io/crossplane-contrib/function-environment-configs:v0.4.0
  - xpkg.crossplane.io/crossplane-contrib/function-patch-and-transform:v0.9.0
- all versions have a default value but can also be set
