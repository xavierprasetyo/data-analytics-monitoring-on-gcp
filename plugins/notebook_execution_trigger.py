"""
notebook_execution_trigger.py — Deferrable Trigger for Vertex AI Notebook Execution

This trigger polls a Vertex AI long-running operation (LRO) asynchronously,
freeing the Airflow worker slot while the notebook executes on Colab Enterprise.

The trigger runs in Airflow's triggerer process (lightweight async loop),
not in a worker slot, so it doesn't block DAG capacity.

Flow:
  1. Operator submits notebook execution → gets operation name
  2. Operator raises TaskDeferred with this trigger
  3. Trigger polls operation.done() every poll_interval seconds
  4. When done, trigger fires TriggerEvent with result
  5. Operator resumes in execute_complete() to handle result
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime
from typing import Any, AsyncIterator

from airflow.triggers.base import BaseTrigger, TriggerEvent

log = logging.getLogger(__name__)


class NotebookExecutionTrigger(BaseTrigger):
    """
    Polls a Vertex AI NotebookExecutionJob operation until completion.

    Runs in the triggerer process (async), not in a worker slot.
    """

    def __init__(
        self,
        operation_name: str,
        project_id: str,
        region: str,
        poll_interval: int = 30,
        timeout: int = 3600,
    ):
        super().__init__()
        self.operation_name = operation_name
        self.project_id = project_id
        self.region = region
        self.poll_interval = poll_interval
        self.timeout = timeout

    def serialize(self) -> tuple[str, dict[str, Any]]:
        """Serialize trigger for storage between polls."""
        return (
            "notebook_execution_trigger.NotebookExecutionTrigger",
            {
                "operation_name": self.operation_name,
                "project_id": self.project_id,
                "region": self.region,
                "poll_interval": self.poll_interval,
                "timeout": self.timeout,
            },
        )

    async def run(self) -> AsyncIterator[TriggerEvent]:
        """
        Poll the Vertex AI operation until done or timeout.

        Yields a TriggerEvent with the result when the operation completes.
        """
        from google.api_core import exceptions as api_exceptions
        from google.longrunning import operations_pb2
        from google.longrunning.operations_grpc_transport import OperationsGrpcTransport

        start_time = datetime.utcnow()
        elapsed = 0

        log.info(
            "NotebookExecutionTrigger started: polling operation %s every %ds (timeout: %ds)",
            self.operation_name, self.poll_interval, self.timeout,
        )

        while elapsed < self.timeout:
            try:
                # Use synchronous client in async context via to_thread
                done, result_data = await asyncio.to_thread(
                    self._check_operation_status
                )

                if done:
                    log.info(
                        "Notebook execution operation completed after %ds",
                        elapsed,
                    )
                    yield TriggerEvent(result_data)
                    return

            except Exception as e:
                log.error("Error polling operation %s: %s", self.operation_name, e)
                yield TriggerEvent({
                    "status": "error",
                    "message": str(e),
                    "operation_name": self.operation_name,
                })
                return

            log.info(
                "Notebook execution in progress... (elapsed: %ds, next poll in %ds)",
                elapsed, self.poll_interval,
            )
            await asyncio.sleep(self.poll_interval)
            elapsed = (datetime.utcnow() - start_time).total_seconds()

        # Timeout
        yield TriggerEvent({
            "status": "timeout",
            "message": f"Operation timed out after {elapsed:.0f}s",
            "operation_name": self.operation_name,
        })

    def _check_operation_status(self) -> tuple[bool, dict]:
        """
        Check if the Vertex AI operation is complete (synchronous).

        Returns:
            (is_done, result_data) tuple
        """
        from google.cloud import aiplatform_v1

        client = aiplatform_v1.NotebookServiceClient(
            client_options={"api_endpoint": f"{self.region}-aiplatform.googleapis.com"}
        )

        # Get the operation status
        operation = client.transport.operations_client.get_operation(self.operation_name)

        if not operation.done:
            return False, {}

        # Operation is done — extract the result
        if operation.error and operation.error.code != 0:
            return True, {
                "status": "failed",
                "message": operation.error.message,
                "operation_name": self.operation_name,
            }

        # Parse the result from the operation response
        result = aiplatform_v1.NotebookExecutionJob.deserialize(operation.response.value)

        output_uri = getattr(result, "gcs_output_uri", "")
        job_name = getattr(result, "name", "")

        # Check job-level status
        job_state = None
        if hasattr(result, "status") and result.status:
            job_state = result.status.state.name if result.status.state else None

        if job_state in ("FAILED", "CANCELLED"):
            return True, {
                "status": "failed",
                "message": getattr(result.status, "message", "unknown error"),
                "job_state": job_state,
                "operation_name": self.operation_name,
            }

        return True, {
            "status": "success",
            "output_uri": output_uri,
            "job_name": job_name,
            "operation_name": self.operation_name,
        }
