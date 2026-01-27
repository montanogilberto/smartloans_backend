"""
ml_search_worker.py

Robust MercadoLibre search worker that handles:
- Atomic dequeue with proper locking
- 403/WAF blocking with controlled retry logic
- Persist search runs (success or failure)
- Enqueue enrichment jobs for found items
"""

import os
import time
import json
import math
import random
import requests
import secrets
from datetime import datetime, timezone

# Configuration
BACKEND_BASE = os.getenv("BACKEND_BASE", "https://smartloansbackend.azurewebsites.net")
WORKER_KEY = os.getenv("WORKER_KEY", "")
LOCKED_BY = os.getenv("LOCKED_BY", "ml_worker_01")

DEFAULT_LOCK_SECONDS = int(os.getenv("LOCK_SECONDS", "120"))
MAX_ATTEMPTS = int(os.getenv("MAX_ATTEMPTS", "6"))

SLEEP_EMPTY = float(os.getenv("SLEEP_EMPTY", "2.0"))
SLEEP_ERROR = float(os.getenv("SLEEP_ERROR", "3.0"))


def utc_now_iso() -> str:
    """Returns current UTC time in ISO format with milliseconds."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def req_id() -> str:
    """Generates a unique 6-character hex request ID for tracing."""
    return secrets.token_hex(6)


def headers():
    """Returns base headers for API requests."""
    h = {"Content-Type": "application/json"}
    if WORKER_KEY:
        h["X-Worker-Key"] = WORKER_KEY
    return h


def post_json(path: str, payload: dict, rid: str) -> tuple[int, dict | str]:
    """Posts JSON payload to backend and returns (status_code, response)."""
    url = f"{BACKEND_BASE}{path}"
    r = requests.post(
        url,
        headers=headers() | {"X-Request-Id": rid},
        data=json.dumps(payload),
        timeout=30
    )
    try:
        return r.status_code, r.json()
    except Exception:
        return r.status_code, r.text


def get_json(path: str, params: dict | None = None, rid: str = None) -> tuple[int, dict | str]:
    """Makes a GET request and returns (status_code, response)."""
    url = f"{BACKEND_BASE}{path}"
    req_headers = headers()
    if rid:
        req_headers["X-Request-Id"] = rid
    r = requests.get(url, headers=req_headers, params=params, timeout=30)
    try:
        return r.status_code, r.json()
    except Exception:
        return r.status_code, r.text


def parse_sp_output(sp_resp: dict | str) -> dict:
    """
    Parses stored procedure output which may be a dict or JSON string.
    Normalizes to dict.
    """
    if isinstance(sp_resp, dict):
        return sp_resp
    try:
        return json.loads(sp_resp)
    except Exception:
        return {"raw": sp_resp}


def sp_first_result(d: dict) -> dict:
    """Extracts first result from SP response."""
    try:
        return d.get("result", [])[0] or {}
    except Exception:
        return {}


def dequeue_job() -> tuple[str, dict | None]:
    """
    Dequeues a job from the queue using action=4.
    Returns (request_id, job_dict or None).
    """
    rid = req_id()
    payload = {
        "jobs": [{
            "action": 4,
            "locked_by": LOCKED_BY,
            "lock_seconds": DEFAULT_LOCK_SECONDS
        }]
    }
    status, resp = post_json("/mlJobs", payload, rid)
    data = parse_sp_output(resp)
    r0 = sp_first_result(data)
    job_json = r0.get("job_json")
    
    if not job_json:
        return rid, None
    
    if isinstance(job_json, str):
        try:
            job_json = json.loads(job_json)
        except Exception:
            job_json = {"raw": job_json}
    
    return rid, job_json


def update_job(job_id: int, status_: str, last_error: dict | None, 
               unlock: bool = True, backoff_seconds: int | None = None):
    """
    Updates job status using action=2.
    
    Args:
        job_id: The job ID to update
        status_: One of 'succeeded', 'retry', 'failed_permanent'
        last_error: Error details dict or None
        unlock: Whether to release the lock
        backoff_seconds: Seconds until next retry (for retry status)
    """
    rid = req_id()
    job = {
        "action": 2,
        "job_id": job_id,
        "status": status_,
        "last_error": json.dumps(last_error) if last_error is not None else None,
        "unlock": unlock
    }
    if backoff_seconds is not None:
        job["backoff_seconds"] = int(backoff_seconds)
    
    payload = {"jobs": [job]}
    post_json("/mlJobs", payload, rid)


def enqueue_job(job_type: str, payload_json: dict, 
                priority: int = 100, available_in_seconds: int = 0,
                max_attempts: int = MAX_ATTEMPTS):
    """
    Enqueues a new job using action=1.
    
    Args:
        job_type: Type of job (e.g., 'search', 'enrich', 'score')
        payload_json: Job payload as dict
        priority: Job priority (lower = higher priority)
        available_in_seconds: Delay before job becomes available
        max_attempts: Maximum retry attempts
    """
    rid = req_id()
    payload = {
        "jobs": [{
            "action": 1,
            "job_type": job_type,
            "payload_json": payload_json,
            "priority": priority,
            "available_in_seconds": available_in_seconds,
            "max_attempts": max_attempts
        }]
    }
    post_json("/mlJobs", payload, rid)


def persist_search_run_failed(search_payload: dict, http_status: int, 
                             err: dict, started_at: str):
    """
    Persists a failed search run using action=1 on /mlSearchRuns.
    
    Args:
        search_payload: Original search job payload
        http_status: HTTP status code received
        err: Error details dict
        started_at: ISO timestamp when search started
    """
    rid = req_id()
    run = {
        "action": 1,
        "site_id": search_payload.get("site_id", "MLM"),
        "query_text": search_payload.get("query_text"),
        "domain_id": search_payload.get("domain_id"),
        "category_id": search_payload.get("category_id"),
        "filters_json": search_payload.get("filters_json", {"offset": 0, "limit": 50}),
        "status": "failed",
        "http_status": http_status,
        "error_json": err,
        "started_at": started_at,
        "finished_at": utc_now_iso()
    }
    payload = {"search_runs": [run]}
    post_json("/mlSearchRuns", payload, rid)


def persist_search_run_success(search_payload: dict, results: list, 
                               started_at: str, http_status: int = 200):
    """
    Persists a successful search run with results using action=1.
    
    Args:
        search_payload: Original search job payload
        results: List of normalized item results
        started_at: ISO timestamp when search started
        http_status: HTTP status code (usually 200)
    """
    rid = req_id()
    run = {
        "action": 1,
        "site_id": search_payload.get("site_id", "MLM"),
        "query_text": search_payload.get("query_text"),
        "domain_id": search_payload.get("domain_id"),
        "category_id": search_payload.get("category_id"),
        "filters_json": search_payload.get("filters_json", {"offset": 0, "limit": 50}),
        "status": "succeeded",
        "http_status": http_status,
        "error_json": None,
        "started_at": started_at,
        "finished_at": utc_now_iso(),
        "results": results
    }
    payload = {"search_runs": [run]}
    post_json("/mlSearchRuns", payload, rid)


def call_backend_ml_search(search_payload: dict) -> tuple[int, dict | str]:
    """
    Calls the backend /ml/search proxy endpoint.
    
    May return 403 (WAF blocked) or other HTTP errors.
    
    Args:
        search_payload: Search job payload with query_text, filters_json, etc.
        
    Returns:
        Tuple of (http_status_code, response_body)
    """
    rid = req_id()
    q = search_payload.get("query_text") or ""
    filters = search_payload.get("filters_json", {})
    
    params = {
        "q": q,
        "offset": filters.get("offset", 0),
        "limit": filters.get("limit", 50),
    }
    
    if search_payload.get("category_id"):
        params["category"] = search_payload["category_id"]
    if search_payload.get("seller_id"):
        params["seller_id"] = search_payload["seller_id"]
    
    url = f"{BACKEND_BASE}/ml/search"
    r = requests.get(
        url,
        headers=(headers() | {"X-Request-Id": rid}),
        params=params,
        timeout=30
    )
    
    try:
        return r.status_code, r.json()
    except Exception:
        return r.status_code, r.text


def call_backend_ml_item(item_id: str, site_id: str = "MLM") -> tuple[int, dict | str]:
    """
    Calls the backend /ml/items/{item_id} proxy endpoint for enrichment.
    
    Args:
        item_id: MercadoLibre item ID
        site_id: Site ID (default: MLM)
        
    Returns:
        Tuple of (http_status_code, response_body)
    """
    rid = req_id()
    url = f"{BACKEND_BASE}/ml/items/{item_id}"
    r = requests.get(
        url,
        headers=(headers() | {"X-Request-Id": rid}),
        timeout=30
    )
    
    try:
        return r.status_code, r.json()
    except Exception:
        return r.status_code, r.text


def normalize_results(ml_search_response: dict) -> list:
    """
    Maps MercadoLibre search response to normalized result format.
    
    Args:
        ml_search_response: Raw response from /ml/search
        
    Returns:
        List of normalized item dictionaries
    """
    out = []
    for it in ml_search_response.get("results", []) or []:
        out.append({
            "item_id": it.get("id"),
            "site_id": it.get("site_id"),
            "title": it.get("title"),
            "subtitle": it.get("subtitle"),
            "price": it.get("price"),
            "base_price": it.get("base_price"),
            "currency_id": it.get("currency_id"),
            "condition": it.get("condition"),
            "permalink": it.get("permalink"),
            "seller_id": (it.get("seller") or {}).get("id"),
            "seller_nickname": (it.get("seller") or {}).get("nickname"),
            "thumbnail": it.get("thumbnail"),
            "pictures_count": len(it.get("pictures", [])),
            "accepts_mercadopago": it.get("accepts_mercadopago"),
            "listing_type_id": it.get("listing_type_id"),
            "category_id": it.get("category_id"),
            "domain_id": it.get("domain_id"),
            "raw_json": it
        })
    return out


def normalize_item(item_response: dict) -> dict:
    """
    Normalizes a single item response for enrichment.
    
    Args:
        item_response: Raw response from /ml/items/{item_id}
        
    Returns:
        Normalized item dictionary
    """
    return {
        "item_id": item_response.get("id"),
        "site_id": item_response.get("site_id"),
        "title": item_response.get("title"),
        "subtitle": item_response.get("subtitle"),
        "price": item_response.get("price"),
        "base_price": item_response.get("base_price"),
        "currency_id": item_response.get("currency_id"),
        "condition": item_response.get("condition"),
        "listing_type_id": item_response.get("listing_type_id"),
        "category_id": item_response.get("category_id"),
        "domain_id": item_response.get("domain_id"),
        "permalink": item_response.get("permalink"),
        "thumbnail": item_response.get("thumbnail"),
        "seller_id": item_response.get("seller_id"),
        "seller_address": item_response.get("seller_address"),
        "initial_quantity": item_response.get("initial_quantity"),
        "available_quantity": item_response.get("available_quantity"),
        "sold_quantity": item_response.get("sold_quantity"),
        "accepts_mercadopago": item_response.get("accepts_mercadopago"),
        "attributes": item_response.get("attributes", []),
        "pictures": item_response.get("pictures", []),
        "raw_json": item_response
    }


def compute_backoff(attempts: int) -> int:
    """
    Computes exponential backoff with jitter.
    
    Args:
        attempts: Current attempt number (1-indexed)
        
    Returns:
        Seconds to wait before next retry
    """
    base = 60  # 1 minute base
    secs = min(3600, int(base * (2 ** max(0, attempts - 1))))  # Cap at 1 hour
    return int(secs * (0.7 + random.random() * 0.6))  # 70-130% jitter


def run_forever():
    """Main worker loop that processes jobs until stopped."""
    print(f"[ml_search_worker] Starting - backend={BACKEND_BASE} locked_by={LOCKED_BY}")
    print(f"[ml_search_worker] Config - lock_seconds={DEFAULT_LOCK_SECONDS} max_attempts={MAX_ATTEMPTS}")
    
    while True:
        try:
            rid, job = dequeue_job()
            
            if not job:
                time.sleep(SLEEP_EMPTY)
                continue
            
            job_id = int(job.get("job_id"))
            job_type = (job.get("job_type") or "").lower()
            attempts = int(job.get("attempts") or 0)
            max_attempts = int(job.get("max_attempts") or MAX_ATTEMPTS)
            
            # Parse payload_json
            payload_json = job.get("payload_json")
            if isinstance(payload_json, str):
                try:
                    payload_json = json.loads(payload_json)
                except Exception:
                    payload_json = {"raw": payload_json}
            
            print(f"[{rid}] Processing job_id={job_id} job_type={job_type} attempts={attempts}/{max_attempts}")
            
            # Handle non-search jobs
            if job_type != "search":
                print(f"[{rid}] Unsupported job_type={job_type}, marking failed_permanent")
                update_job(
                    job_id, 
                    "failed_permanent", 
                    {"msg": "unsupported job_type", "job_type": job_type},
                    unlock=True
                )
                continue
            
            # Execute search
            started_at = utc_now_iso()
            http_status, body = call_backend_ml_search(payload_json)
            
            # Success case
            if http_status == 200 and isinstance(body, dict):
                results = normalize_results(body)
                print(f"[{rid}] Search succeeded - {len(results)} results")
                
                # Persist search run with results
                persist_search_run_success(payload_json, results, started_at, http_status=200)
                
                # Enqueue enrichment jobs for each found item
                for r in results:
                    if r.get("item_id"):
                        enqueue_job(
                            "enrich",
                            {"item_id": r["item_id"], "site_id": r.get("site_id", "MLM")},
                            priority=200  # Higher priority than search
                        )
                        print(f"[{rid}] Enqueued enrich job for item_id={r['item_id']}")
                
                update_job(job_id, "succeeded", None, unlock=True)
                continue
            
            # Failure case - 403 or other error
            err_obj = {
                "http_status": http_status, 
                "body_preview": str(body)[:1200]
            }
            print(f"[{rid}] Search failed - http_status={http_status}")
            
            # Persist failed search run
            persist_search_run_failed(payload_json, http_status, err_obj, started_at)
            
            # Retry logic
            if attempts >= max_attempts:
                print(f"[{rid}] Max attempts reached ({max_attempts}), marking failed_permanent")
                update_job(job_id, "failed_permanent", err_obj, unlock=True)
            else:
                backoff = compute_backoff(attempts + 1)
                print(f"[{rid}] Scheduling retry {attempts + 1}/{max_attempts} in {backoff}s")
                update_job(job_id, "retry", err_obj, unlock=True, backoff_seconds=backoff)
        
        except Exception as e:
            print(f"[ml_search_worker] Loop error: {e}")
            import traceback
            traceback.print_exc()
            time.sleep(SLEEP_ERROR)


def run_enrich_worker():
    """Enrichment worker that processes enrich jobs using /ml/items/{item_id}."""
    print(f"[ml_enrich_worker] Starting - backend={BACKEND_BASE}")
    
    while True:
        try:
            rid, job = dequeue_job()
            
            if not job:
                time.sleep(SLEEP_EMPTY)
                continue
            
            job_id = int(job.get("job_id"))
            job_type = (job.get("job_type") or "").lower()
            attempts = int(job.get("attempts") or 0)
            
            payload_json = job.get("payload_json")
            if isinstance(payload_json, str):
                try:
                    payload_json = json.loads(payload_json)
                except Exception:
                    payload_json = {"raw": payload_json}
            
            if job_type != "enrich":
                update_job(job_id, "failed_permanent", {"msg": "unsupported job_type"}, unlock=True)
                continue
            
            item_id = payload_json.get("item_id")
            site_id = payload_json.get("site_id", "MLM")
            
            print(f"[{rid}] Enriching item_id={item_id}")
            
            http_status, body = call_backend_ml_item(item_id, site_id)
            
            if http_status == 200 and isinstance(body, dict):
                normalized = normalize_item(body)
                # TODO: Save to ml_item_features table
                # TODO: Enqueue score job
                print(f"[{rid}] Enrich succeeded for item_id={item_id}")
                update_job(job_id, "succeeded", None, unlock=True)
            else:
                err_obj = {"http_status": http_status, "body_preview": str(body)[:1200]}
                if attempts >= MAX_ATTEMPTS:
                    update_job(job_id, "failed_permanent", err_obj, unlock=True)
                else:
                    backoff = compute_backoff(attempts + 1)
                    update_job(job_id, "retry", err_obj, unlock=True, backoff_seconds=backoff)
        
        except Exception as e:
            print(f"[ml_enrich_worker] Loop error: {e}")
            time.sleep(SLEEP_ERROR)


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "enrich":
        run_enrich_worker()
    else:
        run_forever()

