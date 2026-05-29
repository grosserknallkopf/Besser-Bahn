# Besser-Bahn Prediction API

Self-hosted train delay / connection-reliability prediction. Wraps the
[bahnvorhersage](https://gitlab.com/bahnvorhersage/bahnvorhersage) XGBoost model
in a small rate-limited HTTP API.

**It never talks to Deutsche Bahn.** Clients fetch journeys themselves (the app
already does this via the DB Vendo backend) and POST the per-stop feature rows
here. This service only runs the model. So DB load stays distributed across
users' devices — we don't proxy or scrape DB, and we don't hit bahnvorhersage's
server (whose API is explicitly off-limits). We only reuse their **published
model**, which is the sanctioned path.

## Resources

CPU-only. No GPU, no CUDA — the deps are `xgboost` + `scikit-learn` + `numpy`
(inference is millisecond tree scoring). ~0.5–1 GB RAM, 1 vCPU is plenty.
Image is ~1.6 GB (fat Python base, not the model).

## Endpoints

| Method | Path                  | Notes |
|--------|-----------------------|-------|
| GET    | `/health`             | `{status, offset}` |
| POST   | `/v1/rate-journeys`   | Raw upstream contract: `{predictions, transfer_scores, offset}` |
| POST   | `/v1/journey-scores`  | Adds derived `verbindungsscore` + `puenktlichkeit` (0..100) |
| GET    | `/redoc`, `/docs`     | OpenAPI |

### Input (both POST endpoints)

Columnar `TransferData` — one entry per stop event, all lists same length, rows
**alternating departure, arrival, departure, … starting with a departure**.
A transfer is an (arrival, next-departure) pair; set `minimal_transfer_time`
and `prognosed_transfer_time` on that **arrival** row, `null` elsewhere. See
[`test/sample_request.json`](test/sample_request.json) for a complete example.

Fields: `number, lat, lon, stop_sequence, distance_traveled,
dwell_time_schedule, dwell_time_prognosed, bearing, delay_prognosed,
minute_of_day, minutes_to_prognosed_time, weekday, is_regional, is_arrival,
operator, category, line, prognosed_transfer_time, minimal_transfer_time`.

### Output (`/v1/journey-scores`)

```json
{
  "verbindungsscore": 91.5,   // P(all transfers caught), 0..100, null if direct
  "puenktlichkeit": 72.0,     // P(final arrival ≤ 10 min late), 0..100
  "raw": { "predictions": [[...]], "transfer_scores": [null, 0.915, ...], "offset": 3 }
}
```

`predictions[i]` is a delay PMF: index `offset` = prognosis correct, `offset+k`
= +k min. `transfer_scores[i]` ∈ [0,1] on transfer-arrival rows, else null.

## Run locally

```bash
docker build -t besserbahn-predict .
docker run -p 8000:8000 besserbahn-predict
python3 test/test_predict.py            # smoke test, exits 0 on success
```

Test the **raw upstream** model directly (no wrapper):

```bash
docker run -p 8000:8000 trainconnectionprediction/bahnvorhersage-predictor:latest
BASE_URL=http://127.0.0.1:8000 ENDPOINT=/rate-journeys/ python3 test/test_predict.py
```

## Deploy on Dokploy

Either:

- **Dockerfile app** — new Application, Build type **Dockerfile**, point at this
  repo. Expose port `8000`. Set env `RATE_LIMIT`, `GLOBAL_RATE_LIMIT`.
- **Compose** — deploy `docker-compose.yml` as-is.

The base image is rebuilt weekly upstream with a fresh model; redeploy (no
cache) to pull the latest. Pin a digest if you want reproducibility.

## Config (env)

| Var | Default | Meaning |
|-----|---------|---------|
| `RATE_LIMIT` | `60/minute` | per-IP, per-endpoint |
| `GLOBAL_RATE_LIMIT` | `5000/hour` | per-IP overall |
| `MODEL_PATH` | `cache/xgboost_model.ubj` | from base image |

## Credit

Model + transfer-score maths: **bahnvorhersage.de** team
(`gitlab.com/bahnvorhersage/bahnvorhersage`). This service only re-hosts their
published predictor image and adds an HTTP layer.
