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

# Discover project number for service-agent member strings.
data "google_project" "this" {
  project_id = var.project_id
}

locals {
  pn = data.google_project.this.number
  # service agent => crypto key it must use
  cmek_grants = {
    "service-${local.pn}@gcp-sa-cloud-sql.iam.gserviceaccount.com"            = "sql"
    "service-${local.pn}@gs-project-accounts.iam.gserviceaccount.com"         = "storage"
    "service-${local.pn}@gcp-sa-artifactregistry.iam.gserviceaccount.com"     = "artifacts"
    "service-${local.pn}@gcp-sa-secretmanager.iam.gserviceaccount.com"        = "secrets"
  }
}

resource "google_kms_crypto_key_iam_member" "agents" {
  for_each      = local.cmek_grants
  crypto_key_id = google_kms_crypto_key.key[each.value].id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${each.key}"
}
