"""
cache.py — In-memory prediction cache for Smart Inverter backend.

Stores pre-trained XGBoost models and their last predictions so that
/predict/load and /predict/solar can respond in < 200ms.
"""

import time
from dataclasses import dataclass, field
from typing import Any


@dataclass
class PredictionCache:
    # Trained XGBoost model objects
    load_model: Any = None
    solar_model: Any = None

    # Last computed predictions (list of {time, value})
    load_predictions: list = field(default_factory=list)
    solar_predictions: list = field(default_factory=list)

    # Prediction metadata (how was the prediction made?)
    solar_data_source: str = "unknown"   # real_data | panel_specs | historical_peak | unavailable
    solar_warning: str | None = None     # shown in Flutter UI as an info banner
    load_data_source: str = "unknown"

    # Metadata
    last_refreshed_at: float = 0.0       # unix timestamp
    training_data_points: int = 0        # how many real data points trained on
    load_mae: float = 0.0                # mean absolute error (load model)
    solar_mae: float = 0.0              # mean absolute error (solar model)
    is_ready: bool = False               # True after first successful train

    def age_seconds(self) -> int:
        """Seconds since last successful refresh."""
        if self.last_refreshed_at == 0:
            return -1
        return int(time.time() - self.last_refreshed_at)

    def age_label(self) -> str:
        """Human-readable cache age string."""
        s = self.age_seconds()
        if s < 0:
            return "Not yet trained"
        if s < 60:
            return f"{s}s ago"
        if s < 3600:
            return f"{s // 60}m ago"
        return f"{s // 3600}h ago"


# Global singleton — imported by main.py and ml_predictor.py
prediction_cache = PredictionCache()
