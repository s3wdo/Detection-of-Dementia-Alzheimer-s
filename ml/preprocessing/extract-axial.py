import os
import gc
import nibabel as nib
import numpy as np
from PIL import Image

# Path to your main dataset folder containing the 5 classes
base_dir = r"D:"

print("Starting extraction")

for root, dirs, files in os.walk(base_dir):
    for file in files:
        if file.lower().endswith(('.nii', '.nii.gz')):
            nii_path = os.path.join(root, file)

            try:
                print(f"Processing scan: {file}")

                # Load, force canonical orientation, and load data as float32 to conserve memory
                img = nib.load(nii_path)
                canonical_img = nib.as_closest_canonical(img)
                data = canonical_img.get_fdata()
                z_size = data.shape[2]

                # Target folder is the exact directory where the .nii file is
                target_folder = root

                # Base name of the file without extension
                base_name = os.path.splitext(file)[0]
                if base_name.endswith('.nii'):
                    base_name = os.path.splitext(base_name)[0]

                # Extract every axial slice and save as PNG
                for z in range(z_size):
                    slice_2d = data[:, :, z]

                    if slice_2d.max() > slice_2d.min():
                        slice_normalized = ((slice_2d - slice_2d.min()) / (slice_2d.max() - slice_2d.min()) * 255)
                    else:
                        slice_normalized = np.zeros_like(slice_2d)

                    img_uint8 = slice_normalized.astype(np.uint8)

                    png_name = f"{base_name}_slice_{z:03d}.png"
                    img_path = os.path.join(target_folder, png_name)
                    Image.fromarray(img_uint8).save(img_path)

                # Clean up memory handles
                del data
                img.uncache()
                canonical_img.uncache()
                del img
                del canonical_img
                gc.collect()

                # Delete the original .nii file to save storage space
                os.remove(nii_path)
                print(f"Finished and cleaned original: {file}")

            except Exception as e:
                print(f"Error processing {file}: {e}")

print("All uncompressed scans successfully processed into PNG slices!")
