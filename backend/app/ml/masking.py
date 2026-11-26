"""Brain masking, as used to build the training data (masked-training / masked-testing).

`extract_conservative_mask` and `process_and_crop` are the team's masking code,
unchanged apart from formatting. `mask_for_model` applies them to one uploaded
slice the way `batch_process_dataset` did for each training slice: read as
grayscale, mask and crop, resize to the target size with INTER_AREA.

The dataset script also dropped the last slices of every scan folder
(`prune_last_n`). That choice applies to whole scans, not to a single uploaded
slice, so it has no counterpart here.
"""
import cv2
import numpy as np
from PIL import Image

# Parameters used when the training data was made (batch_process_dataset call).
PAD = 8
DILATION_ITER = 4
TARGET_SIZE = (224, 224)


def extract_conservative_mask(slice_img, dilation_iter=4):
    """Generates a smooth, conservative brain mask using Otsu, convex hull, and dilation."""
    blurred = cv2.GaussianBlur(slice_img, (5, 5), 0)

    # Low threshold to capture dim peripheral cortex
    otsu_val, _ = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    conservative_thresh_val = otsu_val * 0.45
    _, binary = cv2.threshold(blurred, conservative_thresh_val, 255, cv2.THRESH_BINARY)

    # Connected components
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    if num_labels <= 1:
        return np.ones_like(slice_img, dtype=np.uint8) * 255

    largest_label = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    mask = (labels == largest_label).astype(np.uint8) * 255

    # Convex hull on outer boundary
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    filled_mask = np.zeros_like(mask)
    if contours:
        largest_contour = max(contours, key=cv2.contourArea)
        hull = cv2.convexHull(largest_contour)
        cv2.drawContours(filled_mask, [hull], -1, 255, thickness=cv2.FILLED)
    else:
        filled_mask = mask

    # The training code erodes here (shrinks the mask inward), which removes the skull rim.
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (4, 4))
    dilated_mask = cv2.erode(filled_mask, kernel, iterations=dilation_iter)

    return dilated_mask


def process_and_crop(slice_img, pad=8, dilation_iter=4):
    """Masks out non-brain noise and crops tightly to the bounding box."""
    img_norm = cv2.normalize(slice_img, None, 0, 255, cv2.NORM_MINMAX).astype(np.uint8)
    mask = extract_conservative_mask(img_norm, dilation_iter=dilation_iter)

    # Zero out background
    masked_img = cv2.bitwise_and(img_norm, img_norm, mask=mask)

    # Bounding box
    y_indices, x_indices = np.where(mask > 0)
    if len(y_indices) > 0 and len(x_indices) > 0:
        y_min = max(0, np.min(y_indices) - pad)
        y_max = min(slice_img.shape[0], np.max(y_indices) + pad)
        x_min = max(0, np.min(x_indices) - pad)
        x_max = min(slice_img.shape[1], np.max(x_indices) + pad)

        cropped_img = masked_img[y_min:y_max, x_min:x_max]
    else:
        cropped_img = masked_img

    return cropped_img


def mask_for_model(image: Image.Image) -> Image.Image:
    """One uploaded slice -> the brain-only 224 x 224 grayscale image the model expects."""
    rgb = np.asarray(image.convert("RGB"))
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)  # what cv2.imread(..., IMREAD_GRAYSCALE) gives
    processed = process_and_crop(gray, pad=PAD, dilation_iter=DILATION_ITER)
    processed = cv2.resize(processed, TARGET_SIZE, interpolation=cv2.INTER_AREA)
    return Image.fromarray(processed, mode="L")
