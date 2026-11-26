"""One error shape for the whole API: {"error": {"code": "...", "message": "..."}}."""
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


def not_found(message: str = "This item was not found.") -> ApiError:
    # Also used for "exists but is not yours", so IDs cannot be probed.
    return ApiError(404, "NOT_FOUND", message)


def conflict(message: str) -> ApiError:
    return ApiError(409, "CONFLICT", message)


def invalid(message: str, code: str = "VALIDATION_ERROR") -> ApiError:
    return ApiError(422, code, message)


def _body(code: str, message: str) -> dict:
    return {"error": {"code": code, "message": message}}


_STATUS_CODES = {
    401: "UNAUTHENTICATED",
    403: "FORBIDDEN",
    404: "NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
    413: "PAYLOAD_TOO_LARGE",
    429: "RATE_LIMITED",
}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError):
        return JSONResponse(_body(exc.code, exc.message), status_code=exc.status)

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError):
        # Field names only: the submitted values are never echoed back.
        fields = sorted({".".join(str(p) for p in e["loc"] if p != "body") for e in exc.errors()})
        return JSONResponse(
            _body("VALIDATION_ERROR", "Invalid request: " + ", ".join(f for f in fields if f) + "."),
            status_code=422,
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException):
        code = _STATUS_CODES.get(exc.status_code, f"HTTP_{exc.status_code}")
        message = exc.detail if isinstance(exc.detail, str) else "Request failed."
        return JSONResponse(_body(code, message), status_code=exc.status_code)

    @app.exception_handler(Exception)
    async def _unexpected(_: Request, exc: Exception):
        return JSONResponse(_body("INTERNAL_ERROR", "Something went wrong."), status_code=500)
