#!/bin/bash
set -e

echo "------------------------------------------"
echo "Generating app-source and app-config repos"
echo "------------------------------------------"

mkdir -p app-source/app
mkdir -p app-source/tests
mkdir -p app-source/.github/workflows

mkdir -p app-config/base
mkdir -p app-config/overlays/dev
mkdir -p app-config/overlays/prod
mkdir -p app-config/argocd

#############################################
# app-source
#############################################

cat > app-source/app/main.py << 'EOF'
from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/")
def root():
    return {"message": os.getenv("WELCOME_MSG", "Hello from GitOps FastAPI!")}

@app.get("/health")
def health():
    return {"status": "ok"}
EOF

cat > app-source/app/requirements.txt << 'EOF'
fastapi==0.95.2
uvicorn==0.22.0
requests==2.31.0
pytest==7.4.2
EOF

cat > app-source/tests/test_main.py << 'EOF'
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_root():
    res = client.get("/")
    assert res.status_code == 200
    assert "message" in res.json()

def test_health():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}
EOF

cat > app-source/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app /app
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

#############################################
# GHCR + DockerHub + ECR workflow
#############################################
cat > app-source/.github/workflows/build-and-promote.yml << 'EOF'
name: Build, Test, Push & Promote (multi-registry)

on:
  push:
    branches: ["main"]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v4
        with: { python-version: "3.11" }
      - run: pip install -r app/requirements.txt pytest
      - run: pytest -q

  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # ---------- Build image ----------
      - name: Build docker image
        run: |
          docker build -t app:${GITHUB_SHA} .

      # ---------- GitHub Container Registry ----------
      - name: GHCR Login
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - run: |
          docker tag app:${GITHUB_SHA} ghcr.io/${{ github.repository }}/app:${GITHUB_SHA}
          docker push ghcr.io/${{ github.repository }}/app:${GITHUB_SHA}

      # ---------- Docker Hub ----------
      - name: DockerHub Login
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DH_USER }}
          password: ${{ secrets.DH_PASS }}

      - run: |
          docker tag app:${GITHUB_SHA} ${{ secrets.DH_USER }}/gitops-app:${GITHUB_SHA}
          docker push ${{ secrets.DH_USER }}/gitops-app:${GITHUB_SHA}

      # ---------- Amazon ECR ----------
      - name: Configure AWS
        if: secrets.AWS_ROLE_TO_ASSUME != ''
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login to ECR
        if: secrets.ECR_REPO != ''
        uses: aws-actions/amazon-ecr-login@v1

      - run: |
          if [ "${{ secrets.ECR_REPO }}" != "" ]; then
            docker tag app:${GITHUB_SHA} ${{ secrets.ECR_REPO }}:${GITHUB_SHA}
            docker push ${{ secrets.ECR_REPO }}:${GITHUB_SHA}
          fi

      - name: Set output
        id: out
        run: echo "IMAGE_TAG=${GITHUB_SHA}" >> $GITHUB_OUTPUT

  promote:
    needs: [build]
    runs-on: ubuntu-latest
    steps:
      - name: Checkout config repo
        uses: actions/checkout@v4
        with:
          repository: ${{ github.repository_owner }}/app-config
          token: ${{ secrets.GH_APP_CONFIG_TOKEN }}
          path: config

      - run: |
          cd config/overlays/dev
          sed -i "s|REPLACE_TAG|${GITHUB_SHA}|g" patch-image.yaml || true

          git config user.email "actions@github.com"
          git config user.name "GitHub Actions"
          git add .
          git commit -m "ci: promote image ${GITHUB_SHA} to dev"
          git push
EOF

#############################################
# README
#############################################
cat > app-source/README.md << 'EOF'
# app-source  
FastAPI application with CI/CD → ECR / DockerHub / GHCR → GitOps promotion → ArgoCD deploy.

EOF


#############################################
# app-config
#############################################

cat > app-config/base/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-fastapi
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gitops-fastapi
  template:
    metadata:
      labels:
        app: gitops-fastapi
    spec:
      containers:
        - name: app
          image: REPLACE_IMAGE
          ports:
            - containerPort: 8000
EOF

cat > app-config/base/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: gitops-fastapi
spec:
  selector:
    app: gitops-fastapi
  ports:
    - port: 80
      targetPort: 8000
EOF

cat > app-config/base/kustomization.yaml << 'EOF'
resources:
  - deployment.yaml
  - service.yaml
EOF

cat > app-config/overlays/dev/patch-image.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-fastapi
spec:
  template:
    spec:
      containers:
        - name: app
          image: "REPLACE_IMAGE:REPLACE_TAG"
EOF

cat > app-config/overlays/dev/kustomization.yaml << 'EOF'
resources:
  - ../../base
patchesStrategicMerge:
  - patch-image.yaml
EOF

cat > app-config/overlays/prod/patch-image.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gitops-fastapi
spec:
  replicas: 4
  template:
    spec:
      containers:
        - name: app
          image: "REPLACE_IMAGE:REPLACE_TAG"
EOF

cat > app-config/overlays/prod/kustomization.yaml << 'EOF'
resources:
  - ../../base
patchesStrategicMerge:
  - patch-image.yaml
EOF

#############################################
# ArgoCD project + app manifests
#############################################

cat > app-config/argocd/project.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gitops
spec:
  sourceRepos:
    - "*"
  destinations:
    - namespace: "*"
      server: "https://kubernetes.default.svc"
EOF

cat > app-config/argocd/app-dev.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-fastapi-dev
spec:
  project: gitops
  source:
    repoURL: https://github.com/YOUR_ORG/app-config
    path: overlays/dev
    targetRevision: main
  destination:
    namespace: dev
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      selfHeal: true
      prune: true
EOF

cat > app-config/argocd/app-prod.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-fastapi-prod
spec:
  project: gitops
  source:
    repoURL: https://github.com/YOUR_ORG/app-config
    path: overlays/prod
    targetRevision: main
  destination:
    namespace: prod
    server: https://kubernetes.default.svc
  syncPolicy: {}
EOF

#############################################
# ArgoCD Image Updater config
#############################################

mkdir -p app-config/argocd-image-updater

cat > app-config/argocd-image-updater/config.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  registries.conf: |
    registries:
      - name: dockerhub
        api_url: https://registry-1.docker.io
        prefix: docker.io
        default: true
      - name: ghcr
        api_url: https://ghcr.io
        prefix: ghcr.io
      - name: ecr
        api_url: https://aws.amazon.com
EOF

echo "DONE! Repos generated locally:"
echo "  - app-source/"
echo "  - app-config/"

