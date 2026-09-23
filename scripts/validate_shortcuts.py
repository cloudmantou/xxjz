#!/usr/bin/env python3
"""
Validate official shortcut templates (local .shortcut files or iCloud links).

Usage examples:
  python3 scripts/validate_shortcuts.py --profile auto-bill ShortcutTemplates/xiaoxi-auto-bill-official.shortcut
  python3 scripts/validate_shortcuts.py --profile auto-bill https://www.icloud.com/shortcuts/<id>
  python3 scripts/validate_shortcuts.py --profile open-record ShortcutTemplates/xiaoxi-open-record-official.shortcut
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import sys
import urllib.request
from pathlib import Path
from typing import Any


ICLOUD_RE = re.compile(r"^https?://www\.icloud\.com/shortcuts/([0-9a-fA-F]+)$")

USER_ACTIVITY_OPEN = "is.workflow.actions.useractivity.open"
TAKE_SCREENSHOT = "is.workflow.actions.takescreenshot"
DETECT_TEXT = "is.workflow.actions.detect.text"
AUTO_BILL_INTENT = "com.assetlife.app.AutoBillLegacyIntent"
OPEN_RECORD_INTENT = "com.assetlife.app.OpenRecordLegacyIntent"


def fetch_bytes(url: str) -> bytes:
    req = urllib.request.Request(
        url,
        headers={
            "Accept": "application/json, text/plain, */*",
            "User-Agent": "shortcut-validator",
        },
    )
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.read()


def load_workflow(source: str) -> tuple[dict[str, Any], str]:
    source_path = Path(source)
    if source_path.exists():
        data = source_path.read_bytes()
        workflow = plistlib.loads(data)
        return workflow, f"file:{source_path}"

    match = ICLOUD_RE.match(source.strip())
    if not match:
        raise ValueError(f"Unsupported source: {source}")

    shortcut_id = match.group(1).lower()
    record_raw = fetch_bytes(f"https://www.icloud.com/shortcuts/api/records/{shortcut_id}")
    record = json.loads(record_raw)
    download_url = record["fields"]["shortcut"]["value"]["downloadURL"]
    display_name = record["fields"]["name"]["value"]
    workflow_raw = fetch_bytes(download_url)
    workflow = plistlib.loads(workflow_raw)
    return workflow, f"icloud:{display_name}:{shortcut_id}"


def validate_common(actions: list[dict[str, Any]], failures: list[str]) -> None:
    if not actions:
        failures.append("`WFWorkflowActions` is empty.")
        return

    for index, action in enumerate(actions, start=1):
        action_id = action.get("WFWorkflowActionIdentifier")
        if action_id == USER_ACTIVITY_OPEN:
            failures.append(
                f"Action {index} uses `{USER_ACTIVITY_OPEN}` (opens app only, does not pass screenshot)."
            )


def validate_auto_bill(actions: list[dict[str, Any]], failures: list[str]) -> None:
    # Accept both 2-action (image) and 3-action (text) variants
    if len(actions) not in (2, 3):
        failures.append(f"Auto-bill profile expects 2 or 3 actions, found {len(actions)}.")
        return

    first = actions[0]
    first_id = first.get("WFWorkflowActionIdentifier")
    if first_id != TAKE_SCREENSHOT:
        failures.append(f"Action 1 must be `{TAKE_SCREENSHOT}`, found `{first_id}`.")

    if len(actions) == 3:
        # Text-based: Screenshot → Extract Text → Intent(text=...)
        second = actions[1]
        third = actions[2]
        second_id = second.get("WFWorkflowActionIdentifier")
        third_id = third.get("WFWorkflowActionIdentifier")

        if second_id != DETECT_TEXT:
            failures.append(f"Action 2 must be `{DETECT_TEXT}`, found `{second_id}`.")
        if third_id != AUTO_BILL_INTENT:
            failures.append(f"Action 3 must be `{AUTO_BILL_INTENT}`, found `{third_id}`.")
            return

        second_uuid = (second.get("WFWorkflowActionParameters") or {}).get("UUID")
        third_params = third.get("WFWorkflowActionParameters") or {}
        text_param = third_params.get("text")

        if not isinstance(text_param, dict):
            failures.append("Action 3 is missing `text` parameter binding.")
            return

        if text_param.get("WFSerializationType") != "WFTextTokenAttachment":
            failures.append("Action 3 `text` parameter must use `WFTextTokenAttachment`.")
            return

        value = text_param.get("Value")
        if not isinstance(value, dict):
            failures.append("Action 3 `text` parameter has invalid `Value` payload.")
            return

        if value.get("Type") != "ActionOutput":
            failures.append("Action 3 `text.Value.Type` must be `ActionOutput`.")

        output_uuid = value.get("OutputUUID")
        if not output_uuid:
            failures.append("Action 3 `text.Value.OutputUUID` is missing.")
        elif second_uuid and output_uuid != second_uuid:
            failures.append("Action 3 `text` is not bound to Action 2 output UUID.")
    else:
        # Image-based: Screenshot → Intent(image=...)
        second = actions[1]
        second_id = second.get("WFWorkflowActionIdentifier")

        if second_id != AUTO_BILL_INTENT:
            failures.append(f"Action 2 must be `{AUTO_BILL_INTENT}`, found `{second_id}`.")
            return

        first_uuid = (first.get("WFWorkflowActionParameters") or {}).get("UUID")
        second_params = second.get("WFWorkflowActionParameters") or {}
        image = second_params.get("image")

        if not isinstance(image, dict):
            failures.append("Action 2 is missing `image` parameter binding.")
            return

        if image.get("WFSerializationType") != "WFTextTokenAttachment":
            failures.append("Action 2 `image` parameter must use `WFTextTokenAttachment`.")
            return

        value = image.get("Value")
        if not isinstance(value, dict):
            failures.append("Action 2 `image` parameter has invalid `Value` payload.")
            return

        if value.get("Type") != "ActionOutput":
            failures.append("Action 2 `image.Value.Type` must be `ActionOutput`.")

        output_uuid = value.get("OutputUUID")
        if not output_uuid:
            failures.append("Action 2 `image.Value.OutputUUID` is missing.")
        elif first_uuid and output_uuid != first_uuid:
            failures.append("Action 2 `image` is not bound to Action 1 output UUID.")


def validate_open_record(actions: list[dict[str, Any]], failures: list[str]) -> None:
    if len(actions) != 1:
        failures.append(f"Open-record profile expects exactly 1 action, found {len(actions)}.")
        return

    action = actions[0]
    action_id = action.get("WFWorkflowActionIdentifier")
    if action_id != OPEN_RECORD_INTENT:
        failures.append(
            f"Action 1 must be `{OPEN_RECORD_INTENT}`, found `{action_id}`."
        )
        return

    params = action.get("WFWorkflowActionParameters") or {}
    if "image" in params:
        failures.append("Open-record action must not contain `image` parameter.")


def detect_profile(source: str) -> str:
    lowered = source.lower()
    if "auto-bill" in lowered or "autobill" in lowered:
        return "auto-bill"
    if "open-record" in lowered or "record" in lowered:
        return "open-record"
    return "auto-bill"


def validate_source(source: str, forced_profile: str | None) -> tuple[bool, str]:
    workflow, label = load_workflow(source)
    actions = workflow.get("WFWorkflowActions", [])
    if not isinstance(actions, list):
        return False, f"[{label}] `WFWorkflowActions` is not a list."

    profile = forced_profile or detect_profile(source)
    failures: list[str] = []
    validate_common(actions, failures)

    if profile == "auto-bill":
        validate_auto_bill(actions, failures)
    elif profile == "open-record":
        validate_open_record(actions, failures)
    else:
        failures.append(f"Unknown profile: {profile}")

    if failures:
        joined = "\n".join(f"  - {item}" for item in failures)
        return False, f"[{label}] FAIL ({profile})\n{joined}"
    return True, f"[{label}] PASS ({profile})"


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate shortcut structures.")
    parser.add_argument(
        "sources",
        nargs="+",
        help="Local .shortcut file path(s) or iCloud shortcut link(s).",
    )
    parser.add_argument(
        "--profile",
        choices=["auto-bill", "open-record"],
        default=None,
        help="Validation profile to enforce.",
    )
    args = parser.parse_args()

    overall_ok = True
    for source in args.sources:
        try:
            ok, message = validate_source(source, args.profile)
        except Exception as exc:  # noqa: BLE001
            ok = False
            message = f"[{source}] ERROR: {exc}"
        print(message)
        overall_ok = overall_ok and ok

    return 0 if overall_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
