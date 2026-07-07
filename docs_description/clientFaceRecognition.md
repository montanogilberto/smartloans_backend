# Client Face Recognition - Consolidated Documentation

## Overview

This module provides CRUD operations and connector workflows for client face recognition.

Liveness detection and face matching (selfie vs. ID photo) run entirely
client-side in the frontend via `@vladmandic/face-api` (a face-api.js fork).
The backend's role is limited to persisting captures/results and storing
images/contract PDFs in Azure Blob Storage — it no longer calls any face
detection/verification API.

It includes:

1. **CRUD endpoints** backed by SQL Server stored procedures.
2. **Image upload connector** that persists a single ID/selfie capture to
   Azure Blob Storage as soon as it's taken.
3. **Contract connector** that optionally uploads a contract PDF and persists
   verification/contract data through the CRUD SP.

Primary implementation files:
- `routes_/clientFaceRecognition.py`
- `modules/clientFaceRecognitions.py`
- Frontend liveness/match logic: `src/utils/faceLiveness.ts`, `src/components/FaceLivenessCapture.tsx`
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
immediately, decoupled from the wizard's completion, so a capture isn't
lost if the user doesn't finish. Returns only `{ blobUrl }` — no
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

### 5) POST `/api/clientFaceRecognition/contract`
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

## Client-side liveness + face match (replaces Azure Face Liveness)

Previously this module proxied Azure's "Liveness With Verify" API
(`/api/clientFaceRecognition/create-session` + `/api/clientFaceRecognition/verify`).
That gated, per-check-billed integration has been replaced entirely by a
self-hosted flow using `@vladmandic/face-api` running in the browser/WebView:

1. Frontend loads face-api.js model weights from `public/models/face-api`
   (`src/utils/faceLiveness.ts`, `loadFaceApiModels`).
2. `FaceLivenessCapture` opens the front camera, picks a random challenge
   (blink / turn-left / turn-right / smile), and waits for it to be detected
   from live video frames.
3. On success it captures a selfie frame and computes its face descriptor.
4. The page (`ClientFaceRecognitionPage.tsx` / `ClientsPage.tsx`) also computes
   a descriptor from the already-captured ID front photo
   (`getFaceDescriptorFromImage`), then compares the two via
   `compareFaceDescriptors` (Euclidean distance, threshold `0.6`).
5. The selfie is uploaded via `/api/clientFaceRecognition/upload-image`
   (`side: "selfie"`), and `confidenceScore`/`isVerified` are persisted via the
   existing CRUD endpoint (`upsertClientFaceRecognition`).

No backend call is made for the liveness check or the face match itself —
the backend only ever receives the final computed result plus the images to
store. There is no external vendor, no approval gate, and no per-check cost.

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

---

## Blob Naming Conventions

Current patterns in code:
- ID/selfie image (uploaded via `upload-image` connector):
  - `clients/<YYYY>/<MM>/<side>_<clientId>_<timestamp>_<uid>.jpg`
- Contract PDF:
  - `clients/<YYYY>/<MM>/contract_<timestamp>_<uid>.pdf`

`documentType` is normalized by replacing spaces with underscores.

---

## Confidence Logic

Computed entirely client-side in `src/utils/faceLiveness.ts`:
- `compareFaceDescriptors` — Euclidean distance between the ID and selfie
  face descriptors; match threshold `0.6` (face-api.js's own recommended cutoff).
- `distanceToConfidence` — maps that distance onto a `0-1` confidence figure
  for display/storage, replacing what used to be Azure's `matchConfidence`.

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

## Upload single image connector
```bash
curl -X POST "https://smartloansbackend.azurewebsites.net/api/clientFaceRecognition/upload-image" \
  -H "Content-Type: application/json" \
  -d '{"companyId":1,"clientId":123,"side":"front","imageBase64":"<base64>"}'
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
