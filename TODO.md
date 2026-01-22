# MercadoLibre OAuth 403 Debugging - TODO

## ✅ Completed Steps

### 1. Enhanced ml_proxy.py with Comprehensive Debugging
**File**: `routes_/ml_proxy.py`

Added detailed logging to all endpoints:
- `/ml/search` - Main search endpoint
- `/ml/items/{item_id}` - Item detail endpoint  
- `/ml/whoami` - Token validation debug endpoint

**New Debug Logs Include**:
- `TOKEN present: True/False` and token length
- `Has Authorization: True/False` 
- `UA: [User-Agent string]`
- `All headers keys: [list]`
- Detailed 403 retry logic with logging

### 2. Enhanced mercadolibre.py with Database Debugging
**File**: `modules/mercadolibre.py`

Added comprehensive database connection and token management logging:
- `[DB] Connection created - server: X, database: Y`
- `[DB] Tokens retrieved - has_access: True, access_len: XX`
- `[DB] Tokens inserted/updated - token_id: X`
- `[Token] Current token status - has_token: True, token_len: XX`
- `[Token] Token refreshed successfully`

### 3. Enhanced mercadolibre.py callback with Debugging
**File**: `routes_/mercadolibre.py`

Added callback logging:
- `[OAuth] Callback received - code_len: X, state: xxx...`
- `[OAuth] Token exchange successful - user_id: X, access_len: XX`
- `[OAuth] Tokens saved successfully - user_id: X`

## 🔍 Testing Instructions

### Step 1: Test OAuth Flow (if not already done)
```bash
# 1. Navigate to authorize URL
GET /mercadolibre/oauth/authorize

# 2. Complete OAuth in browser (ML will redirect)
# 3. Check callback response - should show:
{"ok": true, "saved": true, "user_id": "XXXXXX"}
```

### Step 2: Check Token Retrieval
```bash
# Test /ml/whoami endpoint
GET /ml/whoami

# Expected response (if working):
{"id": XXXXX, "nickname": "...", ...}

# Expected logs:
# [TOKEN present: True, token_len: XX]
# [Has Authorization: True]
# [DB] Connection created - server: sql.bsite.net\MSSQL2016, database: montanogilberto_smartloans
```

### Step 3: Test Search Endpoint
```bash
# Test search (should trigger 403 debugging)
GET /ml/search?q=iphone

# Expected logs:
# [TOKEN present: True, token_len: XX]
# [Has Authorization: True]
# [UA: Mozilla/5.0...]
# [All headers keys: [...]]
# [ML search WITH token status=403]
# [403 WITH token -> retry WITHOUT token]
```

## 📊 Expected Log Analysis

### Scenario A: Token Not Being Sent (Issue #1)
```
[TOKEN present: False, len: 0]
[Has Authorization: False]
→ Fix: Check get_valid_access_token() implementation
```

### Scenario B: Database Mismatch (Issue #2)
```
[OAuth] Tokens saved - server: sql.bsite.net\MSSQL2016, database: montanogilberto_smartloans
[DB] Tokens retrieved - server: DIFFERENT_SERVER, database: DIFFERENT_DB
→ Fix: Ensure all components use same database connection
```

### Scenario C: Token Expired/Invalid
```
[Token] Token expired, refreshing...
[OAuth] Token refresh failed (401): ...
→ Fix: Re-run OAuth flow to get new tokens
```

### Scenario D: Working Correctly
```
[TOKEN present: True, token_len: 51]
[Has Authorization: True]
[ML search WITH token status=200]
→ No issues found
```

## 🔧 Common Fixes

### Fix 1: Different Database Connection
If logs show different servers:
- Check `databases.py` connection string
- Ensure environment variables are consistent
- Verify Azure App Service configuration

### Fix 2: Token Expiration
If token is expired:
- Call `/mercadolibre/oauth/authorize` to re-authenticate
- Check token expiration in logs: `expires_at: ...`

### Fix 3: Missing Environment Variables
If `ML_CLIENT_ID`, `ML_CLIENT_SECRET` not loaded:
- Check `.env` file
- Verify Azure App Service Application Settings
- Check logs for: `ML_CLIENT_ID loaded? False`

## 📝 Log Output Locations

- **Local Development**: Console output / Terminal
- **Azure App Service**: Log Stream / Kudu / Application Insights
- **FastAPI Logs**: Configured logger (check `main.py` logging setup)

## 🚨 Next Actions

1. **Deploy changes** to production
2. **Monitor logs** when calling `/ml/search?q=iphone`
3. **Check log output** for debugging information
4. **Identify root cause** from log patterns above
5. **Apply fix** based on identified issue

## 📞 Debugging Commands

```bash
# Check current token status
curl https://your-api.com/ml/whoami

# Test search (should show 403 if broken)
curl "https://your-api.com/ml/search?q=iphone"

# View logs (Azure)
az webapp log tail --name smartloansbackend

# View logs (local)
python main.py
```

