"""Brain masking before the model, and Grad-CAM after it.
The EfficientNetV2-S built here has random weights: these tests check the
pipeline and who may see the map, not what the real model predicts."""
import base64
import io

import numpy as np
import pytest
import torch
import yaml
from PIL import Image, ImageDraw

from app.ml.gradcam import grad_cam
from app.ml.masking import mask_for_model
from app.ml.torch_predictor import ARCHITECTURES, load_torch_predictor
from tests.conftest import upload

API = "/api/v1"


def _phantom(size=200) -> Image.Image:
    """A head-like test picture: bright skull ring, grey brain, black background with noise."""
    rng = np.random.default_rng(0)
    img = Image.fromarray(rng.integers(0, 12, (size, size), dtype=np.uint8))
    draw = ImageDraw.Draw(img)
    draw.ellipse((20, 30, 180, 175), fill=230)  # skull
    draw.ellipse((32, 42, 168, 163), fill=110)  # brain
    return img


@pytest.fixture
def real_predictor(tmp_path):
    model_path = tmp_path / "model.pt"
    torch.manual_seed(0)
    torch.save(ARCHITECTURES["efficientnet_v2_s"](4).state_dict(), str(model_path))
    config = {
        "name": "TestNet", "version": "test", "architecture": "efficientnet_v2_s", "confirmed": True,
        "input_size": 224, "channels": 3, "resize_interpolation": "bilinear", "scale": 1 / 255,
        "mean": [0.485, 0.456, 0.406], "std": [0.229, 0.224, 0.225],
        "classes": ["AD", "LMCI", "EMCI", "CN"], "output": "logits",
        "masking": "brain_v1", "explain": "gradcam",
    }
    config_path = tmp_path / "model_config.yaml"
    config_path.write_text(yaml.safe_dump(config))
    return load_torch_predictor(model_path, config_path, allow_pickle=False)


def test_masking_keeps_the_brain_and_blacks_out_the_rest():
    out = np.asarray(mask_for_model(_phantom().convert("RGB")))
    assert out.shape == (224, 224)  # cropped to the brain, then resized as in training
    assert out[112, 112] > 0  # brain kept
    corners = [out[0, 0], out[0, -1], out[-1, 0], out[-1, -1]]
    assert max(corners) == 0  # background noise removed


def test_grad_cam_gives_a_map_of_the_input_size(real_predictor):
    tensor = real_predictor.preprocess(Image.new("RGB", (224, 224), 90))
    cam = grad_cam(real_predictor._module, tensor, 0)
    assert cam.shape == (224, 224)
    assert cam.min() >= 0 and cam.max() <= 1


def test_prediction_carries_the_masked_input_and_a_map(real_predictor):
    prediction = real_predictor.predict(_phantom().convert("RGB"))
    assert abs(sum(prediction.probabilities.values()) - 1) < 1e-5
    assert prediction.explanation_method == "gradcam"
    assert Image.open(io.BytesIO(prediction.model_input_png)).size == (224, 224)
    assert Image.open(io.BytesIO(prediction.heatmap_png)).size == (224, 224)


def _approve(client, world, aid, release):
    body = {"decision": "confirmed", "clinical_notes": "", "patient_summary": "Summary.", "release_to_patient": release}
    assert client.post(f"{API}/analyses/{aid}/review", headers=world.h_doctor_a, json=body).status_code == 201


def test_the_map_is_shown_to_the_doctor_and_to_the_patient_only_after_release(client, world, run_jobs, real_predictor):
    buf = io.BytesIO()
    _phantom().save(buf, format="PNG")
    receipt = client.post(f"{API}/scans", headers=world.h_patient_1,
                          json={"image_base64": base64.b64encode(buf.getvalue()).decode(), "filename": "s.png"}).json()
    aid = receipt["analysis_id"]
    assert run_jobs(real_predictor) == 1

    doctor = client.get(f"{API}/analyses/{aid}/explanation", headers=world.h_doctor_a)
    assert doctor.status_code == 200, doctor.text
    body = doctor.json()
    assert body["method"] == "gradcam" and body["width"] == 224 and body["height"] == 224
    heat = Image.open(io.BytesIO(base64.b64decode(body["heatmap_base64"])))
    assert heat.mode == "RGB" and heat.size == (224, 224)  # coloured map

    # Patients: nothing before release; other doctors: never.
    assert client.get(f"{API}/analyses/{aid}/explanation", headers=world.h_patient_1).status_code == 404
    assert client.get(f"{API}/analyses/{aid}/explanation", headers=world.h_doctor_b).status_code == 404
    _approve(client, world, aid, release=True)
    assert client.get(f"{API}/analyses/{aid}/explanation", headers=world.h_patient_1).status_code == 200


def test_stub_results_have_no_map(client, world, run_jobs):
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    missing = client.get(f"{API}/analyses/{aid}/explanation", headers=world.h_doctor_a)
    assert missing.status_code == 404  # the stub never produces a map, so none is shown
