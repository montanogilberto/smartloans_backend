from fastapi import APIRouter
from modules.rewardBenefits import (
    reward_benefits_all_sp, reward_benefit_reserve_sp,
    reward_benefit_bind_sp, reward_benefits_for_client_sp,
)

router = APIRouter()


@router.post(
    "/all_rewardBenefits",
    summary="Beneficios de prestamo canjeables con puntos",
    description="""
Los PUNTOS se ganan por conducta (pagar a tiempo, expediente, referidos), no
por azar, y por eso pueden valer. Las fichas del arcade no se canjean nunca ni
se convierten en puntos.

Body: { "rewardBenefits": [{ "companyId": int, "clientId": int }] }
Returns: { "rewardBenefits": [{ benefitKey, name, benefitType, value,
           pointsCost, affordable }] }
""",
)
def all_reward_benefits(json: dict):
    return reward_benefits_all_sp(json)


@router.post(
    "/rewardBenefits/reserve",
    summary="Canjear puntos por un beneficio",
    description="""
Descuenta los puntos y aparta el beneficio para el proximo prestamo, en una
sola transaccion. Solo puede haber UN beneficio apartado sin prestamo por
cliente.

Body: { "rewardBenefits": [{ companyId, clientId, benefitKey }] }
Returns: { status: "reserved", benefitKey, benefitType, value, pointsSpent, balance }

409 insufficient_points / benefit_already_reserved   400 unknown_benefit
""",
)
def reserve_reward_benefit(json: dict):
    return reward_benefit_reserve_sp(json)


@router.post(
    "/rewardBenefits/bind",
    summary="Amarrar el beneficio apartado a un prestamo",
    description="""
Se llama al crear el prestamo. Si el cliente no tenia nada apartado responde
status 'none', que no es error.

Body: { "rewardBenefits": [{ companyId, clientId, loanId }] }
""",
)
def bind_reward_benefit(json: dict):
    return reward_benefit_bind_sp(json)


@router.post(
    "/one_rewardBenefit",
    summary="Beneficios apartados o aplicados del cliente",
    description="""
Body: { "rewardBenefits": [{ companyId, clientId, loanId?: int }] }
Returns: { "loanRewardBenefits": [...] }
""",
)
def one_reward_benefit(json: dict):
    return reward_benefits_for_client_sp(json)
