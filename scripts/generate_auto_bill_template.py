#!/usr/bin/env python3
"""
Generate the 2-step auto-bill shortcut template:
  1. Take Screenshot
  2. AutoBillLegacyIntent with image bound to screenshot output

Output: ShortcutTemplates/xiaoxi-auto-bill-official.shortcut
"""

import plistlib
import uuid
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT = REPO_ROOT / "ShortcutTemplates" / "xiaoxi-auto-bill-official.shortcut"

SCREENSHOT_UUID = "A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D"
INTENT_UUID   = "F6E5D4C3-B2A1-4F0E-9D8C-7B6A5F4E3D2B"

def main() -> None:
    screenshot_action = {
        "WFWorkflowActionIdentifier": "is.workflow.actions.takescreenshot",
        "WFWorkflowActionParameters": {
            "UUID": SCREENSHOT_UUID,
        },
    }

    intent_action = {
        "WFWorkflowActionIdentifier": "com.assetlife.app.AutoBillLegacyIntent",
        "WFWorkflowActionParameters": {
            "UUID": INTENT_UUID,
            "image": {
                "WFSerializationType": "WFTextTokenAttachment",
                "Value": {
                    "Type": "ActionOutput",
                    "OutputUUID": SCREENSHOT_UUID,
                    "OutputName": "Screenshot",
                },
            },
        },
    }

    workflow = {
        "WFQuickActionSurfaces": [],
        "WFWorkflowActions": [screenshot_action, intent_action],
        "WFWorkflowClientVersion": "1146.16",
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowHasShortcutInputVariables": False,
        "WFWorkflowIcon": {
            "WFWorkflowIconGlyphNumber": 57640,
            "WFWorkflowIconStartColor": 3019654015,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [
            "WFAppStoreAppContentItem",
            "WFArticleContentItem",
            "WFContactContentItem",
            "WFDateContentItem",
            "WFEmailAddressContentItem",
            "WFFolderContentItem",
            "WFGenericFileContentItem",
            "WFImageContentItem",
            "WFPDFContentItem",
            "WFPhoneNumberContentItem",
            "WFRichTextContentItem",
            "WFSafariWebPageContentItem",
            "WFStringContentItem",
            "WFURLContentItem",
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
