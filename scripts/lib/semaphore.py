"""
Semaphore API client library for triggering Ansible deployments.

Provides SemaphoreDeployer class for interacting with Semaphore REST API,
including task creation, status polling, WebSocket output streaming, and
ARA playbook URL extraction.
"""

from datetime import datetime
from http.client import IncompleteRead
import json
import os
import re
import time
from typing import Any, Optional
from urllib.request import Request, urlopen
from urllib.error import HTTPError, URLError
from websocket import (
    create_connection,
    WebSocketConnectionClosedException,
    WebSocketTimeoutException,
)

SEMAPHORE_URL = os.environ.get("SEMAPHORE_URL", "https://semaphore.k.oneill.net")
SEMAPHORE_DISPLAY_URL = os.environ.get("SEMAPHORE_DISPLAY_URL", SEMAPHORE_URL)
ARA_URL = "https://ara.k.oneill.net"
TERMINAL_TASK_STATUSES = {"success", "error", "stopped"}
TRANSIENT_HTTP_STATUSES = {502, 503, 504}


def env_float(name: str, default: float) -> float:
    """Read a float from the environment, falling back on invalid values."""
    try:
        return float(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


def env_int(name: str, default: int) -> int:
    """Read an int from the environment, falling back on invalid values."""
    try:
        return int(os.environ.get(name, default))
    except (TypeError, ValueError):
        return default


class DeploymentError(Exception):
    """Custom exception for deployment failures"""

    pass


class TransientSemaphoreError(DeploymentError):
    """Semaphore request failed due to a retryable condition."""

    pass


class SemaphoreDeployer:
    """Semaphore deployment manager with retry logic and ARA links"""

    def __init__(
        self,
        token: str,
        hosts: str,
        project: str,
        template: str,
        tags: Optional[str] = None,
        max_attempts: int = 3,
    ):
        self.token = token
        self.hosts = hosts
        self.project_name = project
        self.template_name = template
        self.tags = tags
        self.max_attempts = max_attempts
        self.attempts: list[dict] = []
        self.project_id: Optional[int] = None
        self.template_id: Optional[int] = None
        self.api_retry_attempts = max(1, env_int("SEMAPHORE_API_RETRY_ATTEMPTS", 5))
        self.api_retry_delay = max(0.1, env_float("SEMAPHORE_API_RETRY_DELAY", 2.0))
        self.ws_reconnect_delay = max(
            0.1, env_float("SEMAPHORE_WS_RECONNECT_DELAY", 5.0)
        )
        self.task_idle_timeout = max(60, env_int("SEMAPHORE_TASK_IDLE_TIMEOUT", 900))

    def api_request(
        self,
        method: str,
        endpoint: str,
        data: Optional[dict] = None,
        retry: Optional[bool] = None,
    ) -> Any:
        """Make an API request to Semaphore"""
        url = f"{SEMAPHORE_URL}/api{endpoint}"
        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        }

        body = json.dumps(data).encode("utf-8") if data else None
        request = Request(url, data=body, headers=headers, method=method)
        retry = method == "GET" if retry is None else retry
        attempts = self.api_retry_attempts if retry else 1

        for attempt in range(1, attempts + 1):
            try:
                with urlopen(request, timeout=30) as response:
                    response_data = response.read().decode("utf-8")
                    return json.loads(response_data) if response_data else {}
            except HTTPError as e:
                try:
                    error_body = e.read().decode("utf-8") if e.fp else ""
                except (IncompleteRead, UnicodeDecodeError) as body_error:
                    error_body = f"failed to read error body: {body_error}"
                message = f"API error {e.code}: {error_body}"
                if e.code in TRANSIENT_HTTP_STATUSES:
                    if retry and attempt < attempts:
                        self.print_retry_warning(message, attempt, attempts)
                        continue
                    raise TransientSemaphoreError(message) from e
                raise DeploymentError(message) from e
            except (
                URLError,
                IncompleteRead,
                UnicodeDecodeError,
                json.JSONDecodeError,
            ) as e:
                reason = getattr(e, "reason", str(e))
                message = f"Connection/read error: {reason}"
                if retry and attempt < attempts:
                    self.print_retry_warning(message, attempt, attempts)
                    continue
                raise TransientSemaphoreError(message) from e

        raise DeploymentError(f"Semaphore API request failed: {method} {endpoint}")

    def print_retry_warning(self, message: str, attempt: int, attempts: int) -> None:
        delay = self.api_retry_delay * attempt
        print(
            f"Warning: Semaphore API request failed ({message}); "
            f"retrying in {delay:.1f}s ({attempt}/{attempts})"
        )
        time.sleep(delay)

    def resolve_project_id(self) -> int:
        """Resolve project name to ID via API"""
        projects = self.api_request("GET", "/projects")
        for project in projects:
            if project.get("name") == self.project_name:
                return project["id"]
        raise DeploymentError(f"Project '{self.project_name}' not found")

    def resolve_template_id(self, project_id: int) -> int:
        """Resolve template name to ID via API"""
        templates = self.api_request("GET", f"/project/{project_id}/templates")
        for template in templates:
            if template.get("name") == self.template_name:
                return template["id"]
        raise DeploymentError(
            f"Template '{self.template_name}' not found in project {self.project_name}"
        )

    def resolve_ids(self) -> None:
        """Resolve project and template names to IDs"""
        print(f"Resolving project '{self.project_name}'...")
        self.project_id = self.resolve_project_id()
        print(f"  Found project ID: {self.project_id}")

        print(f"Resolving template '{self.template_name}'...")
        self.template_id = self.resolve_template_id(self.project_id)
        print(f"  Found template ID: {self.template_id}")

    def build_arguments(self) -> Optional[str]:
        """Build CLI arguments as JSON string for the Semaphore task"""
        args = []

        # Add --limit if hosts is not "all"
        if self.hosts != "all":
            # Convert space-separated hosts to comma-separated
            host_list = ",".join(self.hosts.split())
            args.extend(["--limit", host_list])

        # Add --tags if specified
        if self.tags:
            args.extend(["--tags", self.tags])

        # Return JSON string or None if no args
        return json.dumps(args) if args else None

    def get_task_url(self, task_id: int) -> str:
        """Get the Semaphore UI URL for a task"""
        return f"{SEMAPHORE_DISPLAY_URL}/project/{self.project_id}/history?t={task_id}"

    def create_task(self) -> int:
        """Create a new Semaphore task and return its ID"""
        payload = {
            "template_id": self.template_id,
        }

        arguments = self.build_arguments()
        if arguments:
            payload["arguments"] = arguments

        print(f"Creating Semaphore task with payload: {json.dumps(payload)}")

        response = self.api_request(
            "POST", f"/project/{self.project_id}/tasks", payload
        )

        task_id = response.get("id")
        if not task_id:
            raise DeploymentError(f"No task ID in response: {response}")

        task_url = self.get_task_url(task_id)
        print(f"Created task {task_id}")
        print(f"🔗 Semaphore Task: {task_url}")
        return task_id

    def get_task_status(self, task_id: int) -> dict:
        """Get the current status of a task"""
        return self.api_request("GET", f"/project/{self.project_id}/tasks/{task_id}")

    def get_task_status_name(self, task_id: int) -> str:
        """Read task status without letting transient API failures abort monitoring."""
        try:
            return self.get_task_status(task_id).get("status", "unknown")
        except TransientSemaphoreError as e:
            print(f"Warning: Could not read task {task_id} status: {e}")
            return "unknown"

    def get_task_output(self, task_id: int) -> str:
        """Get the output of a task"""
        response = self.api_request(
            "GET", f"/project/{self.project_id}/tasks/{task_id}/output"
        )
        # Response is a list of output lines
        if isinstance(response, list):
            return "\n".join(item.get("output", "") for item in response)
        return str(response)

    def stream_task_output_ws(self, task_id: int) -> str:
        """Stream task output via WebSocket, return final status"""
        ws_url = SEMAPHORE_URL.replace("https://", "wss://") + "/api/ws"
        last_activity = time.monotonic()

        while True:
            idle_seconds = time.monotonic() - last_activity
            if idle_seconds >= self.task_idle_timeout:
                status = self.get_task_status_name(task_id)
                if status in TERMINAL_TASK_STATUSES:
                    return status
                print(
                    f"Task {task_id} produced no output or status update for "
                    f"{idle_seconds:.0f}s; Semaphore status is {status!r}, "
                    "continuing to wait"
                )
                last_activity = time.monotonic()

            # Connect to WebSocket
            try:
                ws = create_connection(
                    ws_url,
                    header={"Authorization": f"Bearer {self.token}"},
                    timeout=30,
                )
            except Exception as e:
                print(f"WebSocket connection failed: {e}")
                status = self.get_task_status_name(task_id)
                if status in TERMINAL_TASK_STATUSES:
                    return status
                time.sleep(self.ws_reconnect_delay)
                continue

            # Stream messages
            try:
                ws.settimeout(60)
                while True:
                    idle_seconds = time.monotonic() - last_activity
                    if idle_seconds >= self.task_idle_timeout:
                        status = self.get_task_status_name(task_id)
                        if status in TERMINAL_TASK_STATUSES:
                            return status
                        print(
                            f"Task {task_id} produced no output or status update for "
                            f"{idle_seconds:.0f}s; Semaphore status is {status!r}, "
                            "reconnecting and continuing to wait"
                        )
                        last_activity = time.monotonic()
                        break

                    try:
                        message = ws.recv()
                    except (
                        WebSocketTimeoutException,
                        WebSocketConnectionClosedException,
                    ):
                        status = self.get_task_status_name(task_id)
                        if status in TERMINAL_TASK_STATUSES:
                            return status
                        print("WebSocket interrupted - reconnecting...")
                        break  # Reconnect

                    try:
                        data = json.loads(message)
                    except json.JSONDecodeError:
                        continue

                    if data.get("task_id") != task_id:
                        continue

                    last_activity = time.monotonic()

                    if data.get("type") == "log":
                        timestamp = data.get("time", "")
                        output = data.get("output", "")
                        if timestamp:
                            try:
                                dt = datetime.fromisoformat(timestamp)
                                print(f"  [{dt.strftime('%H:%M:%S.%f')[:-3]}] {output}")
                            except ValueError:
                                print(f"  > {output}")
                        else:
                            print(f"  > {output}")
                    elif data.get("type") == "update":
                        status = data.get("status")
                        if status in TERMINAL_TASK_STATUSES:
                            return status
            finally:
                ws.close()

    def extract_ara_url(self, output: str) -> Optional[str]:
        """Extract ARA playbook URL from task output"""
        match = re.search(rf"ARA Playbook URL: ({ARA_URL}/playbooks/\d+\.html)", output)
        return match.group(1) if match else None

    def wait_for_task(self, task_id: int) -> tuple[bool, Optional[str]]:
        """Wait for task using WebSocket streaming"""
        print(f"Streaming output for task {task_id}...")

        final_status = self.stream_task_output_ws(task_id)
        success = final_status == "success"

        # Fetch full output for ARA extraction
        try:
            output = self.get_task_output(task_id)
        except DeploymentError as e:
            print(f"Warning: Failed to fetch final output for task {task_id}: {e}")
            output = ""
        ara_url = self.extract_ara_url(output)

        if success:
            print(f"✅ Task {task_id} completed successfully")
        else:
            print(f"❌ Task {task_id} failed with status: {final_status}")

        return success, ara_url

    def deploy_single_attempt(self) -> tuple[bool, Optional[str], str, int]:
        """Run a single deployment attempt. Returns (success, ara_url, task_url, task_id)"""
        task_id = self.create_task()
        task_url = self.get_task_url(task_id)
        success, ara_url = self.wait_for_task(task_id)

        if ara_url:
            print(f"📊 ARA Report: {ara_url}")
        else:
            print("📊 ARA Report: Not found in output")

        return success, ara_url, task_url, task_id

    def deploy_with_retries(self) -> bool:
        """Deploy with retry logic"""
        for attempt in range(1, self.max_attempts + 1):
            print(f"\n--- Deployment attempt {attempt}/{self.max_attempts} ---")

            start_time = time.time()
            success, ara_url, task_url, task_id = self.deploy_single_attempt()
            elapsed = time.time() - start_time

            self.attempts.append(
                {
                    "attempt": attempt,
                    "task_id": task_id,
                    "task_url": task_url,
                    "success": success,
                    "ara_url": ara_url,
                }
            )

            if success:
                if attempt > 1:
                    print(
                        f"✅ Deployment succeeded on attempt {attempt}/{self.max_attempts}"
                    )
                return True

            if attempt < self.max_attempts:
                if elapsed < 10:
                    print(
                        f"❌ Attempt {attempt} failed after {elapsed:.0f}s. Retrying in 10s..."
                    )
                    time.sleep(10)
                else:
                    print(
                        f"❌ Attempt {attempt} failed after {elapsed:.0f}s. Retrying immediately..."
                    )

        print(f"❌ All {self.max_attempts} attempts failed")
        return False

    def write_summary(self) -> None:
        """Write deployment summary to console and GitHub Actions job summary"""
        if not self.attempts:
            return

        last = self.attempts[-1]
        status = "✅ Success" if last["success"] else "❌ Failed"

        lines = [
            "## Deployment Summary",
            f"**Status:** {status}",
            f"**Hosts:** {self.hosts}",
        ]

        if len(self.attempts) == 1:
            lines.append(f"**Semaphore:** {last['task_url']}")
            if last["ara_url"]:
                lines.append(f"**ARA:** {last['ara_url']}")
        else:
            lines.append("**Attempts:**")
            for a in self.attempts:
                s = "✅" if a["success"] else "❌"
                lines.append(f"- {s} Attempt {a['attempt']}: {a['task_url']}")
                if a["ara_url"]:
                    lines.append(f"  - ARA: {a['ara_url']}")

        summary = "\n".join(lines)

        # Print to console
        print(f"\n{summary}")

        # Write to GitHub Actions job summary if available
        summary_file = os.environ.get("GITHUB_STEP_SUMMARY")
        if summary_file:
            try:
                with open(summary_file, "a") as f:
                    f.write(summary + "\n")
            except OSError as e:
                print(f"Warning: Failed to write GitHub summary: {e}")

    def deploy(self) -> None:
        """Main deployment entry point"""
        print("Starting Ansible deployment via Semaphore")
        print(f"  Hosts: {self.hosts}")
        print(f"  Project: {self.project_name}")
        print(f"  Template: {self.template_name}")
        if self.tags:
            print(f"  Tags: {self.tags}")

        self.resolve_ids()

        success = self.deploy_with_retries()
        self.write_summary()

        if not success:
            raise DeploymentError("Deployment failed after all retries")
