terraform {
  required_providers {
    google = {
      source = "hashicorp/google"

    }
  }

}

provider "google" {
  credentials = var.credentials_file
  project     = var.project
  region      = var.region
  zone        = var.zone
}