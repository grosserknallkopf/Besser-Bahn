# Besser-Bahn prediction API.
#
# Built on top of bahnvorhersage's published predictor image, which already
# carries the trained XGBoost model (cache/xgboost_model.ubj), the data schema,
# and every Python dep (fastapi, xgboost, scikit-learn, polars, numpy, …) plus
# the ml_models / predictor_webserver / public_config packages we import.
# The base is rebuilt weekly upstream — re-pull to get the latest model.
FROM trainconnectionprediction/bahnvorhersage-predictor:latest

WORKDIR /usr/src/app

# Add our only extra dependency (the rate limiter). Root for the install,
# then drop back to the unprivileged user the base image defines (uid 420).
USER root
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Our wrapper. The base already provides everything app.main imports.
COPY app/ /usr/src/app/app/

USER tcp

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
