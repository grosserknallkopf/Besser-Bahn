"""Besser-Bahn prediction API.

Thin HTTP wrapper around the bahnvorhersage delay-prediction model. It does
NOT talk to Deutsche Bahn — clients fetch journeys themselves (DB Vendo) and
POST the per-stop feature rows here; this service only runs the XGBoost model
and returns delay probabilities + transfer scores.

The model and the transfer-score maths come verbatim from the upstream image
(`ml_models.single_predictor.SinglePredictor`, `predictor_webserver.types`),
so predictions match bahnvorhersage.de 1:1. We only add: a rate limiter, a
health probe, and a convenience endpoint that derives the journey-level
Verbindungsscore + Pünktlichkeit.
"""
import os

from fastapi import FastAPI, Request
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

# Provided by the upstream base image (WORKDIR /usr/src/app).
from ml_models.single_predictor import SinglePredictor
from predictor_webserver.types import TransferData, PredictionResults
from public_config import OFFSET

from app.scores import journey_scores

# Per-IP limits. Override in Dokploy via env. The model is cheap, so the limit
# is really just abuse protection, not a capacity guard.
RATE_LIMIT = os.getenv("RATE_LIMIT", "60/minute")
GLOBAL_LIMIT = os.getenv("GLOBAL_RATE_LIMIT", "5000/hour")

limiter = Limiter(key_func=get_remote_address, default_limits=[GLOBAL_LIMIT])
app = FastAPI(title="Besser-Bahn Prediction API", version="1.0.0")
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Loads the XGBoost model + schema once at startup (a few MB, CPU-only).
predictor = SinglePredictor()


@app.get("/health")
def health():
    return {"status": "ok", "offset": OFFSET}


@app.post("/v1/rate-journeys")
@limiter.limit(RATE_LIMIT)
def rate_journeys(request: Request, transfer_data: TransferData):
    """Raw upstream contract: returns `predictions` (delay PMF per row),
    `transfer_scores` (0..1 per transfer row, null otherwise) and `offset`.

    Rows MUST alternate departure, arrival, departure, … starting with a
    departure (this is what the model was trained on)."""
    probas, transfer_scores = predictor.predict(transfer_data.to_polars())
    return PredictionResults(predictions=probas, transfer_scores=transfer_scores)


@app.post("/v1/journey-scores")
@limiter.limit(RATE_LIMIT)
def journey_scores_endpoint(request: Request, transfer_data: TransferData):
    """Same input as /v1/rate-journeys, but also returns the two
    human-facing numbers the app shows per connection:

    - `verbindungsscore`  — P(all transfers caught) = product of transfer scores
                            (null/100 for a direct connection).
    - `puenktlichkeit`    — P(final arrival ≤ 10 min late), from the last
                            arrival row's delay PMF.

    Both 0..100. `raw` carries the unprocessed predictions/transfer_scores."""
    probas, transfer_scores = predictor.predict(transfer_data.to_polars())
    derived = journey_scores(
        predictions=probas,
        transfer_scores=transfer_scores,
        is_arrival=transfer_data.is_arrival,
        offset=OFFSET,
    )
    raw = PredictionResults(predictions=probas, transfer_scores=transfer_scores)
    return {
        "verbindungsscore": derived["verbindungsscore"],
        "puenktlichkeit": derived["puenktlichkeit"],
        "raw": {
            "predictions": raw.predictions,
            "transfer_scores": raw.transfer_scores,
            "offset": raw.offset,
        },
    }
