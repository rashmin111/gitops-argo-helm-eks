# app-source (GitOps demo app)

Simple FastAPI app. CI builds a docker image, pushes it to ECR, updates the GitOps config repo (app-config) with the new tag.

## Setup
- Create ECR repository and add `ECR_REPOSITORY` secret in GitHub (full repo URL).
- Create Personal Access Token `GH_APP_CONFIG_TOKEN` with permission to push to `app-config`.
- Optional: configure GitHub Actions OIDC and set `AWS_ROLE_TO_ASSUME`.

## Local run
pip install -r app/requirements.txt
uvicorn app.main:app --reload --port 8000


## CI
Push to `main` triggers:
- tests
- build/push image
- update `app-config/overlays/dev/patch-image.yaml` and push
- open PR to prod overlay (requires human approval)


### CI/CD Pipeline
- On push to main:
  - Test
  - Build image
  - Push to ECR
  - Update app-config/environments/dev/values-dev.yaml
  - Create PR for GitOps repo
