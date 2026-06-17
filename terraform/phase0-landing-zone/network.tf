# ---------------------------------------------------------------------------
# Custom VPC (no auto subnets — explicit ranges only)
# ---------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                            = "${var.name_prefix}-vpc"
  auto_create_subnetworks         = false
  routing_mode                    = "REGIONAL"
  delete_default_routes_on_create = false
  depends_on                      = [google_project_service.enabled]
}

# Primary workload subnet. Cloud Run uses this for Direct VPC egress.
resource "google_compute_subnetwork" "main" {
  name                     = "${var.name_prefix}-main"
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = var.subnet_main_cidr
  private_ip_google_access  = true # reach Google APIs without external IP

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Dedicated subnet reserved for Cloud Run Direct VPC egress.
# Keeping Run egress in its own range simplifies firewall scoping & IP planning.
resource "google_compute_subnetwork" "run" {
  name                     = "${var.name_prefix}-run"
  network                  = google_compute_network.vpc.id
  region                   = var.region
  ip_cidr_range            = var.subnet_run_cidr
  private_ip_google_access  = true
}

# ---------------------------------------------------------------------------
# Private Service Access — required for Cloud SQL PRIVATE IP
# ---------------------------------------------------------------------------
resource "google_compute_global_address" "psa_range" {
  name          = "${var.name_prefix}-psa"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
  depends_on              = [google_project_service.enabled]
}

# Export custom routes to the peered (Cloud SQL) network so private connectivity works.
resource "google_compute_network_peering_routes_config" "psa_routes" {
  peering              = google_service_networking_connection.psa.peering
  network              = google_compute_network.vpc.name
  import_custom_routes = true
  export_custom_routes = true
}

# ---------------------------------------------------------------------------
# Cloud NAT — outbound internet for private workloads (FCM/APNs, Cloudflare API,
# composer/pip/npm pulls in Cloud Build). No inbound; ingress is via the LB only.
# ---------------------------------------------------------------------------
resource "google_compute_router" "router" {
  name    = "${var.name_prefix}-router"
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.name_prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ---------------------------------------------------------------------------
# Firewall — deny-by-default posture. Internal east-west + IAP SSH only.
# All public ingress terminates at the External HTTPS LB (Phase 5), not here.
# ---------------------------------------------------------------------------
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "${var.name_prefix}-deny-all-ingress"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 65534
  deny { protocol = "all" }
  source_ranges = ["0.0.0.0/0"]
  log_config { metadata = "INCLUDE_ALL_METADATA" }
}

resource "google_compute_firewall" "allow_internal" {
  name      = "${var.name_prefix}-allow-internal"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000
  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }
  source_ranges = [var.subnet_main_cidr, var.subnet_run_cidr]
}

# IAP TCP forwarding range — lets you SSH to any future debug/GCE box WITHOUT a
# public IP (break-glass), instead of exposing 22 to the world.
resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "${var.name_prefix}-allow-iap-ssh"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"
  priority  = 1000
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"] # Google IAP range
  target_tags   = ["iap-ssh"]
}

# ---------------------------------------------------------------------------
# OPTIONAL: Serverless VPC Access connector.
# Direct VPC egress (subnet above) is preferred & cheaper. Uncomment only if a
# workload requires the legacy connector path.
# ---------------------------------------------------------------------------
# resource "google_vpc_access_connector" "connector" {
#   name          = "${var.name_prefix}-conn"
#   region        = var.region
#   subnet { name = google_compute_subnetwork.run.name }
#   machine_type  = "e2-micro"
#   min_instances = 2
#   max_instances = 4
# }
