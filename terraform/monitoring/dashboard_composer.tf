# ---------------------------------------------------------------------------
# dashboard_composer.tf — Cloud Monitoring Dashboard for Composer health
#
# Migrated from the original dashboard.tf. This is the detailed operational
# dashboard with 4 sections:
#   1. Health Summary    — Scorecards for at-a-glance status
#   2. Pipeline Health   — DAG runs, task instances, durations, custom errors
#   3. Infra Health      — Scheduler, database, webserver, workers
#   4. Capacity/Parsing  — Queue depth, DAG bag size, parse time, parse errors
# ---------------------------------------------------------------------------

resource "google_monitoring_dashboard" "composer_operational" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Composer Operational Health — ${var.composer_env_name}"

    mosaicLayout = {
      columns = 48
      tiles = concat(

        # ================================================================
        # SECTION 1: HEALTH SUMMARY — Scorecards (row 0, y=0)
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
            width  = 12
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
            xPos   = 12
            yPos   = 4
            width  = 12
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
            xPos   = 24
            yPos   = 4
            width  = 12
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
            xPos   = 36
            yPos   = 4
            width  = 12
            height = 4
            widget = {
              title = "Active/Queued Tasks"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/unfinished_task_instances\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
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
        ],

        # ================================================================
        # SECTION 2: PIPELINE HEALTH — Charts (y=6)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 8
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
            yPos   = 12
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
            yPos   = 12
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
          {
            xPos   = 0
            yPos   = 20
            width  = 24
            height = 8
            widget = {
              title = "Task Duration"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_workflow\" AND metric.type = \"composer.googleapis.com/workflow/task/run_duration\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_PERCENTILE_50"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "p50"
                  },
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_workflow\" AND metric.type = \"composer.googleapis.com/workflow/task/run_duration\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_PERCENTILE_95"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "p95"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Duration (seconds)"
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
        # SECTION 3: INFRASTRUCTURE HEALTH — Charts (y=24)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 28
            width  = 48
            height = 4
            widget = {
              title = "🔧 Infrastructure Health"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 32
            width  = 12
            height = 8
            widget = {
              title = "Scheduler Heartbeat"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/scheduler_heartbeat_count\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_SUM"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Heartbeats"
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
            xPos   = 12
            yPos   = 32
            width  = 12
            height = 8
            widget = {
              title = "Database Health"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/database_health\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_FRACTION_TRUE"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Health fraction"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Health (0-1)"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 24
            yPos   = 32
            width  = 12
            height = 8
            widget = {
              title = "Webserver Health"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/web_server/health\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_FRACTION_TRUE"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Health fraction"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "Health (0-1)"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 36
            yPos   = 32
            width  = 12
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
          {
            xPos   = 0
            yPos   = 40
            width  = 24
            height = 8
            widget = {
              title = "Worker CPU Usage"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/workloads_cpu_quota_usage\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_RATE"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "CPU usage rate"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "CPU (cores/sec)"
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
              title = "Worker Memory Usage"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/workload/memory/bytes_used\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Memory used"
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
        # SECTION 4: CAPACITY & PARSING — Charts (y=42)
        # ================================================================

        [
          {
            xPos   = 0
            yPos   = 48
            width  = 48
            height = 4
            widget = {
              title = "📦 Capacity & Parsing"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },
          {
            xPos   = 0
            yPos   = 52
            width  = 24
            height = 8
            widget = {
              title = "Active/Queued Tasks"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/unfinished_task_instances\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "Tasks"
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
          {
            xPos   = 24
            yPos   = 52
            width  = 24
            height = 8
            widget = {
              title = "DAG Bag Size"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "${local.composer_env_filter} AND metric.type = \"composer.googleapis.com/environment/dagbag_size\""
                        aggregation = {
                          alignmentPeriod  = "300s"
                          perSeriesAligner = "ALIGN_MEAN"
                        }
                      }
                    }
                    plotType       = "LINE"
                    legendTemplate = "DAGs loaded"
                  }
                ]
                timeshiftDuration = "0s"
                yAxis = {
                  label = "DAG count"
                  scale = "LINEAR"
                }
              }
            }
          },
          {
            xPos   = 0
            yPos   = 60
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
            yPos   = 60
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
