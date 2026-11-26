"""The report PDF: who may download it, and what each version leaves out.
Built with page compression off, so the text can be searched in the bytes."""
import base64
import io

from tests.conftest import upload
from tests.test_explanations import _phantom, real_predictor  # noqa: F401  (fixture)

API = "/api/v1"


def _review(client, world, aid, *, release, notes="NOTESECRET clinician remark", summary="SUMMARYTEXT for you"):
    body = {"decision": "confirmed", "clinical_notes": notes, "patient_summary": summary, "release_to_patient": release}
    response = client.post(f"{API}/analyses/{aid}/review", headers=world.h_doctor_a, json=body)
    assert response.status_code == 201, response.text


def _pdf(client, headers, aid, **params):
    return client.get(f"{API}/analyses/{aid}/report.pdf", headers=headers, params=params)


def test_doctor_gets_the_full_report_once_reviewed(client, world, run_jobs):
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    early = _pdf(client, world.h_doctor_a, aid)
    assert early.status_code == 409  # not reviewed yet

    _review(client, world, aid, release=False)
    response = _pdf(client, world.h_doctor_a, aid)
    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "application/pdf"
    assert response.headers["content-disposition"].startswith('attachment; filename="NeuroSense-report-P-')
    pdf = response.content
    assert pdf.startswith(b"%PDF")
    for text in [b"Doctor version", b"Model confidence", b"NOTESECRET", b"SUMMARYTEXT", b"Not released",
                 b"SIMULATED RESULT", b"Disclaimer"]:
        assert text in pdf, text


def test_patient_gets_a_reduced_copy_only_after_release(client, world, run_jobs):
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    _review(client, world, aid, release=False)
    assert _pdf(client, world.h_patient_1, aid).status_code == 404  # reviewed but not released

    client.post(f"{API}/analyses/{aid}/release", headers=world.h_doctor_a)
    response = _pdf(client, world.h_patient_1, aid)
    assert response.status_code == 200, response.text
    pdf = response.content
    assert b"Patient copy" in pdf and b"SUMMARYTEXT" in pdf
    for hidden in [b"NOTESECRET", b"Model confidence", b"Softmax", b"Release", b"Doctor version"]:
        assert hidden not in pdf, hidden


def test_nobody_else_gets_the_report(client, world, run_jobs):
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    _review(client, world, aid, release=True)
    assert _pdf(client, world.h_doctor_b, aid).status_code == 404  # not their patient
    assert _pdf(client, world.h_patient_2, aid).status_code == 404  # someone else's result
    assert client.get(f"{API}/analyses/{aid}/report.pdf").status_code == 401


def test_times_follow_the_readers_offset(client, world, run_jobs):
    aid = upload(client, world.h_patient_1)["analysis_id"]
    run_jobs()
    _review(client, world, aid, release=False)
    assert b"UTC" in _pdf(client, world.h_doctor_a, aid).content
    assert b"UTC" not in _pdf(client, world.h_doctor_a, aid, utc_offset_minutes=240).content
    assert _pdf(client, world.h_doctor_a, aid, utc_offset_minutes=99999).status_code == 422


def test_the_mri_slice_and_gradcam_overlay_are_in_the_pdf(client, world, run_jobs, real_predictor):  # noqa: F811
    buf = io.BytesIO()
    _phantom().save(buf, format="PNG")
    aid = client.post(f"{API}/scans", headers=world.h_patient_1,
                      json={"image_base64": base64.b64encode(buf.getvalue()).decode(), "filename": "s.png"}
                      ).json()["analysis_id"]
    assert run_jobs(real_predictor) == 1
    _review(client, world, aid, release=True)
    for headers in (world.h_doctor_a, world.h_patient_1):
        pdf = _pdf(client, headers, aid).content
        assert pdf.count(b"/Subtype /Image") == 2  # the slice and the overlay
        assert b"Grad-CAM overlay" in pdf
