import io
import base64
import time
import logging
from pathlib import Path

import qrcode
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import HTMLResponse, StreamingResponse
from pydantic import BaseModel

from auth import get_current_user, require_role
from config import settings
import wireguard as wg
import invites_logic as inv
import audit

logger = logging.getLogger("seccion9")
router = APIRouter(tags=["invites"])

TEMPLATES_DIR = Path(__file__).parent.parent / "templates"


class CreateInviteReq(BaseModel):
    client_name: str
    create_client: bool = False
    expire_hours: int = 24


def _ip(r: Request) -> str:
    return r.headers.get("X-Real-IP") or r.client.host


def _qr_b64(data: str) -> str:
    qr = qrcode.QRCode(version=1, box_size=8, border=3)
    qr.add_data(data)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return base64.b64encode(buf.read()).decode()


def _template(name: str, **kw) -> str:
    try:
        return (TEMPLATES_DIR / name).read_text(encoding="utf-8").format_map(kw)
    except FileNotFoundError:
        return f"<h1>Template '{name}' not found</h1>"


def _invite_url(token: str) -> str:
    base = settings.get_invite_base_url()
    return f"{base}/invite/{token}"


@router.post("/api/invites", status_code=201)
async def create_invite(request: Request, req: CreateInviteReq, user: dict = Depends(require_role("admin", "tecnico"))):
    if req.create_client:
        try:
            wg.add_client(req.client_name)
            audit.log_action(user["username"], user["role"], "add_client", req.client_name, "via invite", _ip(request))
        except ValueError as e:
            if "already exists" not in str(e).lower() and "ya existe" not in str(e).lower():
                raise HTTPException(status_code=400, detail=str(e))

    config = wg.get_client_config(req.client_name)
    if not config:
        raise HTTPException(status_code=400, detail=f"No config for '{req.client_name}'. Create client first.")

    try:
        invite = inv.create_invite(req.client_name, user["username"], req.expire_hours)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    invite["url"] = _invite_url(invite["token"])
    audit.log_action(user["username"], user["role"], "create_invite", req.client_name, f"expire={req.expire_hours}h", _ip(request))
    return invite


@router.get("/api/invites")
async def list_invites(user: dict = Depends(get_current_user)):
    invites = inv.list_invites()
    now = time.time()
    result = []
    for i in invites:
        valid, reason = inv.is_valid(i)
        entry = {**i, "valid": valid, "reason": reason, "url": _invite_url(i["token"]), "remaining_hours": round(max(0, i["expires_at"] - now) / 3600, 1)}
        result.append(entry)
    return result


@router.delete("/api/invites/{token}")
async def revoke_invite(request: Request, token: str, user: dict = Depends(require_role("admin", "tecnico"))):
    invite = inv.get_invite(token)
    if not inv.delete_invite(token):
        raise HTTPException(status_code=404, detail="Invite not found")
    target = invite["client_name"] if invite else token[:8]
    audit.log_action(user["username"], user["role"], "revoke_invite", target, "", _ip(request))
    return {"message": "Invite revoked"}





# # Añade al principio del archivo
#import asyncio

# Dentro de async def create_invite(...)  — reemplaza las llamadas síncronas:
 #   if req.create_client:
  #      try:
   #         await asyncio.to_thread(wg.add_client, req.client_name)
    #        audit.log_action(...)
     #   except ValueError as e:
      #      ...

   # config = await asyncio.to_thread(wg.get_client_config, req.client_name)








# ── Public onboard ────────────────────────────────────────────

@router.get("/api/onboard/{token}")
async def onboard_page(token: str):
    invite = inv.get_invite(token)
    if not invite:
        return HTMLResponse(_template("onboard_error.html", title="Invalid link", message="This link does not exist or was revoked."), status_code=404)

    valid, reason = inv.is_valid(invite)
    if not valid:
        msg = "This link has expired." if reason == "expired" else "This link was already used."
        return HTMLResponse(_template("onboard_error.html", title="Link unavailable", message=msg), status_code=410)

    client_name = invite["client_name"]
    config = wg.get_client_config(client_name)
    if not config:
        return HTMLResponse(_template("onboard_error.html", title="Config error", message="VPN config not found. Contact admin."), status_code=500)

    qr_b64 = _qr_b64(config)
    config_escaped = config.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    inv.claim_invite(token)
    return HTMLResponse(_template("onboard_wg.html", client_name=client_name, token=token, config_escaped=config_escaped, qr_b64=qr_b64))


@router.get("/api/onboard/{token}/download")
async def onboard_download(token: str):
    invite = inv.get_invite(token)
    if not invite:
        raise HTTPException(status_code=404, detail="Invite not found")
    config = wg.get_client_config(invite["client_name"])
    if not config:
        raise HTTPException(status_code=500, detail="Config not found")
    return StreamingResponse(
        iter([config.encode()]),
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{invite["client_name"]}.conf"'},
    )
