# app-config (GitOps manifest repo)

This repo contains Kustomize base + overlays and ArgoCD Application manifests.

### How to use:
- Dev overlay is updated automatically by CI (app-source). ArgoCD auto-syncs dev.
- Prod overlay changes should go through PR review (CI creates a PR). After merge, ArgoCD syncs prod (manual or automated by policy).

### Placeholders to replace:
- REPLACE_ME_ECR_REPO -> e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/devops-fastapi
- REPLACE_TAG -> the image tag, CI replaces this with commit SHA
- Update argocd/project.yaml repo URL to your org


## Quick setup checklist (copy into your notes)

Create two GitHub repos: your-org/app-source and your-org/app-config. Push each repo with the corresponding files above.

### In app-source repo secrets:

- ECR_REPOSITORY = full ECR repo URL (create ECR repo first)
- GH_APP_CONFIG_TOKEN = PAT that can write to app-config (or configure repo permissions so GITHUB_TOKEN can push)
- AWS_ROLE_TO_ASSUME (optional) for OIDC-based ECR push; or provide AWS creds if not using OIDC.
- YOUR_AWS_REGION if you left placeholders.
- Create ECR repo and allow CI role to push.
- Install ArgoCD on your Kubernetes cluster (EKS, k3d, minikube). Expose UI and login.
- Apply ArgoCD project.yaml, app-dev.yaml, app-prod.yaml from app-config/argocd/.
- Push a change to app-source/main and observe:
- CI runs tests, builds and pushes image to ECR
- CI updates app-config/overlays/dev/patch-image.yaml with new tag and pushes
- ArgoCD detects change and auto-syncs dev namespace (if configured)
When ready, review the PR created for prod and merge to promote.

## Helpful commands

### ArgoCD UI port-forward:

- kubectl -n argocd port-forward svc/argocd-server 8080:443
open https://localhost:8080
- Check ArgoCD apps:
- kubectl -n argocd get applications

### Force sync in ArgoCD CLI:

- argocd app sync gitops-fastapi-dev
