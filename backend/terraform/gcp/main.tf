locals {
  apis = [
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]

  src_dir = "${path.module}/../.."

  src_files = sort(tolist(fileset(local.src_dir, "{server.py,context.py,resources.py,me.txt,requirements.txt,Dockerfile,.dockerignore}")))
  data_files = sort(tolist(fileset(local.src_dir, "data/**")))

  src_hash = substr(sha1(join("", [
    for f in concat(local.src_files, local.data_files) : filesha1("${local.src_dir}/${f}")
  ])), 0, 12)

  image_tag = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.twin.repository_id}/${var.service_name}:${local.src_hash}"

  frontend_dir = "${path.module}/../../../frontend"

  frontend_root_files = [
    for f in [
      "package.json",
      "package-lock.json",
      "next.config.ts",
      "tsconfig.json",
      "postcss.config.mjs",
      "eslint.config.mjs",
      "next-env.d.ts",
      "Dockerfile",
      ".dockerignore",
    ] : f if fileexists("${local.frontend_dir}/${f}")
  ]

  frontend_files = sort(distinct(concat(
    local.frontend_root_files,
    tolist(fileset(local.frontend_dir, "app/**")),
    tolist(fileset(local.frontend_dir, "components/**")),
    tolist(fileset(local.frontend_dir, "public/**")),
  )))

  frontend_hash = substr(sha1(join("", [
    for f in local.frontend_files : filesha1("${local.frontend_dir}/${f}")
  ])), 0, 12)

  frontend_image_tag = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.twin.repository_id}/${var.frontend_service_name}:${local.frontend_hash}"
}

resource "google_project_service" "enabled" {
  for_each                   = toset(local.apis)
  service                    = each.value
  disable_dependent_services = false
  disable_on_destroy         = false
}

resource "google_artifact_registry_repository" "twin" {
  location      = var.region
  repository_id = "twin"
  format        = "DOCKER"
  description   = "Twin backend container images"

  depends_on = [google_project_service.enabled]
}

resource "google_storage_bucket" "memory" {
  name                        = var.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = false

  depends_on = [google_project_service.enabled]
}

resource "google_service_account" "runtime" {
  account_id   = "${var.service_name}-sa"
  display_name = "Twin backend runtime SA"
}

resource "google_storage_bucket_iam_member" "runtime_bucket" {
  bucket = google_storage_bucket.memory.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret" "openrouter" {
  secret_id = "${var.service_name}-openrouter-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.enabled]
}

resource "google_secret_manager_secret_version" "openrouter" {
  secret      = google_secret_manager_secret.openrouter.id
  secret_data = var.openrouter_api_key
}

resource "google_secret_manager_secret_iam_member" "runtime_access" {
  secret_id = google_secret_manager_secret.openrouter.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}

data "google_client_config" "default" {}

data "google_project" "current" {}

locals {
  frontend_url = "https://${var.frontend_service_name}-${data.google_project.current.number}.${var.region}.run.app"

  cors_origins = join(",", compact([
    local.frontend_url,
    var.cors_origins,
  ]))
}

resource "docker_image" "backend" {
  name = local.image_tag

  build {
    context    = local.src_dir
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
  }

  triggers = {
    src_hash = local.src_hash
  }

  depends_on = [google_artifact_registry_repository.twin]
}

resource "docker_registry_image" "backend" {
  name          = docker_image.backend.name
  keep_remotely = true

  triggers = {
    src_hash = local.src_hash
  }
}

resource "google_cloud_run_v2_service" "backend" {
  name                = var.service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.runtime.email

    containers {
      image = local.image_tag

      ports {
        container_port = 8080
      }

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.memory.name
      }

      env {
        name  = "CORS_ORIGINS"
        value = local.cors_origins
      }

      env {
        name = "OPENROUTER_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.openrouter.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.enabled,
    google_secret_manager_secret_version.openrouter,
    google_secret_manager_secret_iam_member.runtime_access,
    docker_registry_image.backend,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.backend.name
  location = google_cloud_run_v2_service.backend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "docker_image" "frontend" {
  name = local.frontend_image_tag

  build {
    context    = local.frontend_dir
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
  }

  triggers = {
    src_hash = local.frontend_hash
  }

  depends_on = [google_artifact_registry_repository.twin]
}

resource "docker_registry_image" "frontend" {
  name          = docker_image.frontend.name
  keep_remotely = true

  triggers = {
    src_hash = local.frontend_hash
  }
}

resource "google_service_account" "frontend_runtime" {
  account_id   = "${var.frontend_service_name}-sa"
  display_name = "Twin frontend runtime SA"
}

resource "google_cloud_run_v2_service" "frontend" {
  name                = var.frontend_service_name
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.frontend_runtime.email

    containers {
      image = local.frontend_image_tag

      ports {
        container_port = 8080
      }

      env {
        name  = "BACKEND_URL"
        value = google_cloud_run_v2_service.backend.uri
      }
    }
  }

  depends_on = [
    google_project_service.enabled,
    docker_registry_image.frontend,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "frontend_public" {
  name     = google_cloud_run_v2_service.frontend.name
  location = google_cloud_run_v2_service.frontend.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
