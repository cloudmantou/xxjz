#!/usr/bin/env python3
"""
Generate the 3-step text-fallback auto-bill shortcut template:
  1. Take Screenshot
  2. Detect Text
  3. AutoBillLegacyIntent with text bound to extracted text output

Output: ShortcutTemplates/xiaoxi-auto-bill-text-fallback.shortcut
"""

import plistlib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "ShortcutTemplates" / "xiaoxi-auto-bill-text-fallback.shortcut"

SCREENSHOT_UUID = "11A2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"
DETECT_TEXT_UUID = "22B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"
INTENT_UUID = "33C2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"


def main() -> None:
    screenshot_action = {
        "WFWorkflowActionIdentifier": "is.workflow.actions.takescreenshot",
        "WFWorkflowActionParameters": {
            "UUID": SCREENSHOT_UUID,
        },
    }

    detect_text_action = {
        "WFWorkflowActionIdentifier": "is.workflow.actions.detect.text",
        "WFWorkflowActionParameters": {
            "UUID": DETECT_TEXT_UUID,
            "WFInput": {
                "WFSerializationType": "WFTextTokenAttachment",
                "Value": {
                    "Type": "ActionOutput",
                    "OutputUUID": SCREENSHOT_UUID,
                    "OutputName": "Screenshot",
                },
            },
        },
    }

    intent_action = {
        "WFWorkflowActionIdentifier": "com.assetlife.app.AutoBillLegacyIntent",
        "WFWorkflowActionParameters": {
            "UUID": INTENT_UUID,
            "text": {
                "WFSerializationType": "WFTextTokenAttachment",
                "Value": {
                    "Type": "ActionOutput",
                    "OutputUUID": DETECT_TEXT_UUID,
                    "OutputName": "Text",
                },
            },
        },
    }

    workflow = {
        "WFQuickActionSurfaces": [],
        "WFWorkflowActions": [screenshot_action, detect_text_action, intent_action],
        "WFWorkflowClientVersion": "1146.16",
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowIcon": {
            "WFWorkflowIconGlyphNumber": 57640,
            "WFWorkflowIconStartColor": 3019654015,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [
            "WFImageContentItem",
            "WFRichTextContentItem",
            "WFStringContentItem",
        ],
        "WFWorkflowMinimumClientVersion": 1,
        "WFWorkflowMinimumClientVersionString": "1",
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": ["NCWidget", "WatchKit"],
    }

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "wb") as f:
        plistlib.dump(workflow, f, fmt=plistlib.FMT_BINARY)

    print(f"Generated: {OUTPUT}")


if __name__ == "__main__":
    main()
