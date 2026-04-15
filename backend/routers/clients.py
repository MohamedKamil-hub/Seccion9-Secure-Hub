import io
import base64
import logging
import asyncio
from dataclasses import asdict

import qrcode
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from auth import get_current_user
import wireguard as wg
import audit

logger = logging.getLogger("seccion9")
router = APIRouter(tags=["clients"])


class AddClientReq(BaseModel):
    name: str


def _ip(r: Request) -> str:
    return r.headers.get("X-Real-IP") or r.client.host


def _make_qr(config: str, box_size: int = 8, border: int = 3):
    qr = qrcode.QRCode(version=1, box_size=box_size, border=border)
    qr.add_data(config)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return buf


@router.get("/api/clients")
async def list_clients(user: dict = Depends(get_current_user)):
    clients = await asyncio.to_thread(wg.list_clients)
    return [asdict(c) for c in clients]


@router.post("/api/clients", status_code=201)
async def add_client(request: Request, req: AddClientReq, user: dict = Depends(get_current_user)):
    try:
        result = await asyncio.to_thread(wg.add_client, req.name)
        audit.log_action(user["username"], user["role"], "add_client", req.name, "", _ip(request))
        return result
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.delete("/api/clients/{name}")
async def remove_client(request: Request, name: str, user: dict = Depends(get_current_user)):
    try:
        await asyncio.to_thread(wg.remove_client, name)
        audit.log_action(user["username"], user["role"], "delete_client", name, "", _ip(request))
        return {"message": f"Client '{name}' deleted"}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.get("/api/clients/{name}/config")
async def get_config(name: str, user: dict = Depends(get_current_user)):
    config = await asyncio.to_thread(wg.get_client_config, name)
    if not config:
        raise HTTPException(status_code=404, detail=f"Config not found for '{name}'")
    return {"name": name, "config": config}


@router.get("/api/clients/{name}/qr")
async def get_qr(name: str, user: dict = Depends(get_current_user)):
    config = await asyncio.to_thread(wg.get_client_config, name)
    if not config:
        raise HTTPException(status_code=404, detail=f"Config not found for '{name}'")
    return StreamingResponse(_make_qr(config, 10, 4), media_type="image/png")


@router.get("/api/clients/{name}/qr-base64")
async def get_qr_b64(name: str, user: dict = Depends(get_current_user)):
    config = await asyncio.to_thread(wg.get_client_config, name)
    if not config:
        raise HTTPException(status_code=404, detail=f"Config not found for '{name}'")
    buf = _make_qr(config)
    b64 = base64.b64encode(buf.read()).decode()
    return {"name": name, "qr_base64": f"data:image/png;base64,{b64}"}
