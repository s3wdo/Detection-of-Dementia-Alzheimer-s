"""A full MRI scan (.nii / .nii.gz) -> one result, following the team's pipeline:

1. Extract axial slices as in `extract-axial.py`: canonical orientation
   (`nib.as_closest_canonical`), every slice along the third axis, each scaled
   to 0..255 on its own min/max and cast to uint8.
2. Rotate every slice 90 degrees counter-clockwise (the rotation the training
   slices were given).
3. Keep only slices the brain detector accepts (`FilterScans.py`: score < 0.4).
4. Mask and crop each kept slice exactly like the training data
   (`app.ml.masking`, resize with INTER_AREA), then drop the last
   `prune_last` slices of the scan (the top of the head), as the dataset script did.
5. Classify every remaining slice with the model and average the class
   probabilities. Grad-CAM is made for the slice that is most confident in the
   averaged top class.

Nothing here is a clinical measurement. The averaged scores are model output.
"""
from __future__ import annotations

import io
import zlib
from dataclasses import dataclass
from typing import Protocol, Sequence

import cv2
import numpy as np
from PIL import Image

from app.ml.masking import DILATION_ITER, PAD, TARGET_SIZE, process_and_crop

GZIP_MAGIC = b"\x1f\x8b"


class VolumeError(ValueError):
    """The file is not a scan the pipeline can use. `code` goes into the API error / job."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


class BrainFilter(Protocol):
    """Step 3. Returns one score per slice; slices with score < threshold are kept."""

    threshold: float

    def scores(self, slices_rgb_224: np.ndarray) -> np.ndarray: ...


# ---------------------------------------------------------------- step 1 + 2

def read_nifti(raw: bytes, *, max_unpacked_bytes: int) -> np.ndarray:
    """The scan's voxel data in canonical (RAS+) orientation, as float64 (like get_fdata)."""
    import nibabel as nib

    if raw[:2] == GZIP_MAGIC:
        raw = _gunzip_limited(raw, max_unpacked_bytes)
    try:
        image = nib.Nifti1Image.from_bytes(raw)
    except Exception as exc:  # noqa: BLE001 - nibabel raises several types for bad files
        try:
            image = nib.Nifti2Image.from_bytes(raw)
        except Exception:  # noqa: BLE001
            raise VolumeError("VOLUME_INVALID", "The file is not a readable NIfTI scan.") from exc
    shape = image.shape
    if len(shape) == 4 and shape[3] == 1:
        image = image.slicer[..., 0]
        shape = image.shape
    if len(shape) != 3:
        raise VolumeError("VOLUME_INVALID", "The scan must be one 3-D volume.")
    if min(shape) < 16 or max(shape) > 512:
        raise VolumeError("VOLUME_INVALID", "The scan's size is outside 16-512 voxels per side.")
    canonical = nib.as_closest_canonical(image)
    return np.asarray(canonical.get_fdata(), dtype=np.float64)


def _gunzip_limited(raw: bytes, limit: int) -> bytes:
    decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
    try:
        out = decompressor.decompress(raw, limit + 1)
    except zlib.error as exc:
        raise VolumeError("VOLUME_INVALID", "The .nii.gz file could not be decompressed.") from exc
    if len(out) > limit or decompressor.unconsumed_tail:
        raise VolumeError("VOLUME_TOO_LARGE", "The scan is too large once decompressed.")
    return out


def axial_slices(data: np.ndarray) -> list[np.ndarray]:
    """Steps 1 and 2: every axial slice as uint8, rotated 90 degrees counter-clockwise."""
    slices = []
    for z in range(data.shape[2]):
        slice_2d = data[:, :, z]
        if slice_2d.max() > slice_2d.min():
            normalized = (slice_2d - slice_2d.min()) / (slice_2d.max() - slice_2d.min()) * 255
        else:
            normalized = np.zeros_like(slice_2d)
        img_uint8 = normalized.astype(np.uint8)  # truncates, as the extraction script did
        slices.append(np.ascontiguousarray(np.rot90(img_uint8, k=1)))  # k=1: counter-clockwise
    return slices


# ---------------------------------------------------------------- step 3

def filter_input(slice_uint8: np.ndarray) -> np.ndarray:
    """What FilterScans.py fed the detector: the PNG read as 3-channel, RGB, cv2.resize to 224."""
    rgb = cv2.cvtColor(slice_uint8, cv2.COLOR_GRAY2RGB)
    return cv2.resize(rgb, (224, 224))  # cv2 default interpolation, as in the script


def keep_brain_slices(slices: Sequence[np.ndarray], brain_filter: BrainFilter, batch: int = 32) -> list[int]:
    """Indices (in scan order) of the slices the detector keeps."""
    kept: list[int] = []
    for start in range(0, len(slices), batch):
        chunk = np.stack([filter_input(s) for s in slices[start : start + batch]])
        scores = np.asarray(brain_filter.scores(chunk)).reshape(-1)
        kept.extend(start + i for i, score in enumerate(scores) if score < brain_filter.threshold)
    return kept


# ---------------------------------------------------------------- step 4

def masked_slice(slice_uint8: np.ndarray) -> Image.Image:
    """The masked, cropped 224 x 224 slice, as made for the training data."""
    processed = process_and_crop(slice_uint8, pad=PAD, dilation_iter=DILATION_ITER)
    processed = cv2.resize(processed, TARGET_SIZE, interpolation=cv2.INTER_AREA)
    return Image.fromarray(processed, mode="L")


# ---------------------------------------------------------------- the whole scan

@dataclass(frozen=True)
class VolumeResult:
    probabilities: dict[str, float]  # averaged over the slices used
    slices_total: int  # axial slices in the scan
    slices_kept: int  # accepted by the brain detector
    slices_used: int  # after pruning the top slices
    slice_index: int  # the slice shown to the doctor (0-based, in the scan's axial order)
    slice_png: bytes  # that slice as extracted and rotated (before masking)
    model_input_png: bytes | None  # that slice after masking
    heatmap_png: bytes | None
    explanation_method: str | None


def analyse_volume(
    raw: bytes,
    predictor,
    brain_filter: BrainFilter,
    *,
    prune_last: int,
    min_slices: int,
    max_unpacked_bytes: int,
) -> VolumeResult:
    data = read_nifti(raw, max_unpacked_bytes=max_unpacked_bytes)
    slices = axial_slices(data)
    kept = keep_brain_slices(slices, brain_filter)
    used = kept[: max(0, len(kept) - prune_last)]
    if len(used) < min_slices:
        raise VolumeError(
            "VOLUME_TOO_FEW_SLICES",
            f"Only {len(used)} brain slices were left after filtering; at least {min_slices} are needed.",
        )

    masked = [masked_slice(slices[i]) for i in used]
    per_slice = predictor.predict_many(masked)
    labels = list(per_slice[0].keys())
    averaged = {label: float(np.mean([p[label] for p in per_slice])) for label in labels}
    top = max(averaged, key=averaged.get)  # type: ignore[arg-type]
    best = int(np.argmax([p[top] for p in per_slice]))

    heatmap, method = predictor.explain(masked[best], top) if hasattr(predictor, "explain") else (None, None)
    return VolumeResult(
        probabilities=averaged,
        slices_total=len(slices),
        slices_kept=len(kept),
        slices_used=len(used),
        slice_index=used[best],
        slice_png=_png(Image.fromarray(slices[used[best]], mode="L")),
        model_input_png=_png(masked[best]) if not getattr(predictor, "simulated", True) else None,
        heatmap_png=heatmap,
        explanation_method=method,
    )


def _png(image: Image.Image) -> bytes:
    out = io.BytesIO()
    image.save(out, format="PNG")
    return out.getvalue()


__all__ = ["VolumeError", "VolumeResult", "analyse_volume", "axial_slices", "keep_brain_slices", "read_nifti"]
