terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# --- Provider Configuration ---
provider "google" {
  project = "sahara-wellness-prototype"
  region  = "asia-south1"
}

# --- IAM & Service Accounts ---

resource "google_service_account" "sahara_app_sa" {
  account_id   = "sahara-app-backend-sa"
  display_name = "Service Account for Sahara Backend Application"
  description  = "Used by the Cloud Run service to access Google Cloud APIs securely."
}

resource "google_project_iam_member" "vertex_ai_user_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/aiplatform.user"
  member  = google_service_account.sahara_app_sa.member
}

resource "google_project_iam_member" "firestore_user_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/datastore.user"
  member  = google_service_account.sahara_app_sa.member
}

resource "google_project_iam_member" "logging_logwriter_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/logging.logWriter"
  member  = google_service_account.sahara_app_sa.member
}

resource "google_project_iam_member" "secret_manager_viewer_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/secretmanager.viewer"
  member  = google_service_account.sahara_app_sa.member
}

resource "google_project_iam_member" "secret_manager_accessor_binding" {
  project = "sahara-wellness-prototype"
  role    = "roles/secretmanager.secretAccessor"
  member  = google_service_account.sahara_app_sa.member
}

# --- Firestore Database ---

resource "google_project_service" "firestore" {
  project            = "sahara-wellness-prototype"
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

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

resource "google_project_service" "cloudrun" {
  project            = "sahara-wellness-prototype"
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_cloud_run_v2_service" "sahara_backend" {
  project  = "sahara-wellness-prototype"
  name     = "sahara-backend-service"
  location = "asia-south1"

  template {
    service_account = google_service_account.sahara_app_sa.email

    # --- THIS IS THE NEW, CRITICAL LINE ---
    # Increase the request timeout to 300 seconds (5 minutes).
    # This gives the Hugging Face API plenty of time for a cold start.
    timeout = "300s"

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }

  depends_on = [
    google_project_service.cloudrun
  ]
}

resource "google_cloud_run_v2_service_iam_member" "allow_public_access" {
  project  = "sahara-wellness-prototype"
  name     = "sahara-backend-service"
  location = "asia-south1"
  role     = "roles/run.invoker"
  member   = "allUsers"
}



resource "google_service_account_iam_member" "cloudbuild_can_act_as_app_sa" {
  service_account_id = google_service_account.sahara_app_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:78116732933@cloudbuild.gserviceaccount.com" # The Cloud Build Worker
}