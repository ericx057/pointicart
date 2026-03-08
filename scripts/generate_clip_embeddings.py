#!/usr/bin/env python3
"""
Generate CLIP text embeddings for Pointicart product names.

Usage:
    pip install torch transformers
    python generate_clip_embeddings.py

This creates clip_text_embeddings.json which you should add to your Xcode project.
"""

import json
import torch
from transformers import CLIPProcessor, CLIPModel

# Product names to encode (lowercase, must match your store catalog)
PRODUCT_NAMES = [
    "jacket",
    "t-shirt",
    "hoodie",
    "sweater",
    "pants",
    "dress",
    "sneakers",
    "scarf",
    "cap",
    "beanie",
    "gloves",
    "belt",
    "clutch",
    "premium laces",
    "sunglasses",
    "watch",
    "handbag",
    "socks",
    "tank top",
]

def main():
    print("Loading CLIP model...")
    # Use the same CLIP variant as your CoreML model
    # For MobileCLIP, use "apple/mobileclip-s2" if available, otherwise standard CLIP
    model_name = "openai/clip-vit-base-patch32"

    model = CLIPModel.from_pretrained(model_name)
    processor = CLIPProcessor.from_pretrained(model_name)

    print(f"Encoding {len(PRODUCT_NAMES)} product names...")

    embeddings = {}

    for name in PRODUCT_NAMES:
        # CLIP text prompts work better with context
        prompt = f"a photo of a {name}"

        inputs = processor(text=[prompt], return_tensors="pt", padding=True)

        with torch.no_grad():
            text_features = model.get_text_features(**inputs)
            # Normalize to unit vector
            text_features = text_features / text_features.norm(dim=-1, keepdim=True)

        # Convert to Python list
        embedding = text_features[0].tolist()
        embeddings[name] = embedding
        print(f"  {name}: {len(embedding)} dims")

    # Save to JSON
    output_path = "clip_text_embeddings.json"
    with open(output_path, "w") as f:
        json.dump(embeddings, f, indent=2)

    print(f"\nSaved embeddings to {output_path}")
    print("Copy this file to your Xcode project's Resources folder.")

if __name__ == "__main__":
    main()
