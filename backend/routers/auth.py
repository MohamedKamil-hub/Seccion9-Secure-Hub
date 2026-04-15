import logging
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from pydantic import BaseModel
from auth import authenticate_user, create_access_token, get_current_user, check_brute_force, record_failed_attempt, record_success, update_password
import audit

logger = logging.getLogger("seccion9")
router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


def _ip(r: Request) -> str:
    return r.headers.get("X-Real-IP") or r.client.host


@router.post("/login", response_model=LoginResponse)
async def login(request: Request, form_data: OAuth2PasswordRequestForm = Depends()):
    ip = _ip(request)
    check_brute_force(ip)
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        record_failed_attempt(ip)
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Bad credentials")
    record_success(ip)
    token = create_access_token(data={"sub": user["username"], "role": user["role"]})
    audit.log_action(user["username"], user["role"], "login", "", "", ip)
    return LoginResponse(access_token=token)


@router.post("/change-password")
async def change_password(request: Request, req: ChangePasswordRequest, user: dict = Depends(get_current_user)):
    if not authenticate_user(user["username"], req.current_password):
        raise HTTPException(status_code=400, detail="Wrong current password")
    if len(req.new_password) < 8:
        raise HTTPException(status_code=400, detail="Min 8 characters")
    update_password(user["username"], req.new_password)
    audit.log_action(user["username"], user["role"], "change_password", user["username"], "", _ip(request))
    return {"message": "Password updated"}


@router.get("/me")
async def get_me(user: dict = Depends(get_current_user)):
    return {"username": user["username"], "role": user["role"]}
