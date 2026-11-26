"""Grad-CAM for the predicted class, following the team's Grad-CAM script:
target layer `model.features[-1]`, channel weights = mean gradient, ReLU,
scaled so the strongest value is 1, resized to the input size.

The map shows which image regions most raised the model's score for its
predicted class. It is not a measurement of damage or disease.
"""
import cv2
import numpy as np
import torch


def grad_cam(module: torch.nn.Module, input_tensor: torch.Tensor, class_idx: int) -> np.ndarray:
    """Returns an array of the input's height x width with values 0..1."""
    target_layer = module.features[-1]
    store: dict[str, torch.Tensor] = {}

    def save_activations(_module, _input, output):
        store["activations"] = output.detach()

    def save_gradients(_module, _grad_input, grad_output):
        store["gradients"] = grad_output[0].detach()

    # Hooks only for this call, so ordinary predictions run without them.
    handles = [
        target_layer.register_forward_hook(save_activations),
        target_layer.register_full_backward_hook(save_gradients),
    ]
    try:
        module.zero_grad()
        with torch.enable_grad():
            x = input_tensor.clone().detach().requires_grad_(True)
            output = module(x)
            output[0, class_idx].backward()
    finally:
        for handle in handles:
            handle.remove()
        module.zero_grad(set_to_none=True)

    weights = torch.mean(store["gradients"], dim=[2, 3], keepdim=True)
    cam = torch.relu(torch.sum(weights * store["activations"], dim=1, keepdim=True))
    cam = cam.squeeze().cpu().numpy()
    cam = cam / cam.max() if cam.max() > 0 else np.zeros_like(cam)
    height, width = input_tensor.shape[-2:]
    return cv2.resize(cam, (width, height))


def heatmap_png(cam: np.ndarray) -> bytes:
    """The map as an 8-bit grayscale PNG (0 = no contribution, 255 = strongest)."""
    ok, encoded = cv2.imencode(".png", np.uint8(255 * np.clip(cam, 0, 1)))
    if not ok:
        raise ValueError("could not encode the heatmap")
    return encoded.tobytes()


def colour_heatmap_png(gray_png: bytes) -> bytes:
    """The stored grayscale map with the JET colour scale, as in the team's script."""
    gray = cv2.imdecode(np.frombuffer(gray_png, np.uint8), cv2.IMREAD_GRAYSCALE)
    ok, encoded = cv2.imencode(".png", cv2.applyColorMap(gray, cv2.COLORMAP_JET))
    if not ok:
        raise ValueError("could not encode the heatmap")
    return encoded.tobytes()
