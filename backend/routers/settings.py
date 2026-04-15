import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from auth import get_current_user, require_role
from config import settings, save_panel_setting
import audit

logger = logging.getLogger("seccion9")
router = APIRouter(prefix="/api/settings", tags=["settings"])


class UpdateSettingsReq(BaseModel):
    dns_servers: str | None = None


def _ip(r: Request) -> str:
    return r.headers.get("X-Real-IP") or r.client.host


def _validate_dns(dns: str):
    for part in dns.split(","):
        part = part.strip()
        octets = part.split(".")
        if len(octets) != 4 or not all(s.isdigit() and 0 <= int(s) <= 255 for s in octets):
            raise HTTPException(status_code=400, detail=f"Invalid DNS IP: '{part}'")


@router.get("")
async def get_settings(user: dict = Depends(get_current_user)):
    return {"dns_servers": settings.get_dns()}


@router.put("")
async def update_settings(request: Request, req: UpdateSettingsReq, user: dict = Depends(require_role("admin"))):
    if req.dns_servers is not None:
        dns = req.dns_servers.strip()
        _validate_dns(dns)
        save_panel_setting("dns_servers", dns)
        audit.log_action(user["username"], user["role"], "update_settings", "dns", f"dns={dns}", _ip(request))
    return {"dns_servers": settings.get_dns()}
