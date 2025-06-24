# Open WebUI on Google Cloud Run: Infrastructure & Deployment Guide

This guide explains how to deploy and operate your personal fork of Open WebUI on Google Cloud Run with a stateful, production-grade configuration. It covers infrastructure, authentication, persistence, and CI/CD best practices, as well as troubleshooting tips.

---

## Table of Contents
- [Overview](#overview)
- [Infrastructure Components](#infrastructure-components)
- [Prerequisites](#prerequisites)
- [Environment Variables](#environment-variables)
- [Deployment Steps](#deployment-steps)
- [API Key Management](#api-key-management)
- [Testing & Validation](#testing--validation)
- [Persistence & Resilience](#persistence--resilience)
- [CI/CD with Cloud Build](#cicd-with-cloud-build)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview
This setup runs Open WebUI as a stateless container on Google Cloud Run, with persistent data (users, API keys, knowledge bases, etc.) stored in Google Cloud SQL (PostgreSQL with pgvector). All secrets are managed via Google Secret Manager. The deployment is automated using `cloudbuild.yaml`.

---

## Infrastructure Components
- **Google Cloud Run**: Hosts the Open WebUI Docker container, auto-scales, and exposes a secure HTTPS endpoint.
- **Google Cloud SQL (PostgreSQL + pgvector)**: Stores user data, API keys, knowledge bases, and embeddings.
- **Google Secret Manager**: Manages sensitive data like DB URLs and secret keys.
- **Artifact Registry**: Stores the Open WebUI Docker image.
- **Google Cloud Build**: Automates build and deployment via `cloudbuild.yaml`.

---

## Prerequisites
- GCP project with billing enabled
- Cloud SQL and Cloud Run APIs enabled
- `gcloud` CLI installed and authenticated
- Docker installed (for local builds)
- Your fork of Open WebUI cloned locally

---

## Environment Variables
Key variables (see `.env.example`):
- `WEBUI_URL`: Public URL of your Cloud Run service
- `OPENWEBUI_API_KEY`: User-specific API key (generated from the deployed UI)
- `DATABASE_URL`: PostgreSQL Cloud SQL connection string (secret)
- `WEBUI_SECRET_KEY`: Flask/Django secret key (secret)
- `VECTOR_DB`: Set to `pgvector`

Secrets are set via Cloud Secret Manager and injected at deploy time.

---

## Deployment Steps
1. **Build and Push Docker Image**
   - Use `cloudbuild.yaml` or your own build pipeline to build and push the Docker image to Artifact Registry.

2. **Provision Cloud SQL**
   - Create a PostgreSQL instance with the `pgvector` extension enabled (see `enable_pgvector.sh`).

3. **Store Secrets**
   - Store `DATABASE_URL` and `WEBUI_SECRET_KEY` in Secret Manager.

4. **Deploy to Cloud Run**
   - Use `startup.sh` or the following command:
     ```bash
     gcloud run deploy open-webui \
       --project=<your-project> \
       --image=us-central1-docker.pkg.dev/<your-project>/<repo>/open-webui:main \
       --platform=managed \
       --region=us-central1 \
       --port=8080 \
       --allow-unauthenticated \
       --add-cloudsql-instances=<YOUR_INSTANCE_CONNECTION_NAME> \
       --set-secrets=WEBUI_SECRET_KEY=webui-secret-key:latest,DATABASE_URL=openwebui-database-url:latest \
       --set-env-vars="VECTOR_DB=pgvector" \
       --min-instances=0 \
       --max-instances=1 \
       --timeout=300s \
       --memory=4Gi
     ```

5. **First-Time Setup**
   - Visit the deployed UI, create your admin user, and generate an API key from **Settings → Account → API Keys**.

---

## API Key Management
- **Do NOT use example keys from `.env.example` for production.**
- Always generate your API key from the deployed UI after creating your admin user.
- Store your API key securely (never commit to source control).

---

## Testing & Validation
- Use `test_suite.sh` to validate:
  - API connectivity and authentication (`/api/models`)
  - Knowledge base creation and document upload
  - Persistence across Cloud Run restarts
- See `specs/gcloud-test.md` and `specs/fix1.txt` for troubleshooting and improved test logic.

---

## Persistence & Resilience
- All user and knowledge base data is stored in Cloud SQL, so it persists across Cloud Run restarts and redeployments.
- API keys are tied to users in the database and remain valid until revoked.

---

## CI/CD with Cloud Build
- The `cloudbuild.yaml` automates Docker builds and deployment to Cloud Run.
- Integrate with GitHub Actions or other CI providers as needed.

---

## Troubleshooting
- **API returns HTML instead of JSON:**
  - Check that you are using a valid, user-generated API key.
  - Ensure you are calling the correct endpoint (`/api/models`).
  - Confirm that Cloud SQL is provisioned and secrets are set correctly.
- **Test suite failures:**
  - See error messages for details. Most issues are due to endpoint typos, missing/invalid API keys, or missing database migrations/extensions.
- **Cloud Run deployment issues:**
  - Check the Cloud Run and Cloud Build logs in the GCP Console.

---

## References
- [Open WebUI API Docs](https://docs.openwebui.com/getting-started/api-endpoints/)
- [Open WebUI GitHub](https://github.com/open-webui/open-webui)
- [Google Cloud Run Docs](https://cloud.google.com/run/docs)
- [Google Cloud SQL Docs](https://cloud.google.com/sql/docs)
- [Cloud Build Docs](https://cloud.google.com/build/docs)
- [pgvector for PostgreSQL](https://github.com/pgvector/pgvector)

---

For questions or improvements, open an issue or PR on your fork!
