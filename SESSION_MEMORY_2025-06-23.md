# Open WebUI Session Memory — 2025-06-23

## Summary
This session focused on connecting to and testing the Open WebUI API deployed on Google Cloud Run, as well as preparing for log tailing and documenting the process.

---

## Key Actions & Outcomes

### 1. Log Tailing Request
- Initial request: create a script to tail logs from the Open WebUI container.
- Discovery: `startup.sh` deploys to Google Cloud Run, not a local Docker container.
- Next step (pending): create a script to tail logs from the Cloud Run service using `gcloud`.

### 2. API Key & Testing
- Generated a new API key from the Open WebUI web interface and exported it as `OPENWEBUI_API_KEY`.
- Tested the API using `curl`:
    - Used the endpoint: `https://open-webui-1044214148467.us-central1.run.app/api/chat/completions`
    - Added the correct `Authorization` header.
    - Discovered the API requires a `model` parameter and a `messages` array (OpenAI-compatible format), not a `prompt` field.
    - Corrected the payload and successfully received a response from the model `gpt-4-0613`.

### 3. Saved Working Test Script
- Created `test_openwebui_api.sh`:
    - Sends a test chat completion request to the deployed Open WebUI instance.
    - Uses the exported `OPENWEBUI_API_KEY` for authentication.
    - Script is executable and ready for reuse.

---

## Example Working `curl` Command
```sh
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
```

---

## Next Steps
- (Optional) Script log tailing for the Cloud Run service: `gcloud logs tail service open-webui ...`
- Further automate or document API testing as needed.

---

*Session timestamp: 2025-06-23, local time: 17:00+2*
