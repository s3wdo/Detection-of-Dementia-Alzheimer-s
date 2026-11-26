# Junior Phase notebooks

These Google Colab notebooks are from the Junior Phase (Spring 2026), when the team compared ImageNet-pretrained Keras backbones on public four-stage dementia datasets before moving to ADNI in the Senior Phase.

| Notebook | Dataset | Backbones | Setup |
|:--|:--|:--|:--|
| `01_oasis_backbone_screening.ipynb` | OASIS MRI slices (Mild, Moderate, Non and Very Mild Dementia) | ResNet50, ResNet101V2, MobileNetV2, MobileNetV3Small, EfficientNetB0, EfficientNetB4, Xception, InceptionV3 | up to 10 epochs |
| `02_augmented_dataset_comparison.ipynb` | Augmented Alzheimer MRI Dataset (Kaggle), same four stages | ResNet50V2, EfficientNetV2S, EfficientNetB0, EfficientNetV2B1, MobileNetV2, MobileNetV3Small, MobileNetV3Large, Xception, InceptionV3 | up to 15 epochs, seed 42 |

Both notebooks fine-tune every layer of each backbone with a new four-class head, using a random 80/20 image split, Adam at 1e-4 and early stopping with a patience of 3. They report accuracy, precision, recall, F1, ROC AUC and average precision with confusion matrices and curves for every backbone.

These splits are made per image, not per person, so slices of one subject can appear in both training and test data. This kind of split can inflate accuracy, which is why the Senior Phase rebuilt the evaluation with a subject-level split on ADNI (see [`../ml/`](../ml/)).

To run them, open each notebook in Colab and upload the dataset archive to the path set in its first cell.
