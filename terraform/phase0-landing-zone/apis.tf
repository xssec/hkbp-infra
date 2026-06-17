# Enable every API the migration needs. disable_on_destroy=false so a
# `terraform destroy` of this module never tears down APIs other stacks rely on.
locals {
  services = [
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "sqladmin.googleapis.com",
    "datamigration.googleapis.com",
    "secretmanager.googleapis.com",
    "compute.googleapis.com",
    "vpcaccess.googleapis.com",
    "servicenetworking.googleapis.com",
    "redis.googleapis.com",
    "pubsub.googleapis.com",
    "cloudscheduler.googleapis.com",
    "storage.googleapis.com",
    "cloudkms.googleapis.com",
    "binaryauthorization.googleapis.com",
    "containeranalysis.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]
}

resource "google_project_service" "enabled" {
  for_each                   = toset(local.services)
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

# Let freshly-enabled APIs propagate before any resource that depends on them
# (SAs, service identities). Kills the "API has not been used / SERVICE_DISABLED"
# race on a cold project.
resource "time_sleep" "wait_for_apis" {
  depends_on      = [google_project_service.enabled]
  create_duration = "60s"
}
