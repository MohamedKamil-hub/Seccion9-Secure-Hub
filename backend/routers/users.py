import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from auth import get_current_user, require_role, list_users, create_user, delete_user, update_user_role, reset_user_password, ROLES
import audit

logger = logging.getLogger("seccion9")
router = APIRouter(tags=["users"])


class CreateUserReq(BaseModel):
    username: str
    password: str
    role: str = "viewer"

class UpdateRoleReq(BaseModel):
    role: str

class ResetPassReq(BaseModel):
    new_password: str


def _ip(r: Request) -> str:
    return r.headers.get("X-Real-IP") or r.client.host


@router.get("/api/users")
async def api_list_users(user: dict = Depends(require_role("admin"))):
    return list_users()


@router.post("/api/users", status_code=201)
async def api_create_user(request: Request, req: CreateUserReq, user: dict = Depends(require_role("admin"))):
    try:
        new = create_user(req.username, req.password, req.role, user["username"])
        audit.log_action(user["username"], user["role"], "create_user", req.username, f"role={req.role}", _ip(request))
        return new
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.delete("/api/users/{username}")
async def api_delete_user(request: Request, username: str, user: dict = Depends(require_role("admin"))):
    try:
        delete_user(username, user["username"])
        audit.log_action(user["username"], user["role"], "delete_user", username, "", _ip(request))
        return {"message": f"User '{username}' deleted"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.put("/api/users/{username}/role")
async def api_update_role(request: Request, username: str, req: UpdateRoleReq, user: dict = Depends(require_role("admin"))):
    try:
        update_user_role(username, req.role, user["username"])
        audit.log_action(user["username"], user["role"], "change_role", username, f"new_role={req.role}", _ip(request))
        return {"message": f"Role updated to '{req.role}'"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.post("/api/users/{username}/reset-password")
async def api_reset_password(request: Request, username: str, req: ResetPassReq, user: dict = Depends(require_role("admin"))):
    try:
        reset_user_password(username, req.new_password, user["username"])
        audit.log_action(user["username"], user["role"], "reset_password", username, "", _ip(request))
        return {"message": "Password reset"}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/api/roles")
async def api_list_roles(user: dict = Depends(get_current_user)):
    return ROLES


@router.get("/api/audit")
async def api_audit_log(hours: int = 24, username: str | None = None, action: str | None = None, user: dict = Depends(require_role("admin", "tecnico"))):
    return audit.get_log(hours, username, action)
