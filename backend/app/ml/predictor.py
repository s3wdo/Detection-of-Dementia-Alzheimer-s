"""The predictor interface, the stub used until the real model arrives, and the factory."""
import hashlib
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from PIL import Image

from app.core.config import Settings
from app.db.models import MODEL_LABELS

log = logging.getLogger("neurosense.ml")


@dataclass(frozen=True)
class Prediction:
    probabilities: dict[str, float]  # one entry per label in MODEL_LABELS, sums to 1
    # Only from a real model: the image it actually analysed (PNG, after masking)
    # and its Grad-CAM map for the predicted class (grayscale PNG). The stub has neither.
    model_input_png: bytes | None = None
    heatmap_png: bytes | None = None
    explanation_method: str | None = None

    @property
    def label(self) -> str:
        return max(self.probabilities, key=self.probabilities.get)  # type: ignore[arg-type]

    @property
    def confidence(self) -> float:
        return self.probabilities[self.label]


class Predictor(Protocol):
    name: str
    version: str
    sha256: str | None
    simulated: bool

    def predict(self, image: Image.Image) -> Prediction: ...


class StubPredictor:
    """Stands in for the model. Its output is derived from the image bytes, so the
    same image always gives the same answer, and it is ALWAYS marked simulated.
    These numbers are not model outputs and say nothing about the scan.
    """

    name = "Stub predictor (no model connected)"
    version = "stub"
    sha256 = None
    simulated = True

    def predict(self, image: Image.Image) -> Prediction:
        digest = hashlib.sha256(image.tobytes()).digest()
        top = digest[0] % len(MODEL_LABELS)
        confidence = 0.60 + (digest[1] / 255) * 0.35  # 0.60 – 0.95
        rest = (1 - confidence) / (len(MODEL_LABELS) - 1)
        return Prediction({label: (confidence if i == top else rest) for i, label in enumerate(MODEL_LABELS)})

    def predict_many(self, images: list[Image.Image]) -> list[dict[str, float]]:
        return [self.predict(image).probabilities for image in images]


def build_predictor(settings: Settings) -> Predictor:
    """The real model when both the .pt file and a complete config are present;
    otherwise the stub. Never fails startup: a broken model file is logged and
    the stub is used, so results stay marked as simulated."""
    model_path, config_path = Path(settings.model_path), Path(settings.model_config_path)
    if not model_path.is_file():
        log.warning("No model file at %s: using the stub predictor (results are simulated).", model_path)
        return StubPredictor()
    try:
        from app.ml.torch_predictor import load_torch_predictor

        predictor = load_torch_predictor(model_path, config_path, allow_pickle=settings.allow_pickled_model)
        log.warning("Loaded model %s %s (sha256 %s).", predictor.name, predictor.version, predictor.sha256)
        return predictor
    except Exception as exc:  # noqa: BLE001 - any loading problem falls back to the stub
        log.error("Model could not be loaded (%s): using the stub predictor (results are simulated).", exc)
        return StubPredictor()
