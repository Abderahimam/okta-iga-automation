"""
scim_provisioning.py
--------------------
SCIM 2.0 provisioning automation for Okta.

Implements the SCIM 2.0 protocol to create, update, and deprovision users
through Okta's SCIM API endpoint. Suitable for integrating HR systems,
Active Directory, or any identity source with Okta.

Usage:
    from scim_provisioning import ScimProvisioner

    provisioner = ScimProvisioner(
        scim_base_url="https://company.okta.com/scim/v2",
        bearer_token="...",
    )
    user = provisioner.create_user({
        "userName": "jdoe@company.com",
        "name": {"givenName": "John", "familyName": "Doe"},
        "emails": [{"value": "jdoe@company.com", "primary": True}],
    })
"""

from __future__ import annotations

import logging
import time
import random
from typing import Any, Dict, Generator, List, Optional

import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

logger = logging.getLogger("scim_provisioning")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

class ScimError(Exception):
    def __init__(self, message: str, status_code: int = 0) -> None:
        super().__init__(message)
        self.status_code = status_code


# ---------------------------------------------------------------------------
# SCIM Provisioner
# ---------------------------------------------------------------------------

class ScimProvisioner:
    """SCIM 2.0 provisioner for Okta.

    Parameters
    ----------
    scim_base_url : Full SCIM base URL, e.g. ``https://company.okta.com/scim/v2``.
    bearer_token  : OAuth 2.0 bearer token (or Okta API token) for authentication.
    timeout       : HTTP request timeout in seconds.
    max_retries   : Maximum retry attempts for transient failures.
    """

    _SCIM_SCHEMAS   = ["urn:ietf:params:scim:schemas:core:2.0:User"]
    _PATCH_OP_SCHEMA = "urn:ietf:params:scim:api:messages:2.0:PatchOp"

    def __init__(
        self,
        scim_base_url: str,
        bearer_token: str,
        timeout: int = 30,
        max_retries: int = 3,
    ) -> None:
        self._base_url    = scim_base_url.rstrip("/")
        self._timeout     = timeout
        self._max_retries = max_retries
        self._session     = self._build_session(bearer_token)

    # ------------------------------------------------------------------
    # Session
    # ------------------------------------------------------------------

    @staticmethod
    def _build_session(token: str) -> requests.Session:
        session = requests.Session()
        session.headers.update({
            "Authorization": f"Bearer {token}",
            "Accept":        "application/scim+json",
            "Content-Type":  "application/scim+json",
        })
        retry = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[500, 502, 503, 504],
            allowed_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        )
        session.mount("https://", HTTPAdapter(max_retries=retry))
        return session

    def _request(self, method: str, path: str, json: Optional[Dict] = None, params: Optional[Dict] = None) -> Any:
        url = f"{self._base_url}{path}"
        for attempt in range(1, self._max_retries + 2):
            resp = self._session.request(method, url, json=json, params=params, timeout=self._timeout)

            if resp.status_code == 429:
                retry_after_header = resp.headers.get("Retry-After")
                retry_after = int(retry_after_header) if retry_after_header is not None else None
                wait = retry_after if retry_after is not None else min(2 ** attempt + random.uniform(0, 1), 60)
                if attempt > self._max_retries:
                    raise ScimError("Rate limit exceeded.", status_code=429)
                logger.warning("Rate limited. Retrying in %.1fs.", wait)
                time.sleep(wait)
                continue

            if not resp.ok:
                detail = resp.json().get("detail", resp.text) if resp.content else resp.reason
                raise ScimError(f"[{method} {url}] HTTP {resp.status_code}: {detail}", status_code=resp.status_code)

            return resp.json() if resp.content and resp.status_code != 204 else None

        raise ScimError("Max retries exhausted.")

    def _paginate(self, path: str, filter_expr: Optional[str] = None) -> Generator[Dict, None, None]:
        params: Dict[str, Any] = {"count": 100, "startIndex": 1}
        if filter_expr:
            params["filter"] = filter_expr

        while True:
            response = self._request("GET", path, params=params)
            resources = response.get("Resources", [])
            for resource in resources:
                yield resource

            total_results = response.get("totalResults", 0)
            start_index   = response.get("startIndex", 1)
            items_per_page = response.get("itemsPerPage", len(resources))
            next_index     = start_index + items_per_page

            if next_index > total_results or not resources:
                break
            params["startIndex"] = next_index

    # ------------------------------------------------------------------
    # Users
    # ------------------------------------------------------------------

    def get_user(self, user_id: str) -> Dict:
        """Retrieve a SCIM user by their Okta SCIM ID."""
        logger.debug("get_user: %s", user_id)
        return self._request("GET", f"/Users/{user_id}")

    def find_user_by_username(self, username: str) -> Optional[Dict]:
        """Find a user by userName (email). Returns None if not found."""
        results = list(self._paginate("/Users", filter_expr=f'userName eq "{username}"'))
        return results[0] if results else None

    def list_users(self, filter_expr: Optional[str] = None) -> List[Dict]:
        """Return all SCIM users, optionally filtered."""
        return list(self._paginate("/Users", filter_expr=filter_expr))

    def create_user(self, user_data: Dict) -> Dict:
        """Provision a new user via SCIM."""
        payload = self._build_scim_user(user_data)
        username = user_data.get("userName", "unknown")
        logger.info("Provisioning SCIM user: %s", username)
        return self._request("POST", "/Users", json=payload)

    def update_user(self, user_id: str, user_data: Dict) -> Dict:
        """Replace a user's full SCIM representation (PUT)."""
        payload = self._build_scim_user(user_data)
        payload["id"] = user_id
        logger.info("Updating SCIM user: %s", user_id)
        return self._request("PUT", f"/Users/{user_id}", json=payload)

    def patch_user(self, user_id: str, operations: List[Dict]) -> Dict:
        """Apply a SCIM PATCH to update specific attributes."""
        logger.info("Patching SCIM user: %s", user_id)
        payload = {
            "schemas":    [self._PATCH_OP_SCHEMA],
            "Operations": operations,
        }
        return self._request("PATCH", f"/Users/{user_id}", json=payload)

    def deactivate_user(self, user_id: str) -> Dict:
        """Deactivate a user by setting active=false via PATCH."""
        logger.info("Deactivating SCIM user: %s", user_id)
        return self.patch_user(user_id, [{"op": "replace", "path": "active", "value": False}])

    def delete_user(self, user_id: str) -> None:
        """Hard-delete a SCIM user (use deactivate_user for soft-delete)."""
        logger.info("Deleting SCIM user: %s", user_id)
        self._request("DELETE", f"/Users/{user_id}")

    # ------------------------------------------------------------------
    # Groups
    # ------------------------------------------------------------------

    def list_groups(self, filter_expr: Optional[str] = None) -> List[Dict]:
        return list(self._paginate("/Groups", filter_expr=filter_expr))

    def get_group(self, group_id: str) -> Dict:
        return self._request("GET", f"/Groups/{group_id}")

    def create_group(self, display_name: str, members: Optional[List[str]] = None) -> Dict:
        """Create a SCIM group. ``members`` is a list of SCIM user IDs."""
        logger.info("Creating SCIM group: %s", display_name)
        payload: Dict[str, Any] = {
            "schemas":     ["urn:ietf:params:scim:schemas:core:2.0:Group"],
            "displayName": display_name,
        }
        if members:
            payload["members"] = [{"value": m} for m in members]
        return self._request("POST", "/Groups", json=payload)

    def add_group_member(self, group_id: str, user_id: str) -> Dict:
        return self.patch_group(group_id, [{"op": "add", "path": "members", "value": [{"value": user_id}]}])

    def remove_group_member(self, group_id: str, user_id: str) -> Dict:
        return self.patch_group(group_id, [{"op": "remove", "path": f'members[value eq "{user_id}"]'}])

    def patch_group(self, group_id: str, operations: List[Dict]) -> Dict:
        payload = {
            "schemas":    [self._PATCH_OP_SCHEMA],
            "Operations": operations,
        }
        return self._request("PATCH", f"/Groups/{group_id}", json=payload)

    # ------------------------------------------------------------------
    # Bulk sync helper
    # ------------------------------------------------------------------

    def sync_users_from_source(self, source_users: List[Dict]) -> Dict[str, List[str]]:
        """Synchronise a list of source user records with Okta via SCIM.

        Parameters
        ----------
        source_users : List of dicts with at minimum ``userName`` (email).

        Returns
        -------
        Dict with keys ``created``, ``updated``, ``skipped`` containing userNames.
        """
        results: Dict[str, List[str]] = {"created": [], "updated": [], "skipped": []}

        for src in source_users:
            username = src.get("userName")
            if not username:
                logger.warning("Skipping record with no userName: %s", src)
                results["skipped"].append(str(src))
                continue

            existing = self.find_user_by_username(username)
            if existing:
                try:
                    self.update_user(existing["id"], src)
                    results["updated"].append(username)
                    logger.info("Updated user: %s", username)
                except ScimError as exc:
                    logger.error("Failed to update %s: %s", username, exc)
                    results["skipped"].append(username)
            else:
                try:
                    self.create_user(src)
                    results["created"].append(username)
                    logger.info("Created user: %s", username)
                except ScimError as exc:
                    logger.error("Failed to create %s: %s", username, exc)
                    results["skipped"].append(username)

        logger.info(
            "Sync complete. Created: %d  Updated: %d  Skipped: %d",
            len(results["created"]),
            len(results["updated"]),
            len(results["skipped"]),
        )
        return results

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _build_scim_user(self, data: Dict) -> Dict:
        """Normalise a user dict into a valid SCIM 2.0 User resource."""
        payload: Dict[str, Any] = {
            "schemas":  self._SCIM_SCHEMAS,
            "userName": data.get("userName") or data.get("email", ""),
            "active":   data.get("active", True),
        }

        # Name
        name = data.get("name", {})
        if name or data.get("firstName") or data.get("lastName"):
            payload["name"] = {
                "givenName":  name.get("givenName")  or data.get("firstName", ""),
                "familyName": name.get("familyName") or data.get("lastName", ""),
                "formatted":  name.get("formatted")  or f"{data.get('firstName', '')} {data.get('lastName', '')}".strip(),
            }

        # Emails
        if "emails" in data:
            payload["emails"] = data["emails"]
        elif "email" in data or "userName" in data:
            email = data.get("email") or data.get("userName", "")
            payload["emails"] = [{"value": email, "primary": True, "type": "work"}]

        # Phone
        if data.get("phoneNumber"):
            payload["phoneNumbers"] = [{"value": data["phoneNumber"], "type": "work"}]

        # Enterprise extension
        enterprise_attrs: Dict[str, Any] = {}
        for attr in ("employeeNumber", "department", "organization", "division", "costCenter", "manager"):
            if data.get(attr):
                enterprise_attrs[attr] = data[attr]
        if enterprise_attrs:
            payload["urn:ietf:params:scim:schemas:extension:enterprise:2.0:User"] = enterprise_attrs
            payload["schemas"].append("urn:ietf:params:scim:schemas:extension:enterprise:2.0:User")

        return payload
