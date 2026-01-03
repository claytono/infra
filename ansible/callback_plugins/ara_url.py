"""Print ARA playbook URL at end of every playbook run."""

import os
from ansible.plugins.callback import CallbackBase


class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "notification"
    CALLBACK_NAME = "ara_url"
    CALLBACK_NEEDS_ENABLED = False

    def __init__(self):
        super().__init__()
        self._ara_enabled = False
        self._ara_client = None

    def v2_playbook_on_start(self, playbook):
        """Pre-flight check: validate ARA config and create client early."""
        api_server = os.environ.get("ARA_API_SERVER", "")
        if not api_server:
            self._display.v("ara_url: ARA_API_SERVER not set, skipping URL reporting")
            return

        try:
            from ara.clients.http import AraHttpClient

            # Validate we can create a client with required config
            self._ara_client = AraHttpClient(
                endpoint=api_server,
                timeout=int(os.environ.get("ARA_API_TIMEOUT", "30")),
                auth=(
                    os.environ.get("ARA_API_USERNAME"),
                    os.environ.get("ARA_API_PASSWORD"),
                ),
            )
            self._ara_enabled = True

            # Print playbook ID at start
            response = self._ara_client.get("/api/v1/playbooks", order="-id", limit=1)
            if response.get("results"):
                playbook_id = response["results"][0]["id"]
                url = f"{api_server}/playbooks/{playbook_id}.html"
                self._display.display(f"ARA Playbook ID: {playbook_id} URL: {url}")

        except ImportError:
            self._display.warning("ara_url: ARA package not installed, URL reporting disabled")
        except Exception as e:
            self._display.warning(f"ara_url: Failed to initialize ARA client: {e}")

    def v2_playbook_on_stats(self, stats):
        """Print ARA URL at end - fires regardless of success/failure."""
        if not self._ara_enabled or not self._ara_client:
            return

        api_server = os.environ.get("ARA_API_SERVER", "")
        try:
            response = self._ara_client.get("/api/v1/playbooks", order="-id", limit=1)
            if response.get("results"):
                playbook_id = response["results"][0]["id"]
                url = f"{api_server}/playbooks/{playbook_id}.html"
                self._display.display(f"ARA Playbook ID: {playbook_id} URL: {url}")

        except Exception as e:
            self._display.warning(f"ara_url: Failed to retrieve playbook URL: {e}")
