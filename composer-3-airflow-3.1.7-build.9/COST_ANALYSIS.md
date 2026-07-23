# Monitoring & Alerting Cost Analysis — Airflow 3.1.7

> **Environment:** `composer-3-airflow-3.1.7-build.9`
>
> **Last Updated:** 2026-07-23
>
> **Scope:** This document covers the cost of the **monitoring and alerting layer only** — the resources provisioned by `monitoring.tf`, `logging.tf`, and `pubsub.tf`. It does **not** cover the cost of Cloud Composer itself, BigQuery, or other pipeline infrastructure.
>
> **Pricing Source:** [Google Cloud Observability Pricing](https://cloud.google.com/stackdriver/pricing) and [Pub/Sub Pricing](https://cloud.google.com/pubsub/pricing). All prices are in USD. Always verify against the latest official pricing page, as rates may change.

---

## Resource Inventory

| Resource Type | Count | Source File |
|---|---|---|
| Notification Channels | 1–2 | `monitoring.tf` — Email (always) + Slack (optional) |
| Alerting Policies (metric-based) | 5 | `monitoring.tf` |
| Alerting Policies (log-based metric) | 2 | `logging.tf` |
| Log-Based Metrics | 2 | `logging.tf` |
| Pub/Sub Topics | 1 | `pubsub.tf` |
| Pub/Sub Subscriptions | 1 | `pubsub.tf` |
| **Total Alert Conditions** | **7** | 1 condition per policy |

---

## Cost Breakdown by Service

### 1. Cloud Monitoring — Alerting Policies

Alerting policies are charged **per condition per month**.

| Component | Rate |
|---|---|
| Per condition | **$1.50 / month** |
| Time-series query volume | **$0.35 / 1,000,000 time series** |

#### Policies from `monitoring.tf` (5 policies, 1 condition each)

| # | Policy | Condition Type |
|---|---|---|
| 1 | Failed DAG Runs | `condition_threshold` |
| 2 | Failed Task Instances | `condition_threshold` |
| 3 | Scheduler Heartbeat Missing | `condition_absent` |
| 4 | Worker Pod Evictions | `condition_threshold` |
| 5 | Database Health Degraded | `condition_threshold` |

#### Policies from `logging.tf` (2 policies, 1 condition each)

| # | Policy | Condition Type |
|---|---|---|
| 6 | Error Logs Detected | `condition_threshold` (on log-based metric) |
| 7 | DAG Parse Errors | `condition_threshold` (on log-based metric) |

#### Monthly Alerting Cost

```
7 conditions × $1.50/condition = $10.50 / month
```

> **Time-series volume charges** are negligible for this lab. A single Composer environment with one DAG produces a very small number of time series (well under 1 million). Expect **$0.00** additional from time-series volume.

---

### 2. Cloud Logging — Log-Based Metrics

| Component | Rate | Free Tier |
|---|---|---|
| Log-based metric creation | **Free** | — |
| Log ingestion (underlying) | **$0.50 / GiB** | 50 GiB/project/month |
| Log storage (default retention) | **Free** for first 30 days | — |

#### This Environment's Log-Based Metrics

| Metric Name | Filter | Expected Volume |
|---|---|---|
| `composer_task_errors` | ERROR+ severity logs matching `TASK_FAILURE` JSON pattern | Very low (only on failures) |
| `composer_dag_parse_errors` | ERROR+ severity logs matching DAG parse error patterns | Very low (only on parse errors) |

#### Monthly Log-Based Metric Cost

The metrics themselves are **free to create**. The cost comes from the underlying log ingestion, which is shared across all Cloud Logging usage in the project.

For a learning lab with a single DAG running daily:
- Composer generates roughly **1–5 GiB/month** of logs (well within the 50 GiB free tier)
- **Expected cost: $0.00** (covered by free tier)

> If your project already ingests > 50 GiB/month of logs from other services, the marginal cost of Composer logs is ~$0.50–$2.50/month.

---

### 3. Cloud Monitoring — Notification Channels

| Channel Type | Cost |
|---|---|
| Email | **Free** (included with alerting policies) |
| Slack (webhook) | **Free** (included with alerting policies) |

**Monthly notification channel cost: $0.00**

---

### 4. Cloud Pub/Sub

Pub/Sub pricing is based on **data throughput**, not on the number of topics or subscriptions.

| Component | Rate | Free Tier |
|---|---|---|
| Throughput (publish + deliver) | **$40 / TiB** | 10 GiB/month |
| Message storage (> 24h retention) | Usage-based | First 24h free |
| Minimum message size | 1,000 bytes | — |

#### This Environment's Pub/Sub Resources

| Resource | Configuration |
|---|---|
| Topic: `composer-alerts` | For programmatic alert forwarding |
| Subscription: `{topic}-debug-sub` | Pull subscription, 1-day retention, 7-day auto-expiry |

#### Monthly Pub/Sub Cost

Alert notifications are tiny messages (< 1 KB each) and extremely infrequent. Even with daily DAG failures, the total throughput is measured in **kilobytes per month**.

**Monthly Pub/Sub cost: $0.00** (covered by free tier)

---

## Total Monthly Cost

| Service | Component | Monthly Cost |
|---|---|---|
| Cloud Monitoring | 7 alerting policy conditions | **$10.50** |
| Cloud Monitoring | Time-series volume | ~$0.00 |
| Cloud Monitoring | Notification channels | $0.00 |
| Cloud Logging | Log-based metrics (creation) | $0.00 |
| Cloud Logging | Log ingestion (shared) | $0.00 ¹ |
| Pub/Sub | Topic + subscription throughput | $0.00 |
| | **Total** | **~$10.50 / month** |
| | **Annual** | **~$126.00 / year** |

¹ Assumes project is within the 50 GiB/month free log ingestion tier.

---

## Version-Specific Notes

- This version **does not** use the `severity` field on alert policies (the field is omitted from the Terraform configs). This does **not** affect pricing — it only affects how alerts are visually categorized in the Cloud Monitoring console.
- The SLA feature is **removed** in Airflow 3.x, so SLA-based alerting is not an option in this version.
- `BashOperator` and `PythonOperator` have moved to `providers-standard` in Airflow 3.x, but this has no impact on monitoring costs.

---

## Cost Scaling Considerations

If you adapt this setup for production, costs will scale based on:

| Factor | Impact |
|---|---|
| **More alert policies** | +$1.50/month per additional condition |
| **More Composer environments** | Duplicate the 7 policies per environment (+$10.50/month each) |
| **Higher log volume** (many DAGs, verbose logging) | May exceed 50 GiB free tier → $0.50/GiB after that |
| **High-throughput Pub/Sub** (downstream consumers) | Unlikely to exceed free tier for alerting-only use |

---

## Cost Optimization Tips

1. **Consolidate conditions**: Use multi-condition policies where possible to reduce the per-condition cost.
2. **Tune log filters**: Narrow log-based metric filters to reduce unnecessary log ingestion.
3. **Set log exclusion filters**: Exclude noisy, low-value logs at the project level before they're ingested.
4. **Use the free tier wisely**: The 50 GiB/month log ingestion and 10 GiB/month Pub/Sub free tiers are generous for lab and small production workloads.
5. **Review regularly**: Use the [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator) to estimate costs before scaling.

---

## References

- [Google Cloud Observability Pricing](https://cloud.google.com/stackdriver/pricing)
- [Cloud Monitoring Alerting Pricing](https://cloud.google.com/monitoring/pricing)
- [Cloud Logging Pricing](https://cloud.google.com/logging/pricing)
- [Pub/Sub Pricing](https://cloud.google.com/pubsub/pricing)
- [Google Cloud Pricing Calculator](https://cloud.google.com/products/calculator)
