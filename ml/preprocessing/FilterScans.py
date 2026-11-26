import os
import cv2
import numpy as np
import tensorflow as tf
from shutil import copy2
from tensorflow.keras.applications.efficientnet_v2 import preprocess_input

# CONFIG
SOURCE_PNG_DIR = r'D:\Other_Rotated'
OUTPUT_BRAIN_DIR = r'D:\Other3'
IMG_SIZE = (224, 224)

THRESHOLD = 0.4
BATCH_SIZE = 32

# LOAD MODEL
MODEL_PATH = r"D:\EfficientNetV2S_brain_detector.keras"

try:
    model = tf.keras.models.load_model(
        MODEL_PATH,
        custom_objects={'preprocess_input': preprocess_input},
        compile=False
    )
    print("Model loaded successfully (EfficientNetV2 logic applied)")
except Exception as e:
    print(f"Failed to load model: {e}")
    exit()


def filter_png_dataset():
    os.makedirs(OUTPUT_BRAIN_DIR, exist_ok=True)

    # 1. Fast pre-count of all PNGs so we have a target denominator
    print("Scanning directory structure to count total PNGs...")
    total_pngs = 0
    for root, dirs, files in os.walk(SOURCE_PNG_DIR):
        total_pngs += sum(1 for f in files if f.lower().endswith('.png'))

    print(f"Found {total_pngs:,} total PNGs to process.\nStarting filtration...")

    processed_count = 0
    kept_count = 0

    # 2. Main processing loop
    for root, dirs, files in os.walk(SOURCE_PNG_DIR):
        png_files = [f for f in files if f.lower().endswith('.png')]
        if not png_files:
            continue

        rel_path = os.path.relpath(root, SOURCE_PNG_DIR)
        target_folder = os.path.join(OUTPUT_BRAIN_DIR, rel_path)

        for i in range(0, len(png_files), BATCH_SIZE):
            batch_filenames = png_files[i: i + BATCH_SIZE]
            images_to_predict = []
            valid_paths = []

            for file in batch_filenames:
                file_path = os.path.join(root, file)
                try:
                    img = cv2.imread(file_path)
                    if img is None:
                        processed_count += 1
                        continue

                    # Preprocessing: Convert to RGB and Resize
                    img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                    img_resized = cv2.resize(img_rgb, IMG_SIZE)

                    images_to_predict.append(img_resized)
                    valid_paths.append((file_path, file))
                except Exception as e:
                    print(f"\nError reading {file}: {e}")
                    processed_count += 1

            if not images_to_predict:
                continue

            # Batch Prediction
            predictions = model.predict(np.array(images_to_predict), verbose=0)

            folder_created = False
            batch_kept = 0
            for idx, pred in enumerate(predictions):
                score = pred[0]
                processed_count += 1

                if score < THRESHOLD:
                    if not folder_created:
                        os.makedirs(target_folder, exist_ok=True)
                        folder_created = True

                    src_path, filename = valid_paths[idx]
                    copy2(src_path, os.path.join(target_folder, filename))
                    kept_count += 1
                    batch_kept += 1

            # Print live progress update
            percent = (processed_count / total_pngs) * 100
            print(f"\rProgress: {processed_count:,} / {total_pngs:,} ({percent:.2f}%) | Kept: {kept_count:,}", end="",
                  flush=True)

    print(f"\n\nFiltration Complete!")
    print(f"Total Processed: {processed_count:,}")
    print(f"Total Brain Slices Kept: {kept_count:,}")
    print(f"Saved to: {OUTPUT_BRAIN_DIR}")


if __name__ == "__main__":
    filter_png_dataset()
