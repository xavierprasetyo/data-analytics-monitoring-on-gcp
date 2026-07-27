# ---------------------------------------------------------------------------
# dashboard_pipeline_health.tf — Pipeline Health Dashboard
#
# Cross-service dashboard showing:
#   1. Datastream Health — Event throughput, replication lag
#   2. BigQuery Jobs    — Slot utilization, job counts, scheduled query status
#   3. Composer Summary — Scorecards for scheduler, webserver, database
# ---------------------------------------------------------------------------

resource "google_monitoring_dashboard" "pipeline_health" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Pipeline Health — Cross-Service Overview"

    mosaicLayout = {
      columns = 48
      tiles = concat(

        # ================================================================
        # SECTION 1: DATASTREAM HEALTH (y=0)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 0
            width  = 48
            height = 4
            widget = {
              title = "🔄 Datastream Health"
              text = {
                content = ""
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
              title = "Stream Event Throughput"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"datastream.googleapis.com/stream/event_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_RATE"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["resource.labels.stream_id"]
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "$${resource.labels.stream_id}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Events/sec"
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
              title = "Replication Lag"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"datastream.googleapis.com/stream/freshness\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_MAX"
                          crossSeriesReducer = "REDUCE_MAX"
                          groupByFields      = ["resource.labels.stream_id"]
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "$${resource.labels.stream_id}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Latency (seconds)"
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
              title = "Unsupported Events"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"datastream.googleapis.com/stream/unsupported_event_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["resource.labels.stream_id"]
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "$${resource.labels.stream_id}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Count"
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
              title = "Throughput (Bytes)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"datastream.googleapis.com/Stream\" AND metric.type = \"datastream.googleapis.com/stream/bytes_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_RATE"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["resource.labels.stream_id"]
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "$${resource.labels.stream_id}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Bytes/sec"
                  scale = "LINEAR"
                }
              }
            }
          },
        ],

        # ================================================================
        # SECTION 2: BIGQUERY JOBS (y=18)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 20
            width  = 48
            height = 4
            widget = {
              title = "📊 BigQuery Jobs"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 24
            width  = 24
            height = 8
            widget = {
              title = "Slot Utilization"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_project\" AND metric.type = \"bigquery.googleapis.com/slots/total_available\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Available slots"
                  },
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_project\" AND metric.type = \"bigquery.googleapis.com/slots/allocated_for_project\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Allocated slots"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Slots"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 24
            width  = 24
            height = 8
            widget = {
              title = "Job Count by State"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"bigquery_project\" AND metric.type = \"bigquery.googleapis.com/job/num_in_flight\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_MEAN"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = ["metric.labels.state"]
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "$${metric.labels.state}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Job count"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 0
            yPos   = 32
            width  = 24
            height = 8
            widget = {
              title = "Bytes Processed per Job"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"global\" AND metric.type = \"bigquery.googleapis.com/query/scanned_bytes\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_SUM"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Bytes processed"
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
            yPos   = 32
            width  = 24
            height = 8
            widget = {
              title = "Scheduled Query Errors"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"global\" AND metric.type = \"logging.googleapis.com/user/bq_scheduled_query_failures\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_SUM"
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "Failures"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Error count"
                  scale = "LINEAR"
                }
              }
            }
          },
        ],

        # ================================================================
        # SECTION 3: COMPOSER SUMMARY (y=36)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 40
            width  = 48
            height = 4
            widget = {
              title = "🎵 Composer Summary"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 44
            width  = 12
            height = 4
            widget = {
              title = "Scheduler"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/scheduler_heartbeat_count\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
                thresholds = [
                  {
                    value     = 1
                    color     = "RED"
                    direction = "BELOW"
                    label     = "Down"
                  }
                ]
              }
            }
          },
          {
            xPos   = 12
            yPos   = 44
            width  = 12
            height = 4
            widget = {
              title = "Webserver"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/web_server/health\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_FRACTION_TRUE"
                    }
                  }
                }
                thresholds = [
                  {
                    value     = 0.9
                    color     = "RED"
                    direction = "BELOW"
                    label     = "Unhealthy"
                  }
                ]
              }
            }
          },
          {
            xPos   = 24
            yPos   = 44
            width  = 12
            height = 4
            widget = {
              title = "Database"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/database_health\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_FRACTION_TRUE"
                    }
                  }
                }
                thresholds = [
                  {
                    value     = 0.9
                    color     = "RED"
                    direction = "BELOW"
                    label     = "Unhealthy"
                  }
                ]
              }
            }
          },
          {
            xPos   = 36
            yPos   = 44
            width  = 12
            height = 4
            widget = {
              title = "Failed DAG Runs (Total)"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesQueryLanguage = "fetch cloud_composer_workflow | metric 'composer.googleapis.com/workflow/run_count' | filter (metric.state == 'failed') | align delta(1h) | every 1h | group_by [], [value_sum: sum(val())]"
                }
                thresholds = [
                  {
                    value     = 1
                    color     = "RED"
                    direction = "ABOVE"
                    label     = "Failures!"
                  }
                ]
              }
            }
          },
          {
            xPos   = 0
            yPos   = 48
            width  = 48
            height = 8
            widget = {
              title = "Failed DAG Runs by Workflow (Top 10)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesQueryLanguage = "fetch cloud_composer_workflow | metric 'composer.googleapis.com/workflow/run_count' | filter (metric.state == 'failed') | align delta(5m) | every 5m | group_by [resource.workflow_name], [value_sum: sum(val())] | top 10"
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "$${resource.labels.workflow_name}"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Failed runs"
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
    google_logging_metric.bq_scheduled_query_failures,
  ]
}
