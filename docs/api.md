# NeuroSense API contract

Base URL: `/api/v1`. JSON in and out. Every route except login, refresh, logout and `/health` needs `Authorization: Bearer <access token>`.

Live, always-current reference: `http://localhost:8000/docs` on a running server. This file explains the rules behind it.

## Rules that apply everywhere

- **Identity comes from the token.** For a patient, the server ignores any `patient_id`, sender name or similar field in a request body.
- **Doctors** reach only patients assigned to them. **Patients** reach only their own record.
- **Unreleased results are invisible to patients.** Any patient request for an analysis that the doctor has not released returns 404.
- **Not yours = 404**, the same as "does not exist". **Wrong role = 403.**
- **Times** are ISO 8601 in UTC. **IDs** are UUIDs. People also have display IDs: `A-1001` (admin), `D-1001` (doctor), `P-1024` (patient, sent as `mrn`).
- **Labels** are `CN` (cognitively normal), `EMCI` (early mild cognitive impairment), `LMCI` (late MCI) and `AD` (Alzheimer's disease).

### Errors

```json
{"error": {"code": "NOT_FOUND", "message": "This item was not found."}}
```

| Status | Code | Meaning |
|---|---|---|
| 401 | `UNAUTHENTICATED`, `INVALID_CREDENTIALS` | Missing, invalid or expired token; wrong email or password |
| 403 | `FORBIDDEN` | The route is for the other role |
| 404 | `NOT_FOUND` | Unknown, not yours, or (for patients) not released |
| 409 | `CONFLICT` | Not allowed in the current state, for example a second review |
| 413 | `PAYLOAD_TOO_LARGE`, `IMAGE_TOO_LARGE` | Request body over 2 MB, or image over 1 MB |
| 422 | `VALIDATION_ERROR`, `IMAGE_*` | Invalid input. The message names the fields, never the submitted values |
| 429 | `RATE_LIMITED` | Too many sign-in attempts |

## Authentication

| Method | Path | Body | Reply |
|---|---|---|---|
| POST | `/auth/login` | `{"email", "password"}`. `email` may also be an account ID (`P-1024`) | `{"access_token", "refresh_token", "user"}` |
| POST | `/auth/refresh` | `{"refresh_token"}` | A new pair. Each refresh token works once |
| POST | `/auth/logout` | `{"refresh_token"}` | 204 |
| GET | `/me` | — | `user` |
| GET | `/me/profile` | — | `{"personal": [{"label","value"}], "health": [...]}` |

```json
{"id": "…", "full_name": "Sarah Johnson", "role": "patient",
 "subtitle": "Patient ID P-1024", "patient_id": "…", "display_id": "P-1024"}
```

There is no self-registration. Accounts are created by an admin.

## Admin

Admins only (403 for doctors and patients). Admins have no access to scans, results, notes or messages.

| Method | Path | Purpose |
|---|---|---|
| GET | `/admin/users` | Every account: `id`, `display_id`, `role`, `full_name`, `email`, `is_active`; patients also `doctor_display_id`, `doctor_name`; doctors also `patient_count` |
| POST | `/admin/users` | Create an account. The server assigns the next ID: `A-`, `D-` or `P-` |
| PATCH | `/admin/users/{user_id}/doctor` | `{"doctor_display_id"}`: move a patient to another doctor |

```json
POST /admin/users
{"role": "patient", "full_name": "New Patient", "email": "new.patient@example.org", "password": "at least 8 characters",
 "doctor_display_id": "D-1001", "date_of_birth": "1950-02-03", "sex": "female"}
```

`role` is `admin`, `doctor` or `patient`. A patient needs `doctor_display_id` (an existing doctor), `date_of_birth` and `sex`. A doctor may have a `specialty`. 409 when the email is already used.

## Scans and analyses

| Method | Path | Who | Purpose |
|---|---|---|---|
| POST | `/scans` | patient (own record), doctor (assigned patient, with `patient_id`) | Upload a scan; queues the analysis |
| GET | `/scans/mine` | patient | Own uploads with a coarse state |
| GET | `/patients/{pid}/analyses` | doctor; patient (released only) | Completed analyses, newest first |
| GET | `/analyses/{aid}` | doctor; patient (released only) | One analysis |
| GET | `/analyses/{aid}/status` | doctor | Job progress |
| GET | `/analyses/{aid}/image` | doctor; patient (released only) | The stored image |
| GET | `/analyses/{aid}/explanation` | doctor; patient (released only) | Grad-CAM map: `{"method":"gradcam","target_label","image_base64" (the brain-masked image the model analysed),"heatmap_base64" (JET colours),"width","height"}`. 404 when there is none (stub results, older results, after retention) |
| GET | `/analyses/{aid}/report.pdf?utc_offset_minutes=` | doctor (reviewed results); patient (released only) | The report as a PDF (`application/pdf`, `Content-Disposition: attachment; filename="NeuroSense-report-<patient ID>-<date>.pdf"`). Doctors get the doctor version (model confidence, class scores, override reason, clinical notes, release state); patients get the patient copy without them. Includes the MRI slice and the Grad-CAM overlay when stored. `utc_offset_minutes` (-840 to 840) puts times in the reader's local time, otherwise UTC. 409 before the review; 404 when not visible. Each download is audited (`report_downloaded`) |
| POST | `/analyses/{aid}/retry` | doctor | Re-queue a failed analysis |
| GET | `/doctor/review-queue` | doctor | Everything waiting: to review, or failed |
| POST | `/analyses/{aid}/review` | doctor | Confirm or override |
| POST | `/analyses/{aid}/release` | doctor | Make a reviewed result visible to the patient |

### Upload

```json
POST /scans
{"image_base64": "iVBORw0KGgo…", "filename": "slice.png", "patient_id": "<doctors only>"}

202
{"scan_id": "…", "analysis_id": "…", "status": "received"}
```

The image must be a PNG or JPEG (checked from the file's content, not its name), at most 256 × 256 pixels and 1 MB, single-frame, and decodable. Errors: `IMAGE_INVALID_BASE64`, `IMAGE_UNSUPPORTED_FORMAT`, `IMAGE_UNREADABLE`, `IMAGE_DIMENSIONS_TOO_LARGE` (422), `IMAGE_TOO_LARGE` (413).

Uploading the same image for the same patient again returns the first receipt. If that analysis had failed, it is queued again.

The reply never contains analysis output. A patient's upload list looks like this:

```json
GET /scans/mine
[{"scan_id": "…", "analysis_id": "…", "uploaded_at": "…", "state": "received"}]
```

`state` is `received`, `released` or `needs_reupload`. It does not say whether the analysis has run or whether the doctor has looked at it.

### Full MRI scan upload (doctor)

```
POST /scans/volume?patient_id=<assigned patient>&filename=brain.nii.gz
Content-Type: application/octet-stream
<the .nii or .nii.gz file>

202
{"scan_id": "…", "analysis_id": "…", "status": "received"}
```

Doctors only (a patient gets 403; a patient who is not assigned to the doctor gives 404). The body is the raw file, at most 64 MB, and at most 256 MB once a `.gz` is decompressed. The server checks that it is a readable 3-D NIfTI scan with 16–512 voxels per side. Errors: `VOLUME_INVALID` (422), `VOLUME_TOO_LARGE` (413), `FULL_SCANS_UNAVAILABLE` (503, when the server has no brain detector). The same file for the same patient returns the first receipt.

The analysis then follows the team's pipeline (see `docs/backend.md`). It fails with `error_code` `VOLUME_TOO_FEW_SLICES` when fewer than 10 brain slices are left, and these failures are not retried.

### Job status (doctor)

```json
GET /analyses/{aid}/status
{"analysis_id": "…", "job_status": "queued", "error_code": null}
```

`job_status`: `queued`, `running`, `completed`, `failed`. `GET /analyses/{aid}` returns 404 until the job is `completed`.

### Analysis, doctor view

```json
{"id": "…", "patient_id": "…", "created_at": "…",
 "predicted_label": "EMCI", "confidence": 0.91,
 "probabilities": {"CN": 0.03, "EMCI": 0.91, "LMCI": 0.04, "AD": 0.02},
 "status": "awaitingConfirmation",
 "model_name": "Stub predictor (no model connected)", "model_version": "stub",
 "simulated": true,
 "review": null}
```

- `status`: `awaitingConfirmation` or `pendingReview` before review (confidence at or above, or below, the gate), then `confirmed` or `overridden`.
- `simulated` is `true` whenever no real model produced the result. Clients must show it.
- `input_kind`: `slice` (one uploaded image) or `volume` (a full scan). For a full scan, `slices_total`, `slices_kept` (accepted by the brain detector), `slices_used` (after leaving out the top slices) and `slice_index` (0-based axial slice shown as the image) are also set; `probabilities` are averaged over the `slices_used` slices. Patients never get these fields.
- `review`, once reviewed: `final_label`, `doctor_name`, `reviewed_at`, `override_reason`, `clinical_notes`, `patient_summary`, `released_to_patient`.

### Analysis, patient view (released only)

The same, **without** `confidence` and `probabilities`, and with a review that has only `final_label`, `doctor_name`, `reviewed_at`, `patient_summary` and `released_to_patient`. Clinical notes and the override reason are never sent to patients.

### Review queue

```json
GET /doctor/review-queue
[{"analysis_id": "…", "patient_id": "…", "patient_name": "Sarah Johnson", "patient_display_id": "P-1024",
  "uploaded_at": "…", "job_status": "completed", "analysis": { … doctor view … }},
 {"analysis_id": "…", "patient_id": "…", "patient_name": "Robert Smith", "patient_display_id": "P-1031",
  "uploaded_at": "…", "job_status": "failed", "analysis": null}]
```

Oldest first. Reading it changes nothing: an item leaves the queue only when it is reviewed (or, for a failed one, retried).

### Review and release

```json
POST /analyses/{aid}/review
{"decision": "overridden", "final_label": "LMCI",
 "override_reason": "Clinical picture differs from the model output.",
 "clinical_notes": "doctor-only", "patient_summary": "shown to the patient",
 "release_to_patient": false}

201 → the analysis (doctor view)
```

- `decision`: `confirmed` or `overridden`.
- An override needs a `final_label` different from the prediction and an `override_reason` of at least 10 characters (422 otherwise).
- 409 if the analysis has no result yet, or was already reviewed. A review cannot be changed.
- `release_to_patient: true` releases in the same step and needs a `patient_summary`.
- `POST /analyses/{aid}/release` releases later. 409 without a review or without a patient summary. Releasing twice returns the same result and notifies once.

### Image

```json
GET /analyses/{aid}/image
{"image_base64": "…", "mime": "image/png", "width": 224, "height": 224}
```

404 once the image has been removed by the retention policy.

## Patients (doctor)

| Method | Path | Purpose |
|---|---|---|
| GET | `/patients?search=&filter=` | Assigned patients. `filter`: `all`, `needsReview`, `reviewed`, `noAnalyses` |
| GET | `/patients/{pid}` | One patient. A patient may read their own record (without `latest_analysis`) |
| PATCH | `/patients/{pid}/contact` | `{"phone", "emergency_contact"}` |
| GET | `/patients/{pid}/notes` | Doctor-only notes, newest first |
| POST | `/patients/{pid}/notes` | `{"body"}`. The author is the signed-in doctor |

```json
{"id": "…", "mrn": "P-1024", "full_name": "Sarah Johnson", "date_of_birth": "1958-03-12", "sex": "female",
 "phone": "…", "email": "…", "emergency_contact": "…", "latest_analysis": { … } }
```

## Appointments

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/appointments` | both | Own appointments, by start time |
| GET | `/appointments/{id}` | both | One appointment |
| POST | `/appointments` | patient: `{"reason", "starts_at", "notes"}` (status `requested`); doctor: also `patient_id` (status `confirmed`) | Create |
| PATCH | `/appointments/{id}` | doctor: `{"status"}` (`confirmed`, `cancelled`, `completed`) or `{"starts_at"}`; patient: `{"status": "cancelled"}` only | Change |

```json
{"id": "…", "patient_id": "…", "patient_name": "…", "doctor_name": "…", "starts_at": "…",
 "duration_min": 30, "reason": "Follow-up", "status": "requested", "location": null}
```

A cancelled or completed appointment cannot be changed (409).

## Messages

| Method | Path | Who | Purpose |
|---|---|---|---|
| GET | `/messages/threads` | doctor | One entry per patient with messages: `patient_id`, `patient_name`, `last`, `unread` |
| GET | `/patients/{pid}/messages` | assigned doctor, the patient | The conversation, oldest first |
| POST | `/patients/{pid}/messages` | assigned doctor, the patient | `{"body", "linked_to"}`. Sender and direction come from the token |
| POST | `/patients/{pid}/messages/read` | assigned doctor, the patient | Marks the other side's messages read |

```json
{"id": "…", "patient_id": "…", "from_doctor": false, "sender_name": "Sarah Johnson",
 "body": "…", "created_at": "…", "read_at": null, "linked_to": null}
```

## Notifications

| Method | Path | Purpose |
|---|---|---|
| GET | `/notifications` | Own notifications, newest first (up to 100) |
| POST | `/notifications/{id}/read` | Mark one read |
| POST | `/notifications/read-all` | Mark all read |

```json
{"id": "…", "user_id": "…", "type": "analysis", "title": "…", "body": "…", "created_at": "…", "read_at": null,
 "entity_type": "analysis", "entity_id": "…", "patient_id": "…"}
```

`type`: `review`, `message`, `appointment`, `analysis`. `entity_type` says what it is about (`analysis`, `appointment`, `message`, `patient`, `upload`); the app decides which screen to open.

When they are created:

| Event | Who is notified |
|---|---|
| Analysis completed | The assigned doctor only |
| Analysis failed | The doctor, and the patient ("please upload again") |
| Result released | The patient |
| Appointment requested / changed | The other side |
| New message | The other side. The message text is not copied into the notification |

The same event never creates two notifications, even if the operation is retried.

## Timeline and dashboards

| Method | Path | Who | Reply |
|---|---|---|---|
| GET | `/patients/{pid}/timeline` | assigned doctor; the patient (released results only) | Events, newest first |
| GET | `/doctor/dashboard` | doctor | `patient_count`, `pending_reviews`, `recent_analyses`, `upcoming_appointments`, `recent_activity` |
| GET | `/patient/dashboard` | patient | `latest_released` (patient view or null), `next_appointment`, `recent_activity` |

```json
{"id": "…-ai", "patient_id": "…", "date": "…", "type": "mriAnalysis", "source": "ai",
 "title": "MRI analysis", "summary": "Early MCI · 91.0% model confidence",
 "patient_name": "Sarah Johnson", "pending": true}
```

`type`: `mriAnalysis`, `doctorReview`, `appointment`, `message`. `source`: `ai`, `doctor`, `admin`.

In the patient's timeline the `mriAnalysis` summary is the class name only, without the model confidence.

## Health

`GET /health` (no token): `{"status": "ok", "model": "stub", "model_name": "…", "model_version": "…", "full_scans": "enabled"}`. `model` is `stub` until a real model is loaded. `full_scans` is `disabled` when the brain detector is missing.

## Not in this API

- Counselling: answered inside the app from predefined content.
- Account creation and password reset.
