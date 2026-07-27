# ---------------------------------------------------------------------------
# dashboard_cost_storage.tf — Cost & Storage Dashboard
#
# Provides visibility into:
#   1. BigQuery Activity  — Upload activity, stored bytes (daily gauge)
#   2. GCS Buckets        — Request counts, network, stored bytes (daily gauge)
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
            height = 4
            widget = {
              title = "💾 BigQuery Storage"
              text = {
                content = "Storage metrics (stored_bytes, table_count) are daily gauges — select 'Last 7 days' for best visibility. Upload metrics update in real-time."
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 4
            width  = 24
            height = 8
            widget = {
              title = "Uploaded Bytes (Real-Time)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/uploaded_bytes\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
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
                  label = "Bytes"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 4
            width  = 24
            height = 8
            widget = {
              title = "Uploaded Rows (Real-Time)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/uploaded_row_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
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
                  label = "Rows"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 0
            yPos   = 12
            width  = 24
            height = 8
            widget = {
              title = "Total Stored Bytes (Daily Gauge — Use 7d View)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/stored_bytes\""
                        aggregation = {
                          alignmentPeriod    = "86400s"
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
            yPos   = 12
            width  = 24
            height = 8
            widget = {
              title = "Table Count per Dataset (Daily Gauge — Use 7d View)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_dataset\" AND metric.type = \"bigquery.googleapis.com/storage/table_count\""
                        aggregation = {
                          alignmentPeriod    = "86400s"
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
            yPos   = 20
            width  = 48
            height = 8
            widget = {
              title = "Query Bytes Scanned (Real-Time)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"global\" AND metric.type = \"bigquery.googleapis.com/query/scanned_bytes_billed\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_SUM"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Bytes billed"
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
        # SECTION 2: GCS BUCKETS (y=28)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 28
            width  = 48
            height = 4
            widget = {
              title = "🗄️ GCS Buckets"
              text = {
                content = "Storage size and object count are daily gauges — select 'Last 7 days' for best visibility. API requests update in real-time."
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 32
            width  = 24
            height = 8
            widget = {
              title = "API Request Count (Real-Time)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/api/request_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
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
                  label = "Requests"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 32
            width  = 24
            height = 8
            widget = {
              title = "Network Bytes Sent (Real-Time)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/network/sent_bytes_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
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
                  label = "Bytes"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 0
            yPos   = 40
            width  = 24
            height = 8
            widget = {
              title = "Bucket Size (Daily Gauge — Use 7d View)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/storage/total_bytes\""
                        aggregation = {
                          alignmentPeriod    = "86400s"
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
            yPos   = 40
            width  = 24
            height = 8
            widget = {
              title = "Object Count (Daily Gauge — Use 7d View)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"gcs_bucket\" AND metric.type = \"storage.googleapis.com/storage/object_count\""
                        aggregation = {
                          alignmentPeriod    = "86400s"
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
        ],
      )
    }
  })

  depends_on = [
    google_bigquery_dataset.monitoring_reports,
  ]
}
