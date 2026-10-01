from fastapi import APIRouter
from modules.services import services_sp, all_services_sp, one_services_sp


router = APIRouter()

@router.post("/services", summary="services CRUD (expenseType='general' party, e.g. CFE/agua/internet/renta)")
def services(json: dict):
    return services_sp(json)


@router.post("/all_services", summary="all services for a company")
def all_services(json: dict):
    return all_services_sp(json)


@router.post("/one_services", summary="one service")
def one_services(json: dict):
    return one_services_sp(json)
