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
