# Phase 0 — HKBP GCP Landing Zone (Terraform)

Provisions the secure foundation everything else (Phases 1–8) builds on:

| File | Provisions |
|---|---|
| `bootstrap.sh` | GCS remote-state bucket (versioned, private) + `backend.hcl` |
| `apis.tf` | All required Google APIs |
| `network.tf` | Custom VPC, 2 subnets, Private Service Access (Cloud SQL), Cloud NAT, deny-by-default firewall, IAP SSH |
| `iam.tf` | Per-service runtime SAs (least priv) + CI/CD deployer SA |
| `kms.tf` | CMEK keyring + keys (sql/storage/artifacts/secrets), service-agent grants, 90d rotation |
| `artifact_registry.tf` | CMEK Docker repo, immutable tags, puller bindings |
| `secrets.tf` | Secret Manager containers (CMEK) + scoped accessors |
| `storage.tf` | Private media bucket (CMEK, versioned, lifecycle) |

## Prerequisites

- `gcloud` authenticated with an identity that has, at project level: `roles/owner` or the combination of `resourcemanager.projectIamAdmin`, `compute.networkAdmin`, `iam.serviceAccountAdmin`, `cloudkms.admin`, `serviceusage.serviceUsageAdmin`.
- The **project already exists** and billing is linked. (Project/billing creation needs org-level perms and is intentionally out of scope — keeps this module runnable by a project-scoped identity.)
- Terraform >= 1.6.

## Apply order

```bash
# 1. One-time: create the state bucket + backend.hcl
chmod +x bootstrap.sh
./bootstrap.sh hkbp-prod asia-southeast2

# 2. Init with remote backend
terraform init -backend-config=backend.hcl

# 3. Configure vars
cp terraform.tfvars.example terraform.tfvars   # edit project_id

# 4. Review + apply
terraform plan
terraform apply
```

First `apply` enables APIs; if you hit a transient "API not yet active" race, re-run `apply` once — `google_project_service` dependencies usually prevent this but propagation can lag.

## Populate secret values (out-of-band — never in tfvars)

```bash
echo -n 'CHANGE_ME' | gcloud secrets versions add db-pass            --data-file=-
echo -n 'CHANGE_ME' | gcloud secrets versions add app-key            --data-file=-
echo -n 'CHANGE_ME' | gcloud secrets versions add jwt-signing-key    --data-file=-
# ...etc for db-migration-pass, cf-origin-cert, fcm-server-key
```

## What the next phases consume (terraform outputs)

```bash
terraform output artifact_registry          # -> cloudbuild.yaml image path (Phase 2)
terraform output runtime_service_accounts   # -> gcloud run deploy --service-account (Phase 4)
terraform output deployer_service_account   # -> Cloud Build trigger identity (Phase 2)
terraform output subnet_run                 # -> gcloud run deploy --subnet (Direct VPC egress)
terraform output kms_keys                    # -> Cloud SQL/bucket CMEK (Phase 3)
terraform output psa_connection             # -> Cloud SQL private IP depends on this (Phase 3)
```

## Security posture baked in

- **No public ingress at the VPC** — default-deny firewall; all inbound arrives via the External HTTPS LB (Phase 5). IAP-only SSH (`35.235.240.0/20`) for break-glass, no `0.0.0.0/0:22`.
- **Private-only data plane** — PSA peering ready for Cloud SQL private IP; NAT for egress, no inbound NAT.
- **CMEK everywhere** — SQL, Storage, Artifact Registry, Secret Manager encrypted with your KMS keys; `prevent_destroy` on keys so state ops can't orphan ciphertext.
- **Least-privilege identities** — one SA per service, scoped roles only; separate deployer SA with `actAs` on runtime SAs; no SA keys (use WIF/built-in identity).
- **Immutable image tags** + project-level vuln scanning (Container Analysis).
- **Flow logs** on the main subnet; **NAT error logging** for egress troubleshooting.

## Teardown

`terraform destroy` leaves APIs enabled (`disable_on_destroy=false`) and KMS keys intact (`prevent_destroy`). Remove those manually only if you're decommissioning the whole project.
