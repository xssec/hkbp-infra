output "vpc_id" {
  value       = google_compute_network.vpc.id
  description = "VPC self link — referenced by Cloud SQL (Phase 3) and Run (Phase 4)."
}

output "subnet_main" {
  value       = google_compute_subnetwork.main.id
  description = "Primary subnet self link."
}

output "subnet_run" {
  value       = google_compute_subnetwork.run.id
  description = "Cloud Run Direct VPC egress subnet — pass to `gcloud run deploy --subnet`."
}

output "psa_connection" {
  value       = google_service_networking_connection.psa.peering
  description = "Private Service Access peering — Cloud SQL private IP depends on this."
}

output "artifact_registry" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
  description = "Image path prefix for cloudbuild.yaml."
}

output "runtime_service_accounts" {
  value       = { for k, v in google_service_account.runtime : k => v.email }
  description = "Per-service runtime SA emails — pass to `gcloud run deploy --service-account`."
}

output "deployer_service_account" {
  value       = google_service_account.deployer.email
  description = "CI/CD deployer SA — assign to the Cloud Build trigger (Phase 2)."
}

output "kms_keys" {
  value       = { for k, v in google_kms_crypto_key.key : k => v.id }
  description = "CMEK key IDs for sql/storage/artifacts/secrets."
}

output "media_bucket" {
  value       = google_storage_bucket.media.url
  description = "Media/uploads bucket (Phase 1 stateless refactor target)."
}
