# Served model files

The server loads these at start-up. `GET /health` reports `"model": "loaded"` when they are in place and `"stub"` when it falls back to the clearly labelled stub predictor.

| File | What it is | Size | SHA-256 |
|:--|:--|--:|:--|
| `model.pt` | Four-class EfficientNetV2-S (`single_rotating_best`, 2026-11-23), weights only, trained as described in [`ml/`](../../ml/) | 81.6 MB | `0ac789b31ff63737275a72f81e32a0b221819eaefa4a68f70a99c78b3ace090e` |
| `model_config.yaml` | Preprocessing, class order (AD, LMCI, EMCI, CN) and architecture for `model.pt` | 1 KB | |
| `brain_detector.keras` | Binary EfficientNetV2-S brain-slice detector used by `FilterScans.py` and by full-volume uploads; run with Keras on the PyTorch backend | 93.8 MB | `df5dafd222ea023f8e662e260b641b4d1f93650952c95af8578f134116695470` |
| `model_config.example.yaml` | Annotated template for a different model | 1 KB | |

The model was trained on ADNI data. It is provided for academic review of this project only.
