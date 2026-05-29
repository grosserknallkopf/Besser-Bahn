#!/usr/bin/env python3
"""Smoke test for the Besser-Bahn prediction API.

Synthetic journey: Kiel -> Hamburg (RE7) --[transfer, 5 min min / 8 min sched]-->
Berlin (ICE 1701). Rows in sample_request.json alternate dep,arr,dep,arr.

Run against a running container (Dockerfile or the raw upstream image):

    # our wrapper:
    docker build -t besserbahn-predict prediction-service/
    docker run -p 8000:8000 besserbahn-predict
    python3 prediction-service/test/test_predict.py

    # or test the raw upstream endpoint directly:
    docker run -p 8000:8000 trainconnectionprediction/bahnvorhersage-predictor:latest
    BASE_URL=http://127.0.0.1:8000 ENDPOINT=/rate-journeys/ python3 .../test_predict.py

Exits 0 on success, 1 on failure.
"""
import json
import os
import sys
import urllib.request
from pathlib import Path

BASE_URL = os.getenv("BASE_URL", "http://127.0.0.1:8000")
# /v1/journey-scores (our wrapper) returns the derived numbers too.
ENDPOINT = os.getenv("ENDPOINT", "/v1/journey-scores")
SAMPLE = Path(__file__).with_name("sample_request.json")


def _post(path: str, body: dict) -> dict:
    req = urllib.request.Request(
        BASE_URL + path,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def main() -> int:
    payload = json.loads(SAMPLE.read_text())
    n_rows = len(payload["number"])
    print(f"POST {ENDPOINT}  ({n_rows} stop rows, 1 transfer)")

    try:
        # health first
        with urllib.request.urlopen(BASE_URL + "/health", timeout=10) as r:
            print("  health:", json.loads(r.read()))
    except Exception as e:  # noqa: BLE001 — raw upstream image has no /health
        print(f"  (no /health: {e})")

    resp = _post(ENDPOINT, payload)

    # The raw upstream endpoint returns predictions/transfer_scores/offset.
    # Our /v1/journey-scores nests those under "raw" and adds derived numbers.
    raw = resp.get("raw", resp)
    preds = raw["predictions"]
    scores = raw["transfer_scores"]
    offset = raw["offset"]

    assert len(preds) == n_rows, f"expected {n_rows} prediction rows, got {len(preds)}"
    assert len(scores) == n_rows, f"expected {n_rows} score entries, got {len(scores)}"

    # PMFs must each sum to ~1.
    for i, pmf in enumerate(preds):
        s = sum(pmf)
        assert 0.95 <= s <= 1.05, f"row {i} PMF sums to {s:.3f}, not ~1"

    # The single transfer is written onto BOTH its rows (arrival@B + departure@B),
    # so two non-null scores, equal, both in [0, 1].
    non_null = [s for s in scores if s is not None]
    assert len(non_null) == 2, f"expected 2 transfer-row scores, got {len(non_null)}: {scores}"
    ts = non_null[0]
    assert 0.0 <= ts <= 1.0, f"transfer score {ts} out of [0,1]"

    print(f"  offset = {offset}")
    print(f"  transfer score (catch prob) = {ts:.4f}  ({ts * 100:.1f}%)")

    if "verbindungsscore" in resp:
        print(f"  Verbindungsscore = {resp['verbindungsscore']}%")
        print(f"  Pünktlichkeit    = {resp['puenktlichkeit']}%")
        assert 0 <= resp["verbindungsscore"] <= 100
        assert 0 <= resp["puenktlichkeit"] <= 100

    print("\nPASS — model ran and returned sane probabilities.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as e:
        print(f"\nFAIL — {e}")
        sys.exit(1)
    except Exception as e:  # noqa: BLE001
        print(f"\nERROR — {type(e).__name__}: {e}")
        sys.exit(1)
