"""Settings read from environment variables (see .env.example)."""
from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # protected_namespaces=() lets us name settings model_path / model_config_path.
    model_config = SettingsConfigDict(env_file=".env", extra="ignore", protected_namespaces=())

    app_env: str = "development"
    database_url: str

    jwt_secret: str
    access_token_minutes: int = 15
    refresh_token_days: int = 14

    seed_password: str = ""

    max_image_side: int = 256
    max_image_bytes: int = 1_048_576
    max_body_bytes: int = 2_097_152

    # Workflow routing only; not evidence of clinical reliability.
    confidence_gate: float = 0.80

    image_retention_days: int = 30

    model_path: str = "models/model.pt"
    model_config_path: str = "models/model_config.yaml"
    allow_pickled_model: bool = False

    # Full scans (.nii / .nii.gz), uploaded by doctors. See app/ml/volume.py.
    brain_filter_path: str = "models/brain_detector.keras"
    brain_filter_threshold: float = 0.4  # FilterScans.py: keep slices scoring below this
    volume_prune_last: int = 15  # top-of-head slices dropped, as in the dataset script
    volume_min_slices: int = 10
    max_volume_bytes: int = 67_108_864  # 64 MB as uploaded
    max_volume_unpacked_bytes: int = 268_435_456  # 256 MB after .gz decompression

    # Analysis worker
    max_analysis_attempts: int = 3
    worker_poll_seconds: float = 2.0
    start_worker: bool = True

    # Login attempts allowed per email per minute.
    login_attempts_per_minute: int = 5

    @model_validator(mode="after")
    def _strong_secret_in_production(self) -> "Settings":
        # A guessable secret would let anyone forge sign-in tokens.
        if self.app_env == "production" and (len(self.jwt_secret) < 32 or "CHANGE-ME" in self.jwt_secret):
            raise ValueError("In production JWT_SECRET must be a random value of at least 32 characters")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
