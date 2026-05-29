"""Derive the two journey-level numbers the app displays from the model's raw
output. Logic mirrors what the bahnvorhersage.de frontend shows.

Input rows alternate departure, arrival, departure, … starting with a
departure (the upstream `SinglePredictor.predict` contract):

    idx 0  dep @ A
    idx 1  arr @ B   \\ transfer at B (idx 1 + idx 2)
    idx 2  dep @ B   /
    idx 3  arr @ C   (final arrival)
"""
from typing import Optional

import numpy as np
import numpy.typing as npt


def connection_score(
    transfer_scores: npt.NDArray, is_arrival: list[bool]
) -> Optional[float]:
    """Verbindungsscore 0..100 = product of each transfer's catch probability.

    The model writes the same score onto BOTH rows of a transfer (the arrival
    and the following departure), so we count each transfer once by taking only
    the arrival rows. Returns None for a direct connection (no transfers)."""
    valid = [
        s
        for s, arr in zip(transfer_scores.tolist(), is_arrival)
        if arr and s is not None and not np.isnan(s)
    ]
    if not valid:
        return None
    prod = 1.0
    for s in valid:
        prod *= s
    return round(prod * 100, 1)


def punctuality(
    predictions: npt.NDArray,
    is_arrival: list[bool],
    offset: int,
    threshold_min: int = 10,
) -> Optional[float]:
    """Pünktlichkeit 0..100 = P(final-arrival extra delay ≤ threshold_min).

    Sums the last arrival row's PMF up to `offset + threshold_min`."""
    arrival_idx = [i for i, a in enumerate(is_arrival) if a]
    if not arrival_idx:
        return None
    last = arrival_idx[-1]
    pmf = predictions[last]
    cut = offset + threshold_min
    return round(float(np.sum(pmf[: cut + 1])) * 100, 1)


def journey_scores(
    predictions: npt.NDArray,
    transfer_scores: npt.NDArray,
    is_arrival: list[bool],
    offset: int,
) -> dict:
    return {
        "verbindungsscore": connection_score(transfer_scores, is_arrival),
        "puenktlichkeit": punctuality(predictions, is_arrival, offset),
    }
