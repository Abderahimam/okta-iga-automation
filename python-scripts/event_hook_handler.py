"""
event_hook_handler.py
---------------------
Okta Event Hook processing and automation engine.

Receives Okta event hook POST requests, validates the payload signature,
and dispatches events to registered handler functions for automated responses.

Supported events (examples):
  - user.lifecycle.create          → send welcome email, assign default groups
  - user.lifecycle.deactivate      → revoke app access, notify IT
  - user.authentication.sso        → risk scoring, geo-anomaly detection
  - user.mfa.factor.activate       → audit logging
  - user.account.lock              → notify security team

Usage:
    # Run the built-in development server (NOT for production)
    python event_hook_handler.py

    # In production, deploy behind gunicorn/uvicorn and an API gateway.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
from datetime import datetime, timezone
from functools import wraps
from typing import Any, Callable, Dict, List, Optional

from flask import Flask, jsonify, request, Response

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("event_hook_handler")

# ---------------------------------------------------------------------------
# Flask app
# ---------------------------------------------------------------------------

app = Flask(__name__)

# ---------------------------------------------------------------------------
# Configuration  (override via environment variables)
# ---------------------------------------------------------------------------

OKTA_HOOK_SECRET      = os.getenv("OKTA_HOOK_SECRET", "")          # HMAC shared secret
OKTA_VERIFICATION_KEY = os.getenv("OKTA_HOOK_VERIFY_KEY", "")      # One-time verification key
REQUIRE_SIGNATURE     = os.getenv("OKTA_REQUIRE_SIGNATURE", "true").lower() == "true"

# ---------------------------------------------------------------------------
# Signature verification
# ---------------------------------------------------------------------------

def verify_signature(payload: bytes, header_signature: str) -> bool:
    """Validate the Okta-provided HMAC-SHA256 signature.

    Okta signs the raw request body with a shared secret.
    The header value is ``x-okta-verification-challenge`` during setup,
    and ``x-okta-request-id`` + custom headers during live events.

    For full production hardening, follow:
    https://developer.okta.com/docs/concepts/event-hooks/#verifying-requests
    """
    if not OKTA_HOOK_SECRET:
        logger.warning("OKTA_HOOK_SECRET not set – skipping signature verification.")
        return True

    expected = hmac.new(
        OKTA_HOOK_SECRET.encode("utf-8"),
        payload,
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(expected, header_signature)


def require_valid_signature(func: Callable) -> Callable:
    """Decorator that rejects requests with invalid signatures."""
    @wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> Any:
        if not REQUIRE_SIGNATURE:
            return func(*args, **kwargs)

        sig_header = request.headers.get("x-okta-signature", "")
        if not sig_header:
            logger.warning("Missing signature header. Rejecting request.")
            return jsonify({"error": "Missing signature"}), 401

        if not verify_signature(request.get_data(), sig_header):
            logger.warning("Signature mismatch. Rejecting request.")
            return jsonify({"error": "Invalid signature"}), 401

        return func(*args, **kwargs)
    return wrapper


# ---------------------------------------------------------------------------
# Event registry
# ---------------------------------------------------------------------------

_handlers: Dict[str, List[Callable[[Dict], None]]] = {}


def register_handler(event_type: str) -> Callable:
    """Decorator to register a function as an event handler.

    Usage::

        @register_handler("user.lifecycle.create")
        def on_user_created(event: dict) -> None:
            ...
    """
    def decorator(func: Callable) -> Callable:
        _handlers.setdefault(event_type, []).append(func)
        logger.info("Registered handler '%s' for event '%s'.", func.__name__, event_type)
        return func
    return decorator


def dispatch_event(event: Dict) -> None:
    """Invoke all registered handlers for the given event."""
    event_type = event.get("eventType", "")
    handlers   = _handlers.get(event_type, [])

    if not handlers:
        logger.debug("No handlers registered for event type: %s", event_type)
        return

    for handler in handlers:
        try:
            logger.info("Dispatching '%s' to handler '%s'.", event_type, handler.__name__)
            handler(event)
        except Exception as exc:  # noqa: BLE001
            logger.error(
                "Handler '%s' raised %s for event '%s': %s",
                handler.__name__, type(exc).__name__, event_type, exc,
                exc_info=True,
            )


# ---------------------------------------------------------------------------
# HTTP endpoints
# ---------------------------------------------------------------------------

@app.route("/healthz", methods=["GET"])
def health_check() -> Response:
    """Kubernetes/ALB liveness probe endpoint."""
    return jsonify({"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()})


@app.route("/okta/events", methods=["GET"])
def okta_verify() -> Response:
    """One-time verification endpoint called by Okta during hook registration."""
    challenge = request.args.get("challenge") or OKTA_VERIFICATION_KEY
    if not challenge:
        return jsonify({"error": "No challenge provided"}), 400
    logger.info("Okta verification challenge received.")
    return jsonify({"verification": challenge})


@app.route("/okta/events", methods=["POST"])
@require_valid_signature
def okta_event_hook() -> Response:
    """Main event hook endpoint. Receives and processes Okta event payloads."""
    body = request.get_json(silent=True)
    if not body:
        logger.error("Empty or non-JSON payload received.")
        return jsonify({"error": "Invalid payload"}), 400

    events: List[Dict] = body.get("data", {}).get("events", [])
    if not events:
        logger.warning("Payload contained no events: %s", body)
        return jsonify({"processed": 0}), 200

    logger.info("Received %d event(s).", len(events))
    for event in events:
        dispatch_event(event)

    return jsonify({"processed": len(events)}), 200


# ---------------------------------------------------------------------------
# Built-in event handlers
# ---------------------------------------------------------------------------

@register_handler("user.lifecycle.create")
def on_user_created(event: Dict) -> None:
    """Triggered when a new Okta user is created."""
    actor  = event.get("actor", {})
    target = (event.get("target") or [{}])[0]
    logger.info(
        "New user created | actor=%s | newUser=%s",
        actor.get("alternateId"), target.get("alternateId"),
    )
    # TODO: integrate with HR system / send welcome email / assign birthright groups


@register_handler("user.lifecycle.deactivate")
def on_user_deactivated(event: Dict) -> None:
    """Triggered when a user account is deactivated (Leaver workflow)."""
    target = (event.get("target") or [{}])[0]
    logger.info("User deactivated: %s", target.get("alternateId"))
    # TODO: revoke all application access, notify IT helpdesk, archive data


@register_handler("user.session.start")
def on_user_login(event: Dict) -> None:
    """Triggered on every successful authentication."""
    actor  = event.get("actor", {})
    client = event.get("client", {})
    geo    = client.get("geographicalContext", {})
    logger.info(
        "User login | user=%s | ip=%s | city=%s | country=%s",
        actor.get("alternateId"),
        client.get("ipAddress"),
        geo.get("city"),
        geo.get("country"),
    )
    # TODO: risk scoring, impossible-travel detection


@register_handler("user.authentication.sso")
def on_sso_event(event: Dict) -> None:
    """Triggered on SSO authentication to an application."""
    actor  = event.get("actor", {})
    target = (event.get("target") or [{}])[0]
    outcome = event.get("outcome", {}).get("result", "UNKNOWN")
    logger.info(
        "SSO event | user=%s | app=%s | outcome=%s",
        actor.get("alternateId"), target.get("displayName"), outcome,
    )


@register_handler("user.account.lock")
def on_account_locked(event: Dict) -> None:
    """Triggered when a user account is locked out."""
    target = (event.get("target") or [{}])[0]
    logger.warning("Account locked: %s", target.get("alternateId"))
    # TODO: notify security team via PagerDuty / Slack


@register_handler("user.mfa.factor.activate")
def on_mfa_factor_enrolled(event: Dict) -> None:
    """Triggered when a user enrolls a new MFA factor."""
    actor  = event.get("actor", {})
    target = (event.get("target") or [{}])[0]
    logger.info(
        "MFA factor enrolled | user=%s | factor=%s",
        actor.get("alternateId"), target.get("displayName"),
    )


@register_handler("policy.lifecycle.update")
def on_policy_updated(event: Dict) -> None:
    """Triggered when an Okta policy is modified – important for SOX audit trails."""
    actor  = event.get("actor", {})
    target = (event.get("target") or [{}])[0]
    logger.warning(
        "Policy updated (AUDIT) | actor=%s | policy=%s",
        actor.get("alternateId"), target.get("displayName"),
    )


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port  = int(os.getenv("PORT", "8080"))
    debug = os.getenv("FLASK_DEBUG", "false").lower() == "true"
    logger.info("Starting event hook handler on port %d (debug=%s).", port, debug)
    app.run(host="0.0.0.0", port=port, debug=debug)
