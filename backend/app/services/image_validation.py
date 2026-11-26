"""Checks an uploaded image and normalises it to PNG. The client is never trusted."""
import base64
import binascii
import hashlib
import io
from dataclasses import dataclass

from PIL import Image, UnidentifiedImageError

from app.core.config import Settings
from app.core.errors import ApiError, invalid

# Refuse to decode anything far larger than the allowed size (decompression bombs).
Image.MAX_IMAGE_PIXELS = 4_000_000

_ALLOWED_FORMATS = {"PNG", "JPEG"}


@dataclass(frozen=True)
class ValidImage:
    png: bytes
    width: int
    height: int
    sha256: str  # of the bytes the client sent, used to recognise a repeated upload


def validate_image(image_base64: str, settings: Settings) -> ValidImage:
    try:
        raw = base64.b64decode(image_base64, validate=True)
    except (binascii.Error, ValueError):
        raise invalid("The image is not valid base64.", "IMAGE_INVALID_BASE64")
    if not raw:
        raise invalid("The image is empty.", "IMAGE_EMPTY")
    if len(raw) > settings.max_image_bytes:
        raise ApiError(413, "IMAGE_TOO_LARGE", "The image file is too large.")

    try:
        with Image.open(io.BytesIO(raw)) as probe:
            # The real format, from the file's content. The filename is ignored.
            if probe.format not in _ALLOWED_FORMATS:
                raise invalid("Only PNG and JPEG images are supported.", "IMAGE_UNSUPPORTED_FORMAT")
            if getattr(probe, "n_frames", 1) != 1:
                raise invalid("Animated or multi-frame images are not supported.", "IMAGE_UNSUPPORTED_FORMAT")
            width, height = probe.size  # read from the header, before decoding pixels
            if width > settings.max_image_side or height > settings.max_image_side:
                raise invalid(
                    f"The image must be at most {settings.max_image_side} × {settings.max_image_side} pixels.",
                    "IMAGE_DIMENSIONS_TOO_LARGE",
                )
            if width < 16 or height < 16:
                raise invalid("The image is too small.", "IMAGE_DIMENSIONS_TOO_SMALL")
            probe.verify()
        # verify() leaves the image unusable, so decode again for real.
        with Image.open(io.BytesIO(raw)) as decoded:
            decoded.load()
            clean = decoded.convert("RGB")
    except ApiError:
        raise
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError):
        raise invalid("The image could not be read.", "IMAGE_UNREADABLE")

    # Re-encode: drops metadata (EXIF, text chunks) and anything appended to the file.
    out = io.BytesIO()
    clean.save(out, format="PNG")
    return ValidImage(png=out.getvalue(), width=width, height=height, sha256=hashlib.sha256(raw).hexdigest())
