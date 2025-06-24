#!/bin/bash
# deploy_stateful.sh
# Automate a production-ready, persistent Open WebUI deployment on Google Cloud Run with Cloud SQL for PostgreSQL
# See: specs/gcloud2.md

set -euo pipefail

# --- CONFIGURATION VARIABLES (per spec) ---
PROJECT_ID="aqgprag"  # Set your GCP project ID
REGION="us-central1"
SQL_INSTANCE_NAME="open-webui-postgres-db"
DB_NAME="openwebui"
DB_USER="postgres"
DB_PASSWORD=$(openssl rand -base64 16)
WEBUI_SECRET_KEY_VALUE=$(openssl rand -base64 32)
# Adjust image as needed
CONTAINER_IMAGE="us-central1-docker.pkg.dev/${PROJECT_ID}/openwebui-docker/open-webui:main"
CLOUD_RUN_SERVICE="open-webui"

# --- 1. Enable Required APIs ---
gcloud services enable run.googleapis.com \
                       sqladmin.googleapis.com \
                       secretmanager.googleapis.com \
                       iam.googleapis.com \
                       --project=${PROJECT_ID}

echo "[INFO] Required APIs enabled."

# --- 2. Provision Cloud SQL for PostgreSQL Instance (with pgvector) ---
gcloud sql instances create ${SQL_INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --database-version=POSTGRES_15 \
  --region=${REGION} \
  --tier=db-g1-small \
  --root-password=${DB_PASSWORD} \
  --database-flags=cloudsql.extensions.pgvector=on

echo "[INFO] Cloud SQL instance created."

gcloud sql databases create ${DB_NAME} \
  --instance=${SQL_INSTANCE_NAME} \
  --project=${PROJECT_ID}

echo "[INFO] Dedicated database created."

# --- 3. Store Secrets in Secret Manager ---
# 3.1 WEBUI_SECRET_KEY for JWT signing
 echo -n "${WEBUI_SECRET_KEY_VALUE}" | gcloud secrets create webui-secret-key \
   --project=${PROJECT_ID} \
   --replication-policy="automatic" \
   --data-file=-

# 3.2 Construct and store DATABASE_URL
INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe ${SQL_INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --format='value(connectionName)')
DATABASE_URL="postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@/${DB_NAME}?host=/cloudsql/${INSTANCE_CONNECTION_NAME}"
echo -n "${DATABASE_URL}" | gcloud secrets create openwebui-database-url \
  --project=${PROJECT_ID} \
  --replication-policy="automatic" \
  --data-file=-

echo "[INFO] Secrets created in Secret Manager."

# --- 4. Grant Cloud Run Service Account Access to Secrets ---
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
gcloud secrets add-iam-policy-binding webui-secret-key \
  --project=${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding openwebui-database-url \
  --project=${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"
# (Optional) If you use openai-api-key secret, grant access as well
# gcloud secrets add-iam-policy-binding openai-api-key \
#   --project=${PROJECT_ID} \
#   --member="serviceAccount:${SERVICE_ACCOUNT}" \
#   --role="roles/secretmanager.secretAccessor"
echo "[INFO] Service account granted secret access."

# --- 5. Deploy Open WebUI to Cloud Run (per spec) ---
gcloud run deploy ${CLOUD_RUN_SERVICE} \
  --project=${PROJECT_ID} \
  --image=${CONTAINER_IMAGE} \
  --platform=managed \
  --region=${REGION} \
  --port=8080 \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=1 \
  --timeout=300s \
  --memory=4Gi \
  --add-cloudsql-instances="${INSTANCE_CONNECTION_NAME}" \
  --set-env-vars="VECTOR_DB=pgvector" \
  --set-secrets=WEBUI_SECRET_KEY=webui-secret-key:latest,DATABASE_URL=openwebui-database-url:latest

echo "[SUCCESS] Deployment complete. Verify service and test connectivity."
