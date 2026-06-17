# Media/static asset bucket (user uploads move here in Phase 1 — off container FS).
# Private; objects served via signed URLs or through the LB/CDN, never public ACLs.
resource "google_storage_bucket" "media" {
  name                        = "${var.project_id}-media"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning { enabled = true }

  encryption {
    default_kms_key_name = google_kms_crypto_key.key["storage"].id
  }

  lifecycle_rule {
    condition { age = 90 }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.agents]
}

# php-monolith and svc-content read/write media; others none.
resource "google_storage_bucket_iam_member" "media_rw" {
  for_each = toset(["php-monolith", "svc-content"])
  bucket   = google_storage_bucket.media.name
  role     = "roles/storage.objectAdmin"
  member   = "serviceAccount:${google_service_account.runtime[each.value].email}"
}
