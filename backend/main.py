"""
SECCION9 LITE API -- v5.1 (Stateless, WireGuard only)
No React. No OpenVPN. No SQLite. Pure lightweight.
"""

import os
import logging
from contextlib import asynccontextmanager
from logging.handlers import RotatingFileHandler

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import settings
import invites_logic as inv
import audit
import metrics

from routers import auth, users, clients
from routers import invites as invites_router
from routers import metrics as metrics_router
from routers import server, settings as settings_router
from routers import pymes as pymes_router

os.makedirs("/var/log/seccion9", exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        RotatingFileHandler("/var/log/seccion9/api.log", maxBytes=5*1024*1024, backupCount=3),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger("seccion9")


@asynccontextmanager
async def lifespan(app: FastAPI):
    inv.cleanup_expired()
    audit.init_db()
    metrics.start_polling()
    logger.info(f"SECCION9 LITE v5.1 started on {settings.api_host}:{settings.api_port}")
    yield
    logger.info("SECCION9 LITE shut down")


app = FastAPI(title="SECCION9 LITE API", version="5.1.0", docs_url="/api/docs", redoc_url=None, lifespan=lifespan)

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(clients.router)
app.include_router(invites_router.router)
app.include_router(metrics_router.router)
app.include_router(server.router)
app.include_router(settings_router.router)
app.include_router(pymes_router.router)


@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "seccion9-lite", "version": "5.1.0"}


@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception):
    logger.error(f"Unhandled error on {request.url.path}: {exc}")
    return JSONResponse(status_code=500, content={"detail": "Internal server error"})


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=settings.api_host, port=settings.api_port, log_level="info")
