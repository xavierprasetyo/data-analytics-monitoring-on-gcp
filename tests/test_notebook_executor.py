"""
Tests for the notebook_executor DAG and sample notebook.

Validates:
  1. The sample notebook is valid JSON (ipynb format)
  2. The notebooks.yaml config loads correctly
  3. The DAG structure has the expected tasks
"""

import json
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
import yaml

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

PROJECT_ROOT = Path(__file__).parent.parent
NOTEBOOKS_DIR = PROJECT_ROOT / "notebooks"
CONFIG_PATH = PROJECT_ROOT / "dags" / "config" / "notebooks.yaml"
DAG_PATH = PROJECT_ROOT / "dags" / "notebook_executor.py"


# ---------------------------------------------------------------------------
# Test: Sample notebook is valid JSON
# ---------------------------------------------------------------------------


class TestSampleNotebook:
    """Validate the orders_report.ipynb notebook file."""

    def test_notebook_file_exists(self):
        """The sample notebook must exist in the notebooks/ directory."""
        notebook_path = NOTEBOOKS_DIR / "orders_report.ipynb"
        assert notebook_path.exists(), f"Notebook not found at {notebook_path}"

    def test_notebook_is_valid_json(self):
        """The .ipynb file must be valid JSON."""
        notebook_path = NOTEBOOKS_DIR / "orders_report.ipynb"
        with open(notebook_path) as f:
            nb = json.load(f)
        assert isinstance(nb, dict), "Notebook root must be a JSON object"

    def test_notebook_has_required_structure(self):
        """The notebook must have the standard ipynb structure."""
        notebook_path = NOTEBOOKS_DIR / "orders_report.ipynb"
        with open(notebook_path) as f:
            nb = json.load(f)

        assert "cells" in nb, "Notebook must have 'cells' key"
        assert "nbformat" in nb, "Notebook must have 'nbformat' key"
        assert nb["nbformat"] == 4, "Notebook must be nbformat 4"
        assert len(nb["cells"]) > 0, "Notebook must have at least one cell"

    def test_notebook_has_code_cells(self):
        """The notebook must contain at least one code cell."""
        notebook_path = NOTEBOOKS_DIR / "orders_report.ipynb"
        with open(notebook_path) as f:
            nb = json.load(f)

        code_cells = [c for c in nb["cells"] if c["cell_type"] == "code"]
        assert len(code_cells) >= 3, "Notebook should have at least 3 code cells"

    def test_notebook_has_parameter_cell(self):
        """The notebook must have a parameters-tagged cell for Airflow injection."""
        notebook_path = NOTEBOOKS_DIR / "orders_report.ipynb"
        with open(notebook_path) as f:
            nb = json.load(f)

        param_cells = [
            c for c in nb["cells"]
            if c["cell_type"] == "code"
            and "parameters" in c.get("metadata", {}).get("tags", [])
        ]
        assert len(param_cells) == 1, "Notebook must have exactly one parameters cell"

    def test_notebook_references_bigquery(self):
        """The notebook must contain BigQuery queries."""
        notebook_path = NOTEBOOKS_DIR / "orders_report.ipynb"
        with open(notebook_path) as f:
            nb = json.load(f)

        all_source = " ".join(
            " ".join(c.get("source", []))
            for c in nb["cells"]
            if c["cell_type"] == "code"
        )
        assert "bigquery" in all_source.lower(), "Notebook must reference BigQuery"
        assert "monitoring_lab_silver" in all_source, "Notebook must query silver dataset"


# ---------------------------------------------------------------------------
# Test: notebooks.yaml config
# ---------------------------------------------------------------------------


class TestNotebooksConfig:
    """Validate the notebooks.yaml configuration file."""

    def test_config_file_exists(self):
        """The config file must exist."""
        assert CONFIG_PATH.exists(), f"Config not found at {CONFIG_PATH}"

    def test_config_is_valid_yaml(self):
        """The config must be valid YAML."""
        with open(CONFIG_PATH) as f:
            config = yaml.safe_load(f)
        assert isinstance(config, dict), "Config root must be a YAML mapping"

    def test_config_has_notebooks_key(self):
        """The config must have a 'notebooks' key with entries."""
        with open(CONFIG_PATH) as f:
            config = yaml.safe_load(f)
        assert "notebooks" in config, "Config must have 'notebooks' key"
        assert len(config["notebooks"]) > 0, "Must have at least one notebook entry"

    def test_notebook_entries_have_required_fields(self):
        """Each notebook entry must have 'name' and 'gcs_uri'."""
        with open(CONFIG_PATH) as f:
            config = yaml.safe_load(f)

        for nb in config["notebooks"]:
            assert "name" in nb, f"Notebook entry missing 'name': {nb}"
            assert "gcs_uri" in nb, f"Notebook entry missing 'gcs_uri': {nb}"

    def test_orders_report_entry_exists(self):
        """The orders_report notebook must be registered."""
        with open(CONFIG_PATH) as f:
            config = yaml.safe_load(f)

        names = [nb["name"] for nb in config["notebooks"]]
        assert "orders_report" in names, "orders_report must be in notebooks.yaml"

    def test_entries_use_airflow_variables(self):
        """GCS URIs should use Airflow variable templates, not hardcoded project IDs."""
        with open(CONFIG_PATH) as f:
            config = yaml.safe_load(f)

        for nb in config["notebooks"]:
            gcs_uri = nb["gcs_uri"]
            # Should use Airflow variable template
            assert "var.value.project_id" in gcs_uri, (
                f"gcs_uri should use Airflow variables, got: {gcs_uri}"
            )
