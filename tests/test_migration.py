import brownie
import pytest
from brownie import CompoundToNotionalV2
from brownie import accounts
from tests.helpers import get_balance_trade_action, execute_proposal
from scripts.environment import setup_env


@pytest.fixture
def env():
    return setup_env()

def test_migrate_comp_to_v2(accounts, CompoundToNotionalV2, env):
    account = accounts[5]
    cETH = env['currencies']['cETH'].get('asset')
    cUSDC = env['currencies']['cUSDC'].get('asset')
    USDC = env['currencies']['cUSDC'].get('underlying')
    notional = env.get('notional')
    comptroller = env.get('comptroller')

    compToV2 = CompoundToNotionalV2.deploy(
        notional.address,
        accounts[0].address,
        cETH.address,
        {"from": accounts[0]},
    )

    input = notional.updateAuthorizedCallbackContract.encode_input(
        compToV2.address, True)
    # execute_proposal
    execute_proposal(env, [notional.address], [0], [input])

    # NOTE: these approvals allow deposit and repayment
    compToV2.enableTokens(
        [cUSDC.address, cETH.address], {"from": accounts[0]}
    )

    comptroller.enterMarkets(
        [cUSDC.address, cETH.address], {"from": account}
    )
    cETH.mint({"from": account, "value": 10e18})
    cUSDC.borrow(100e6, {"from": account})

    # NOTE: these approvals need to be set by the user
    USDC.approve(compToV2.address, 2 ** 255, {"from": account})
    cETH.approve(compToV2.address, 2 ** 255, {"from": account})

    borrowAction = get_balance_trade_action(
        3,
        "None",
        [{"tradeActionType": "Borrow", "marketIndex": 1, "notional": 120e8, "maxSlippage": 0}],
        withdrawEntireCashBalance=True,
        redeemToUnderlying=True,
    )

    assert cETH.balanceOf(account) > 0
    assert cUSDC.borrowBalanceStored(account) > 0

    # Assert that the FC check will fail on insufficient collateral
    with brownie.reverts("Insufficient free collateral"):
        compToV2.migrateBorrowFromCompound(
            cUSDC.address, 0, [1], [100], [borrowAction], {"from": account}
        )

    compToV2.migrateBorrowFromCompound(
        cUSDC.address,
        0,
        [1],
        [cETH.balanceOf(account)],
        [borrowAction],
        {"from": account},
    )


    assert cETH.balanceOf(account) == 0
    assert cUSDC.borrowBalanceStored(account) == 0

    assert notional.getAccountBalance(1, account)[0] > 0
    portfolio = notional.getAccountPortfolio(account)
    assert len(portfolio) == 1
    assert portfolio[0][3] == -120e8

