Excellent. Let's create a comprehensive test suite to validate your new stateful infrastructure and address your questions about API key management and programmatic knowledge base uploads.

### When to Create a New `OPENWEBUI_API_KEY`?

The `OPENWEBUI_API_KEY` you're using in your script is a **user-specific API key**. It's not a global system key. You generate it from within the Open WebUI interface after you've logged in.

Here's the workflow:
1.  **First-time Setup:** After the initial deployment, you visit the UI, create your admin user account, and log in.
2.  **Generate Your Key:** Go to **Settings -> Account**, click the "API Keys" tab, and generate a new key.
3.  **Store and Use the Key:** Copy this generated key (`sk-...`) and store it securely (e.g., in Google Secret Manager or your local environment variables). This is the key your Python client or test scripts will use to authenticate as *your user*.

You only need to create a new key if:
*   The current key is compromised.
*   You want to create a different key for a different service (e.g., one for testing, one for production).
*   You want to revoke access for a service that was using an old key.

Because the user data is now stored in Cloud SQL, **this key will be persistent across restarts.** You do not need to generate a new one every time.

### Automating Knowledge Base (KB) Document Uploads

Yes, you can absolutely upload documents to a Knowledge Base programmatically via the API. You do not need to do it manually through the UI.

The process involves two main API calls:
1.  **Create the Knowledge Base:** A `POST` request to `/api/v1/knowledge/create` to create an empty KB.
2.  **Upload a File:** A `POST` request to `/api/v1/files/` to upload your document.
3.  **Add the File to the KB:** A `POST` request to `/api/v1/knowledge/{id}/file/add` to associate the uploaded file with your KB.

I've included this workflow in the test suite below.

---

### **Test Suite for Open WebUI Stateful Infrastructure**

This test suite is designed to be run from a shell environment where `gcloud` and `curl` are installed and configured. It validates the persistence of users, API keys, and knowledge bases.

**Prerequisites:**
1.  The Open WebUI service is deployed on Cloud Run.
2.  You have the URL of your service.
3.  You have generated a user-specific API key from the UI and set it as an environment variable:
    ```bash
    export OPENWEBUI_API_KEY="sk-your-generated-key"
    export WEBUI_URL="https://your-cloud-run-service-url.run.app"
    ```

---

#### **`test_suite.sh`**

```bash
#!/bin/bash

# ==============================================================================
# Open WebUI Stateful Infrastructure Test Suite
# ==============================================================================
# This script validates the persistence of data across service restarts in a
# stateful Open WebUI deployment on Google Cloud Run with Cloud SQL.
#
# Prerequisites:
#   - gcloud CLI installed and authenticated.
#   - curl and jq installed.
#   - Environment variables set:
#     - OPENWEBUI_API_KEY: A user-generated API key from the Open WebUI interface.
#     - WEBUI_URL: The full URL of your deployed Open WebUI service.
# ==============================================================================

# --- Configuration ---
if [[ -z "$OPENWEBUI_API_KEY" || -z "$WEBUI_URL" ]]; then
    echo "Error: Please set both OPENWEBUI_API_KEY and WEBUI_URL environment variables."
    exit 1
fi

AUTH_HEADER="Authorization: Bearer $OPENWEBUI_API_KEY"
CONTENT_TYPE_HEADER="Content-Type: application/json"

# --- Helper Functions ---
function run_test {
    test_name=$1
    command=$2
    echo -e "\n--- Running Test: $test_name ---"
    eval $command
    if [ $? -eq 0 ]; then
        echo "✅ PASSED: $test_name"
    else
        echo "❌ FAILED: $test_name"
        exit 1
    fi
}

function check_status {
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" "$1")
    if [ "$response_code" -ne 200 ]; then
        echo "Error: API call failed with status code $response_code for URL $1"
        curl -s "$1" # Print error response
        return 1
    fi
    return 0
}

# --- Test Cases ---

# Test 1: Basic API Connectivity and Authentication
test_api_connectivity() {
    echo "Pinging the /api/v1/models endpoint to verify API key and connectivity..."
    response=$(curl -s -H "$AUTH_HEADER" "${WEBUI_URL}/api/v1/models")
    check_status "${WEBUI_URL}/api/v1/models"
    # Check if the response contains the expected 'data' key which is a list
    if ! echo "$response" | jq -e '.data | type == "array"' > /dev/null; then
        echo "Error: /api/v1/models response is not a valid JSON array."
        echo "Response: $response"
        return 1
    fi
    echo "API is responsive and authentication is successful."
}

# Test 2: Programmatically Create a Knowledge Base
test_create_kb() {
    echo "Attempting to create a new knowledge base named 'test-kb'..."
    KB_NAME="persistent-test-kb-$(date +%s)"
    
    # Check if KB with this name already exists and delete it to ensure a clean test
    existing_kbs=$(curl -s -H "$AUTH_HEADER" "${WEBUI_URL}/api/v1/knowledge")
    existing_id=$(echo "$existing_kbs" | jq -r ".[] | select(.name==\"$KB_NAME\") | .id")
    if [ ! -z "$existing_id" ]; then
        echo "Warning: KB '$KB_NAME' already exists. Deleting it before test."
        curl -s -X DELETE -H "$AUTH_HEADER" "${WEBUI_URL}/api/v1/knowledge/${existing_id}/delete"
    fi

    # Create the new KB
    response=$(curl -s -X POST -H "$AUTH_HEADER" -H "$CONTENT_TYPE_HEADER" \
      -d "{\"name\": \"$KB_NAME\", \"description\": \"A KB for persistence testing.\"}" \
      "${WEBUI_URL}/api/v1/knowledge/create")
    
    KB_ID=$(echo "$response" | jq -r '.id')
    if [ -z "$KB_ID" ] || [ "$KB_ID" == "null" ]; then
        echo "Error: Failed to create knowledge base."
        echo "Response: $response"
        return 1
    fi
    echo "Knowledge Base created with ID: $KB_ID"
    export KB_ID  # Export for subsequent tests
}

# Test 3: Programmatically Upload a Document and Add to Knowledge Base
test_upload_and_add_doc() {
    if [ -z "$KB_ID" ]; then echo "KB_ID not set. Skipping test."; return 1; fi
    
    echo "Uploading a test document..."
    # Create a dummy text file for upload
    echo "This is a test document for Open WebUI persistence testing." > testdoc.txt

    # 1. Upload the file
    upload_response=$(curl -s -X POST -H "$AUTH_HEADER" -F "file=@testdoc.txt" "${WEBUI_URL}/api/v1/files/")
    FILE_ID=$(echo "$upload_response" | jq -r '.id')
    if [ -z "$FILE_ID" ] || [ "$FILE_ID" == "null" ]; then
        echo "Error: Failed to upload file."
        echo "Response: $upload_response"
        rm testdoc.txt
        return 1
    fi
    echo "Document uploaded with File ID: $FILE_ID"

    # 2. Add the file to the knowledge base
    echo "Adding file to knowledge base..."
    add_response=$(curl -s -X POST -H "$AUTH_HEADER" -H "$CONTENT_TYPE_HEADER" \
      -d "{\"file_id\": \"$FILE_ID\"}" \
      "${WEBUI_URL}/api/v1/knowledge/${KB_ID}/file/add")

    # Verify the file is now associated with the KB
    files_in_kb=$(echo "$add_response" | jq -r '.files[].id')
    if [[ ! "$files_in_kb" == *"$FILE_ID"* ]]; then
        echo "Error: File was not successfully added to the knowledge base."
        echo "Response: $add_response"
        rm testdoc.txt
        return 1
    fi
    echo "Document successfully added to knowledge base."
    rm testdoc.txt
}

# Test 4: Restart the Cloud Run Service to Test Persistence
test_restart_service() {
    echo "Restarting the Cloud Run service... (This may take a minute)"
    # A simple way to trigger a restart is to deploy a new revision with an updated label
    REVISION_LABEL="last-restarted-$(date +%s)"
    gcloud run services update open-webui \
      --project=${PROJECT_ID:-aqgprag} \
      --region=us-central1 \
      --update-labels="restarted=$REVISION_LABEL" \
      --quiet
      
    echo "Waiting for the new revision to become active..."
    sleep 60 # Give it time to restart and stabilize
}

# Test 5: Verify Knowledge Base Persistence
test_verify_kb_persistence() {
    if [ -z "$KB_ID" ]; then echo "KB_ID not set. Skipping test."; return 1; fi

    echo "Verifying that the knowledge base '$KB_NAME' still exists after restart..."
    response=$(curl -s -H "$AUTH_HEADER" "${WEBUI_URL}/api/v1/knowledge/${KB_ID}")
    
    retrieved_id=$(echo "$response" | jq -r '.id')
    if [ "$retrieved_id" != "$KB_ID" ]; then
        echo "Error: Knowledge base with ID $KB_ID not found after restart."
        echo "Response: $response"
        return 1
    fi
    echo "Knowledge base persistence confirmed."
}

# Test 6: Verify Document Persistence within the Knowledge Base
test_verify_doc_persistence() {
    if [ -z "$KB_ID" ]; then echo "KB_ID not set. Skipping test."; return 1; fi

    echo "Verifying that the document still exists in the knowledge base..."
    response=$(curl -s -H "$AUTH_HEADER" "${WEBUI_URL}/api/v1/knowledge/${KB_ID}")
    
    file_count=$(echo "$response" | jq -r '.files | length')
    if [ "$file_count" -ne 1 ]; then
        echo "Error: Document count in knowledge base is not 1 after restart."
        echo "Response: $response"
        return 1
    fi
    echo "Document persistence within the knowledge base confirmed."
}


# --- Execution Flow ---
run_test "API Connectivity & Auth" "test_api_connectivity"
run_test "Create Knowledge Base" "test_create_kb"
run_test "Upload and Add Document" "test_upload_and_add_doc"
run_test "Restart Cloud Run Service" "test_restart_service"
run_test "Verify Knowledge Base Persistence" "test_verify_kb_persistence"
run_test "Verify Document Persistence" "test_verify_doc_persistence"

echo -e "\n🎉 All tests passed successfully! Your stateful infrastructure is working correctly."

```

#### **How to Run the Test Suite:**

1.  **Save the script** to a file named `test_suite.sh`.
2.  **Make it executable:** `chmod +x test_suite.sh`.
3.  **Set your environment variables:**
    ```bash
    export OPENWEBUI_API_KEY="sk-..."  # Your key from the UI
    export WEBUI_URL="https://..."   # Your Cloud Run service URL
    ```
4.  **Run the script:** `./test_suite.sh`

This test suite provides a robust validation of your entire stateful setup, from basic API access to the core persistence logic of your knowledge bases, giving you high confidence in your infrastructure.
