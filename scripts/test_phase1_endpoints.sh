#!/bin/bash
# Banking-first Phase 1 — endpoint smoke against the deployed backend.
# Safe: STP runs in MOCK mode until STP_* env vars exist (no real money).
# Usage: ./scripts/test_phase1_endpoints.sh [BASE_URL]
set -e
BASE="${1:-https://smartloansbackend.azurewebsites.net}"
CID=2165; CO=1008; TS=$(date +%s)
j() { python3 -m json.tool 2>/dev/null || cat; }

echo "== 1. link CLABE (checksum-valid test CLABE) =="
LINK=$(curl -s -X POST $BASE/bank-account/link -H "Content-Type: application/json" \
  -d "{\"clientId\":$CID,\"companyId\":$CO,\"clabe\":\"014180000000099655\",\"holderName\":\"GILBERTO MONTANO QUIHUIS\"}")
echo "$LINK" | j
BA=$(echo "$LINK" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('bankAccountId',''))")
CENTS=$(echo "$LINK" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('mockVerificationCents',''))")

if [ -n "$BA" ] && [ -n "$CENTS" ]; then
echo "== 2. verify micro-deposit =="
curl -s -X POST $BASE/bank-account/verify -H "Content-Type: application/json" \
  -d "{\"clientId\":$CID,\"companyId\":$CO,\"bankAccountId\":$BA,\"amountCents\":$CENTS}" | j
fi

echo "== 3. simulate SPEI-in: DEPOSIT 500 =="
curl -s -X POST $BASE/walletTransactions -H "Content-Type: application/json" \
  -d "{\"walletTransactions\":[{\"action\":1,\"companyId\":$CO,\"clientId\":$CID,\"entryType\":\"DEPOSIT\",\"direction\":\"C\",\"amountMXN\":500,\"idempotencyKey\":\"curl:dep:$TS\"}]}" | j

echo "== 4. balance =="
curl -s -X POST $BASE/ledger/balance -H "Content-Type: application/json" \
  -d "{\"companyId\":$CO,\"clientId\":$CID}" | j

echo "== 5. disburse payout 100 (mock STP → settled + CEP) =="
curl -s -X POST $BASE/payments/disburse -H "Content-Type: application/json" \
  -d "{\"companyId\":$CO,\"clientId\":$CID,\"purpose\":\"lender_payout\",\"amountMXN\":100,\"idempotencyKey\":\"curl:payout:$TS\"}" | j

echo "== 6. status =="
curl -s -X POST $BASE/payments/status -H "Content-Type: application/json" \
  -d "{\"companyId\":$CO,\"idempotencyKey\":\"curl:payout:$TS\"}" | j

echo "== 7. statement =="
curl -s -X POST $BASE/all_walletTransactions -H "Content-Type: application/json" \
  -d "{\"walletTransactions\":[{\"companyId\":$CO,\"clientId\":$CID}]}" | j
