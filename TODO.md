# TODO - Azure Notification Hub Reliability Fixes

- [ ] Update `modules/azure_notifications.py` to read env vars at runtime inside `send_azure_push`.
- [ ] Add explicit diagnostics logs:
  - [ ] Hub name
  - [ ] Connection string presence (boolean only)
  - [ ] Signed URI
  - [ ] Notification format
  - [ ] Target tag
  - [ ] Final payload JSON
- [ ] Improve payload/format handling:
  - [ ] Default to `fcm` format with Android-safe payload (`data`).
  - [ ] Allow override via env var for backward compatibility.
- [ ] Keep SAS signing URI and POST URI aligned and log the exact signed URI.
- [ ] Preserve current return contract (`sent`, `reason`, `status_code`, `response_text`).
- [ ] Add guidance notes in `PUSH_NOTIFICATIONS.md` about required device installation tags (e.g., `user_123`) for targeted delivery.
