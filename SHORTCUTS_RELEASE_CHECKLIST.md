# Shortcuts Release Checklist

This checklist keeps our shared shortcuts aligned with the "Achai-compatible" structure and prevents "open app only" regressions.

## Official Templates

- `ShortcutTemplates/xiaoxi-auto-bill-official.shortcut`
- `ShortcutTemplates/xiaoxi-open-record-official.shortcut`

## Required Structure

### Auto Bill (Achai-compatible)
1. Action 1: `is.workflow.actions.takescreenshot`
2. Action 2: `com.assetlife.app.AutoBillLegacyIntent`
3. Action 2 `image` parameter must be bound to Action 1 output (`ActionOutput`).
4. Must **not** contain `is.workflow.actions.useractivity.open`.

### Open Record
1. Action 1: `com.assetlife.app.OpenRecordLegacyIntent`
2. Must **not** contain `image` parameter.
3. Must **not** contain `is.workflow.actions.useractivity.open`.

## Automated Validation

Run before publishing iCloud share links:

```bash
python3 scripts/validate_shortcuts.py --profile auto-bill ShortcutTemplates/xiaoxi-auto-bill-official.shortcut
python3 scripts/validate_shortcuts.py --profile open-record ShortcutTemplates/xiaoxi-open-record-official.shortcut
```

Validate published iCloud links after sharing:

```bash
python3 scripts/validate_shortcuts.py --profile auto-bill https://www.icloud.com/shortcuts/<auto-bill-id>
python3 scripts/validate_shortcuts.py --profile open-record https://www.icloud.com/shortcuts/<open-record-id>
```

Expected output is `PASS`. Any `FAIL` means do not publish.

## Manual Runtime Verification

1. Delete old shortcuts on test device and re-import official templates.
2. Run auto-bill shortcut once.
3. Confirm app logs include:
   - `[App] Received autoBill user activity, imagePathFromActivity=...`
   - `[QuickRecord] recognizePendingImage at: ...`
4. Confirm amount/category are auto-filled on quick record page.
5. Run open-record shortcut and confirm it opens quick record page directly.

## Notes

- If logs show `imagePathFromActivity=nil` and `pendingImagePath=nil`, the shortcut is likely using `Open App` instead of an intent action.
- CloudKit SSL/network errors are unrelated to screenshot parameter passing.
