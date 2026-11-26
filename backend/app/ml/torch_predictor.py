"""Loads the trained PyTorch model and runs it on CPU.

Nothing about the model is assumed here. Input size, preprocessing, class order
and output type all come from model_config.yaml, which the model owner fills in
(see models/model_config.example.yaml). An incomplete config is an error.
"""
import hashlib
import io
import logging
from pathlib import Path

import numpy as np
import torch
import yaml
from PIL import Image

from app.db.models import MODEL_LABELS
from app.ml.predictor import Prediction

log = logging.getLogger("neurosense.ml")

_REQUIRED = ("name", "version", "input_size", "channels", "resize_interpolation", "scale", "mean", "std", "classes", "output")
_INTERPOLATION = {
    "nearest": Image.Resampling.NEAREST,
    "bilinear": Image.Resampling.BILINEAR,
    "bicubic": Image.Resampling.BICUBIC,
    # cv2.INTER_AREA, which the masking script used to make the training images.
    "area": "area",
}


class ModelConfigError(ValueError):
    pass


def load_config(path: Path) -> dict:
    if not path.is_file():
        raise ModelConfigError(f"model config not found at {path}")
    config = yaml.safe_load(path.read_text()) or {}
    missing = [key for key in _REQUIRED if config.get(key) is None]
    if missing:
        raise ModelConfigError("model config is missing: " + ", ".join(missing))
    if sorted(config["classes"]) != sorted(MODEL_LABELS):
        raise ModelConfigError(f"classes must be exactly {list(MODEL_LABELS)} in the model's output order")
    if config["channels"] not in (1, 3):
        raise ModelConfigError("channels must be 1 or 3")
    if len(config["mean"]) != config["channels"] or len(config["std"]) != config["channels"]:
        raise ModelConfigError("mean and std need one value per channel")
    if config["resize_interpolation"] not in _INTERPOLATION:
        raise ModelConfigError("resize_interpolation must be nearest, bilinear, bicubic or area")
    if config["output"] not in ("logits", "probabilities"):
        raise ModelConfigError("output must be 'logits' or 'probabilities'")
    # Optional steps. Absent means off, so an older config keeps working unchanged.
    if config.get("masking", "none") not in ("none", "brain_v1"):
        raise ModelConfigError("masking must be 'none' or 'brain_v1'")
    if config.get("explain", "none") not in ("none", "gradcam"):
        raise ModelConfigError("explain must be 'none' or 'gradcam'")
    return config


def _efficientnet_v2_s(outputs: int) -> torch.nn.Module:
    import torchvision

    model = torchvision.models.efficientnet_v2_s(weights=None)
    model.classifier[1] = torch.nn.Linear(model.classifier[1].in_features, outputs)
    return model


def _efficientnet_v2_s_linear(outputs: int) -> torch.nn.Module:
    """The same network with the classifier replaced by a single Linear layer
    (no dropout), as in single_rotating_best.pt (keys classifier.weight / .bias)."""
    import torchvision

    model = torchvision.models.efficientnet_v2_s(weights=None)
    model.classifier = torch.nn.Linear(1280, outputs)
    return model


# Architectures a weights-only file can be loaded into. The name comes from
# `architecture` in model_config.yaml; the server never picks one by itself.
ARCHITECTURES = {"efficientnet_v2_s": _efficientnet_v2_s, "efficientnet_v2_s_linear": _efficientnet_v2_s_linear}


def _load_module(path: Path, allow_pickle: bool, architecture: str | None = None) -> torch.nn.Module:
    """TorchScript first, then a weights-only file (tensors only, no code is run)
    into a declared architecture. A full pickled model only when explicitly
    allowed, because unpickling runs code from the file."""
    try:
        return torch.jit.load(str(path), map_location="cpu")
    except Exception:  # noqa: BLE001 - not a TorchScript archive
        pass
    try:
        weights = torch.load(str(path), map_location="cpu", weights_only=True)
    except Exception:  # noqa: BLE001 - not a plain weights file
        weights = None
    if isinstance(weights, dict):
        if architecture not in ARCHITECTURES:
            raise ValueError(
                "the file contains only weights (a state_dict). Set `architecture` in the model config "
                f"to one of {sorted(ARCHITECTURES)}, or ask the model owner for a TorchScript export"
            )
        module = ARCHITECTURES[architecture](len(MODEL_LABELS))
        module.load_state_dict(weights, strict=True)  # every tensor must match
        return module
    if not allow_pickle:
        raise ValueError(
            "the file is not TorchScript. To load a full pickled model from a trusted source, "
            "set ALLOW_PICKLED_MODEL=true"
        )
    loaded = torch.load(str(path), map_location="cpu", weights_only=False)
    if isinstance(loaded, dict):
        raise ValueError(
            "the file contains only weights (a state_dict). The model's architecture code is "
            "required to load it: ask the model owner for a TorchScript export or the model class"
        )
    if not isinstance(loaded, torch.nn.Module):
        raise ValueError("the file does not contain a PyTorch model")
    return loaded


class TorchPredictor:
    simulated = False

    def __init__(self, module: torch.nn.Module, config: dict, sha256: str):
        self._module = module.eval()
        self._config = config
        # Until the model owner confirms preprocessing and class order, every
        # result carries this note in its model name.
        note = "" if config.get("confirmed") is True else " (settings unconfirmed)"
        self.confirmed = not note
        self.name = str(config["name"])[: 80 - len(note)] + note
        self.version = str(config["version"])
        self.sha256 = sha256

    def preprocess(self, image: Image.Image) -> torch.Tensor:
        c = self._config
        size = int(c["input_size"])
        image = image.convert("L" if c["channels"] == 1 else "RGB")
        if image.size != (size, size):
            method = _INTERPOLATION[c["resize_interpolation"]]
            if method == "area":
                import cv2

                image = Image.fromarray(cv2.resize(np.asarray(image), (size, size), interpolation=cv2.INTER_AREA))
            else:
                image = image.resize((size, size), method)
        array = np.asarray(image, dtype=np.float32) * float(c["scale"])
        if array.ndim == 2:
            array = array[:, :, None]
        array = (array - np.asarray(c["mean"], dtype=np.float32)) / np.asarray(c["std"], dtype=np.float32)
        return torch.from_numpy(array).permute(2, 0, 1).unsqueeze(0)  # NCHW

    def model_input(self, image: Image.Image) -> Image.Image:
        """The image as the model sees it: brain-masked first when the config says so."""
        if self._config.get("masking", "none") == "brain_v1":
            from app.ml.masking import mask_for_model

            return mask_for_model(image)
        return image

    def predict_many(self, images: list[Image.Image], batch: int = 16) -> list[dict[str, float]]:
        """Class probabilities for images that are already the model's input
        (masked slices); used for the slices of a full scan."""
        results: list[dict[str, float]] = []
        for start in range(0, len(images), batch):
            tensor = torch.cat([self.preprocess(im) for im in images[start : start + batch]])
            with torch.inference_mode():
                output = self._module(tensor)
            output = output[0] if isinstance(output, (tuple, list)) else output
            if output.shape[-1] != len(MODEL_LABELS):
                raise ValueError(f"model returned {output.shape[-1]} values, expected {len(MODEL_LABELS)}")
            if self._config["output"] == "logits":
                output = torch.softmax(output, dim=1)
            for row in output:
                results.append({label: float(row[i]) for i, label in enumerate(self._config["classes"])})
        return results

    def explain(self, image: Image.Image, label: str) -> tuple[bytes | None, str | None]:
        """Grad-CAM for `label` on a model-input image, when the config asks for it."""
        if self._config.get("explain", "none") != "gradcam" or not hasattr(self._module, "features"):
            return None, None
        try:
            from app.ml.gradcam import grad_cam, heatmap_png

            index = list(self._config["classes"]).index(label)
            return heatmap_png(grad_cam(self._module, self.preprocess(image), index)), "gradcam"
        except Exception:  # noqa: BLE001 - a missing map must not lose the prediction
            log.error("Grad-CAM failed; the result is stored without a map")
            return None, None

    def predict(self, image: Image.Image) -> Prediction:
        image = self.model_input(image)
        probabilities = self.predict_many([image])[0]
        heatmap, method = self.explain(image, max(probabilities, key=probabilities.get))
        shown = io.BytesIO()
        image.save(shown, format="PNG")
        return Prediction(probabilities, model_input_png=shown.getvalue(), heatmap_png=heatmap, explanation_method=method)


def load_torch_predictor(model_path: Path, config_path: Path, *, allow_pickle: bool) -> TorchPredictor:
    config = load_config(config_path)
    sha256 = hashlib.sha256(model_path.read_bytes()).hexdigest()
    return TorchPredictor(_load_module(model_path, allow_pickle, config.get("architecture")), config, sha256)
