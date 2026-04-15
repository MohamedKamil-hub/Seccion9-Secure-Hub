import io
import asyncio
import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from auth import get_current_user, require_role
import pymes
import audit

logger = logging.getLogger("seccion9")
router = APIRouter(tags=["pymes"])


class CreatePymeReq(BaseModel):
    name: str
    display_name: str
    lan_subnet: str
    lan_interface: str = "eth0"
    lan_dns: str = "192.168.1.1"
    notes: str = ""


class UpdatePymeReq(BaseModel):
    display_name: str | None = None
    lan_dns: str | None = None
    lan_interface: str | None = None
    notes: str | None = None


class AssignClientReq(BaseModel):
    client_name: str


def _ip(r: Request) -> str:
    return r.headers.get("X-Real-IP") or r.client.host


def _sanitize_pyme(p: dict) -> dict:
    """Remove private_key from API responses."""
    safe = dict(p)
    safe.pop("private_key", None)
    return safe


@router.get("/api/pymes")
async def list_all(user: dict = Depends(get_current_user)):
    result = await asyncio.to_thread(pymes.list_pymes)
    out = []
    for p in result:
        safe = _sanitize_pyme(p)
        status = await asyncio.to_thread(pymes.get_gateway_status, p["name"])
        safe["gateway_status"] = status["status"]
        out.append(safe)
    return out


@router.get("/api/pymes/{name}")
async def get_one(name: str, user: dict = Depends(get_current_user)):
    p = await asyncio.to_thread(pymes.get_pyme, name)
    if not p:
        raise HTTPException(status_code=404, detail=f"PYME '{name}' not found")
    safe = _sanitize_pyme(p)
    safe["gateway_status"] = (await asyncio.to_thread(pymes.get_gateway_status, name))
    return safe


@router.post("/api/pymes", status_code=201)
async def create(request: Request, req: CreatePymeReq, user: dict = Depends(require_role("admin"))):
    try:
        result = await asyncio.to_thread(
            pymes.create_pyme,
            req.name, req.display_name, req.lan_subnet,
            req.lan_interface, req.lan_dns, user["username"], req.notes,
        )
        audit.log_action(user["username"], user["role"], "create_pyme", req.name, f"subnet={req.lan_subnet}", _ip(request))
        return _sanitize_pyme(result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except RuntimeError as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/api/pymes/{name}")
async def update(request: Request, name: str, req: UpdatePymeReq, user: dict = Depends(require_role("admin"))):
    fields = {k: v for k, v in req.model_dump().items() if v is not None}
    if not fields:
        raise HTTPException(status_code=400, detail="No fields to update")
    try:
        result = await asyncio.to_thread(pymes.update_pyme, name, fields)
        audit.log_action(user["username"], user["role"], "update_pyme", name, str(fields), _ip(request))
        return _sanitize_pyme(result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/api/pymes/{name}")
async def delete(request: Request, name: str, user: dict = Depends(require_role("admin"))):
    try:
        await asyncio.to_thread(pymes.delete_pyme, name)
        audit.log_action(user["username"], user["role"], "delete_pyme", name, "", _ip(request))
        return {"message": f"PYME '{name}' deleted"}
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))


# -- Client assignment -----------------------------------------

@router.post("/api/pymes/{name}/clients")
async def assign(request: Request, name: str, req: AssignClientReq, user: dict = Depends(require_role("admin", "tecnico"))):
    try:
        result = await asyncio.to_thread(pymes.assign_client, name, req.client_name)
        audit.log_action(user["username"], user["role"], "assign_client_pyme", req.client_name, f"pyme={name}", _ip(request))
        return _sanitize_pyme(result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/api/pymes/{name}/clients/{client_name}")
async def unassign(request: Request, name: str, client_name: str, user: dict = Depends(require_role("admin", "tecnico"))):
    try:
        result = await asyncio.to_thread(pymes.unassign_client, name, client_name)
        audit.log_action(user["username"], user["role"], "unassign_client_pyme", client_name, f"pyme={name}", _ip(request))
        return _sanitize_pyme(result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


# -- Gateway config --------------------------------------------

@router.get("/api/pymes/{name}/gateway-config")
async def gateway_config(name: str, user: dict = Depends(require_role("admin"))):
    config = await asyncio.to_thread(pymes.generate_gateway_config, name)
    if not config:
        raise HTTPException(status_code=404, detail="PYME not found")
    return {"name": name, "config": config}


@router.get("/api/pymes/{name}/gateway-config/download")
async def gateway_download(name: str, user: dict = Depends(require_role("admin"))):
    config = await asyncio.to_thread(pymes.generate_gateway_config, name)
    if not config:
        raise HTTPException(status_code=404, detail="PYME not found")
    return StreamingResponse(
        iter([config.encode()]),
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="pyme-{name}.conf"'},
    )


@router.get("/api/pymes/{name}/setup-instructions")
async def setup_instructions(name: str, user: dict = Depends(require_role("admin"))):
    """Return setup instructions for the PYME IT team."""
    p = await asyncio.to_thread(pymes.get_pyme, name)
    if not p:
        raise HTTPException(status_code=404, detail="PYME not found")

    instructions = (
        f"# {p['display_name']} -- Gateway Setup Instructions\n\n"
        f"## 1. Install WireGuard on the gateway device\n"
        f"```\napt update && apt install -y wireguard resolvconf\n```\n\n"
        f"## 2. Copy the config file\n"
        f"Copy the provided `pyme-{name}.conf` to `/etc/wireguard/wg0.conf`\n\n"
        f"## 3. Enable IP forwarding\n"
        f"```\necho 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf\nsysctl -p\n```\n\n"
        f"## 4. Start WireGuard\n"
        f"```\nsystemctl enable wg-quick@wg0\nsystemctl start wg-quick@wg0\n```\n\n"
        f"## 5. Add static route on LAN router\n"
        f"On your main router, add:\n"
        f"- Destination: {p['gateway_ip'].rsplit('.', 1)[0]}.0/24\n"
        f"- Gateway: [IP of this device on LAN]\n\n"
        f"## Network Details\n"
        f"- VPN tunnel IP: {p['gateway_ip']}\n"
        f"- LAN subnet: {p['lan_subnet']}\n"
        f"- LAN interface: {p['lan_interface']}\n"
        f"- VPN server: {settings.server_public_ip}:{settings.server_port}\n"
    )

    from config import settings
    return {"name": name, "instructions": instructions}


# -- Client PYME access info ----------------------------------

@router.get("/api/clients/{client_name}/pymes")
async def client_pymes(client_name: str, user: dict = Depends(get_current_user)):
    return await asyncio.to_thread(pymes.get_client_pymes, client_name)
