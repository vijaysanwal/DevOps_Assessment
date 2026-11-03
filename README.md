# DevOps Assessment — Terraform + Database Reliability

A plan-only AWS infrastructure design plus a fully runnable local PostgreSQL backup/restore exercise.

## Contents

- `infra/modules`: reusable VPC/network, ECS/Fargate + ALB, and RDS modules.
- `infra/envs/dev` and `infra/envs/prod`: independent environment inputs and S3 backend configuration examples.
- `database`: PostgreSQL 16 Docker Compose setup, migration, and deterministic seed data.
- `scripts`: timestamped custom-format backup and safe restore into a new database.
- `.github/workflows/terraform.yml`: PR validation and plan-only workflow for both environments.

## Architecture

Internet → public Application Load Balancer → ECS/Fargate tasks in private subnets → private RDS PostgreSQL.

The ALB security group accepts HTTP on port 80 from the internet. The ECS task security group accepts the application port only from the ALB security group. The RDS security group accepts PostgreSQL port 5432 only from the ECS task security group. RDS is not publicly accessible.

The network module creates two public and two private subnets across available AZs, an Internet Gateway, and NAT Gateway routing for private workloads. Dev uses one NAT Gateway to reduce cost; prod uses one NAT Gateway per public subnet for AZ-level egress resilience.

The sample ECS workload uses the public `nginx:1.27-alpine` image as a placeholder. Replace it with an image in ECR for a real application. The task execution role is limited to the AWS-managed ECS task execution policy. Container logs go to CloudWatch Logs.

## Prerequisites

- Docker Engine and Docker Compose v2
- Terraform CLI >= 1.5 for infrastructure validation
- AWS CLI only if configuring a real remote state backend or deploying (deployment is not required)
- Bash

## Local database: start and verify

From the repository root:

```bash
docker compose -f database/docker-compose.yml up -d
docker compose -f database/docker-compose.yml ps
```

The container runs the SQL files mounted into `/docker-entrypoint-initdb.d` only when the PostgreSQL data volume is first initialized.

Verify tables and row counts:

```bash
docker compose -f database/docker-compose.yml exec db \
  psql -U assessment -d assessment -c "\\dt"

docker compose -f database/docker-compose.yml exec db \
  psql -U assessment -d assessment -c "SELECT COUNT(*) AS bookings FROM hotel_bookings;"

docker compose -f database/docker-compose.yml exec db \
  psql -U assessment -d assessment -c "SELECT COUNT(*) AS events FROM booking_events;"
```

Expected: 150 bookings and event rows for a subset of bookings.

To rerun initialization from a clean local volume (this deletes local database data):

```bash
docker compose -f database/docker-compose.yml down -v
docker compose -f database/docker-compose.yml up -d
```

Local credentials are intentionally simple for this isolated exercise. Do not use them outside local development. Override them with environment variables if needed.

## Query optimization and index rationale

Assessment query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

Migration creates:

```sql
CREATE INDEX idx_hotel_bookings_city_created_org_status
ON hotel_bookings (city, created_at, org_id, status)
INCLUDE (amount);
```

Why this order:
- `city` is an equality predicate, so it is first.
- `created_at` is a range predicate, so it follows the equality key.
- `org_id` and `status` are included as subsequent key columns to help grouping/order access.
- `amount` is included as a non-key column, making an index-only scan possible when visibility-map conditions permit.

The best index depends on table size, cardinality, and workload. Verify with `EXPLAIN (ANALYZE, BUFFERS)` after the table is large enough; a sequential scan can be optimal for a small table.

Run:

```bash
docker compose -f database/docker-compose.yml exec db psql -U assessment -d assessment
```

Then paste:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

## Backup and restore verification

Create a timestamped PostgreSQL custom-format dump:

```bash
chmod +x scripts/*.sh
./scripts/backup.sh
```

The dump is saved under `database/backups/`. Backups are intentionally git-ignored.

Restore into a fresh database. The default target name is timestamped:

```bash
./scripts/restore.sh
```

Or provide an explicit target database and backup path:

```bash
./scripts/restore.sh assessment_restore_test database/backups/assessment_YYYYMMDDTHHMMSSZ.dump
```

Verify the restored data:

```bash
docker compose -f database/docker-compose.yml exec db \
  psql -U assessment -d assessment_restore_test \
  -c "SELECT COUNT(*) FROM hotel_bookings;"

docker compose -f database/docker-compose.yml exec db \
  psql -U assessment -d assessment_restore_test \
  -c "SELECT COUNT(*) FROM booking_events;"
```

The restored booking count should match the source database (150 with the supplied seed). The restore script creates a new target database and does not drop or overwrite the source database.

## Terraform: format, init, validate, plan

No AWS deployment is required. The GitHub Actions workflow uses `terraform init -backend=false`, validates each environment, and runs `terraform plan -refresh=false`. A placeholder password is used only for this plan-only workflow.

Run locally for Dev:

```bash
cd infra/envs/dev
terraform fmt -check -recursive ../../..
terraform init -backend=false
export TF_VAR_db_password='local-plan-only-password-change-me'
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars
```

Repeat from `infra/envs/prod`.

### Remote backend configuration

Each environment contains `backend.hcl.example` with a distinct S3 key. For a real shared backend, first create an encrypted, versioned S3 bucket and enable S3 lockfile support. Copy the example to `backend.hcl`, replace the bucket name, then initialize:

```bash
cp backend.hcl.example backend.hcl
# Edit backend.hcl with your globally unique state bucket.
terraform init -backend-config=backend.hcl
```

The S3 backend uses `use_lockfile = true` for state locking. Keep state bucket access restricted and enable versioning, encryption, and public-access blocking. Never commit backend credentials or state files. The S3 bucket must exist before `terraform init`.

### Environment differences

| Setting | Dev | Prod |
|---|---:|---:|
| ECS CPU / memory | 256 / 512 MiB | 1024 / 2048 MiB |
| Desired ECS tasks | 1 | 3 |
| RDS instance | db.t4g.micro | db.t4g.medium |
| RDS allocated storage | 20 GiB | 100 GiB |
| Backup retention | 1 day | 14 days |
| Deletion protection | false | true |
| NAT gateways | 1 | 1 per public subnet |
| Multi-AZ RDS | false | true |

For this assessment, `multi_az` is tied to the prod deletion-protection setting as a simple environment distinction. In a production codebase, these should be independent variables.

### Security and operational notes

- Do not commit database passwords. Supply `TF_VAR_db_password` through a secure CI secret or secret manager.
- Terraform state can contain sensitive values. Restrict access and enable S3 versioning and encryption.
- The example uses HTTP on the ALB to keep the assessment self-contained. Production should terminate HTTPS with ACM and redirect HTTP to HTTPS.
- For production, consider WAF, VPC endpoints, ECS autoscaling, alarms, RDS enhanced monitoring, deletion safeguards, and a dedicated KMS key.
- The RDS password is passed as a Terraform variable for assessment simplicity. A production design should use Secrets Manager-managed credentials and avoid exposing secrets in plans/state where possible.
- NAT Gateways and RDS resources incur AWS charges if deployed. This repository is intended for plan-only review.

## GitHub submission

1. Create a public GitHub repository, for example `devops-assessment`.
2. Copy the contents of this project into the repository.
3. Review `.gitignore`; never commit `.tfstate`, `.dump`, secrets, or real backend config.
4. Push the code:

```bash
git init
git add .
git commit -m "Add Terraform and PostgreSQL reliability assessment"
git branch -M main
git remote add origin https://github.com/<your-username>/devops-assessment.git
git push -u origin main
```

5. Open a pull request to trigger Terraform validation for both environments.
6. Share the GitHub repository URL with the recruiter.

## Reviewer quick run

```bash
docker compose -f database/docker-compose.yml up -d
./scripts/backup.sh
./scripts/restore.sh
```

Terraform validation (from each environment directory):

```bash
terraform fmt -check -recursive ../../..
terraform init -backend=false
terraform validate
terraform plan -refresh=false -var-file=terraform.tfvars
```
