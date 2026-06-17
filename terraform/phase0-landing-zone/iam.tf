# ---------------------------------------------------------------------------
# Per-service runtime service accounts (one identity per Cloud Run service).
# NO shared SAs, NO default compute SA usage, NO exported SA keys.
# ---------------------------------------------------------------------------
locals {
  # service name => list of project-level roles it actually needs (least privilege)
  runtime_sas = {
    "php-monolith" = ["roles/cloudsql.client"]
    "py-api"       = ["roles/cloudsql.client"]
    "py-worker"    = ["roles/cloudsql.client", "roles/pubsub.subscriber"]
    "svc-content"  = ["roles/cloudsql.client"]
    "svc-auth"     = ["roles/cloudsql.client"]
  }

  # flatten {sa => [roles]} into bindable pairs
  sa_role_pairs = merge([
    for sa, roles in local.runtime_sas : {
      for r in roles : "${sa}:${r}" => { sa = sa, role = r }
    }
  ]...)
}

resource "google_service_account" "runtime" {
  for_each     = local.runtime_sas
  account_id   = "sa-${each.key}"
  display_name = "Cloud Run runtime: ${each.key}"
}

resource "google_project_iam_member" "runtime_roles" {
  for_each = local.sa_role_pairs
  project  = var.project_id
  role     = each.value.role
  member   = "serviceAccount:${google_service_account.runtime[each.value.sa].email}"
}

# ---------------------------------------------------------------------------
# Deploy identity used by Cloud Build to build images & deploy Cloud Run.
# (Phase 2 trigger runs as this SA — keep it separate from runtime SAs.)
# ---------------------------------------------------------------------------
resource "google_service_account" "deployer" {
  account_id   = "sa-deployer"
  display_name = "Cloud Build deployer (CI/CD)"
}

resource "google_project_iam_member" "deployer_roles" {
  for_each = toset([
    "roles/run.developer",              # deploy/update Cloud Run revisions
    "roles/artifactregistry.writer",    # push images
    "roles/cloudbuild.builds.editor",   # run builds
    "roles/logging.logWriter",          # build logs
    "roles/secretmanager.secretAccessor"
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Deployer must be able to impersonate runtime SAs to deploy services as them.
resource "google_service_account_iam_member" "deployer_act_as" {
  for_each           = google_service_account.runtime
  service_account_id = each.value.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
