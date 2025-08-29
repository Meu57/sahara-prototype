# ---------------------------------------------------------------- #
#                     --- PROVIDER SETUP ---                       #
# ---------------------------------------------------------------- #
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "sahara-wellness-prototype"
  region  = "asia-south1" # ✅ Cloud Run, Firestore, etc. stay in asia-south1
}

provider "google-beta" {
  project = "sahara-wellness-prototype"
  region  = "asia-south1"
}

# ---------------------------------------------------------------- #
#              --- SERVICE ACCOUNT FOR BACKEND APP ---            #
# ---------------------------------------------------------------- #
resource "google_service_account" "sahara_app_sa" {
  account_id   = "sahara-app-backend-sa"
  display_name = "Service Account for Sahara Backend Application"
  description  = "Runs the Cloud Run service and accesses APIs."
}

# ---------------------------------------------------------------- #
#         --- IAM ROLES FOR BACKEND SERVICE ACCOUNT ---           #
# ---------------------------------------------------------------- #
resource "google_project_iam_member" "vertex_ai_user" {
  project = "sahara-wellness-prototype"
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.sahara_app_sa.email}"
}

resource "google_project_iam_member" "firestore_user" {
  project = "sahara-wellness-prototype"
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.sahara_app_sa.email}"
}

# ---------------------------------------------------------------- #
#               --- ENABLE REQUIRED GOOGLE SERVICES ---           #
# ---------------------------------------------------------------- #
resource "google_project_service" "firestore_api" {
  service            = "firestore.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudrun_api" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

# ---------------------------------------------------------------- #
#                        --- FIRESTORE SETUP ---                   #
# ---------------------------------------------------------------- #
resource "google_firestore_database" "database" {
  name        = "(default)"
  location_id = "asia-south1"
  type        = "FIRESTORE_NATIVE"
  project     = "sahara-wellness-prototype"
  depends_on  = [google_project_service.firestore_api]
}

# ---------------------------------------------------------------- #
#                    --- CLOUD RUN BACKEND SERVICE ---            #
# ---------------------------------------------------------------- #

data "google_cloudbuild_trigger" "main_trigger" {
  project = "sahara-wellness-prototype"
  trigger_id = "push-to-main-v2" # The name of our trigger
  location = "global"                        # ✅ Cloud Build triggers are usually in 'global'
}


resource "google_cloud_run_v2_service" "sahara_backend" {
  name     = "sahara-backend-service"
  location = "asia-south1"
  project  = "sahara-wellness-prototype"

  template {
    service_account = google_service_account.sahara_app_sa.email
    timeout         = "60s"

    containers {
      image = "asia-south1-docker.pkg.dev/sahara-wellness-prototype/sahara-repo/sahara-backend:latest"




      resources {
        startup_cpu_boost = false
        cpu_idle          = true
        limits = {
          cpu    = "0.5"
          memory = "512Mi"
        }
      }
    }
  }

  depends_on = [
  google_project_service.cloudrun_api,
  
  data.google_cloudbuild_trigger.main_trigger
]

}

# ---------------------------------------------------------------- #
#              --- DEVELOPER ACCESS TO CLOUD RUN ---              #
# ---------------------------------------------------------------- #
resource "google_cloud_run_v2_service_iam_member" "developer_access" {
  name     = google_cloud_run_v2_service.sahara_backend.name
  location = google_cloud_run_v2_service.sahara_backend.location
  project  = "sahara-wellness-prototype"
  role     = "roles/run.invoker"
  member   = "user:ameenkhanuuuu57@gmail.com"
}

# ---------------------------------------------------------------- #
#           --- CI/CD PERMISSIONS FOR CLOUD BUILD SA ---          #
# ---------------------------------------------------------------- #
data "google_project" "project" {}

locals {
  cloud_build_sa_member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

resource "google_project_iam_member" "cloudbuild_artifact_admin" {
  project = "sahara-wellness-prototype"
  role    = "roles/artifactregistry.admin"
  member  = local.cloud_build_sa_member
}

resource "google_service_account_iam_member" "cloudbuild_is_service_account_user" {
  service_account_id = google_service_account.sahara_app_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = local.cloud_build_sa_member
}

# ---------------------------------------------------------------- #
#               --- API GATEWAY INFRASTRUCTURE ---                #
# ---------------------------------------------------------------- #

# ✅ Task 1: Create a dedicated Service Account for API Gateway
resource "google_service_account" "api_gateway_sa" {
  account_id   = "sahara-api-gateway-sa"
  display_name = "Service Account for Sahara API Gateway"
  description  = "Has permission to invoke the private Cloud Run service."
}

# ✅ Task 2: Grant Gateway SA permission to invoke Cloud Run
resource "google_cloud_run_v2_service_iam_member" "gateway_invoker_binding" {
  project  = google_cloud_run_v2_service.sahara_backend.project
  name     = google_cloud_run_v2_service.sahara_backend.name
  location = google_cloud_run_v2_service.sahara_backend.location
  role     = "roles/run.invoker"
  member   = google_service_account.api_gateway_sa.member
}

# ✅ Task 3: Enable required APIs for API Gateway
resource "google_project_service" "apigateway" {
  project            = "sahara-wellness-prototype"
  service            = "apigateway.googleapis.com"
  disable_on_destroy = false
}
resource "google_project_service" "servicemanagement" {
  project            = "sahara-wellness-prototype"
  service            = "servicemanagement.googleapis.com"
  disable_on_destroy = false
}
resource "google_project_service" "servicecontrol" {
  project            = "sahara-wellness-prototype"
  service            = "servicecontrol.googleapis.com"
  disable_on_destroy = false
}

# ✅ Task 4: Define the API Gateway API
resource "google_api_gateway_api" "sahara_api" {
  provider   = google-beta
  project    = "sahara-wellness-prototype"
  api_id     = "sahara-api"
  depends_on = [google_project_service.apigateway]
}

# ✅ NEW: Enable the managed service created by the API Gateway
resource "google_project_service" "sahara_api_managed_service_enablement" {
  project            = "sahara-wellness-prototype"
  service            = google_api_gateway_api.sahara_api.managed_service
  disable_on_destroy = false
  depends_on         = [google_api_gateway_api.sahara_api]
}


# ✅ Task 5: Define the API Config using OpenAPI spec
resource "google_api_gateway_api_config" "sahara_api_config" {
  provider        = google-beta
  project         = "sahara-wellness-prototype"
  api             = google_api_gateway_api.sahara_api.api_id
  api_config_id_prefix = "sahara-config-"

  openapi_documents {
    document {
      path     = "api_gateway_spec.yaml"
      contents = base64encode(templatefile("api_gateway_spec.yaml", {
        cloud_run_url = google_cloud_run_v2_service.sahara_backend.uri,
        jwt_audience  = google_cloud_run_v2_service.sahara_backend.uri
      }))
    }
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [google_project_service.apigateway]
}

# ✅ Task 6: Deploy the Gateway in a supported region
resource "google_api_gateway_gateway" "sahara_gateway" {
  provider   = google-beta
  project    = "sahara-wellness-prototype"
  gateway_id = "sahara-gateway"
  api_config = google_api_gateway_api_config.sahara_api_config.id
  region     = "asia-northeast1"
  depends_on = [google_project_service.sahara_api_managed_service_enablement] # ✅ Updated dependency
}



# --- OUTPUTS ---

# output "gateway_url" {
  # description = "The public default URL of the API Gateway"
  # value       = "https://${google_api_gateway_gateway.sahara_gateway.default_hostname}"
# }