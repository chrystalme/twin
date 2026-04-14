output "service_url" {
  value       = google_cloud_run_v2_service.backend.uri
  description = "Public URL of the Cloud Run service"
}

output "frontend_url" {
  value       = google_cloud_run_v2_service.frontend.uri
  description = "Public URL of the Next.js frontend Cloud Run service"
}

output "bucket_name" {
  value       = google_storage_bucket.memory.name
  description = "GCS bucket storing conversation memory"
}

output "artifact_registry_repo" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.twin.repository_id}"
  description = "Push images here"
}

output "runtime_service_account" {
  value       = google_service_account.runtime.email
  description = "Service account used by the Cloud Run service"
}
