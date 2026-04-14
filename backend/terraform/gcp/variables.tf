variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for Cloud Run and Artifact Registry"
  default     = "us-central1"
}

variable "service_name" {
  type        = string
  description = "Cloud Run service name"
  default     = "twin-backend"
}

variable "frontend_service_name" {
  type        = string
  description = "Cloud Run service name for the Next.js frontend"
  default     = "twin-frontend"
}

variable "bucket_name" {
  type        = string
  description = "GCS bucket for conversation memory (must be globally unique)"
}

variable "openrouter_api_key" {
  type        = string
  description = "OpenRouter API key (stored in Secret Manager)"
  sensitive   = true
}

variable "cors_origins" {
  type        = string
  description = "Comma-separated CORS origins"
  default     = "http://localhost:3000"
}
