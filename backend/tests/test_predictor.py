"""The predictor on its own (no API): the stub, and loading a .pt file.
The tiny models built here only test the loading code; they are not NeuroSense models."""
from pathlib import Path

import pytest
import torch
import yaml
from PIL import Image

from app.core.config import get_settings
from app.db.models import MODEL_LABELS
from app.ml.predictor import StubPredictor, build_predictor
from app.ml.torch_predictor import ModelConfigError, load_config, load_torch_predictor

CONFIG = {
    "name": "TinyTestNet",
    "version": "test",
    "input_size": 32,
    "channels": 1,
    "resize_interpolation": "bilinear",
    "scale": 1 / 255,
    "mean": [0.5],
    "std": [0.5],
    "classes": ["AD", "LMCI", "EMCI", "CN"],
    "output": "logits",
}


class Tiny(torch.nn.Module):
    """Always favours output unit 2, whatever the input."""

    def __init__(self):
        super().__init__()
        self.pool = torch.nn.AdaptiveAvgPool2d(1)

    def forward(self, x):
        base = self.pool(x).flatten(1) * 0
        return base + torch.tensor([[0.0, 0.0, 3.0, 0.0]])


def _write_config(folder: Path, **changes) -> Path:
    path = folder / "model_config.yaml"
    path.write_text(yaml.safe_dump({**CONFIG, **changes}))
    return path


def _image():
    return Image.new("L", (128, 128), 120)


def test_stub_is_deterministic_and_always_simulated():
    stub = StubPredictor()
    first, second = stub.predict(_image()), stub.predict(_image())
    assert first == second
    assert stub.simulated is True
    assert set(first.probabilities) == set(MODEL_LABELS)
    assert abs(sum(first.probabilities.values()) - 1) < 1e-9
    assert first.confidence == max(first.probabilities.values())


def test_torchscript_model_loads_and_uses_the_configured_class_order(tmp_path):
    model_path = tmp_path / "model.pt"
    torch.jit.script(Tiny()).save(str(model_path))
    predictor = load_torch_predictor(model_path, _write_config(tmp_path), allow_pickle=False)

    prediction = predictor.predict(_image())
    assert predictor.simulated is False and len(predictor.sha256) == 64
    assert prediction.label == "EMCI"  # unit 2 in the configured order
    assert abs(sum(prediction.probabilities.values()) - 1) < 1e-5

    # The same weights with a different configured order give a different label:
    # the order must come from the model owner, it cannot be guessed.
    reordered = _write_config(tmp_path, classes=["CN", "EMCI", "LMCI", "AD"])
    assert load_torch_predictor(model_path, reordered, allow_pickle=False).predict(_image()).label == "LMCI"


def test_pickled_model_needs_explicit_permission(tmp_path):
    model_path = tmp_path / "model.pt"
    torch.save(Tiny(), str(model_path))
    config = _write_config(tmp_path)
    with pytest.raises(ValueError, match="ALLOW_PICKLED_MODEL"):
        load_torch_predictor(model_path, config, allow_pickle=False)
    assert load_torch_predictor(model_path, config, allow_pickle=True).predict(_image()).label == "EMCI"


def test_weights_only_file_needs_a_declared_architecture(tmp_path):
    model_path = tmp_path / "model.pt"
    torch.save(torch.nn.Linear(4, 4).state_dict(), str(model_path))
    with pytest.raises(ValueError, match="architecture"):
        load_torch_predictor(model_path, _write_config(tmp_path), allow_pickle=True)
    # Weights that do not fit the declared architecture are refused too.
    with pytest.raises(RuntimeError):
        load_torch_predictor(model_path, _write_config(tmp_path, architecture="efficientnet_v2_s"), allow_pickle=False)


def test_weights_only_file_loads_into_the_declared_architecture(tmp_path):
    from app.ml.torch_predictor import ARCHITECTURES

    model_path = tmp_path / "model.pt"
    torch.save(ARCHITECTURES["efficientnet_v2_s"](4).state_dict(), str(model_path))
    settings = {"architecture": "efficientnet_v2_s", "channels": 3, "input_size": 64, "mean": [0.5] * 3, "std": [0.5] * 3}
    predictor = load_torch_predictor(model_path, _write_config(tmp_path, **settings), allow_pickle=False)
    prediction = predictor.predict(_image())
    assert predictor.simulated is False
    assert abs(sum(prediction.probabilities.values()) - 1) < 1e-5
    # Not confirmed by the model owner: every result says so in its model name.
    assert predictor.name == "TinyTestNet (settings unconfirmed)"
    confirmed = load_torch_predictor(model_path, _write_config(tmp_path, confirmed=True, **settings), allow_pickle=False)
    assert confirmed.name == "TinyTestNet"


@pytest.mark.parametrize(
    "changes",
    [
        {"classes": None},
        {"mean": None},
        {"classes": ["A", "B", "C", "D"]},
        {"classes": ["AD", "LMCI", "EMCI"]},
        {"channels": 2},
        {"mean": [0.5, 0.5]},
        {"output": "sigmoid"},
        {"resize_interpolation": "lanczos"},
    ],
)
def test_incomplete_or_wrong_config_is_refused(tmp_path, changes):
    with pytest.raises(ModelConfigError):
        load_config(_write_config(tmp_path, **changes))


def test_wrong_number_of_outputs_is_an_error(tmp_path):
    model_path = tmp_path / "model.pt"
    torch.jit.script(torch.nn.Sequential(torch.nn.Flatten(), torch.nn.Linear(32 * 32, 3))).save(str(model_path))
    predictor = load_torch_predictor(model_path, _write_config(tmp_path), allow_pickle=False)
    with pytest.raises(ValueError, match="expected 4"):
        predictor.predict(_image())


def test_factory_falls_back_to_the_stub(tmp_path):
    settings = get_settings()

    def build(**overrides):
        return build_predictor(settings.model_copy(update=overrides))

    # No file.
    assert build(model_path=str(tmp_path / "missing.pt")).simulated is True
    # A file but no config: the real model is NOT used with guessed settings.
    model_path = tmp_path / "model.pt"
    torch.jit.script(Tiny()).save(str(model_path))
    assert build(model_path=str(model_path), model_config_path=str(tmp_path / "none.yaml")).simulated is True
    # A corrupt file.
    bad = tmp_path / "bad.pt"
    bad.write_bytes(b"not a model")
    assert build(model_path=str(bad), model_config_path=str(_write_config(tmp_path))).simulated is True
    # File and complete config: the real predictor.
    real = build(model_path=str(model_path), model_config_path=str(_write_config(tmp_path)))
    assert real.simulated is False and real.name.startswith("TinyTestNet")


def test_newer_weights_with_a_single_linear_classifier_load(tmp_path):
    from app.ml.torch_predictor import ARCHITECTURES

    model_path = tmp_path / "model.pt"
    torch.save(ARCHITECTURES["efficientnet_v2_s_linear"](4).state_dict(), str(model_path))
    settings = {"architecture": "efficientnet_v2_s_linear", "channels": 3, "input_size": 64, "mean": [0.5] * 3, "std": [0.5] * 3}
    predictor = load_torch_predictor(model_path, _write_config(tmp_path, **settings), allow_pickle=False)
    many = predictor.predict_many([_image(), Image.new("L", (128, 128), 30)])
    assert len(many) == 2 and all(abs(sum(p.values()) - 1) < 1e-5 for p in many)
    # The older layout (Dropout + Linear) does not fit these weights.
    with pytest.raises(Exception):
        load_torch_predictor(model_path, _write_config(tmp_path, **{**settings, "architecture": "efficientnet_v2_s"}), allow_pickle=False)


def test_area_resizing_matches_the_training_resize(tmp_path):
    """Review comment 6: training resized with cv2 INTER_AREA."""
    import cv2
    import numpy as np

    model_path = tmp_path / "model.pt"
    torch.jit.save(torch.jit.script(Tiny()), str(model_path))
    predictor = load_torch_predictor(model_path, _write_config(tmp_path, resize_interpolation="area"), allow_pickle=False)
    pixels = (np.arange(96 * 96) % 251).astype(np.uint8).reshape(96, 96)
    tensor = predictor.preprocess(Image.fromarray(pixels, mode="L"))
    expected = cv2.resize(pixels, (32, 32), interpolation=cv2.INTER_AREA).astype(np.float32) / 255
    assert np.allclose(tensor[0, 0].numpy(), (expected - 0.5) / 0.5, atol=1e-5)
