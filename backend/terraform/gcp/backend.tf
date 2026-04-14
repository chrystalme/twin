terraform {
  backend "gcs" {
    bucket = "twin-tfstate-chrys-digital-twin"
    prefix = "twin/gcp"
  }
}
