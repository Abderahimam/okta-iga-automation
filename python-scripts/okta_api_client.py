"""
okta_api_client.py
------------------
Production-ready Okta API client library with:
  - Exponential back-off + jitter retry logic
  - Automatic pagination (cursor & offset)
  - Rate-limit (429) handling
  - Structured logging
  - Type-annotated public API

Usage:
    from okta_api_client import OktaClient

    client = OktaClient(domain="company.okta.com", api_token="...")
    user   = client.get_user("jdoe@company.com")
"""

from __future__ import annotations

import logging
import time
import random
from typing import Any, Dict, Generator, List, Optional
from urllib.parse import urlencode, urljoin

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("okta_api_client")


# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class OktaApiError(Exception):
    """Raised when the Okta API returns a non-2xx response."""

    def __init__(self, message: str, status_code: int = 0, error_code: str = "") -> None:
        super().__init__(message)
        self.status_code = status_code
        self.error_code  = error_code


class OktaRateLimitError(OktaApiError):
    """Raised when the client has been permanently rate-limited (after retries)."""


# ---------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------

class OktaClient:
    """Thread-safe Okta Management API client.

    Parameters
    ----------
    domain:     Okta organisation domain, e.g. ``company.okta.com``.
    api_token:  Okta SSWS API token (store in a secret manager, not in code).
    max_retries: Maximum number of automatic retries on transient errors.
    timeout:    HTTP request timeout in seconds.
    """

    _DEFAULT_TIMEOUT   = 30
    _DEFAULT_RETRIES   = 3
    _BACKOFF_BASE      = 2
    _BACKOFF_MAX       = 60

    def __init__(
        self,
        domain: str,
        api_token: str,
        max_retries: int = _DEFAULT_RETRIES,
        timeout: int = _DEFAULT_TIMEOUT,
    ) -> None:
        if not domain or not api_token:
            raise ValueError("Both 'domain' and 'api_token' are required.")

        self._base_url   = f"https://{domain.rstrip('/')}"
        self._api_token  = api_token
        self._timeout    = timeout
        self._max_retries = max_retries
        self._session    = self._build_session()

    # ------------------------------------------------------------------
    # Session helpers
    # ------------------------------------------------------------------

    def _build_session(self) -> requests.Session:
        session = requests.Session()
        session.headers.update({
            "Authorization": f"SSWS {self._api_token}",
            "Accept":        "application/json",
            "Content-Type":  "application/json",
        })
        retry = Retry(
            total=self._max_retries,
            backoff_factor=1,
            status_forcelist=[500, 502, 503, 504],
            allowed_methods=["GET", "POST", "PUT", "DELETE"],
            raise_on_status=False,
        )
        adapter = HTTPAdapter(max_retries=retry)
        session.mount("https://", adapter)
        return session

    def _url(self, path: str) -> str:
        return urljoin(self._base_url, path)

    def _request(
        self,
        method: str,
        path: str,
        params: Optional[Dict] = None,
        json: Optional[Dict]   = None,
    ) -> Any:
        """Execute a single HTTP request with rate-limit retry."""
        url = self._url(path)
        for attempt in range(1, self._max_retries + 2):
            response = self._session.request(
                method,
                url,
                params=params,
                json=json,
                timeout=self._timeout,
            )

            if response.status_code == 429:
                retry_after_header = response.headers.get("Retry-After")
                retry_after = int(retry_after_header) if retry_after_header is not None else None
                wait = retry_after if retry_after is not None else (
                    min(self._BACKOFF_BASE ** attempt + random.uniform(0, 1), self._BACKOFF_MAX)
                )
                if attempt > self._max_retries:
                    raise OktaRateLimitError(
                        f"Rate limit exceeded after {attempt} retries.",
                        status_code=429,
                    )
                logger.warning("Rate limited. Retrying in %.1fs (attempt %d).", wait, attempt)
                time.sleep(wait)
                continue

            if not response.ok:
                body = {}
                try:
                    body = response.json()
                except Exception:
                    pass
                raise OktaApiError(
                    f"[{method} {path}] HTTP {response.status_code}: {body.get('errorSummary', response.text)}",
                    status_code=response.status_code,
                    error_code=body.get("errorCode", ""),
                )

            if response.status_code == 204 or not response.content:
                return None
            return response.json()

        raise OktaApiError("Max retries exhausted.", status_code=0)

    def _paginate(
        self,
        path: str,
        params: Optional[Dict] = None,
    ) -> Generator[Any, None, None]:
        """Yield all pages from a paginated Okta list endpoint."""
        params = dict(params or {})
        params.setdefault("limit", 200)
        url: Optional[str] = self._url(path)

        while url:
            response = self._session.get(url, params=params, timeout=self._timeout)
            if not response.ok:
                body = {}
                try:
                    body = response.json()
                except Exception:
                    pass
                raise OktaApiError(
                    f"[GET {url}] HTTP {response.status_code}: {body.get('errorSummary', response.text)}",
                    status_code=response.status_code,
                )

            for item in response.json():
                yield item

            # Follow the 'next' Link header if present
            link = response.headers.get("Link", "")
            url  = None
            params = {}
            for part in link.split(","):
                if 'rel="next"' in part:
                    url = part.split(";")[0].strip().strip("<>")
                    break

    # ------------------------------------------------------------------
    # Users
    # ------------------------------------------------------------------

    def get_user(self, user_id_or_login: str) -> Dict:
        """Retrieve a single user by ID or login."""
        logger.debug("get_user: %s", user_id_or_login)
        return self._request("GET", f"/api/v1/users/{user_id_or_login}")

    def list_users(self, filter_expr: Optional[str] = None, search: Optional[str] = None) -> List[Dict]:
        """Return all users, optionally filtered."""
        params: Dict[str, str] = {}
        if filter_expr:
            params["filter"] = filter_expr
        if search:
            params["search"] = search
        return list(self._paginate("/api/v1/users", params))

    def create_user(self, profile: Dict, credentials: Optional[Dict] = None, activate: bool = True) -> Dict:
        """Create a new Okta user."""
        logger.info("Creating user: %s", profile.get("login"))
        payload: Dict[str, Any] = {"profile": profile}
        if credentials:
            payload["credentials"] = credentials
        return self._request("POST", f"/api/v1/users?activate={str(activate).lower()}", json=payload)

    def update_user(self, user_id: str, profile: Dict) -> Dict:
        """Partially update a user's profile."""
        logger.info("Updating user: %s", user_id)
        return self._request("POST", f"/api/v1/users/{user_id}", json={"profile": profile})

    def deactivate_user(self, user_id: str, send_email: bool = False) -> None:
        """Deactivate a user account."""
        logger.info("Deactivating user: %s", user_id)
        self._request("POST", f"/api/v1/users/{user_id}/lifecycle/deactivate?sendEmail={str(send_email).lower()}")

    def reactivate_user(self, user_id: str) -> Dict:
        """Reactivate a previously deactivated user."""
        logger.info("Reactivating user: %s", user_id)
        return self._request("POST", f"/api/v1/users/{user_id}/lifecycle/reactivate?sendEmail=true")

    def suspend_user(self, user_id: str) -> None:
        """Suspend a user (reversible)."""
        logger.info("Suspending user: %s", user_id)
        self._request("POST", f"/api/v1/users/{user_id}/lifecycle/suspend")

    def unsuspend_user(self, user_id: str) -> None:
        """Unsuspend a previously suspended user."""
        logger.info("Unsuspending user: %s", user_id)
        self._request("POST", f"/api/v1/users/{user_id}/lifecycle/unsuspend")

    def get_user_factors(self, user_id: str) -> List[Dict]:
        """Return all enrolled MFA factors for a user."""
        return self._request("GET", f"/api/v1/users/{user_id}/factors") or []

    # ------------------------------------------------------------------
    # Groups
    # ------------------------------------------------------------------

    def list_groups(self, search: Optional[str] = None) -> List[Dict]:
        params = {"search": search} if search else {}
        return list(self._paginate("/api/v1/groups", params))

    def get_group(self, group_id: str) -> Dict:
        return self._request("GET", f"/api/v1/groups/{group_id}")

    def get_group_members(self, group_id: str) -> List[Dict]:
        return list(self._paginate(f"/api/v1/groups/{group_id}/users"))

    def add_user_to_group(self, group_id: str, user_id: str) -> None:
        logger.info("Adding %s to group %s", user_id, group_id)
        self._request("PUT", f"/api/v1/groups/{group_id}/users/{user_id}")

    def remove_user_from_group(self, group_id: str, user_id: str) -> None:
        logger.info("Removing %s from group %s", user_id, group_id)
        self._request("DELETE", f"/api/v1/groups/{group_id}/users/{user_id}")

    # ------------------------------------------------------------------
    # Applications
    # ------------------------------------------------------------------

    def list_apps(self) -> List[Dict]:
        return list(self._paginate("/api/v1/apps"))

    def get_app(self, app_id: str) -> Dict:
        return self._request("GET", f"/api/v1/apps/{app_id}")

    def assign_user_to_app(self, app_id: str, user_id: str, profile: Optional[Dict] = None) -> Dict:
        logger.info("Assigning %s to app %s", user_id, app_id)
        payload: Dict[str, Any] = {"id": user_id, "scope": "USER"}
        if profile:
            payload["profile"] = profile
        return self._request("POST", f"/api/v1/apps/{app_id}/users", json=payload)

    def remove_user_from_app(self, app_id: str, user_id: str) -> None:
        logger.info("Removing %s from app %s", user_id, app_id)
        self._request("DELETE", f"/api/v1/apps/{app_id}/users/{user_id}")

    def get_app_users(self, app_id: str) -> List[Dict]:
        return list(self._paginate(f"/api/v1/apps/{app_id}/users"))

    # ------------------------------------------------------------------
    # System Logs
    # ------------------------------------------------------------------

    def get_logs(
        self,
        since: Optional[str]       = None,
        until: Optional[str]       = None,
        filter_expr: Optional[str] = None,
        event_type: Optional[str]  = None,
    ) -> List[Dict]:
        """Return system log events for the given time window."""
        params: Dict[str, str] = {"limit": "1000"}
        if since:
            params["since"] = since
        if until:
            params["until"] = until
        if filter_expr:
            params["filter"] = filter_expr
        if event_type:
            params["eventType"] = event_type
        return list(self._paginate("/api/v1/logs", params))

    # ------------------------------------------------------------------
    # Policies
    # ------------------------------------------------------------------

    def list_policies(self, policy_type: str = "MFA_ENROLL") -> List[Dict]:
        return self._request("GET", f"/api/v1/policies?type={policy_type}") or []

    def get_policy(self, policy_id: str) -> Dict:
        return self._request("GET", f"/api/v1/policies/{policy_id}")

    def create_policy(self, policy: Dict) -> Dict:
        logger.info("Creating policy: %s", policy.get("name"))
        return self._request("POST", "/api/v1/policies", json=policy)

    def update_policy(self, policy_id: str, updates: Dict) -> Dict:
        return self._request("PUT", f"/api/v1/policies/{policy_id}", json=updates)

    # ------------------------------------------------------------------
    # Health / connectivity
    # ------------------------------------------------------------------

    def ping(self) -> bool:
        """Return True if the Okta API is reachable and the token is valid."""
        try:
            self._request("GET", "/api/v1/users/me")
            return True
        except OktaApiError:
            return False
