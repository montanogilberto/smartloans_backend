# Push Notifications Fix Workflow TODO

- [x] Review push notification request flow (`routes_/pushNotification.py` -> `modules/pushNotifications.py` -> SQL SP).
- [x] Identify bug: Azure push is sent when `action == 1` even if SP response status is error.
- [x] Update `modules/pushNotifications.py` to parse SP response before action branch.
- [x] Gate Azure push send with: `action == 1` and SP response indicates success.
- [x] Keep API response body aligned with SP response payload.
- [ ] Run a quick syntax/import verification.
