# Secret *containers* are created here (CMEK-encrypted, app-managed replication
# pinned to region). VALUES are added out-of-band — never commit secret values.
#   echo -n 'super-secret' | gcloud secrets versions add db-pass --data-file=-
locals {
  secret_ids = [
    "db-pass",            # Cloud SQL app user password
    "db-migration-pass",  # DMS source replication user
    "app-key",            # PHP app encryption key
    "jwt-signing-key",    # mobile API JWT signing
    "cf-origin-cert",     # Cloudflare Authenticated Origin Pull cert/key (Phase 5)
    "fcm-server-key",     # push notifications (py-worker)
  ]
}

resource "google_secret_manager_secret" "secrets" {
  for_each  = toset(local.secret_ids)
  secret_id = each.value

  replication {
    user_managed {
      replicas {
        location = var.region
        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.key["secrets"].id
        }
      }
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.agents]
}

# Grant each runtime SA accessor ONLY on the secrets it needs.
locals {
  secret_access = {
    "php-monolith:db-pass"        = { sa = "php-monolith", secret = "db-pass" }
    "php-monolith:app-key"        = { sa = "php-monolith", secret = "app-key" }
    "svc-auth:jwt-signing-key"    = { sa = "svc-auth", secret = "jwt-signing-key" }
    "svc-auth:db-pass"            = { sa = "svc-auth", secret = "db-pass" }
    "svc-content:db-pass"         = { sa = "svc-content", secret = "db-pass" }
    "py-api:db-pass"              = { sa = "py-api", secret = "db-pass" }
    "py-worker:db-pass"           = { sa = "py-worker", secret = "db-pass" }
    "py-worker:fcm-server-key"    = { sa = "py-worker", secret = "fcm-server-key" }
  }
}

resource "google_secret_manager_secret_iam_member" "accessors" {
  for_each  = local.secret_access
  secret_id = google_secret_manager_secret.secrets[each.value.secret].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime[each.value.sa].email}"
}
