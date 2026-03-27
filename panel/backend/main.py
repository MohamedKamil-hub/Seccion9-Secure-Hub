"""
SECCION9 — API REST para gestión de VPN WireGuard
"""

import io
import logging
import base64
from dataclasses import asdict

import qrcode
import uvicorn
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from config import settings
from auth import authenticate_user, create_access_token, get_current_user
import wireguard as wg

# Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler("/var/log/seccion9/api.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger("seccion9")

# App
app = FastAPI(
    title="SECCION9 VPN API",
    version="1.0.0",
    docs_url="/api/docs",
    redoc_url=None,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Schemas ──────────────────────────────────────────────────

class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class AddClientRequest(BaseModel):
    name: str


class MessageResponse(BaseModel):
    message: str


# ── Auth ─────────────────────────────────────────────────────

@app.post("/api/auth/login", response_model=LoginResponse)
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    if not authenticate_user(form_data.username, form_data.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Usuario o contraseña incorrectos",
        )
    token = create_access_token(data={"sub": form_data.username})
    logger.info(f"Login exitoso: {form_data.username}")
    return LoginResponse(access_token=token)


# ── Clients ──────────────────────────────────────────────────

@app.get("/api/clients")
async def list_clients(user: str = Depends(get_current_user)):
    clients = wg.list_clients()
    return [asdict(c) for c in clients]


@app.post("/api/clients", status_code=201)
async def add_client(
    req: AddClientRequest, user: str = Depends(get_current_user)
):
    try:
        result = wg.add_client(req.name)
        logger.info(f"Cliente añadido vía API: {req.name} por {user}")
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/api/clients/{name}")
async def remove_client(name: str, user: str = Depends(get_current_user)):
    try:
        wg.remove_client(name)
        logger.info(f"Cliente eliminado vía API: {name} por {user}")
        return {"message": f"Cliente '{name}' eliminado"}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@app.get("/api/clients/{name}/config")
async def get_client_config(name: str, user: str = Depends(get_current_user)):
    config = wg.get_client_config(name)
    if not config:
        raise HTTPException(
            status_code=404,
            detail=f"No se encontró config para '{name}'",
        )
    return {"name": name, "config": config}


@app.get("/api/clients/{name}/qr")
async def get_client_qr(name: str, user: str = Depends(get_current_user)):
    config = wg.get_client_config(name)
    if not config:
        raise HTTPException(
            status_code=404,
            detail=f"No se encontró config para '{name}'",
        )
    # Generar QR en memoria
    qr = qrcode.QRCode(version=1, box_size=10, border=4)
    qr.add_data(config)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return StreamingResponse(buf, media_type="image/png")


@app.get("/api/clients/{name}/qr-base64")
async def get_client_qr_base64(
    name: str, user: str = Depends(get_current_user)
):
    config = wg.get_client_config(name)
    if not config:
        raise HTTPException(
            status_code=404,
            detail=f"No se encontró config para '{name}'",
        )
    qr = qrcode.QRCode(version=1, box_size=8, border=3)
    qr.add_data(config)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    b64 = base64.b64encode(buf.read()).decode()
    return {"name": name, "qr_base64": f"data:image/png;base64,{b64}"}


# ── Server Status ────────────────────────────────────────────

@app.get("/api/server/status")
async def server_status(user: str = Depends(get_current_user)):
    return wg.get_server_status()


# ── Health ───────────────────────────────────────────────────

@app.get("/api/health")
async def health():
    return {"status": "ok", "service": "seccion9-vpn-api"}


# ── Run ──────────────────────────────────────────────────────

if __name__ == "__main__":
    import os
    os.makedirs("/var/log/seccion9", exist_ok=True)
    uvicorn.run(
        "main:app",
        host=settings.api_host,
        port=settings.api_port,
        log_level="info",
    )
