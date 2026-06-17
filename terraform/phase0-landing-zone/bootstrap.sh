#!/usr/bin/env bash
# Phase 0 bootstrap — solves the chicken/egg of the Terraform state bucket.
# Run ONCE per project, before `terraform init`. Idempotent.
set -euo pipefail

PROJECT_ID="${1:?usage: ./bootstrap.sh <project_id> [region]}"
REGION="${2:-asia-southeast2}"
STATE_BUCKET="gs://${PROJECT_ID}-tfstate"

echo "[*] Setting active project: ${PROJECT_ID}"
gcloud config set project "${PROJECT_ID}"

echo "[*] Enabling minimal APIs needed to create the state bucket"
gcloud services enable storage.googleapis.com cloudresourcemanager.googleapis.com

echo "[*] Creating versioned, uniform-access state bucket: ${STATE_BUCKET}"
if ! gcloud storage buckets describe "${STATE_BUCKET}" >/dev/null 2>&1; then
  gcloud storage buckets create "${STATE_BUCKET}" \
    --location="${REGION}" \
    --uniform-bucket-level-access \
    --public-access-prevention
  gcloud storage buckets update "${STATE_BUCKET}" --versioning
else
  echo "    bucket already exists, skipping"
fi

echo "[*] Writing backend.hcl"
cat > backend.hcl <<EOF
bucket = "${PROJECT_ID}-tfstate"
prefix = "phase0-landing-zone"
EOF

cat <<EOF

[✓] Bootstrap complete.

Next:
  terraform init -backend-config=backend.hcl
  terraform plan  -var="project_id=${PROJECT_ID}"
  terraform apply -var="project_id=${PROJECT_ID}"

State bucket is versioned (recover prior state) and private (PAP enforced).
EOF
