from fastapi import APIRouter, Depends
from auth import get_current_user
import metrics

router = APIRouter(prefix="/api/metrics", tags=["metrics"])


@router.get("/summary")
async def summary(hours: int = 24, user: dict = Depends(get_current_user)):
    return metrics.get_summary(hours)


@router.get("/connections")
async def connections(hours: int = 24, client: str = None, user: dict = Depends(get_current_user)):
    return metrics.get_connection_log(hours, client)


@router.get("/traffic")
async def traffic(hours: int = 24, user: dict = Depends(get_current_user)):
    return metrics.get_traffic_hourly(hours)


@router.get("/clients")
async def by_client(hours: int = 24, user: dict = Depends(get_current_user)):
    return metrics.get_traffic_by_client(hours)
