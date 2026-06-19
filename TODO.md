# Azure Notification Hubs Integration TODO

- [x] Add `modules/azure_notifications.py` helper for SAS token generation and Azure Hub REST dispatch with `httpx`.
- [x] Convert `pushNotifications_sp` in `modules/pushNotifications.py` to async and call Azure dispatch after successful DB execution when `action == 1`.
- [x] Update `routes_/pushNotification.py` so `/pushNotifications` route is async and awaits handler.
- [x] Add `httpx` dependency to `requirements.txt`.
- [x] Run a quick syntax/import verification.
