# Client Face Recognition - Consolidated Documentation

## Overview

This module provides CRUD operations and connector workflows for client face recognition.

It includes:

1. **CRUD endpoints** backed by SQL Server stored procedures.
2. **Biometric verification connector** that:
   - uploads ID and selfie images to Azure Blob Storage,
   - runs Azure Face API detect/verify,
   - returns verification outcome and blob URLs.
3. **Contract connector** that optionally uploads a contract PDF and persists verification/contract data through the CRUD SP.

Primary implementation files:
- `routes_/clientFaceRecognition.py`
- `modules/clientFaceRecognitions.py`
- Existing short docs:
  - `docs_description/clientFaceRecognitions.txt`
  - `docs_description/clientFaceRecognitions_all.txt`
  - `docs_description/clientFaceRecognitions_one.txt`

---

## Routes

Defined in `routes_/clientFaceRecognition.py`.

### 1) POST `/clientFaceRecognitions`
**Summary:** `clientFaceRecognitions CRUD`  
**Handler:** `clientFaceRecognitions_sp(json_file)`  
**Purpose:** Insert, update, or delete record(s) through stored procedure.

Stored procedure used:
- `EXEC [dbo].[sp_clientFaceRecognitions] @pjsonfile = <json>`

---

### 2) POST `/all_clientFaceRecognitions`
**Summary:** `all clientFaceRecognitions`  
**Handler:** `all_clientFaceRecognitions_sp(json_file)`  
**Purpose:** Fetch all records (typically filtered by company).

Stored procedure used:
- `EXEC [dbo].[sp_clientFaceRecognitions_all] @pjsonfile = <json>`

---

### 3) POST `/one_clientFaceRecognitions`
**Summary:** `one clientFaceRecognition`  
**Handler:** `one_clientFaceRecognitions_sp(json_file)`  
**Purpose:** Fetch one record by primary key.

Stored procedure used:
- `EXEC [dbo].[sp_clientFaceRecognitions_one] @pjsonfile = <json>`

---

### 4) POST `/api/clientFaceRecognition/upload-image`
**Summary:** `Upload a single ID/selfie image`
**Tags:** `connector`
**Handler:** `upload_id_image_connector(payload)` (async)
**Purpose:** Persists a single captured image (front/back/selfie) to blob storage
immediately, decoupled from the full verify+liveness flow, so a capture isn't
lost if the user doesn't finish the wizard. Returns only `{ blobUrl }` — no
database writes; the frontend upserts the `ClientFaceRecognitions` row itself
via the existing CRUD endpoint.

Input:
```json
{ "companyId": 1, "clientId": 123, "side": "front", "imageBase64": "<base64, no data-uri prefix>" }
```

Success response:
```json
{ "blobUrl": "https://.../clients/2026/07/front_123_20260705063633_360ca894.jpg" }
```

Validation errors (HTTP 400):
- `side` must be `"front"`, `"back"`, or `"selfie"`.
- `imageBase64` is required.

Blob naming: `clients/<YYYY>/<MM>/<side>_<clientId>_<timestamp>_<uid>.jpg`

---

### 5) POST `/api/clientFaceRecognition/verify`
**Summary:** `Biometric verify ClientFaceRecognition`  
**Tags:** `connector`  
**Handler:** `verify_clientFaceRecognition_connector(payload)` (async)  
**Purpose:** End-to-end biometric verification (upload + face detect + face verify).

---

### 6) POST `/api/clientFaceRecognition/contract`
**Summary:** `Submit contract ClientFaceRecognition`  
**Tags:** `connector`  
**Handler:** `contract_clientFaceRecognition_connector(payload)` (async)  
**Purpose:** Optional contract upload + persistence via CRUD SP.

---

## CRUD Payload Patterns

## `/clientFaceRecognitions` (CRUD)

From existing docs, example payload shape:
```json
{
  "action": 1,
  "companyId": 1,
  "documentType": "INE",
  "idFrontImageBlobUrl": "https://example.com/id.jpg",
  "clientSelfieBlobUrl": "https://example.com/selfie.jpg",
  "confidenceScore": 0.9834,
  "isVerified": true,
  "contractAccepted": true,
  "acceptedAt": "2023-10-27T10:00:00"
}
```

> Note: In module internals, the SP is commonly called with:
```json
{
  "clientFaceRecognitions": [
    {
      "...": "..."
    }
  ]
}
```
When integrating, align payload with your SP contract currently deployed in DB.

---

## `/all_clientFaceRecognitions`

Example:
```json
{
  "clientFaceRecognitions": [
    { "companyId": 1 }
  ]
}
```

---

## `/one_clientFaceRecognitions`

Example:
```json
{
  "companyId": 1,
  "clientFaceRecognitionId": 1
}
```

---

## Connector: Create Session (`/api/clientFaceRecognition/create-session`)

Implemented in `create_azure_liveness_session`.

### Purpose
Creates an Azure "Liveness With Verify" session and returns credentials/token
data for the frontend liveness capture flow. **Azure requires the reference
(ID) image at session-creation time** — it cannot be attached later — so the
caller must send the already-captured front ID image in this call.

### Azure call
- `POST {AZURE_FACE_API_ENDPOINT}/face/{AZURE_FACE_LIVENESS_API_VERSION}/detectLivenessWithVerify-sessions`
- **multipart/form-data**, not JSON.

### Request body (to this backend endpoint)
```json
{ "idFrontImageBase64": "<base64 image or data-uri>" }
```

### Form fields sent to Azure
```
livenessOperationMode: "PassiveActive"
deviceCorrelationId:   "<uuid>"
enableSessionImage:    "true"
verifyImage:           <file, from idFrontImageBase64>
```

### Response from backend
```json
{
  "sessionId": "<azure-session-id>",
  "authToken": "<short-lived-token>",
  "raw": { "...azure full payload..." }
}
```

### Known external blocker
Azure Face Liveness Detection is a gated feature (Face Recognition Limited
Access — https://aka.ms/facerecognition). If the configured
`AZURE_FACE_API_ENDPOINT` resource hasn't been approved for it, Azure returns
`403 UnsupportedFeature`. This is an approval/account issue, not a code bug —
confirm the resource has been granted access before assuming a code problem.

---

## Connector: Verification Flow (`/api/clientFaceRecognition/verify`)

Implemented in `verify_clientFaceRecognition_connector`.

### Input payload (expected)
Typical fields used by code:
```json
{
  "companyId": 1,
  "documentType": "INE",
  "idFrontImageBase64": "<base64 image or data-uri>",
  "azureSessionId": "<session-id-from-create-session>"
}
```

### Processing steps
1. Build blob paths under `clients/<YYYY>/<MM>/...`.
2. Upload `idFrontImageBase64` as JPEG to Azure Blob.
3. `GET {AZURE_FACE_API_ENDPOINT}/face/{AZURE_FACE_LIVENESS_API_VERSION}/detectLivenessWithVerify-sessions/{azureSessionId}`.
4. Read the **latest** entry in `results.attempts[]`:
   - `attempts[-1].result.livenessDecision`
   - `attempts[-1].result.verifyResult.isIdentical`
   - `attempts[-1].result.verifyResult.matchConfidence`
5. Azure's liveness-with-verify API does not return an extracted selfie frame
   (no `extractedFace` field exists) — `clientSelfieBlobUrl` is set to the
   uploaded ID image URL as a stand-in.
6. Compute:
   - `is_live = livenessDecision == "realface"`
   - `confidenceScore = matchConfidence`
   - `isVerified = is_live && isIdentical && confidenceScore >= 0.6`
7. If `results.attempts[]` is empty (session not completed yet), returns
   `isVerified: false` with an explanatory `error` rather than raising.

### Success response
```json
{
  "isVerified": true,
  "confidenceScore": 0.98,
  "idFrontImageBlobUrl": "https://.../clients/.../doc_id_....jpg",
  "clientSelfieBlobUrl": "https://.../clients/.../selfie_....jpg"
}
```

### No-face cases (handled as HTTP 200)
If no face in ID:
```json
{
  "isVerified": false,
  "confidenceScore": 0.0,
  "error": "No face detected in ID document",
  "idFrontImageBlobUrl": "https://...",
  "clientSelfieBlobUrl": "https://..."
}
```

If no face in selfie:
```json
{
  "isVerified": false,
  "confidenceScore": 0.0,
  "error": "No face detected in selfie",
  "idFrontImageBlobUrl": "https://...",
  "clientSelfieBlobUrl": "https://..."
}
```

### Error handling
Unexpected exceptions return:
- HTTP `500`
- Body:
```json
{ "error": "<exception message>" }
```

---

## Connector: Contract Flow (`/api/clientFaceRecognition/contract`)

Implemented in `contract_clientFaceRecognition_connector`.

### Input payload (used fields)
```json
{
  "companyId": 1,
  "documentType": "INE",
  "idFrontImageBlobUrl": "https://...",
  "clientSelfieBlobUrl": "https://...",
  "confidenceScore": 0.98,
  "isVerified": true,
  "contractAccepted": true,
  "acceptedAt": "2023-10-27T10:00:00",
  "contractPdfBlobUrl": "https://.../contract.pdf",
  "contractPdfBase64": "<optional base64 pdf>"
}
```

### Behavior
- If `contractPdfBase64` is provided and `contractPdfBlobUrl` is empty:
  - uploads PDF to Azure Blob path:
    - `clients/<YYYY>/<MM>/contract_<timestamp>_<uid>.pdf`
- Then persists data by calling `clientFaceRecognitions_sp(...)` with `action: 1`.

### Persistence payload generated by connector
```json
{
  "clientFaceRecognitions": [
    {
      "action": 1,
      "companyId": "...",
      "documentType": "...",
      "idFrontImageBlobUrl": "...",
      "clientSelfieBlobUrl": "...",
      "confidenceScore": 0.0,
      "isVerified": false,
      "contractAccepted": false,
      "acceptedAt": "..."
    }
  ]
}
```

---

## Environment Variables

Used by `modules/clientFaceRecognitions.py`:

- `AZURE_FACE_API_ENDPOINT`  
  Base endpoint for Azure Face API (trailing slash trimmed).
- `AZURE_FACE_API_KEY`  
  Subscription key for Face API.
- `AZURE_STORAGE_CONNECTION_STRING`  
  Required to instantiate `BlobServiceClient`.
- `CLIENTS_CONTAINER_NAME`  
  Blob container name, default: `"clients"`.
- `AZURE_STORAGE_ACCOUNT_URL_FALLBACK`  
  Optional fallback for building blob public URL when SDK service URL is unavailable.

---

## External Integrations

1. **SQL Server Stored Procedures**
   - `sp_clientFaceRecognitions`
   - `sp_clientFaceRecognitions_all`
   - `sp_clientFaceRecognitions_one`

2. **Azure Blob Storage**
   - Upload images/PDFs with metadata.
   - Uses `azure.storage.blob` (`BlobServiceClient`, `ContentSettings`).

3. **Azure Face API**
   - `POST /face/v1.0/detect` (for each image URL)
   - `POST /face/v1.0/verify` (faceId comparison)

4. **HTTP client**
   - `httpx.AsyncClient(timeout=30.0)`

---

## Blob Naming Conventions

Current patterns in code:
- ID image:
  - `clients/<YYYY>/<MM>/<documentType>_id_<timestamp>_<uid>.jpg`
- Selfie image:
  - `clients/<YYYY>/<MM>/selfie_<timestamp>_<uid>.jpg`
- Contract PDF:
  - `clients/<YYYY>/<MM>/contract_<timestamp>_<uid>.pdf`

`documentType` is normalized by replacing spaces with underscores.

---

## Confidence Logic

Threshold constant:
- `_CONFIDENCE_THRESHOLD = 0.6`

Final verification flag:
- `isVerified = isIdentical && confidence >= 0.6`

---

## cURL Examples

## CRUD
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/clientFaceRecognitions" \
  -H "Content-Type: application/json" \
  -d '{"action":1,"companyId":1,"documentType":"INE","idFrontImageBlobUrl":"https://example.com/id.jpg","clientSelfieBlobUrl":"https://example.com/selfie.jpg","confidenceScore":0.9834,"isVerified":true,"contractAccepted":true,"acceptedAt":"2023-10-27T10:00:00"}'
```

## All
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/all_clientFaceRecognitions" \
  -H "Content-Type: application/json" \
  -d '{"clientFaceRecognitions":[{"companyId":1}]}'
```

## One
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/one_clientFaceRecognitions" \
  -H "Content-Type: application/json" \
  -d '{"companyId":1,"clientFaceRecognitionId":1}'
```

## Create-session connector
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/api/clientFaceRecognition/create-session" \
  -H "Content-Type: application/json" \
  -d '{}'
```

## Upload single image connector
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/api/clientFaceRecognition/upload-image" \
  -H "Content-Type: application/json" \
  -d '{"companyId":1,"clientId":123,"side":"front","imageBase64":"<base64>"}'
```

## Verify connector
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/api/clientFaceRecognition/verify" \
  -H "Content-Type: application/json" \
  -d '{"companyId":1,"documentType":"INE","idFrontImageBase64":"<base64>","azureSessionId":"<session-id>"}'
```

## Contract connector
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/api/clientFaceRecognition/contract" \
  -H "Content-Type: application/json" \
  -d '{"companyId":1,"documentType":"INE","idFrontImageBlobUrl":"https://...","clientSelfieBlobUrl":"https://...","confidenceScore":0.98,"isVerified":true,"contractAccepted":true,"acceptedAt":"2023-10-27T10:00:00","contractPdfBase64":"<base64-pdf>"}'
```

---

## Notes

- All core DB/SP wrappers return `JSONResponse`.
- Empty list scenarios in `_all` and `_one` return:
  - `{ "clientFaceRecognitions": [] }`
- Connector endpoints are async and designed as orchestration services.
- For production hardening, consider validating missing required payload fields before processing base64/upload/API calls.
