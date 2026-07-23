# Cloud Composer Monitoring & Alerting — Learning Lab

A hands-on project to learn how to set up native GCP monitoring and alerting for Cloud Composer pipelines. All infrastructure is managed with **Terraform**.

This repository contains **two implementations** targeting different Composer image versions. Each is a self-contained, fully working project.

---

## Versions

| Directory | Composer Image | Airflow Version | Status |
|---|---|---|---|
| [`composer-3-airflow-2.11.1-build.5/`](composer-3-airflow-2.11.1-build.5/) | `composer-3-airflow-2.11.1-build.5` | Airflow 2.11.1 | **Active** |
| [`composer-3-airflow-3.1.7-build.9/`](composer-3-airflow-3.1.7-build.9/) | `composer-3-airflow-3.1.7-build.9` | Airflow 3.1.7 | Archived |

---

## Key Differences Between Versions

| Feature | Airflow 2.11.1 | Airflow 3.1.7 |
|---|---|---|
| `execution_date` | Deprecated but available | Removed |
| `logical_date` | Available (preferred) | Required |
| `schedule` param | Supported (since 2.4) | Primary |
| SLA feature | ✅ Available | ❌ Removed |
| Listener API (`hookimpl`) | Available (since 2.6) | Available |
| `BashOperator` / `PythonOperator` | Core package | Moved to `providers-standard` |

---

## Quick Start

1. **Pick a version** — `cd` into the version directory matching your Composer environment
2. **Read the version's README** — Each directory has its own complete README with setup instructions
3. **Configure** — Edit `terraform/terraform.tfvars` with your project details
4. **Deploy** — `terraform apply` → `bash scripts/deploy_dags.sh`

```bash
# Example: using the Airflow 2.11.1 version
cd composer-3-airflow-2.11.1-build.5
cat README.md   # Full instructions inside
```

---

## What's Inside Each Version

```
composer-3-airflow-X.Y.Z-build.N/
├── README.md                          # Version-specific instructions & gotchas
├── terraform/                         # Full IaC: Composer, BigQuery, Monitoring, Logging, Pub/Sub
├── dags/                              # Sample ELT pipeline DAG + callbacks
├── plugins/                           # Global failure listener (covers ALL DAGs)
├── scripts/                           # Deployment & simulation scripts
├── sql/                               # BigQuery staging & validation queries
├── monitoring/                        # Shell script alternatives to Terraform
└── tests/                             # Failure trigger scripts
```
