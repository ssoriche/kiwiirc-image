#!/bin/bash

# Setup script for KiwiIRC Docker repository with GitHub CLI
set -e

REPO_NAME="kiwiirc-image"
USERNAME="ssoriche"

echo "Creating GitHub repository: $USERNAME/$REPO_NAME"

# Create GitHub repository
gh repo create "$USERNAME/$REPO_NAME" \
  --public \
  --description "Dockerized KiwiIRC server using distroless base image with automated updates" \
  --clone

# Change to repository directory
cd "$REPO_NAME"

echo "Setting up KiwiIRC Docker repository..."

# Create directory structure
mkdir -p .github/workflows
mkdir -p .github/dependabot

# Create Dockerfile with version pinning
cat > Dockerfile << 'EOF'
# Build stage
FROM node:18-alpine AS builder

WORKDIR /app

# Clone specific KiwiIRC version
ARG KIWIIRC_VERSION=master
RUN apk add --no-cache git
RUN git clone --depth 1 --branch ${KIWIIRC_VERSION} https://github.com/kiwiirc/kiwiirc.git .

# Install dependencies and build
RUN npm ci
RUN npm run build

# Production stage
FROM gcr.io/distroless/nodejs18-debian11:nonroot

WORKDIR /app

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules

EXPOSE 80

USER nonroot:nonroot

CMD ["dist/server.js"]
EOF

# Create version tracking file
cat > kiwiirc-version.txt << 'EOF'
master
EOF

# Create GitHub Actions workflow with KiwiIRC update check
cat > .github/workflows/docker-build.yaml << 'EOF'
name: Build and Push Docker Image

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 2 * * 1'  # Weekly rebuild

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Get KiwiIRC version
      id: kiwiirc-version
      run: echo "version=$(cat kiwiirc-version.txt)" >> $GITHUB_OUTPUT

    - name: Log in to Container Registry
      uses: docker/login-action@v3
      with:
        registry: ${{ env.REGISTRY }}
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - name: Extract metadata
      id: meta
      uses: docker/metadata-action@v5
      with:
        images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
        tags: |
          type=ref,event=branch
          type=ref,event=pr
          type=sha,prefix={{branch}}-
          type=raw,value=latest,enable={{is_default_branch}}

    - name: Set up Docker Buildx
      uses: docker/setup-buildx-action@v3

    - name: Build and push Docker image
      uses: docker/build-push-action@v5
      with:
        context: .
        push: true
        tags: ${{ steps.meta.outputs.tags }}
        labels: ${{ steps.meta.outputs.labels }}
        cache-from: type=gha
        cache-to: type=gha,mode=max
        platforms: linux/amd64,linux/arm64
        build-args: |
          KIWIIRC_VERSION=${{ steps.kiwiirc-version.outputs.version }}
EOF

# Create KiwiIRC update check workflow
cat > .github/workflows/kiwiirc-update-check.yaml << 'EOF'
name: Check KiwiIRC Updates

on:
  schedule:
    - cron: '0 6 * * *'  # Daily at 6 AM
  workflow_dispatch:

jobs:
  check-updates:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write

    steps:
    - name: Checkout repository
      uses: actions/checkout@v4

    - name: Get current KiwiIRC version
      id: current
      run: echo "version=$(cat kiwiirc-version.txt)" >> $GITHUB_OUTPUT

    - name: Get latest KiwiIRC version
      id: latest
      run: |
        LATEST=$(curl -s https://api.github.com/repos/kiwiirc/kiwiirc/releases/latest | jq -r '.tag_name // "master"')
        echo "version=$LATEST" >> $GITHUB_OUTPUT

    - name: Check if update needed
      id: check
      run: |
        if [ "${{ steps.current.outputs.version }}" != "${{ steps.latest.outputs.version }}" ]; then
          echo "update_needed=true" >> $GITHUB_OUTPUT
        else
          echo "update_needed=false" >> $GITHUB_OUTPUT
        fi

    - name: Create Pull Request
      if: steps.check.outputs.update_needed == 'true'
      uses: peter-evans/create-pull-request@v5
      with:
        token: ${{ secrets.GITHUB_TOKEN }}
        commit-message: "chore: update KiwiIRC to ${{ steps.latest.outputs.version }}"
        title: "Update KiwiIRC to ${{ steps.latest.outputs.version }}"
        body: |
          This PR updates KiwiIRC from `${{ steps.current.outputs.version }}` to `${{ steps.latest.outputs.version }}`.

          **Changes:**
          - Updated kiwiirc-version.txt

          **Release Notes:**
          See: https://github.com/kiwiirc/kiwiirc/releases/tag/${{ steps.latest.outputs.version }}
        branch: update-kiwiirc-${{ steps.latest.outputs.version }}
        delete-branch: true
        base: main
        labels: |
          dependencies
          kiwiirc
        reviewers: |
          ${{ github.actor }}

    - name: Update version file
      if: steps.check.outputs.update_needed == 'true'
      run: |
        echo "${{ steps.latest.outputs.version }}" > kiwiirc-version.txt
        git config --local user.email "action@github.com"
        git config --local user.name "GitHub Action"
        git add kiwiirc-version.txt
        git diff --staged --quiet || git commit -m "chore: update KiwiIRC to ${{ steps.latest.outputs.version }}"
EOF

# Create enhanced Dependabot configuration
cat > .github/dependabot.yaml << 'EOF'
version: 2
updates:
  # Docker dependencies
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "02:00"
    open-pull-requests-limit: 5
    reviewers:
      - "ssoriche"
    commit-message:
      prefix: "docker"
      include: "scope"
    labels:
      - "dependencies"
      - "docker"

  # GitHub Actions dependencies
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "monday"
      time: "02:00"
    open-pull-requests-limit: 5
    reviewers:
      - "ssoriche"
    commit-message:
      prefix: "ci"
      include: "scope"
    labels:
      - "dependencies"
      - "github-actions"
EOF

# Create .gitignore
cat > .gitignore << 'EOF'
# Node modules
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Docker
.dockerignore

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Logs
logs/
*.log
EOF

# Create README
cat > README.md << 'EOF'
# KiwiIRC Docker Image

Dockerized KiwiIRC server using distroless base image with automated updates.

## Features

- 🔒 Distroless base image for enhanced security
- 🏗️ Multi-architecture support (amd64, arm64)
- 🤖 Automated builds via GitHub Actions
- 🔄 Automated KiwiIRC version updates
- 📦 Dependabot for dependency updates
- 🐙 GHCR.io registry integration

## Usage

```bash
# Run the latest image
docker run -p 80:80 ghcr.io/ssoriche/kiwiirc-image:latest

# With custom configuration
docker run -p 80:80 -v /path/to/config:/app/config ghcr.io/ssoriche/kiwiirc-image:latest
