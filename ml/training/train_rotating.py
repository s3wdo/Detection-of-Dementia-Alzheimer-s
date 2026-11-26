import os
import time
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.metrics import (
    ConfusionMatrixDisplay,
    accuracy_score,
    confusion_matrix,
    classification_report,
    roc_auc_score,
    roc_curve,
    auc,
    precision_recall_curve,
    average_precision_score
)
from sklearn.model_selection import KFold, train_test_split
from sklearn.preprocessing import label_binarize
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import DataLoader, Subset
from torchvision import datasets, transforms
from torchvision.models import EfficientNet_V2_S_Weights, efficientnet_v2_s
from tqdm import tqdm

# ==========================================
# 1. Setup Results & Dataset Directories
# ==========================================
BASE_RESULTS_DIR = r"C:\senior\Results_RotatingFold"
os.makedirs(BASE_RESULTS_DIR, exist_ok=True)

# Update this if your new data is strictly in D:\masked-testing
DATA_DIR = r"C:\senior\ALL-Data" 

IMG_SIZE = 224
BATCH_SIZE = 20

EPOCHS_PER_FOLD = 1
EARLY_STOPPING_PATIENCE = 12

K_FOLDS = 20

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

# ==========================================
# 2. Define Custom 4-Class Order & Transforms
# ==========================================
CUSTOM_CLASSES = ["AD", "LMCI", "EMCI", "CN"]
CUSTOM_CLASS_TO_IDX = {cls_name: i for i, cls_name in enumerate(CUSTOM_CLASSES)}


class OrderedImageFolder(datasets.ImageFolder):
    def find_classes(self, directory):
        return CUSTOM_CLASSES, CUSTOM_CLASS_TO_IDX


transform = transforms.Compose([
    transforms.Resize((IMG_SIZE, IMG_SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])

print("Loading dataset...")
full_dataset = OrderedImageFolder(DATA_DIR, transform=transform)
class_names = full_dataset.classes
NUM_CLASSES = len(class_names)

# ==========================================
# 3. Strict Patient Grouping & Global 90/10 Split
# ==========================================
patient_folder_to_indices = {}
for idx, (path_str, _) in enumerate(full_dataset.samples):
    # Navigate up 4 directories from the image file to reach the Patient ID:
    # .parents[0] = I296281
    # .parents[1] = 2011-07-07_13_54_53.0
    # .parents[2] = MT1__N3m
    # .parents[3] = 002_S_2010 (Target Patient Folder)
    patient_id_folder = Path(path_str).parents[3]
    patient_folder_to_indices.setdefault(patient_id_folder, []).append(idx)

unique_patients = np.array(sorted(list(patient_folder_to_indices.keys())))
total_patients = len(unique_patients)
print(f"Found {total_patients} total patient/scan folders.")

# Same seed, same test_size -> same split as the original script
cv_patients, test_patients = train_test_split(
    unique_patients, test_size=0.10, random_state=42, shuffle=True
)

print(f"Global Split: {len(cv_patients)} patients for CV, "
      f"{len(test_patients)} patients for Unseen Testing.")

test_indices = [idx for folder in test_patients for idx in patient_folder_to_indices[folder]]
test_subset = Subset(full_dataset, test_indices)
test_loader = DataLoader(test_subset, batch_size=BATCH_SIZE, shuffle=False, pin_memory=True)

# ---> NEW: Save test patient paths to CSV <---
test_paths_data = []
for idx in test_indices:
    path_str, label_idx = full_dataset.samples[idx]
    patient_id = Path(path_str).parents[3].name
    class_name = class_names[label_idx]
    test_paths_data.append({
        "Patient_ID": patient_id,
        "Class": class_name,
        "File_Path": path_str
    })

test_paths_df = pd.DataFrame(test_paths_data)
test_paths_csv = os.path.join(BASE_RESULTS_DIR, "test_patients_paths.csv")
test_paths_df.to_csv(test_paths_csv, index=False)
print(f"Saved {len(test_paths_df)} test image paths to {test_paths_csv}")
# ---------------------------------------------

# ==========================================
# 4. Precompute per-fold index lists
# ==========================================
kf = KFold(n_splits=K_FOLDS, shuffle=True, random_state=123)

fold_train_loaders = []
fold_val_loaders = []

print("\nBuilding fold loaders...")
for fold, (train_idx, val_idx) in enumerate(kf.split(cv_patients)):
    fold_num = fold + 1
    fold_train_folders = cv_patients[train_idx]
    fold_val_folders = cv_patients[val_idx]

    train_indices = [i for f in fold_train_folders for i in patient_folder_to_indices[f]]
    val_indices = [i for f in fold_val_folders for i in patient_folder_to_indices[f]]

    train_subset = Subset(full_dataset, train_indices)
    val_subset = Subset(full_dataset, val_indices)

    fold_train_loaders.append(
        DataLoader(train_subset, batch_size=BATCH_SIZE, shuffle=True, pin_memory=True)
    )
    fold_val_loaders.append(
        DataLoader(val_subset, batch_size=BATCH_SIZE, shuffle=False, pin_memory=True)
    )
    print(f"  Fold {fold_num}: {len(train_indices)} train imgs / {len(val_indices)} val imgs")

# ==========================================
# 5. Model, Loss, Optimizer (built ONCE)
# ==========================================
def build_model():
    weights = EfficientNet_V2_S_Weights.DEFAULT
    model = efficientnet_v2_s(weights=weights)
    in_features = model.classifier[1].in_features
    model.classifier = nn.Linear(in_features, NUM_CLASSES)
    return model.to(device)


model = build_model()

class_weights = torch.FloatTensor([1.2, 1.4, 1.0, 0.85]).to(device)
criterion = nn.CrossEntropyLoss(weight=class_weights)

optimizer = optim.Adam(model.parameters(), lr=1e-5)
scheduler = optim.lr_scheduler.ReduceLROnPlateau(optimizer, mode="min", factor=0.5, patience=2)

best_model_path = os.path.join(BASE_RESULTS_DIR, "single_rotating_best.pt")

# ==========================================
# 6. Training loop with rotating folds
# ==========================================
print(f"\n{'=' * 60}\nPHASE 1: TRAINING SINGLE MODEL WITH ROTATING FOLDS\n{'=' * 60}")
print(f"  EPOCHS_PER_FOLD = {EPOCHS_PER_FOLD}  x  K_FOLDS = {K_FOLDS}  "
      f"=> up to {EPOCHS_PER_FOLD * K_FOLDS} total epochs\n")

best_val_loss = float("inf")
epochs_no_improve = 0
global_epoch = 0
stop_training = False

history = []

for fold_cycle in range(K_FOLDS):
    if stop_training:
        break

    fold_num = fold_cycle + 1
    train_loader = fold_train_loaders[fold_cycle]
    val_loader = fold_val_loaders[fold_cycle]

    print(f"\n--- Switching to Fold {fold_num}/{K_FOLDS} "
          f"(train {len(train_loader.dataset)} imgs, val {len(val_loader.dataset)} imgs) ---")

    for local_epoch in range(1, EPOCHS_PER_FOLD + 1):
        global_epoch += 1
        epoch_start = time.time()

        # -------- TRAIN --------
        model.train()
        running_loss, correct, total = 0.0, 0, 0
        loop = tqdm(train_loader,
                    desc=f"Epoch {global_epoch} [fold {fold_num}, {local_epoch}/{EPOCHS_PER_FOLD}]",
                    leave=False)

        for inputs_b, labels_b in loop:
            inputs_b = inputs_b.to(device, non_blocking=True)
            labels_b = labels_b.to(device, non_blocking=True)

            optimizer.zero_grad()
            outputs = model(inputs_b)
            loss = criterion(outputs, labels_b)
            _, preds = torch.max(outputs, 1)

            loss.backward()
            optimizer.step()

            running_loss += loss.item() * inputs_b.size(0)
            total += labels_b.size(0)
            correct += (preds == labels_b.view_as(preds)).sum().item()

        train_loss = running_loss / total
        train_acc = correct / total

        # -------- VALIDATE (on this fold's val split) --------
        model.eval()
        val_loss, val_correct, val_total = 0.0, 0, 0
        with torch.no_grad():
            for inputs_b, labels_b in val_loader:
                inputs_b = inputs_b.to(device, non_blocking=True)
                labels_b = labels_b.to(device, non_blocking=True)
                outputs = model(inputs_b)
                loss = criterion(outputs, labels_b)
                _, preds = torch.max(outputs, 1)

                val_loss += loss.item() * inputs_b.size(0)
                val_total += labels_b.size(0)
                val_correct += (preds == labels_b.view_as(preds)).sum().item()

        v_loss = val_loss / val_total
        v_acc = val_correct / val_total
        epoch_time = time.time() - epoch_start

        scheduler.step(v_loss)

        history.append({
            "global_epoch": global_epoch,
            "fold": fold_num,
            "local_epoch": local_epoch,
            "train_loss": train_loss,
            "train_acc": train_acc,
            "val_loss": v_loss,
            "val_acc": v_acc,
            "epoch_time_sec": epoch_time,
            "lr": optimizer.param_groups[0]["lr"],
        })

        print(f"  Epoch {global_epoch:3d} (fold {fold_num}, local {local_epoch}) "
              f"| train loss {train_loss:.4f} acc {train_acc:.4f} "
              f"| val loss {v_loss:.4f} acc {v_acc:.4f} "
              f"| lr {optimizer.param_groups[0]['lr']:.2e} "
              f"| {epoch_time:.1f}s")

        if v_loss < best_val_loss:
            best_val_loss = v_loss
            epochs_no_improve = 0
            torch.save(model.state_dict(), best_model_path)
            print(f"    ✓ New best val loss: {best_val_loss:.4f} (saved)")
        else:
            epochs_no_improve += 1

        if epochs_no_improve >= EARLY_STOPPING_PATIENCE:
            print(f"\n  Early stopping at global epoch {global_epoch}. "
                  f"Best val loss: {best_val_loss:.4f}")
            stop_training = True
            break

# ==========================================
# 7. Save training history + curves
# ==========================================
hist_df = pd.DataFrame(history)
hist_df.to_csv(os.path.join(BASE_RESULTS_DIR, "rotating_training_metrics.csv"), index=False)

plt.figure(figsize=(12, 5))
plt.plot(hist_df["global_epoch"], hist_df["train_loss"], label="Train Loss", color="blue", marker="o", ms=3)
plt.plot(hist_df["global_epoch"], hist_df["val_loss"], label="Val Loss (current fold)", color="red", marker="o", ms=3)

colors = ["#f0f0ff", "#fff0f0", "#f0fff0"]
for f in range(1, K_FOLDS + 1):
    sub = hist_df[hist_df["fold"] == f]
    if len(sub):
        plt.axvspan(sub["global_epoch"].min() - 0.5, sub["global_epoch"].max() + 0.5,
                    color=colors[(f - 1) % len(colors)], alpha=0.5, zorder=0)
        plt.axvline(sub["global_epoch"].min() - 0.5, color="gray", lw=1, ls="--")
        plt.text(sub["global_epoch"].min(), plt.ylim()[1] * 0.97,
                 f" fold {f}", color="gray", fontsize=9, va="top")

plt.xlabel("Global Epoch")
plt.ylabel("Loss")
plt.title("Single Model — Rotating Fold Training (Loss)")
plt.legend()
plt.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig(os.path.join(BASE_RESULTS_DIR, "rotating_loss_curve.png"), dpi=200)
plt.close()

plt.figure(figsize=(12, 5))
plt.plot(hist_df["global_epoch"], hist_df["train_acc"], label="Train Acc", color="blue", marker="o", ms=3)
plt.plot(hist_df["global_epoch"], hist_df["val_acc"], label="Val Acc (current fold)", color="red", marker="o", ms=3)
for f in range(1, K_FOLDS + 1):
    sub = hist_df[hist_df["fold"] == f]
    if len(sub):
        plt.axvspan(sub["global_epoch"].min() - 0.5, sub["global_epoch"].max() + 0.5,
                    color=colors[(f - 1) % len(colors)], alpha=0.5, zorder=0)
        plt.axvline(sub["global_epoch"].min() - 0.5, color="gray", lw=1, ls="--")
plt.xlabel("Global Epoch")
plt.ylabel("Accuracy")
plt.title("Single Model — Rotating Fold Training (Accuracy)")
plt.legend()
plt.grid(True, alpha=0.3)
plt.tight_layout()
plt.savefig(os.path.join(BASE_RESULTS_DIR, "rotating_accuracy_curve.png"), dpi=200)
plt.close()

# ==========================================
# 8. Evaluate the single best model on the unseen test set
# ==========================================
print(f"\n{'=' * 60}\nPHASE 2: TESTING BEST SINGLE MODEL ON UNSEEN TEST SET\n{'=' * 60}")

model.load_state_dict(torch.load(best_model_path, map_location=device, weights_only=False))
model.eval()

test_probs = []
ground_truth_test_targets = []

with torch.no_grad():
    for inputs_b, labels_b in test_loader:
        inputs_b = inputs_b.to(device, non_blocking=True)
        outputs = model(inputs_b)
        probs = torch.softmax(outputs, dim=1).cpu().numpy()
        test_probs.extend(probs)
        ground_truth_test_targets.extend(labels_b.numpy())

test_probs = np.array(test_probs)
ground_truth_test_targets = np.array(ground_truth_test_targets)
Y_test_bin = label_binarize(ground_truth_test_targets, classes=range(NUM_CLASSES))

final_preds = np.argmax(test_probs, axis=1)

acc = accuracy_score(ground_truth_test_targets, final_preds)
macro_auc = roc_auc_score(ground_truth_test_targets, test_probs,
                          multi_class="ovr", average="macro")

print(f"Test Accuracy : {acc:.4f} ({acc * 100:.2f}%)")
print(f"Test Macro AUC: {macro_auc:.4f}")
print("\nClassification Report:")
report = classification_report(ground_truth_test_targets, final_preds, target_names=class_names)
print(report)

with open(os.path.join(BASE_RESULTS_DIR, "rotating_classification_report.txt"), "w") as f:
    f.write(f"Test Accuracy: {acc:.4f}\nTest Macro AUC: {macro_auc:.4f}\n\n")
    f.write(report)

cm = confusion_matrix(ground_truth_test_targets, final_preds)
np.savetxt(os.path.join(BASE_RESULTS_DIR, "rotating_confusion_matrix.csv"), cm, delimiter=",", fmt="%d")

fig, ax = plt.subplots(figsize=(8, 6))
ConfusionMatrixDisplay(confusion_matrix=cm, display_labels=class_names).plot(
    cmap=plt.cm.Blues, ax=ax, values_format="d")
plt.title("Rotating-Fold Single Model — Test Confusion Matrix")
plt.savefig(os.path.join(BASE_RESULTS_DIR, "rotating_confusion_matrix_plot.png"), dpi=200)
plt.close()

plt.figure(figsize=(8, 6))
for i in range(NUM_CLASSES):
    fpr, tpr, _ = roc_curve(Y_test_bin[:, i], test_probs[:, i])
    roc_auc_i = auc(fpr, tpr)
    plt.plot(fpr, tpr, lw=2, label=f"{class_names[i]} (AUC = {roc_auc_i:.3f})")
plt.plot([0, 1], [0, 1], "k--", lw=2)
plt.xlim([0, 1]); plt.ylim([0, 1.05])
plt.xlabel("False Positive Rate"); plt.ylabel("True Positive Rate")
plt.title("Rotating-Fold Single Model — ROC Curve")
plt.legend(loc="lower right"); plt.grid(True)
plt.savefig(os.path.join(BASE_RESULTS_DIR, "rotating_roc_curve.png"), dpi=200)
plt.close()

plt.figure(figsize=(8, 6))
for i in range(NUM_CLASSES):
    precision, recall, _ = precision_recall_curve(Y_test_bin[:, i], test_probs[:, i])
    ap = average_precision_score(Y_test_bin[:, i], test_probs[:, i])
    plt.plot(recall, precision, lw=2, label=f"{class_names[i]} (AP = {ap:.3f})")
plt.xlim([0, 1]); plt.ylim([0, 1.05])
plt.xlabel("Recall"); plt.ylabel("Precision")
plt.title("Rotating-Fold Single Model — Precision-Recall Curve")
plt.legend(loc="lower left"); plt.grid(True)
plt.savefig(os.path.join(BASE_RESULTS_DIR, "rotating_pr_curve.png"), dpi=200)
plt.close()

print(f"\nAll done. Results saved to {BASE_RESULTS_DIR}")
