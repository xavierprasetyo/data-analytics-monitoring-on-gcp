# ---------------------------------------------------------------------------
# dashboard_cost_storage.tf — Cost & Storage Dashboard
#
# Provides visibility into:
#   1. BigQuery Storage  — Per-dataset size (logical/physical), billing model
#   2. GCS Buckets       — Per-bucket size, object count, trends
# ---------------------------------------------------------------------------

resource "google_monitoring_dashboard" "cost_storage" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Cost & Storage — BigQuery + GCS"

    mosaicLayout = {
      columns = 48
      tiles = concat(

        # ================================================================
        # SECTION 1: BIGQUERY STORAGE (y=0)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 0
            width  = 48
            height = 2
            widget = {
              title = "💾 BigQuery Storage"
              text = {
                content = "Storage data sourced from daily INFORMATION_SCHEMA.TABLE_STORAGE scheduled query → ${var.bq_reports_dataset_id}.bq_storage_comparison"
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 2
            width  = 24
            height = 8
            widget = {
              title = "Total Stored Bytes (All Datasets)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/stored_bytes\""
                        aggregation = {
                          alignmentPeriod    = "3600s"
                          perSeriesAligner   = "ALIGN_MEAN"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["resource.labels.dataset_id"]
                        }
                      }
                    }
                    plotType       = "STACKED_AREA"
                    legendTemplate = "$${resource.labels.dataset_id}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Bytes"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 2
            width  = 24
            height = 8
            widget = {
              title = "Table Count per Dataset"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/table_count\""
                        aggregation = {
                          alignmentPeriod    = "3600s"
                          perSeriesAligner   = "ALIGN_MEAN"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["resource.labels.dataset_id"]
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "$${resource.labels.dataset_id}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Tables"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 0
            yPos   = 10
            width  = 48
            height = 8
            widget = {
              title = "Storage Growth Trend"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/stored_bytes\""
                        aggregation = {
                          alignmentPeriod  = "86400s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "$${resource.labels.dataset_id}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Bytes"
                  scale = "LINEAR"
                }
              }
            }
          },
        ],

        # ================================================================
        # SECTION 2: GCS BUCKETS (y=18)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 18
            width  = 48
            height = 2
            widget = {
              title = "🗄️ GCS Buckets"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 20
            width  = 24
            height = 8
            widget = {
              title = "Bucket Size (Total Bytes)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/storage/total_bytes\""
                        aggregation = {
                          alignmentPeriod    = "3600s"
                          perSeriesAligner   = "ALIGN_MEAN"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["resource.labels.bucket_name"]
                        }
                      }
                    }
                    plotType       = "STACKED_AREA"
                    legendTemplate = "$${resource.labels.bucket_name}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Bytes"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 20
            width  = 24
            height = 8
            widget = {
              title = "Object Count per Bucket"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/storage/object_count\""
                        aggregation = {
                          alignmentPeriod    = "3600s"
                          perSeriesAligner   = "ALIGN_MEAN"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["resource.labels.bucket_name"]
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "$${resource.labels.bucket_name}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Objects"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 0
            yPos   = 28
            width  = 48
            height = 8
            widget = {
              title = "GCS Storage Growth Trend"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/storage/total_bytes\""
                        aggregation = {
                          alignmentPeriod  = "86400s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "$${resource.labels.bucket_name}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Bytes"
                  scale = "LINEAR"
                }
              }
            }
          },
        ],
      )
    }
  })

  depends_on = [
    google_bigquery_dataset.monitoring_reports,
  ]
}
