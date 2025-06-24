#!/bin/bash

# Test Open WebUI API using your current OPENWEBUI_API_KEY environment variable
# Usage: export OPENWEBUI_API_KEY=sk-xxxx; ./test_openwebui_api.sh

curl -X POST 'https://open-webui-1044214148467.us-central1.run.app/api/chat/completions' \
  -H "Authorization: Bearer $OPENWEBUI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4-0613",
    "messages": [
      {"role": "user", "content": "Write a piece of text here."}
    ],
    "temperature": 0.6
  }'
