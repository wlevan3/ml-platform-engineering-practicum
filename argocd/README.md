# ArgoCD Directory

This directory contains the ArgoCD configuration for the ML Platform.

## Overview

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. The configuration is managed in this directory and applied to the cluster.

## Directory Structure

- `projects/`: Contains ArgoCD AppProject definitions.
- `applications/`: Contains ArgoCD Application definitions.

## GitOps Workflow

1.  Changes are made to the Kubernetes manifests in the `clusters/` directory.
2.  Changes are pushed to the Git repository.
3.  ArgoCD detects the changes and automatically syncs the applications.

## Managing Applications

- **Syncing:** ArgoCD will automatically sync the applications when changes are detected in the Git repository.
- **Manual Sync:** To manually sync an application, use the ArgoCD UI or CLI.
- **Rollback:** To roll back to a previous version, use the ArgoCD UI or CLI.

## Troubleshooting

- **Sync Failures:** Check the ArgoCD UI for sync errors and logs.
- **Pod Errors:** Use `kubectl` to check the status of pods in the `ml-platform-dev` namespace.
