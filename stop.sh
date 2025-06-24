#!/bin/bash
# Delete the Open WebUI Cloud Run service

gcloud run services delete open-webui \
  --project=aqgprag \
  --region=us-central1 \
  --platform=managed \
  --quiet
