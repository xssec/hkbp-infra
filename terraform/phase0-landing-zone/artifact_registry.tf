# Docker repo for all service images. CMEK-encrypted. Vulnerability scanning is
# enabled at the project level via containeranalysis.googleapis.com (apis.tf).
resource "google_artifact_registry_repository" "docker" {
  repository_id = var.name_prefix
  location      = var.region
  format        = "DOCKER"
  description   = "HKBP service container images"
  kms_key_name  = google_kms_crypto_key.key["artifacts"].id

  docker_config {
    immutable_tags = true # prevents tag overwrite — :sha tags are immutable
  }

  depends_on = [google_kms_crypto_key_iam_member.agents]
}

# Deployer pushes; all runtime SAs pull.
resource "google_artifact_registry_repository_iam_member" "pullers" {
  for_each   = google_service_account.runtime
  repository = google_artifact_registry_repository.docker.name
  location   = var.region
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value.email}"
}
