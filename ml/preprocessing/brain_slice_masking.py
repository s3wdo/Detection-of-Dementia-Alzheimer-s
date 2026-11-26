import re
import os
from pathlib import Path
import cv2
import numpy as np
from tqdm import tqdm


def extract_conservative_mask(slice_img, dilation_iter=4):
    """Generates a smooth, conservative brain mask using Otsu, convex hull, and dilation."""
    blurred = cv2.GaussianBlur(slice_img, (5, 5), 0)

    # Low threshold to capture dim peripheral cortex
    otsu_val, _ = cv2.threshold(
        blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU
    )
    conservative_thresh_val = otsu_val * 0.45
    _, binary = cv2.threshold(
        blurred, conservative_thresh_val, 255, cv2.THRESH_BINARY
    )

    # Connected components
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(
        binary, connectivity=8
    )
    if num_labels <= 1:
        return np.ones_like(slice_img, dtype=np.uint8) * 255

    largest_label = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    mask = (labels == largest_label).astype(np.uint8) * 255

    # Convex hull on outer boundary
    contours, _ = cv2.findContours(
        mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
    )
    filled_mask = np.zeros_like(mask)
    if contours:
        largest_contour = max(contours, key=cv2.contourArea)
        hull = cv2.convexHull(largest_contour)
        cv2.drawContours(filled_mask, [hull], -1, 255, thickness=cv2.FILLED)
    else:
        filled_mask = mask

    # Erode inward to trim the bright skull rim
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (4, 4))
    dilated_mask = cv2.erode(filled_mask, kernel, iterations=dilation_iter)

    return dilated_mask


def process_and_crop(slice_img, pad=8, dilation_iter=4):
    """Masks out non-brain noise and crops tightly to the bounding box."""
    img_norm = cv2.normalize(
        slice_img, None, 0, 255, cv2.NORM_MINMAX
    ).astype(np.uint8)
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


def natural_sort_key(s):
    """Sort filenames numerically (e.g., slice_2 before slice_10)."""
    return [
        int(text) if text.isdigit() else text.lower()
        for text in re.split(r"(\d+)", str(s))
    ]


from collections import defaultdict

VALID_EXTENSIONS = {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp"}


def batch_process_dataset(
    input_root,
    output_root,
    prune_last_n=15,
    target_size=(224, 224),
    pad=8,
    dilation_iter=4,
):
    """Recursively processes every slice under input_root and mirrors the
    folder structure under output_root. Originals are never modified."""
    input_root = Path(input_root)
    output_root = Path(output_root)

    if input_root.resolve() == output_root.resolve():
        raise ValueError("output_root must be different from input_root")

    # Group slices by folder so pruning applies per scan series
    slices_by_folder = defaultdict(list)
    for file_path in input_root.rglob("*"):
        if file_path.is_file() and file_path.suffix.lower() in VALID_EXTENSIONS:
            slices_by_folder[file_path.parent].append(file_path)

    if not slices_by_folder:
        print(f"No image files found under {input_root}")
        return

    # Build the full work list first so the progress bar knows the total
    work_items = []
    for folder, files in slices_by_folder.items():
        files.sort(key=lambda p: natural_sort_key(p.name))
        if prune_last_n > 0 and len(files) > prune_last_n:
            files = files[:-prune_last_n]
        work_items.extend(files)

    print(
        f"Found {len(work_items)} slices to process across "
        f"{len(slices_by_folder)} folders."
    )

    total_processed = 0
    with tqdm(total=len(work_items), desc="Masking slices", unit="slice") as pbar:
        for file_path in work_items:
            out_dir = output_root / file_path.parent.relative_to(input_root)
            out_dir.mkdir(parents=True, exist_ok=True)

            img = cv2.imread(str(file_path), cv2.IMREAD_GRAYSCALE)
            if img is None:
                tqdm.write(f"Warning: could not read {file_path}")
                pbar.update(1)
                continue

            processed = process_and_crop(
                img, pad=pad, dilation_iter=dilation_iter
            )

            if target_size is not None:
                processed = cv2.resize(
                    processed, target_size, interpolation=cv2.INTER_AREA
                )

            cv2.imwrite(str(out_dir / file_path.name), processed)
            total_processed += 1
            pbar.update(1)

    print(f"Done! Processed {total_processed} slices. Saved to: {output_root}")


if __name__ == "__main__":
    batch_process_dataset(
        input_root=r"C:\senior\testing3",
        output_root=r"C:\senior\masked-testing",
        prune_last_n=15,
        target_size=(224, 224),
        pad=8,
        dilation_iter=4,
    )

    # For the testing set, run again with your testing folder:
