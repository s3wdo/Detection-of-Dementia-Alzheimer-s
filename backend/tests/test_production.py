"""Settings that only apply when the server is on the public internet."""
import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError

import app.main as main
from app.core.config import Settings, get_settings
from app.ml.predictor import StubPredictor


@pytest.mark.parametrize("secret", ["CHANGE-ME", "too-short", "CHANGE-ME" + "x" * 40])
def test_production_refuses_a_weak_signing_secret(secret):
    with pytest.raises(ValidationError):
        Settings(app_env="production", jwt_secret=secret, database_url="postgresql+psycopg://x")


def test_production_accepts_a_strong_signing_secret_and_development_stays_relaxed():
    Settings(app_env="production", jwt_secret="s" * 48, database_url="postgresql+psycopg://x")
    Settings(app_env="development", jwt_secret="CHANGE-ME", database_url="postgresql+psycopg://x")


def _client(monkeypatch, env):
    settings = get_settings().model_copy(update={"app_env": env})
    monkeypatch.setattr(main, "get_settings", lambda: settings)
    return TestClient(main.create_app(predictor=StubPredictor(), start_worker=False))


def test_the_api_documentation_is_off_in_production(monkeypatch):
    with _client(monkeypatch, "production") as client:
        for path in ("/docs", "/redoc", "/openapi.json"):
            assert client.get(path).status_code == 404, path
        assert client.get("/health").status_code == 200


def test_the_api_documentation_stays_on_in_development(monkeypatch):
    with _client(monkeypatch, "development") as client:
        assert client.get("/docs").status_code == 200
