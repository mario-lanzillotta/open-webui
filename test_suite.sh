#!/bin/bash

# ======================================================================
# Open WebUI Stateful Infrastructure Test Suite
# ======================================================================
# This script validates the persistence of data across service restarts in a
# stateful Open WebUI deployment on Google Cloud Run with Cloud SQL.
#
# Prerequisites:
#   - gcloud CLI installed and authenticated.
#   - curl and jq installed.
#   - Environment variables set:
#     - OPENWEBUI_API_KEY: A user-generated API key from the Open WebUI interface.
#     - WEBUI_URL: The full URL of your deployed Open WebUI service.
# ======================================================================

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
    echo "Pinging the /api/models endpoint to verify API key and connectivity..."
    response=$(curl -s -H "$AUTH_HEADER" "${WEBUI_URL}/api/models")
    # Check if response is valid JSON and contains a 'data' array
    if ! echo "$response" | jq -e '.data | type == "array"' >/dev/null 2>&1; then
        # Try to detect if it's HTML or not JSON
        if echo "$response" | grep -q '<!doctype html>'; then
            echo "Error: /api/models returned HTML (likely the frontend splash page). Check your API key and deployment."
        else
            echo "Error: /api/models response does not contain a 'data' array or is not valid JSON."
        fi
        echo "Response: $response"
        return 1
    fi
    echo "API is responsive and authentication is successful."
}

# Test 2: Programmatically Create a Knowledge Base
test_create_kb() {
    echo "Attempting to create a new knowledge base named 'test-kb-'..."
    KB_NAME="persistent-test-kb-$(date +%s)"
    # Check if KB with this name already exists and delete it to ensure a clean test
    existing_kb=$(curl -s -H "$AUTH_HEADER" "${WEBUI_URL}/api/v1/knowledge/list" | jq -r ".[] | select(.name == \"$KB_NAME\") | .id")
    if [ -n "$existing_kb" ]; then
        echo "Deleting existing KB with name $KB_NAME (ID: $existing_kb)"
        curl -s -X DELETE -H "$AUTH_HEADER" "${WEBUI_URL}/api/v1/knowledge/$existing_kb/delete"
    fi
    response=$(curl -s -X POST -H "$AUTH_HEADER" -H "$CONTENT_TYPE_HEADER" \
        -d "{\"name\": \"$KB_NAME\", \"description\": \"Test KB for persistence\"}" \
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
    echo "This is a test document for KB persistence validation." > testdoc.txt
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
