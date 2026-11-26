# NeuroSense backend

FastAPI + PostgreSQL 16, run with Docker Compose. The API contract is in [`api.md`](api.md).

## Run it

Docker Desktop must be running. From the repository root:

```bash
cp backend/.env.example backend/.env
```

Edit `backend/.env` and replace every `CHANGE-ME` (the database password appears twice: in `POSTGRES_PASSWORD` and inside `DATABASE_URL`). Then:

```bash
docker compose up -d --build
```

```bash
docker compose exec api python -m app.db.seed
```

- API: `http://localhost:8000`, interactive docs at `http://localhost:8000/docs`.
- `GET /health` shows whether a model is loaded: `"model": "stub"` or `"loaded"`.
- The container applies database migrations (`alembic upgrade head`) every time it starts.
- `backend/.env` is git-ignored. Never commit it or database dumps. The served model files in `backend/models/` are committed on purpose.

### Seed accounts (fictional, development only)

The seed script creates one admin, two doctors and nine patients. None of them is a real person. Everyone's password is the `SEED_PASSWORD` from `backend/.env`. The script refuses to run when `APP_ENV=production`, and running it twice creates nothing new.

| Role | ID | Email |
|---|---|---|
| Admin | A-1001 | `admin@neurosense.test` |
| Doctor | D-1001 | `ahmed.khan@neurosense.test` |
| Doctor | D-1002 | `layla.nasser@neurosense.test` |
| Patient of D-1001 | P-1024 | `sarah.johnson@neurosense.test` |
| Patient of D-1001 | P-1031 … P-1093 | `robert.smith@`, `emily.davis@`, `michael.chen@`, `aisha.rahman@`, `omar.haddad@`, `lina.saleh@`, `james.carter@neurosense.test` |
| Patient of D-1002 | P-2001 | `noah.fischer@neurosense.test` |

No scans or results are seeded. Analyses only come from uploads.

## Tests

```bash
docker compose exec api pytest -q
```

The tests create and use a separate database (`<name>_test`), built by the real migrations. They also run on GitHub Actions (`.github/workflows/backend.yml`) against a PostgreSQL 16 service.

## How a scan moves through the system

1. **Upload.** `POST /scans` with a base64 PNG or JPEG. The server checks the real file format, the size (at most 256 × 256 pixels and 1 MB), and that the image decodes. It re-encodes the image as PNG (which removes metadata), stores it, and creates an analysis with status `queued`. The reply is a receipt only.
2. **Analysis.** A worker thread inside the API process picks up queued analyses one at a time and runs the predictor. The result is saved, and the assigned doctor gets a notification.
3. **Review queue.** `GET /doctor/review-queue` lists everything waiting: analyses to review and analyses that failed. It is read-only, so items stay until they are reviewed.
4. **Review and release.** The doctor confirms or overrides the result, and releases it. Release needs a patient summary.
5. **Patient.** Only after release can the patient read the result. Until then every patient request about that analysis returns 404, and the upload list says only "received".

### Analysis jobs: what is and isn't handled

- The queue is the `analyses` table (`queued → running → completed | failed`). No Redis or Celery.
- A job is claimed with a row lock, so it cannot run twice.
- If the server restarts during an analysis, the job is queued again at startup.
- A model error is retried up to `MAX_ANALYSIS_ATTEMPTS` (3) times. Then the job is marked `failed`, the doctor and the patient are notified, and the doctor can retry it (`POST /analyses/{id}/retry`). Uploading the same image again also retries it.
- **Limits:** one API process, one analysis at a time, on CPU. That is enough for this project. A separate job queue becomes worth it only with several servers or long-running models.

### Image retention

Image bytes are deleted `IMAGE_RETENTION_DAYS` (default 30) after the doctor's review. The result, the review and the audit trail are kept. The worker runs the purge once a day; to run it by hand:

```bash
docker compose exec api python -m app.services.retention
```

Running it again changes nothing. After the purge the image endpoint returns 404.

## Connecting the trained model

Until a model is connected, the server uses a **stub predictor**. Its output is derived from the image bytes, is not a model output, and every result is stored and returned with `simulated: true`. The app shows a "SIMULATED RESULT" notice on those results.

To connect the real model, put two files in `backend/models/` (the folder is mounted read-only and git-ignored):

1. `model.pt`
2. `model_config.yaml` — copy `model_config.example.yaml` and fill in every value

Then restart: `docker compose restart api`, and check `GET /health`.

The server tries TorchScript first. A weights-only file (`state_dict`) is loaded next: only tensors are read, no code from the file runs, and the weights must fit the architecture named by `architecture` in the config exactly. The only architecture available is `efficientnet_v2_s` (torchvision, 4 outputs). A full pickled model (`torch.save(model)`) is loaded only when `ALLOW_PICKLED_MODEL=true`, because unpickling runs code from the file: enable it only for a file from the team.

**`confirmed: false`.** Until the model owner confirms the preprocessing and the class order, leave `confirmed: false` in the config. The model name on every result then ends with "(settings unconfirmed)", in the API and in the app.

### Current state (2026-10-12)

The team's `efficientnetv2s_model.pt` (weights only) is connected with the settings from the training script (received 2026-10-14): classes AD, LMCI, EMCI, CN in that output order; `Resize((224, 224))`, `ToTensor`, ImageNet mean/std, RGB. The server's preprocessing matches the training transforms to within 1e-6, so `confirmed` is true. The model was trained on `masked-training` images. On the team's 20 sample slices (four scans, with skull and eyes visible) it was right on 10 of 20: AD 5/5, CN 5/5, EMCI 0/5 (all CN), LMCI 0/5 (mostly AD). Four scans are too few to measure accuracy; the training script's own test-set results are in its `Results` folder.

If the file or the configuration is missing or wrong, the server logs the reason and keeps using the stub. It never uses a model with guessed settings.

### What the model owner must provide

Nothing below is assumed by the server.

| Needed | Why |
|---|---|
| How the file was saved: TorchScript, full model, or `state_dict` + architecture code | Decides how it is loaded |
| PyTorch version used for training/export | The server image has PyTorch 2.5.1 (CPU) |
| Input size and number of channels | Preprocessing |
| Exact preprocessing: resize method, pixel scaling, mean and std | A mismatch gives confident, wrong results |
| The class for each output unit, in order | The four labels are `AD`, `LMCI`, `EMCI`, `CN`. The model owner gave the output order AD, LMCI, EMCI, CN (2026-10-14) |
| Whether the model outputs logits or probabilities | Whether the server applies softmax |
| Model name and version | Shown with every result |
| Whether images larger than 256 px should be accepted, and how they should be resized | The app scales larger images down to fit 256 px before upload; images that already fit are sent unchanged |

`CONFIDENCE_GATE` (0.80) only decides whether a result is labelled "pending review" or "awaiting confirmation". It is a workflow setting from the project design, not a measure of clinical reliability.

### Masking and Grad-CAM

With `masking: brain_v1` in the config, the server runs the team's masking code (`app/ml/masking.py`, from the script that made `masked-training`) before the model: grayscale, Otsu-based brain mask with convex hull and erosion, background set to zero, crop to the brain with 8 px padding, resize to 224 × 224 (INTER_AREA). The dataset script's `prune_last_n` drops whole slices from a scan and has no counterpart for a single upload.

With `explain: gradcam`, the worker also makes a Grad-CAM map for the predicted class (`app/ml/gradcam.py`, from the team's Grad-CAM script: last block `features[-1]`, mean-gradient weights, ReLU, scaled to 0–1). The masked image and the map are stored on the analysis, removed with the scan image by the retention purge, and served by `GET /analyses/{aid}/explanation`. The stub never makes a map. A map shows what raised the model's score most; it is not a map of damage.

### Model in use (2026-11-23)

`backend/models/model.pt` is the team's newer `single_rotating_best.pt` (weights only, sha256 `0ac789b3…090e`). Its classifier is one `Linear(1280, 4)` layer, so the config names the architecture `efficientnet_v2_s_linear`. Classes AD, LMCI, EMCI, CN, ImageNet mean/std and masking are as before (confirmed by the team). The previous model is kept as `model-2026-10-14.pt` with `model_config-2026-10-14.yaml`; to switch back, copy both over `model.pt` and `model_config.yaml` and restart.

No accuracy has been measured for this model on the server. Measured speed on the development laptop (CPU, Docker): about 0.08 s per slice for the model and 0.9 s for a Grad-CAM map.

### Resizing (review comment 6)

Training resized the masked, cropped slices to 224 × 224 with OpenCV `INTER_AREA`. The server does the same: the masking step ends with `INTER_AREA`, and the config's `resize_interpolation` is `area` (it said `bilinear` before, but that step never ran, because the masking already returns 224 × 224). A test checks the server's resize against `cv2.resize(..., INTER_AREA)`.

Two differences remain for single-image uploads, and they are why full scans are preferred:

- The app scales images larger than 256 px down to fit 256 px before upload, so the crop is made from a smaller image than in training.
- Training slices were PNG files cut straight from the scan. A JPEG upload has compression artefacts the model has not seen. The upload screen asks for PNG where possible.

A full scan (`.nii`) avoids both: the server extracts the slices itself, exactly as the training data was made.

### Full MRI scans (.nii / .nii.gz)

A doctor can upload a whole scan (`POST /scans/volume`). The worker (`app/ml/volume.py`) follows the team's scripts:

1. **Extract axial slices** as `extract-axial.py` does: `nib.as_closest_canonical`, every slice along the third axis, each scaled to 0–255 on its own minimum and maximum and cast to uint8.
2. **Rotate each slice 90° counter-clockwise** (`np.rot90(k=1)`), so the face points up as in the training slices.
3. **Keep brain slices** with the team's detector (`EfficientNetV2S_brain_detector.keras`, as in `FilterScans.py`): each slice is converted to RGB, resized to 224 × 224 and scored; slices scoring below 0.4 are kept.
4. **Mask and crop** each kept slice with the training masking code (INTER_AREA to 224 × 224), then **leave out the last 15 kept slices** (the top of the head), as the dataset script's `prune_last_n` did.
5. **Classify** every remaining slice and **average the four class scores**. The image stored with the result is the slice most confident in the averaged top class, and its Grad-CAM map is made.

At least 10 slices must remain (`VOLUME_MIN_SLICES`); otherwise the analysis fails with `VOLUME_TOO_FEW_SLICES`. The uploaded file is deleted once the analysis has completed; only the chosen slice is kept, and it is removed by the retention purge like any other image.

The detector is a Keras 3 model. The server runs it with Keras on the PyTorch backend (`KERAS_BACKEND=torch`), so no TensorFlow is installed. It goes in `backend/models/brain_detector.keras` (git-ignored). Without it, `/health` shows `"full_scans": "disabled"` and full-scan uploads get 503: the filtering step is never skipped. Measured on the development laptop: about 0.3 s per slice for the detector, so roughly a minute for a 182-slice scan.

Settings: `BRAIN_FILTER_PATH`, `BRAIN_FILTER_THRESHOLD` (0.4), `VOLUME_PRUNE_LAST` (15), `VOLUME_MIN_SLICES` (10), `MAX_VOLUME_BYTES` (64 MB), `MAX_VOLUME_UNPACKED_BYTES` (256 MB).

## Cloud deployment

The server can run on one small Linux machine (planned: Oracle Cloud Always Free, Arm, 1 OCPU, 4 GB). `docker-compose.prod.yml` adds Caddy for HTTPS, and only Caddy's ports 80 and 443 are public. The API and the database publish no ports.

On the machine, `backend/.env` needs `APP_ENV=production`, `DOMAIN=<ip-with-dashes>.sslip.io` and new random values for every secret. In production the server refuses a weak `JWT_SECRET`, and `/docs`, `/redoc` and `/openapi.json` are off. The model files in `backend/models/` come with the repository.

```bash
docker compose --env-file backend/.env -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

The seed script refuses `APP_ENV=production`. To create the fictional accounts once:

```bash
docker compose --env-file backend/.env -f docker-compose.yml -f docker-compose.prod.yml run --rm -e APP_ENV=development api python -m app.db.seed
```

Oracle's Ubuntu images block inbound traffic in the machine's own firewall as well as in the subnet's Security List, so ports 80 and 443 must be opened in both. In the app, enter the full `https://` address under **Server:** on the login screen.

This setup is for the demo with fictional accounts. It is not suitable for real patient data.

## Using the app with the server

Build or run the app with fixtures off and the server's address:

```bash
flutter run --dart-define=USE_FIXTURES=false --dart-define=API_BASE_URL=http://10.0.2.2:8000/api/v1
```

- **Android emulator:** `10.0.2.2` is the PC.
- **A phone on the same Wi-Fi:** use the PC's address, for example `http://192.168.1.178:8000/api/v1`. Windows Firewall must allow inbound connections to port 8000. On the login screen, **Server:** → **Find server on this Wi-Fi** tries every address of the phone's own network (x.x.x.1–254, port 8000) and picks the one whose `/health` answers like NeuroSense (`status: ok` plus a `model` field). It takes up to about 30 seconds and needs iOS's Local Network permission. If nothing is found, test `http://<PC-IP>:8000/health` in the phone's browser.
- **iOS:** the app allows plain HTTP to local-network addresses only (`NSAllowsLocalNetworking`). iOS asks once for permission to find devices on the local network.
- **Android:** plain HTTP is allowed in debug builds only. Release builds require HTTPS.

Plain HTTP on Wi-Fi sends tokens and images unencrypted. That is acceptable only for development with the fictional seed data. A real deployment needs HTTPS in front of the API.

Counselling answers stay inside the app (predefined answers and safety rules); the server has no counselling endpoint.

## Security notes

- Passwords are hashed with Argon2. Access tokens last 15 minutes. Refresh tokens are random, stored only as a hash, valid 14 days, and replaced on every use; presenting a used one ends that login's sessions. Logout revokes them.
- There is no self-registration. An admin creates every account (`POST /admin/users`); the first admin comes from the seed script.
- Admins manage accounts only. Every clinical route answers 403 or 404 to an admin.
- Every route takes the caller's identity from the token. Patient IDs, sender names and similar fields in request bodies are ignored for patients.
- Another person's record answers 404, the same as a record that doesn't exist.
- Request logs contain the method, the route template, the status and the duration. They contain no bodies, tokens, names or results.
- Login attempts are limited to 5 per minute per email (kept in memory, so per server process).
