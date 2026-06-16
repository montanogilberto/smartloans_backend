# TODO - clientFaceRecognition liveness migration + docs

- [x] Read implementation files:
  - [x] modules/clientFaceRecognitions.py
  - [x] routes_/clientFaceRecognition.py
- [x] Read existing endpoint description files:
  - [x] docs_description/clientFaceRecognitions.txt
  - [x] docs_description/clientFaceRecognitions_all.txt
  - [x] docs_description/clientFaceRecognitions_one.txt
- [x] Create consolidated markdown documentation:
  - [x] docs_description/clientFaceRecognition.md

- [x] Implement Azure Face Liveness migration:
  - [x] Add create-session route in routes_/clientFaceRecognition.py
  - [x] Add create_azure_liveness_session() in modules/clientFaceRecognitions.py
  - [x] Refactor verify_clientFaceRecognition_connector() to use azureSessionId flow
  - [x] Keep response schema unchanged (isVerified, confidenceScore, idFrontImageBlobUrl, clientSelfieBlobUrl)

- [x] Update docs_description/clientFaceRecognition.md with liveness flow
- [ ] Run critical-path API verification (curl) or confirm skip
- [in-progress] Final review and handoff
