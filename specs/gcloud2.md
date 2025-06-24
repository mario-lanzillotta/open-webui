Of course. Here is a detailed technical specification for Windsurf AI to automate the infrastructure setup for a production-ready, persistent Open WebUI instance on Google Cloud using the `gcloud` CLI.

---

### **Technical Specification: Open WebUI Stateful Deployment on Google Cloud**

#### **1. Objective**

To provision and deploy a stateful, production-ready instance of Open WebUI on Google Cloud Run. This specification outlines the automation steps required to use a persistent **Cloud SQL for PostgreSQL** database for both application data (users, chats) and as a **vector store** for the RAG knowledge base, ensuring no data is lost upon instance restarts.

#### **2. Scope**

*   **In-Scope:**
    *   Provisioning a new Cloud SQL for PostgreSQL instance.
    *   Enabling the `pgvector` extension on the instance.
    *   Creating a dedicated database for Open WebUI.
    *   Creating and managing necessary secrets in Google Secret Manager.
    *   Deploying the Open WebUI container image to Cloud Run with persistent configurations.
*   **Out-of-Scope:**
    *   Docker image creation (assumed to be pre-built and available in Artifact Registry).
    *   CI/CD pipeline configuration.
    *   DNS and custom domain mapping.

#### **3. Prerequisites**

The automation script must assume the following:
1.  The `gcloud` CLI is installed, authenticated, and configured with the target Google Cloud project.
2.  The user has permissions to create and manage Cloud SQL, Cloud Run, and Secret Manager resources.
3.  The Open WebUI Docker image is available in a Google Artifact Registry repository within the same project.
4.  The following Google Cloud APIs are enabled in the project:
    *   `run.googleapis.com` (Cloud Run)
    *   `sqladmin.googleapis.com` (Cloud SQL Admin)
    *   `secretmanager.googleapis.com` (Secret Manager)
    *   `iam.googleapis.com` (Identity and Access Management)

#### **4. Step-by-Step Implementation Plan (gcloud CLI)**

##### **Step 4.1: Define Configuration Variables**

The script will begin by defining or sourcing the following variables:

```bash
# User-configurable variables
PROJECT_ID="aqgprag"
REGION="us-central1"
SQL_INSTANCE_NAME="open-webui-postgres-db"
DB_NAME="openwebui"
DB_USER="postgres"

# Auto-generated or securely sourced variables
DB_PASSWORD=$(openssl rand -base64 16) # Generate a secure, random password
WEBUI_SECRET_KEY_VALUE=$(openssl rand -base64 32) # Generate a strong secret key
```

##### **Step 4.2: Enable Required GCP Services**

Ensure all necessary APIs are enabled.

```bash
gcloud services enable run.googleapis.com \
                       sqladmin.googleapis.com \
                       secretmanager.googleapis.com \
                       iam.googleapis.com \
                       --project=${PROJECT_ID}
```

##### **Step 4.3: Provision the Cloud SQL for PostgreSQL Instance**

Create a PostgreSQL instance with the `pgvector` extension enabled.

```bash
gcloud sql instances create ${SQL_INSTANCE_NAME} \
  --project=${PROJECT_ID} \
  --database-version=POSTGRES_15 \
  --region=${REGION} \
  --tier=db-g1-small \
  --root-password=${DB_PASSWORD} \
  --database-flags=cloudsql.extensions.pgvector=on

# Create the dedicated database within the instance
gcloud sql databases create ${DB_NAME} \
  --instance=${SQL_INSTANCE_NAME} \
  --project=${PROJECT_ID}
```

##### **Step 4.4: Create and Populate Secrets in Secret Manager**

All sensitive data will be stored securely.

1.  **Store the `WEBUI_SECRET_KEY`:** This key is for JWT signing and must be persistent.

    ```bash
    echo -n "${WEBUI_SECRET_KEY_VALUE}" | gcloud secrets create webui-secret-key \
      --project=${PROJECT_ID} \
      --replication-policy="automatic" \
      --data-file=-
    ```

2.  **Construct and Store the `DATABASE_URL`:**

    ```bash
    # Get the instance connection name
    INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe ${SQL_INSTANCE_NAME} \
      --project=${PROJECT_ID} \
      --format='value(connectionName)')

    # Construct the database URL for Cloud Run
    DATABASE_URL="postgresql+psycopg2://${DB_USER}:${DB_PASSWORD}@/${DB_NAME}?host=/cloudsql/${INSTANCE_CONNECTION_NAME}"

    # Store the URL in Secret Manager
    echo -n "${DATABASE_URL}" | gcloud secrets create openwebui-database-url \
      --project=${PROJECT_ID} \
      --replication-policy="automatic" \
      --data-file=-
    ```

##### **Step 4.5: Grant Cloud Run Access to Secrets**

The Cloud Run service identity needs permission to access the created secrets.

```bash
# Get the project number
PROJECT_NUMBER=$(gcloud projects describe ${PROJECT_ID} --format='value(projectNumber)')

# Grant the default Compute Engine service account access to the secrets.
# NOTE: In production, it's recommended to use a dedicated service account.
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding webui-secret-key \
  --project=${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding openwebui-database-url \
  --project=${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"
  
gcloud secrets add-iam-policy-binding openai-api-key \
  --project=${PROJECT_ID} \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"
```

#### **5. Updated Deployment Script**

This is the final `gcloud run deploy` command that incorporates all the persistent infrastructure components.

```bash
gcloud run deploy open-webui \
  --project=aqgprag \
  --image=us-central1-docker.pkg.dev/aqgprag/openwebui-docker/open-webui:main \
  --platform=managed \
  --region=us-central1 \
  --port=8080 \
  --allow-unauthenticated \
  --min-instances=0 \
  --max-instances=1 \
  --timeout=300s \
  --memory=4Gi \
  \
  # --- INFRASTRUCTURE INTEGRATIONS --- #
  \
  # Connect the service to the Cloud SQL instance
  --add-cloudsql-instances="${INSTANCE_CONNECTION_NAME}" \
  \
  # Set environment variables for persistence
  --set-env-vars="VECTOR_DB=pgvector" \
  \
  # Mount the secrets into the container as environment variables
  --set-secrets=OPENAI_API_KEY=openai-api-key:latest,WEBUI_SECRET_KEY=webui-secret-key:latest,DATABASE_URL=openwebui-database-url:latest
```

#### **6. Verification**

After deployment, Windsurf AI or the user should verify the setup:
1.  Check the Cloud Run logs for successful startup and database connection messages.
2.  Access the Open WebUI instance URL.
3.  Create a user account.
4.  Restart the Cloud Run instance (by deploying a minor change like a new label) and confirm that the user account persists.
5.  Navigate to **Settings -> RAG** and confirm the vector database is automatically configured.
6.  Create a knowledge base, upload a document, and verify it can be queried after an instance restart.

---
