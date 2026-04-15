import asyncio
from fastapi import APIRouter, Depends
from auth import get_current_user
import wireguard as wg

router = APIRouter(prefix="/api/server", tags=["server"])


@router.get("/status")
async def server_status(user: dict = Depends(get_current_user)):
    return await asyncio.to_thread(wg.get_server_status)
