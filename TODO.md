# FreeTDS Assertion Crash Fix Plan

## Goal
Eliminate unsafe shared DB connection usage causing:
`tds_dataout_stream_write: Assertion 'stream->buffer == (char *) tds->out_buf + tds->out_pos' failed.`

## Steps
1. [x] Patch `modules/users.py`:
   - remove global `conn = connection()`
   - use per-call connection acquisition
   - close cursor/connection in `finally`
2. [x] Search `modules/*.py` for `conn = connection()` global pattern.
3. [x] Patch targeted high-traffic modules to per-call connection lifecycle:
   - [x] `modules/users.py`
   - [x] `modules/login.py`
   - [x] `modules/orders.py`
   - [x] `modules/productCategories.py` already safe before changes
   - [x] `modules/products.py` already safe before changes
4. [ ] Run syntax validation on modified files.
5. [ ] Mark completed steps and summarize changes.
