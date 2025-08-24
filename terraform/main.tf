terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# --- Provider Configuration ---
# This block configures the Google Cloud provider.
provider "google" {
  project = "sahara-wellness-prototype"
  region  = "asia-south1"
}

# --- IAM & Service Accounts ---

# 1. Create a dedicated service account for our Sahara backend application.
resource "google_service_account" "sahara_app_sa" {
  account_id   = "sahara-app-backend-sa"
  display_name = "Service Account for Sahara Backend Application"
  description  = "Used by the Cloud Run service to access Google Cloud APIs securely."
}

# 2. Give the new service account permission to be a "Vertex AI User".
resource "google_project_iam_member" "vertex_ai_user_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/aiplatform.user"
  member  = google_service_account.sahara_app_sa.member
}

# 3. Give the new service account permission to be a "Firestore User".
resource "google_project_iam_member" "firestore_user_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/datastore.user"
  member  = google_service_account.sahara_app_sa.member
}

# 4. Give the service account permission to write logs.
resource "google_project_iam_member" "logging_logwriter_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/logging.logWriter"
  member  = google_service_account.sahara_app_sa.member
}

# 5. Grant the role to VIEW secrets' metadata.
resource "google_project_iam_member" "secret_manager_viewer_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/secretmanager.viewer"
  member  = google_service_account.sahara_app_sa.member
}

# 6. Grant the role to ACCESS the actual value of secrets.
resource "google_project_iam_member" "secret_manager_accessor_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.sahara_app_sa.member
}

# --- Firestore Database ---

# This ensures the Firestore API is enabled before we try to create a database.
resource "google_project_service" "firestore" {
  project            = "sahara-wellness-prototype"
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

# This creates the actual Firestore database instance.
resource "google_firestore_database" "database" {
  project     = "sahara-wellness-prototype"
  name        = "(default)"
  location_id = "asia-south1"
  type        = "FIRESTORE_NATIVE"
  
  depends_on = [
    google_project_service.firestore
  ]
}

# --- Cloud Run Service ---

# This ensures the Cloud Run API is enabled before we try to create a service.
resource "google_project_service" "cloudrun" {
  project            = "sahara-wellness-prototype"
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# This creates the actual Cloud Run service.
resource "google_cloud_run_v2_service" "sahara_backend" {
  project  = "sahara-wellness-prototype"
  name     = "sahara-backend-service"
  location = "asia-south1"

  template {
    service_account = google_service_account.sahara_app_sa.email

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
  
  depends_on = [
    google_project_service.cloudrun
  ]
}

# This makes our Cloud Run service accessible from the public internet.
resource "google_cloud_run_v2_service_iam_member" "allow_public_access" {
  project  = "sahara-wellness-prototype"
  name     = "sahara-backend-service"
  location = "asia-south1"
  role     = "roles/run.invoker"
  member   = "allUsers"
}