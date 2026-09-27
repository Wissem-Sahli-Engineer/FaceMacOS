"""Convert FaceNet (InceptionResnetV1, VGGFace2 weights) to Models/FaceEmbedding.mlpackage (~23 MB, 8-bit).

Developer-only, one time. End users get the compiled model inside the app.
    python3.12 -m venv .venv && source .venv/bin/activate
    pip install torch torchvision coremltools requests tqdm pillow "numpy<2.3"
    pip install --no-deps facenet-pytorch
    python scripts/convert_facenet.py
"""
from pathlib import Path

import coremltools as ct
import coremltools.optimize.coreml as cto
import torch
from facenet_pytorch import InceptionResnetV1

OUTPUT = Path(__file__).resolve().parent.parent / "Models" / "FaceEmbedding.mlpackage"

# Output is already L2-normalized, 512-d.
model = InceptionResnetV1(pretrained="vggface2").eval()
example = torch.rand(1, 3, 160, 160)
traced = torch.jit.trace(model, example)

# facenet-pytorch expects (pixel - 127.5) / 128.
mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(name="image", shape=example.shape, scale=1 / 128.0,
                         bias=[-127.5 / 128.0] * 3, color_layout=ct.colorlayout.RGB)],
    outputs=[ct.TensorType(name="embedding")],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.macOS13,
)

# 8-bit weights: ~4x smaller with negligible embedding change.
config = cto.OptimizationConfig(global_config=cto.OpLinearQuantizerConfig(mode="linear_symmetric"))
mlmodel = cto.linear_quantize_weights(mlmodel, config=config)

mlmodel.short_description = "FaceNet InceptionResnetV1 (VGGFace2) 512-d face embedding, 8-bit weights"
mlmodel.version = "vggface2-int8-1"
OUTPUT.parent.mkdir(exist_ok=True)
mlmodel.save(str(OUTPUT))
print(f"Saved {OUTPUT}")
