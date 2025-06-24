#!/bin/bash

INSTANCE_NAME="open-webui-postgres-db"
PROJECT_ID="aqgprag"
DB_USER="postgres"
DB_NAME="openwebui"
DB_PASSWORD="${OPENWEBUI_DB_PWD}"

# Get the public IP of the instance
INSTANCE_IP=$(gcloud sql instances describe $INSTANCE_NAME --project=$PROJECT_ID --format="value(ipAddresses[0].ipAddress)")

if [ -z "$INSTANCE_IP" ]; then
  echo "[ERROR] Could not retrieve instance IP. Is the instance running and does it have a public IP?"
  exit 1
fi

# Attempt to connect and enable pgvector
PGPASSWORD="$DB_PASSWORD" psql "host=$INSTANCE_IP port=5432 dbname=$DB_NAME user=$DB_USER sslmode=disable" -c "CREATE EXTENSION IF NOT EXISTS vector;"
