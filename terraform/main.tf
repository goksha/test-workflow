provider "google" {
  project = var.project_id
  region  = "us-central1"
  zone    = "us-central1-c"
}

provider "kubectl" {
  host                   = module.gke_auth.host
  cluster_ca_certificate = module.gke_auth.cluster_ca_certificate
  token                  = module.gke_auth.token
  load_config_file       = false
}

terraform {
  required_version = ">= 0.13"
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
    }
  }
  backend "gcs" {
    bucket = "terraform-backend-<project-id>"
    prefix = "argocd-terraform"
  }
}

resource "google_service_account" "main" {
  account_id   = "${var.cluster_name}-sa"
  display_name = "GKE Cluster ${var.cluster_name} Service Account"
}

resource "google_container_cluster" "main" {
  name               = "${var.cluster_name}"
  location           = var.location
  initial_node_count = 3
  node_config {
    service_account = google_service_account.main.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [google_container_cluster.main]
  create_duration = "30s"
}

module "gke_auth" {
  depends_on           = [time_sleep.wait_30_seconds]
  source               = "terraform-google-modules/kubernetes-engine/google//modules/auth"
  project_id           = var.project_id
  cluster_name         = google_container_cluster.main.name
  location             = var.location
  use_private_endpoint = false
}

data "kubectl_file_documents" "manifests" {
    content = file("install.yaml")
}

resource "kubectl_manifest" "test" {
    count     = length(data.kubectl_file_documents.manifests.documents)
    yaml_body = element(data.kubectl_file_documents.manifests.documents, count.index)
    override_namespace = "argocd"
}