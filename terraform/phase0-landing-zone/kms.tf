# ---------------------------------------------------------------------------
# CMEK — customer-managed encryption keys for SQL, Storage, Artifact Registry,
# and Secret Manager. Each service's Google-managed service agent gets
# encrypter/decrypter on its key. Rotation every 90 days.
# ---------------------------------------------------------------------------
resource "google_kms_key_ring" "ring" {
  name       = "${var.name_prefix}-keyring"
  location   = var.region
  depends_on = [google_project_service.enabled]
}

resource "google_kms_crypto_key" "key" {
  for_each        = toset(["sql", "storage", "artifacts", "secrets"])
  name            = "${var.name_prefix}-${each.value}"
  key_ring        = google_kms_key_ring.ring.id
  rotation_period = "7776000s" # 90 days
  purpose         = "ENCRYPT_DECRYPT"

  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Force-provision the Google-managed SERVICE AGENTS that will use each key.
# These agents do NOT exist until the service is first used, so granting IAM to
# them blindly fails with "does not exist". We create them explicitly via the
# service-identity API, then reference their real emails in the grants below.
# ---------------------------------------------------------------------------
resource "google_project_service_identity" "sql" {
  provider   = google-beta
  service    = "sqladmin.googleapis.com"
  depends_on = [time_sleep.wait_for_apis]
}

resource "google_project_service_identity" "secretmanager" {
  provider   = google-beta
  service    = "secretmanager.googleapis.com"
  depends_on = [time_sleep.wait_for_apis]
}

resource "google_project_service_identity" "artifactregistry" {
  provider   = google-beta
  service    = "artifactregistry.googleapis.com"
  depends_on = [time_sleep.wait_for_apis]
}

# GCS service agent: this data source provisions + returns the agent email.
data "google_storage_project_service_account" "gcs" {
  depends_on = [time_sleep.wait_for_apis]
}

# ---------------------------------------------------------------------------
# Grant each agent encrypt/decrypt on its dedicated key.
# ---------------------------------------------------------------------------
resource "google_kms_crypto_key_iam_member" "sql" {
  crypto_key_id = google_kms_crypto_key.key["sql"].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.sql.email}"
}

resource "google_kms_crypto_key_iam_member" "secrets" {
  crypto_key_id = google_kms_crypto_key.key["secrets"].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.secretmanager.email}"
}

resource "google_kms_crypto_key_iam_member" "artifacts" {
  crypto_key_id = google_kms_crypto_key.key["artifacts"].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.artifactregistry.email}"
}

resource "google_kms_crypto_key_iam_member" "storage" {
  crypto_key_id = google_kms_crypto_key.key["storage"].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}
