"""Full MRI scans (.nii / .nii.gz): the pipeline and the upload endpoint.

Every scan here is synthetic: a bright block standing in for brain on some
axial slices. They test the code path, not the model or the brain detector."""
import gzip

import nibabel as nib
import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.core.config import get_settings
from app.db import models as m
from app.main import create_app
from app.ml.predictor import StubPredictor
from app.ml.volume import VolumeError, analyse_volume, axial_slices, keep_brain_slices, read_nifti
from app.services.analysis_worker import process_one

BIG = 256 * 1024 * 1024
BRAIN = range(5, 35)  # the synthetic "brain" slices of a 40-slice scan


class FakeFilter:
    """Stands in for the brain detector: accepts slices with enough bright pixels."""

    threshold = 0.4

    def scores(self, batch):
        return np.array([0.1 if (img > 0).mean() > 0.05 else 0.9 for img in batch], dtype=np.float32)


def scan_data(shape=(64, 64, 40)) -> np.ndarray:
    data = np.zeros(shape, dtype=np.float32)
    for z in BRAIN:
        data[16:48, 12:52, z] = 100 + z
    return data


def nifti_bytes(data=None, affine=None, gz=False) -> bytes:
    data = scan_data() if data is None else data
    raw = nib.Nifti1Image(data, np.eye(4) if affine is None else affine).to_bytes()
    return gzip.compress(raw, mtime=0) if gz else raw


# ---------------------------------------------------------------- steps 1 and 2

def test_slices_are_rotated_so_the_front_of_the_head_is_at_the_top():
    data = np.zeros((40, 50, 16), dtype=np.float32)
    data[:, 45:, 1] = 1  # anterior (high y in RAS)
    data[:5, :, 1] = 0.5  # the patient's left side... (low x in RAS)
    data[:5, 45:, 1] = 1
    slices = axial_slices(read_nifti(nifti_bytes(data), max_unpacked_bytes=BIG))
    image = slices[1]
    assert image.shape == (50, 40)  # rotated: rows come from y, columns from x
    assert image[:5].min() == 255  # the front of the head is at the top
    assert image[10:, :5].min() == 127  # ...and x = 0 is on the left of the image (truncated, as extract-axial.py)
    assert np.array_equal(image, np.rot90((data[:, :, 1] * 255).astype(np.uint8), k=1))


def test_scans_stored_in_another_orientation_are_reoriented_first():
    data = scan_data()
    flipped = data[::-1].copy()  # stored right-to-left
    affine = np.diag([-1.0, 1.0, 1.0, 1.0])
    a = axial_slices(read_nifti(nifti_bytes(data), max_unpacked_bytes=BIG))
    b = axial_slices(read_nifti(nifti_bytes(flipped, affine), max_unpacked_bytes=BIG))
    assert all(np.array_equal(x, y) for x, y in zip(a, b))


def test_gzipped_scans_are_read_and_bombs_are_refused():
    assert read_nifti(nifti_bytes(gz=True), max_unpacked_bytes=BIG).shape == (64, 64, 40)
    with pytest.raises(VolumeError) as error:
        read_nifti(nifti_bytes(gz=True), max_unpacked_bytes=10_000)
    assert error.value.code == "VOLUME_TOO_LARGE"


@pytest.mark.parametrize("raw", [b"not a scan", b"\x1f\x8bbroken gzip", bytes(400)])
def test_files_that_are_not_scans_are_refused(raw):
    with pytest.raises(VolumeError) as error:
        read_nifti(raw, max_unpacked_bytes=BIG)
    assert error.value.code == "VOLUME_INVALID"


def test_a_2d_image_saved_as_nifti_is_refused():
    with pytest.raises(VolumeError):
        read_nifti(nib.Nifti1Image(np.zeros((64, 64), np.float32), np.eye(4)).to_bytes(), max_unpacked_bytes=BIG)


# ---------------------------------------------------------------- steps 3 to 5

def test_only_slices_the_detector_accepts_are_kept():
    slices = axial_slices(read_nifti(nifti_bytes(), max_unpacked_bytes=BIG))
    assert keep_brain_slices(slices, FakeFilter(), batch=7) == list(BRAIN)


class ScriptedPredictor:
    """Returns set scores per slice so the averaging can be checked exactly."""

    simulated = False

    def __init__(self):
        self.seen = 0

    def predict_many(self, images):
        self.seen = len(images)
        out = []
        for i, image in enumerate(images):
            assert image.size == (224, 224) and image.mode == "L"
            ad = 0.9 if i == 3 else 0.5
            out.append({"AD": ad, "LMCI": 1 - ad, "EMCI": 0.0, "CN": 0.0})
        return out

    def explain(self, image, label):
        assert label == "AD"
        return b"heatmap", "gradcam"


def test_the_last_slices_are_pruned_and_scores_averaged():
    predictor = ScriptedPredictor()
    result = analyse_volume(
        nifti_bytes(), predictor, FakeFilter(), prune_last=15, min_slices=10, max_unpacked_bytes=BIG
    )
    assert (result.slices_total, result.slices_kept, result.slices_used) == (40, 30, 15)
    assert predictor.seen == 15
    assert result.probabilities["AD"] == pytest.approx((0.9 + 14 * 0.5) / 15)
    # The slice shown is the one most confident in the averaged top class: the 4th used slice.
    assert result.slice_index == BRAIN[3]
    assert result.heatmap_png == b"heatmap" and result.explanation_method == "gradcam"
    assert Image.open(__import__("io").BytesIO(result.slice_png)).size == (64, 64)
    assert result.model_input_png is not None


def test_too_few_brain_slices_is_an_error_not_a_result():
    with pytest.raises(VolumeError) as error:
        analyse_volume(
            nifti_bytes(), ScriptedPredictor(), FakeFilter(), prune_last=25, min_slices=10, max_unpacked_bytes=BIG
        )
    assert error.value.code == "VOLUME_TOO_FEW_SLICES"


# ---------------------------------------------------------------- the endpoint

@pytest.fixture
def scan_client():
    with TestClient(create_app(predictor=StubPredictor(), start_worker=False, brain_filter=FakeFilter())) as c:
        yield c


def post_volume(client, headers, patient, raw=None, filename="brain.nii"):
    return client.post(
        "/api/v1/scans/volume",
        params={"patient_id": str(patient.id), "filename": filename},
        content=nifti_bytes() if raw is None else raw,
        headers={**headers, "Content-Type": "application/octet-stream"},
    )


def test_doctor_uploads_a_full_scan_and_gets_an_averaged_result(scan_client, world, db):
    response = post_volume(scan_client, world.h_doctor_a, world.patient_1, nifti_bytes(gz=True), "brain.nii.gz")
    assert response.status_code == 202, response.text
    receipt = response.json()
    scan = db.get(m.Scan, receipt["scan_id"])
    assert scan.kind == "volume" and scan.volume is not None and scan.image is None

    assert process_one(db, StubPredictor(), get_settings(), FakeFilter())
    db.expire_all()
    analysis = db.get(m.Analysis, receipt["analysis_id"])
    assert analysis.job_status == m.JobStatus.completed
    assert analysis.scan.volume is None  # the file is not kept after the analysis
    assert analysis.scan.image is not None  # the slice shown to the doctor

    body = scan_client.get(f"/api/v1/analyses/{receipt['analysis_id']}", headers=world.h_doctor_a).json()
    assert body["input_kind"] == "volume"
    assert (body["slices_total"], body["slices_kept"], body["slices_used"]) == (40, 30, 15)
    assert body["slice_index"] in BRAIN
    assert body["simulated"] is True
    image = scan_client.get(f"/api/v1/analyses/{receipt['analysis_id']}/image", headers=world.h_doctor_a)
    assert image.status_code == 200

    # The same file again returns the same receipt.
    again = post_volume(scan_client, world.h_doctor_a, world.patient_1, nifti_bytes(gz=True), "brain.nii.gz")
    assert again.json()["analysis_id"] == receipt["analysis_id"]


def test_patients_and_other_doctors_cannot_upload_full_scans(scan_client, world):
    assert post_volume(scan_client, world.h_patient_1, world.patient_1).status_code == 403
    assert post_volume(scan_client, world.h_doctor_b, world.patient_1).status_code == 404


def test_bad_and_oversized_scan_files_are_refused(scan_client, world, monkeypatch):
    bad = post_volume(scan_client, world.h_doctor_a, world.patient_1, b"this is not a scan")
    assert bad.status_code == 422 and bad.json()["error"]["code"] == "VOLUME_INVALID"
    monkeypatch.setattr(get_settings(), "max_volume_bytes", 1000)
    big = post_volume(scan_client, world.h_doctor_a, world.patient_1)
    assert big.status_code == 413 and big.json()["error"]["code"] == "VOLUME_TOO_LARGE"


def test_full_scans_are_refused_when_the_server_has_no_brain_detector(client, world):
    response = post_volume(client, world.h_doctor_a, world.patient_1)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "FULL_SCANS_UNAVAILABLE"
    assert client.get("/health").json()["full_scans"] == "disabled"


def test_the_worker_never_skips_the_brain_filter(scan_client, world, db):
    receipt = post_volume(scan_client, world.h_doctor_a, world.patient_1).json()
    assert process_one(db, StubPredictor(), get_settings(), None)
    db.expire_all()
    analysis = db.get(m.Analysis, receipt["analysis_id"])
    assert analysis.job_status == m.JobStatus.failed
    assert analysis.error_code == "BRAIN_FILTER_MISSING"


def test_a_scan_with_too_few_brain_slices_fails_without_retrying(scan_client, world, db):
    data = scan_data()
    data[:, :, 12:] = 0  # only 7 brain slices
    receipt = post_volume(scan_client, world.h_doctor_a, world.patient_1, nifti_bytes(data)).json()
    assert process_one(db, StubPredictor(), get_settings(), FakeFilter())
    db.expire_all()
    analysis = db.get(m.Analysis, receipt["analysis_id"])
    assert analysis.job_status == m.JobStatus.failed
    assert analysis.error_code == "VOLUME_TOO_FEW_SLICES"
    assert analysis.attempts == 1
