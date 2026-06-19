# Push Notifications Debug Workflow TODO

- [x] Review push notification request flow (`routes_/pushNotification.py` -> `modules/pushNotifications.py` -> SQL SP).
- [x] Add `print()` tracing in `routes_/pushNotification.py` for request in/out.
- [x] Add `print()` tracing in `modules/pushNotifications.py` for DB execution, SP output, action branching, Azure push call, and exceptions.
- [x] Keep endpoint behavior unchanged (only add diagnostics).
- [ ] Run a quick syntax/import verification.
