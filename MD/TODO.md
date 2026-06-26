# TODO - Stripe connected accounts 500 debug instrumentation

- [x] Review Stripe routes/module flow (`routes_/stripe_payments.py`, `modules/stripe_payments.py`).
- [x] Add detailed debug prints in `create_connected_account`.
- [x] Add detailed debug prints in `get_connected_account_status`.
- [x] Add defensive normalization/logging for unexpected `_sp_connected_accounts` return types.
- [ ] Re-run and verify logs identify exact failing point.
