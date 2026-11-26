"""Step 3 of the full-scan pipeline: the team's brain-slice detector
(EfficientNetV2S_brain_detector.keras, used by FilterScans.py).

The detector is a Keras 3 model (EfficientNetV2-S, one sigmoid output). It is
run with Keras on the PyTorch backend, so the server needs no TensorFlow.
FilterScans.py keeps a slice when its score is below 0.4; the same threshold
is used here.
"""
from __future__ import annotations

import hashlib
import logging
import os
from pathlib import Path

import numpy as np

log = logging.getLogger("neurosense.ml")

# From FilterScans.py (THRESHOLD = 0.4): slices scoring below it are kept.
DEFAULT_THRESHOLD = 0.4


class KerasBrainFilter:
    def __init__(self, path: Path, threshold: float = DEFAULT_THRESHOLD):
        os.environ.setdefault("KERAS_BACKEND", "torch")
        import keras

        if keras.backend.backend() != "torch":
            raise RuntimeError("the brain detector must run on the Keras PyTorch backend")
        self._model = keras.models.load_model(str(path), compile=False)
        self.threshold = threshold
        self.sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
        self.name = "EfficientNetV2-S brain detector"

    def scores(self, slices_rgb_224: np.ndarray) -> np.ndarray:
        # Raw 0..255 RGB, as in FilterScans.py; the model contains its own preprocessing.
        batch = np.asarray(slices_rgb_224, dtype=np.float32)
        return np.asarray(self._model.predict(batch, verbose=0)).reshape(-1)


def build_brain_filter(path: str, threshold: float = DEFAULT_THRESHOLD) -> KerasBrainFilter | None:
    """The detector, or None when its file is missing or cannot be loaded. Without it,
    full-scan uploads are refused: the filtering step is never skipped."""
    file = Path(path)
    if not file.is_file():
        log.warning("No brain detector at %s: full-scan (.nii) uploads are disabled.", file)
        return None
    try:
        detector = KerasBrainFilter(file, threshold)
        log.warning("Loaded brain detector (sha256 %s).", detector.sha256)
        return detector
    except Exception as exc:  # noqa: BLE001
        log.error("Brain detector could not be loaded (%s): full-scan uploads are disabled.", exc)
        return None
