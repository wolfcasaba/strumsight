"""Sanitized MiniMax Token Plan quota checks."""

from __future__ import annotations

import json
import socket
import urllib.error
import urllib.request
from dataclasses import asdict, dataclass
from typing import Any, Callable


QUOTA_URL = "https://www.minimax.io/v1/token_plan/remains"
MAX_RESPONSE_BYTES = 65_536


@dataclass(frozen=True)
class QuotaStatus:
    status: str
    reachable: bool
    quota_known: bool
    remaining_units: int | None = None
    remaining_percent: int | None = None
    interval_remaining_percent: int | None = None
    weekly_remaining_percent: int | None = None
    reset_at: int | str | None = None
    interval_reset_at: int | str | None = None
    weekly_reset_at: int | str | None = None
    model: str | None = None

    def to_dict(self) -> dict[str, object]:
        return {key: value for key, value in asdict(self).items() if value is not None}


def _integer(value: object) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) and value >= 0 else None


def _percentage(value: object) -> int | None:
    parsed = _integer(value)
    return parsed if parsed is not None and parsed <= 100 else None


def _timestamp(value: object) -> int | str | None:
    if isinstance(value, (int, str)) and not isinstance(value, bool):
        return value
    return None


def parse_quota_payload(payload: object) -> QuotaStatus:
    if not isinstance(payload, dict):
        return QuotaStatus("unknown_response", True, False)
    base = payload.get("base_resp")
    if isinstance(base, dict) and base.get("status_code") not in (None, 0):
        return QuotaStatus("provider_error", True, False)
    remains = payload.get("model_remains")
    if not isinstance(remains, list) or not remains:
        return QuotaStatus("unknown_response", True, False)
    rows = [row for row in remains if isinstance(row, dict)]
    if not rows:
        return QuotaStatus("unknown_response", True, False)
    row = next(
        (
            item
            for item in rows
            if isinstance(item.get("model_name"), str)
            and item["model_name"].lower() == "general"
        ),
        next(
            (
                item
                for item in rows
                if isinstance(item.get("model_name"), str)
                and "m3" in item["model_name"].lower()
            ),
            rows[0],
        ),
    )
    model = row.get("model_name") if isinstance(row.get("model_name"), str) else None
    interval_percent = _percentage(row.get("current_interval_remaining_percent"))
    weekly_percent = _percentage(row.get("current_weekly_remaining_percent"))
    known_percentages = [value for value in (interval_percent, weekly_percent) if value is not None]
    if known_percentages:
        remaining_percent = min(known_percentages)
        interval_reset = _timestamp(row.get("end_time"))
        weekly_reset = _timestamp(row.get("weekly_end_time"))
        return QuotaStatus(
            status="ok" if remaining_percent > 0 else "quota_limited",
            reachable=True,
            quota_known=True,
            remaining_percent=remaining_percent,
            interval_remaining_percent=interval_percent,
            weekly_remaining_percent=weekly_percent,
            interval_reset_at=interval_reset,
            weekly_reset_at=weekly_reset,
            model=model,
        )
    total = _integer(row.get("current_interval_total_count"))
    used = _integer(row.get("current_interval_usage_count"))
    if total is None or used is None:
        return QuotaStatus("unknown_response", True, False)
    remaining = max(total - used, 0)
    return QuotaStatus(
        status="ok" if remaining > 0 else "quota_limited",
        reachable=True,
        quota_known=True,
        remaining_units=remaining,
        reset_at=_timestamp(row.get("current_interval_end_time")),
        model=model,
    )


def check_quota(
    api_key: str,
    *,
    opener: Callable[..., Any] = urllib.request.urlopen,
    timeout_seconds: float = 10,
) -> QuotaStatus:
    request = urllib.request.Request(QUOTA_URL, method="GET")
    request.add_header("Authorization", f"Bearer {api_key}")
    request.add_header("Content-Type", "application/json")
    try:
        with opener(request, timeout=timeout_seconds) as response:
            body = response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as error:
        if error.code in (401, 403):
            return QuotaStatus("credential_blocked", True, False)
        if error.code == 429:
            return QuotaStatus("quota_limited", True, False)
        if 500 <= error.code <= 599:
            return QuotaStatus("provider_transient", True, False)
        return QuotaStatus("provider_error", True, False)
    except (urllib.error.URLError, TimeoutError, socket.timeout, OSError):
        return QuotaStatus("provider_transient", False, False)
    if len(body) > MAX_RESPONSE_BYTES:
        return QuotaStatus("invalid_response", True, False)
    try:
        payload = json.loads(body.decode("utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        return QuotaStatus("invalid_response", True, False)
    return parse_quota_payload(payload)
