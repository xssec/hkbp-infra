variable "project_id" {
  description = "GCP project ID (e.g. hkbp-prod). Must already exist."
  type        = string
}

variable "region" {
  description = "Primary region. Jakarta for .id latency/residency."
  type        = string
  default     = "asia-southeast2"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "hkbp"
}

variable "subnet_main_cidr" {
  description = "CIDR for the primary workload subnet."
  type        = string
  default     = "10.10.0.0/20"
}

variable "subnet_run_cidr" {
  description = "CIDR reserved for Cloud Run Direct VPC egress."
  type        = string
  default     = "10.10.16.0/24"
}
