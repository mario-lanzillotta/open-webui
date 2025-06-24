#!/bin/bash
# Deploy Open WebUI to Cloud Run using the image in Artifact Registry

INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe open-webui-postgres-db --project=aqgprag --format='value(connectionName)')
gcloud run deploy open-webui \
  --project=aqgprag \
  --image=us-central1-docker.pkg.dev/aqgprag/openwebui-docker/open-webui:main \
  --platform=managed \
  --region=us-central1 \
  --port=8080 \
  --allow-unauthenticated \
  --add-cloudsql-instances="$INSTANCE_CONNECTION_NAME" \
  --set-secrets=WEBUI_SECRET_KEY=webui-secret-key:latest,DATABASE_URL=openwebui-database-url:latest \
  --set-env-vars="VECTOR_DB=pgvector" \
  --min-instances=0 \
  --max-instances=1 \
  --timeout=300s \
  --memory=4Gi
