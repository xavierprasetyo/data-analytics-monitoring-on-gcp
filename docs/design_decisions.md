# Design Decisions

This document traces key technical decisions made during the development of the monitoring and alerting framework.

---

## 1. Notebook Monitoring: Composer DAG Wrapper vs Cloud Function

**Decision**: Use a Composer DAG wrapper (`notebook_executor.py`) to orchestrate BQ/Colab Enterprise notebooks.

### Problem Statement

BQ Scheduled Notebooks have 3 pain points:
1. **No alerting** — No built-in option to send Slack/email notifications on failure
2. **Checking logs is painful** — Notebook output goes to GCS; engineers must manually download and inspect
3. **Can't rerun with same params** — BQ Console "Run now" uses current parameters, not the failed run's rendered parameters

### Options Evaluated

| Criteria | Cloud Function | Composer DAG Wrapper |
|---|---|---|
| **Effort** | ~2-3 hours | ~3-4 hours |
| **Cost** | Near-zero (Cloud Functions free tier) | Uses existing Composer capacity |
| **Maintainability** | Self-contained, separate codebase | Centralized in Composer alongside other DAGs |
| **Alerting** | ✅ Rich Slack/email via parsed audit logs | ✅ Existing global failure listener |
| **Log visibility** | ✅ Can fetch output from GCS and include in alert | ✅ Logs visible in Airflow UI via XCom |
| **Rerun with same params** | ❌ Requires custom rerun API endpoint or manual `gcloud` command | ✅ Native: "Clear task" in Airflow UI |
| **Coupling** | Independent of Composer | Depends on Composer being healthy |

### Why We Chose Composer DAG Wrapper

1. **Solves all 3 pain points** — The only approach that natively handles alerting, log visibility, AND rerun with the same parameters
2. **Lower total complexity** — Despite slightly more initial effort, the Cloud Function approach would need a separate rerun mechanism (another Cloud Function or manual API calls) to match the Composer wrapper's capability
3. **Centralized operations** — Engineers already use the Airflow UI for other DAGs; notebook executions appear alongside them
4. **Compute stays external** — Composer only triggers the execution; actual notebook compute runs on Colab Enterprise/Vertex AI infrastructure

### When to Use Cloud Function Instead

The Cloud Function approach is better when:
- **No Composer available** — Teams that don't use Cloud Composer/Airflow
- **Minimal footprint** — If only alerting is needed (pain point #1) and rerun/log visibility are acceptable as-is
- **Decoupled architecture** — If Composer downtime should not affect notebook monitoring

### Cloud Function Implementation Sketch

For teams choosing the Cloud Function approach:

```python
# Triggered by EventArc on notebook execution audit logs
def on_notebook_execution(event):
    # 1. Parse audit log → extract job_id, status, notebook name
    # 2. If status == FAILED:
    #    a. Fetch notebook output from GCS (output_uri from job metadata)
    #    b. Parse .ipynb JSON → find cells with error output_type
    #    c. Extract traceback from error cells
    #    d. Send Slack/email with: notebook name, error cell, traceback
    #    e. Include pre-built gcloud rerun command:
    #       gcloud ai notebook-execution-jobs create \
    #         --notebook-source=gs://... \
    #         --output-uri=gs://... \
    #         --project=...
```

---

## 2. Notebook Alert Policy: Dedicated vs Shared

**Decision**: Reuse existing Composer `Error Logs Detected` alert policy.

### Rationale

Since notebooks run as Composer DAG tasks, the existing global failure listener automatically captures failures with full context:
- `dag_id = notebook_executor`
- `task_id = run_{notebook_name}`
- `exception = <error details>`

A dedicated notebook alert policy would use the exact same log data and provide no additional error detail — only different routing (e.g., separate Slack channel).

### When to Create a Dedicated Alert

Consider a dedicated notebook alert policy if:
- Notebook failures need to be routed to a **different notification channel** (e.g., `#notebook-alerts` instead of `#data-alerts`)
- Notebook failures need a **different severity** than general Composer failures

---

## 3. Two Terraform Directories: Simulation vs Monitoring

**Decision**: Split Terraform into `terraform/simulation/` (lab-specific) and `terraform/monitoring/` (reusable).

### Rationale

The monitoring module should be independently deployable against any existing GCP environment. By separating it from simulation infrastructure:
1. **Reusability** — Any team can `git clone`, fill in `terraform.tfvars`, and `terraform apply` against their own project
2. **Zero coupling** — The monitoring module has no `depends_on` references to simulation resources
3. **Independent lifecycle** — Simulation can be destroyed/recreated without affecting monitoring
4. **Clear ownership** — Simulation is "throwaway lab"; monitoring is "production-grade tooling"

### Trade-offs

- **State management** — Two separate `terraform.tfstate` files to manage
- **Variable duplication** — Some values (project_id, region) appear in both tfvars
- **Deployment order** — Simulation must be applied first to generate outputs for monitoring
