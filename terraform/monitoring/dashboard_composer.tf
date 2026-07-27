# ---------------------------------------------------------------------------
# dashboard_composer.tf — Cloud Monitoring Dashboard for Composer health
#
# Simplified operational dashboard with 3 sections:
#   1. Health Summary    — Scorecards for at-a-glance status
#   2. Pipeline Health   — DAG runs, task instances, custom errors
#   3. Infrastructure    — Worker resources, DAG parsing
# ---------------------------------------------------------------------------

resource "google_monitoring_dashboard" "composer_operational" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Composer Operational Health — ${var.composer_env_name}"

    mosaicLayout = {
      columns = 48
      tiles = concat(

        # ================================================================
        # SECTION 1: HEALTH SUMMARY — Scorecards (y=0)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 0
            width  = 48
            height = 4
            widget = {
              title = "⚡ Health Summary"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 4
            width  = 16
            height = 4
            widget = {
              title = "Database Health"
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
            xPos   = 16
            yPos   = 4
            width  = 16
            height = 4
            widget = {
              title = "Scheduler Heartbeat"
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
                    label     = "No heartbeat"
                  }
                ]
              }
            }
          },
          {
            xPos   = 32
            yPos   = 4
            width  = 16
            height = 4
            widget = {
              title = "Total DAGs Loaded"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/dagbag_size\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }
            }
          },
          {
            xPos   = 0
            yPos   = 8
            width  = 24
            height = 4
            widget = {
              title = "Active/Queued Tasks"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/unfinished_task_instances\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MAX"
                    }
                  }
                }
                thresholds = [
                  {
                    value     = 50
                    color     = "YELLOW"
                    direction = "ABOVE"
                    label     = "High queue"
                  }
                ]
              }
            }
          },
          {
            xPos   = 24
            yPos   = 8
            width  = 24
            height = 4
            widget = {
              title = "Zombie Task Count"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/scheduler/zombies_killed\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_SUM"
                    }
                  }
                }
                thresholds = [
                  {
                    value     = 1
                    color     = "YELLOW"
                    direction = "ABOVE"
                    label     = "Zombies detected"
                  }
                ]
              }
            }
          },
        ],

        # ================================================================
        # SECTION 2: PIPELINE HEALTH — Charts (y=14)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 14
            width  = 48
            height = 4
            widget = {
              title = "📊 Pipeline Health"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 18
            width  = 24
            height = 8
            widget = {
              title = "DAG Run Status"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_workflow\" AND metric.type = \"composer.googleapis.com/workflow/run_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
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
                  label = "Run count"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 18
            width  = 24
            height = 8
            widget = {
              title = "Task Instance Status"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/finished_task_instance_count\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
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
                  label = "Task count"
                  scale = "LINEAR"
                }
              }
            }
          },
          # Task Errors — full width since this is the most actionable chart
          {
            xPos   = 0
            yPos   = 26
            width  = 48
            height = 8
            widget = {
              title = "Task Errors (Custom Metric)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND metric.type = \"logging.googleapis.com/user/composer_task_errors\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields = [
                            "metric.labels.dag_id",
                            "metric.labels.task_id"
                          ]
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "$${metric.labels.dag_id} / $${metric.labels.task_id}"
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
        # SECTION 3: INFRASTRUCTURE — Worker health & DAG parsing (y=34)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 34
            width  = 48
            height = 4
            widget = {
              title = "🔧 Infrastructure"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 38
            width  = 24
            height = 8
            widget = {
              title = "Worker Pod Evictions"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/worker/pod_eviction_count\""
                        aggregation = {
                          alignmentPeriod  = "900s"
                          perSeriesAligner = "ALIGN_SUM"
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "Evictions"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Eviction count"
                  scale = "LINEAR"
                }
              }
            }
          },
          # Used vs Limit — when lines converge, you're running out of headroom
          {
            xPos   = 24
            yPos   = 38
            width  = 24
            height = 8
            widget = {
              title = "Worker Memory: Used vs Limit"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_workload\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/workload/memory/bytes_used\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_MEAN"
                          crossSeriesReducer = "REDUCE_SUM"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Used"
                  },
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_workload\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/workload/memory/quota\""
                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_MEAN"
                          crossSeriesReducer = "REDUCE_SUM"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Limit"
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
            yPos   = 46
            width  = 24
            height = 8
            widget = {
              title = "DAG Parse Time"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/dag_processing/total_parse_time\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Total parse time"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Seconds"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 46
            width  = 24
            height = 8
            widget = {
              title = "DAG Parse Errors (Custom Metric)"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND metric.type = \"logging.googleapis.com/user/composer_dag_parse_errors\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_SUM"
                        }
                      }
                    }
                    plotType       = "STACKED_BAR"
                    legendTemplate = "Parse errors"
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
      )
    }
  })

  depends_on = [
    google_logging_metric.task_errors,
    google_logging_metric.dag_parse_errors,
  ]
}
