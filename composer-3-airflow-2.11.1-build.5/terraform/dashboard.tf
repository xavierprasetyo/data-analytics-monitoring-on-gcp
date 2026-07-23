# ---------------------------------------------------------------------------
# dashboard.tf — Cloud Monitoring Dashboard for Composer operational health
#
# Creates a single-pane-of-glass dashboard with 4 sections:
#   1. Health Summary    — Scorecards for at-a-glance status
#   2. Pipeline Health   — DAG runs, task instances, durations, custom errors
#   3. Infra Health      — Scheduler, database, workers (evictions, CPU, memory)
#   4. Capacity/Parsing  — Queue depth, DAG bag size, parse time, parse errors
#
# All metrics are scoped to the specific Composer environment.
# ---------------------------------------------------------------------------

resource "google_monitoring_dashboard" "composer_operational" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "Composer Operational Health — ${var.composer_env_name}"

    # ------------------------------------------------------------------
    # MosaicLayout gives precise control over widget placement and sizing.
    # The grid is 48 columns wide. Each "row" of tiles is stacked vertically.
    #
    # Scorecard row:  4 tiles × 12 columns = 48 (height 4)
    # Chart rows:     2 tiles × 24 columns = 48 (height 8 each)
    # ------------------------------------------------------------------
    mosaicLayout = {
      columns = 48
      tiles   = concat(

        # ================================================================
        # SECTION 1: HEALTH SUMMARY — Scorecards (row 0, y=0)
        # ================================================================

        # --- Section header ---
        [
          {
            xPos   = 0
            yPos   = 0
            width  = 48
            height = 2
            widget = {
              title = "⚡ Health Summary"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },

          # --- Scorecard: Database Health ---
          {
            xPos   = 0
            yPos   = 2
            width  = 12
            height = 4
            widget = {
              title     = "Database Health"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/database_health\""
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

          # --- Scorecard: Scheduler Heartbeat ---
          {
            xPos   = 12
            yPos   = 2
            width  = 12
            height = 4
            widget = {
              title     = "Scheduler Heartbeat"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/scheduler_heartbeat_count\""
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

          # --- Scorecard: DAG Bag Size ---
          {
            xPos   = 24
            yPos   = 2
            width  = 12
            height = 4
            widget = {
              title     = "Total DAGs Loaded"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/dag_bag_size\""
                    aggregation = {
                      alignmentPeriod  = "300s"
                      perSeriesAligner = "ALIGN_MEAN"
                    }
                  }
                }
              }
            }
          },

          # --- Scorecard: Active/Queued Tasks ---
          {
            xPos   = 36
            yPos   = 2
            width  = 12
            height = 4
            widget = {
              title     = "Active/Queued Tasks"
              scorecard = {
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/num_queued_or_running_tasks\""
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
          # --- Section header ---
          {
            xPos   = 0
            yPos   = 6
            width  = 48
            height = 2
            widget = {
              title = "📊 Pipeline Health"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },

          # --- Chart: DAG Run Status (success/failed by state) ---
          {
            xPos   = 0
            yPos   = 8
            width  = 24
            height = 8
            widget = {
              title  = "DAG Run Status"
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

          # --- Chart: Task Instance Status (succeeded/failed by state) ---
          {
            xPos   = 24
            yPos   = 8
            width  = 24
            height = 8
            widget = {
              title  = "Task Instance Status"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/finished_task_instance_count\""
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

          # --- Chart: Task Duration ---
          {
            xPos   = 0
            yPos   = 16
            width  = 24
            height = 8
            widget = {
              title  = "Task Duration"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/task_duration\""
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
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/task_duration\""
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

          # --- Chart: Task Errors (custom log-based metric) ---
          {
            xPos   = 24
            yPos   = 16
            width  = 24
            height = 8
            widget = {
              title  = "Task Errors (Custom Metric)"
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
                          groupByFields      = [
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
          # --- Section header ---
          {
            xPos   = 0
            yPos   = 24
            width  = 48
            height = 2
            widget = {
              title = "🔧 Infrastructure Health"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },

          # --- Chart: Scheduler Heartbeat (trend) ---
          {
            xPos   = 0
            yPos   = 26
            width  = 16
            height = 8
            widget = {
              title  = "Scheduler Heartbeat"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/scheduler_heartbeat_count\""
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

          # --- Chart: Database Health (trend) ---
          {
            xPos   = 16
            yPos   = 26
            width  = 16
            height = 8
            widget = {
              title  = "Database Health"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/database_health\""
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

          # --- Chart: Worker Pod Evictions ---
          {
            xPos   = 32
            yPos   = 26
            width  = 16
            height = 8
            widget = {
              title  = "Worker Pod Evictions"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/worker/pod_eviction_count\""
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

          # --- Chart: Worker CPU Usage ---
          {
            xPos   = 0
            yPos   = 34
            width  = 24
            height = 8
            widget = {
              title  = "Worker CPU Usage"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/worker/cpu/usage_time\""
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

          # --- Chart: Worker Memory Usage ---
          {
            xPos   = 24
            yPos   = 34
            width  = 24
            height = 8
            widget = {
              title  = "Worker Memory Usage"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/worker/memory/bytes_used\""
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
          # --- Section header ---
          {
            xPos   = 0
            yPos   = 42
            width  = 48
            height = 2
            widget = {
              title = "📦 Capacity & Parsing"
              text = {
                content = ""
                format  = "RAW"
              }
            }
          },

          # --- Chart: Active/Queued Tasks (trend) ---
          {
            xPos   = 0
            yPos   = 44
            width  = 24
            height = 8
            widget = {
              title  = "Active/Queued Tasks"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/num_queued_or_running_tasks\""
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

          # --- Chart: DAG Bag Size (trend) ---
          {
            xPos   = 24
            yPos   = 44
            width  = 24
            height = 8
            widget = {
              title  = "DAG Bag Size"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/dag_bag_size\""
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

          # --- Chart: DAG Parse Time ---
          {
            xPos   = 0
            yPos   = 52
            width  = 24
            height = 8
            widget = {
              title  = "DAG Parse Time"
              xyChart = {
                dataSets = [
                  {
                    timeSeriesQuery = {
                      timeSeriesFilter = {
                        filter = "resource.type = \"cloud_composer_environment\" AND resource.labels.environment_name = \"${var.composer_env_name}\" AND metric.type = \"composer.googleapis.com/environment/dag_processing/total_parse_time\""
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

          # --- Chart: DAG Parse Errors (custom log-based metric) ---
          {
            xPos   = 24
            yPos   = 52
            width  = 24
            height = 8
            widget = {
              title  = "DAG Parse Errors (Custom Metric)"
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
    google_composer_environment.lab,
    google_logging_metric.task_errors,
    google_logging_metric.dag_parse_errors,
  ]
}
