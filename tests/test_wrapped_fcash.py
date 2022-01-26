import pytest
import brownie
from tests.helpers import get_balance_trade_action
from brownie import Contract, WrappedfCash
from brownie.network import chain
from scripts.EnvironmentConfig import getEnvironment

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

@pytest.fixture(autouse=True)
def env():
    return getEnvironment()

@pytest.fixture(autouse=True) 
def beacon(WrappedfCash, nUpgradeableBeacon, env):
    impl = WrappedfCash.deploy(env.notional.address, {"from": env.deployer})
    return nUpgradeableBeacon.deploy(impl.address, {"from": env.deployer})

@pytest.fixture(autouse=True) 
def factory(WrappedfCashFactory, beacon, env):
    return WrappedfCashFactory.deploy(beacon.address, {"from": env.deployer})

@pytest.fixture(autouse=True) 
def wrapper(factory, env):
    markets = env.notional.getActiveMarkets(2)
    txn = factory.deployWrapper(2, markets[0][1])
    return Contract.from_abi("Wrapper", txn.events['WrapperDeployed']['wrapper'], WrappedfCash.abi)

@pytest.fixture(autouse=True) 
def lender(wrapper, env):
    env.tokens["DAI"].approve(env.notional.address, 2**255-1, {'from': env.whales["DAI"]})
    env.notional.batchBalanceAndTradeAction(
        env.whales["DAI"],
        [ 
            get_balance_trade_action(
                2,
                "DepositUnderlying",
                [{
                    "tradeActionType": "Lend",
                    "marketIndex": 1,
                    "notional": 100_000e8,
                    "minSlippage": 0
                }],
                depositActionAmount=100_000e18,
                withdrawEntireCashBalance=True,
                redeemToUnderlying=True,
            )
        ], { "from": env.whales["DAI"] }
    )

    return env.whales["DAI"]

# Deploy and Upgrade

def test_deploy_wrapped_fcash(factory, env):
    markets = env.notional.getActiveMarkets(2)
    computedAddress = factory.computeAddress(2, markets[0][1])
    txn = factory.deployWrapper(2, markets[0][1])
    assert txn.events['WrapperDeployed']['wrapper'] == computedAddress

    wrapper = Contract.from_abi("Wrapper", computedAddress, WrappedfCash.abi)
    assert wrapper.getCurrencyId() == 2
    assert wrapper.getMaturity() == markets[0][1]
    assert wrapper.name() == "Wrapped fDAI @ {}".format(markets[0][1])
    assert wrapper.symbol() == "wfDAI:{}".format(markets[0][1])

def test_cannot_deploy_wrapper_twice(factory, env):
    markets = env.notional.getActiveMarkets(2)
    factory.deployWrapper(2, markets[0][1])

    with brownie.reverts():
        factory.deployWrapper(2, markets[0][1])

def test_cannot_deploy_invalid_currency(factory, env):
    markets = env.notional.getActiveMarkets(2)
    with brownie.reverts():
        factory.deployWrapper(99, markets[0][1])

def test_cannot_deploy_invalid_maturity(factory, env):
    markets = env.notional.getActiveMarkets(2)
    with brownie.reverts():
        factory.deployWrapper(2, markets[0][1] + 86400 * 720)

# Test Minting fCash
def test_only_accepts_notional_v2(wrapper, beacon, lender, env):
    impl = WrappedfCash.deploy(env.deployer.address, {"from": env.deployer})

    # Change the address of notional on the beacon
    beacon.upgradeTo(impl.address)

    with brownie.reverts("Invalid caller"):
        env.notional.safeTransferFrom(
            lender.address,
            wrapper.address,
            wrapper.getfCashId(),
            100_000e8,
            "",
            {"from": lender}
        )


def test_cannot_transfer_invalid_fcash(lender, factory, env):
    markets = env.notional.getActiveMarkets(2)
    txn = factory.deployWrapper(2, markets[1][1])
    wrapper = Contract.from_abi("Wrapper", txn.events['WrapperDeployed']['wrapper'], WrappedfCash.abi)
    fCashId = env.notional.encodeToId(2, markets[0][1], 1)

    with brownie.reverts():
        env.notional.safeTransferFrom(
            lender.address,
            wrapper.address,
            fCashId,
            100_000e8,
            "",
            {"from": lender}
        )

def test_cannot_transfer_batch_fcash(wrapper, lender, env):
    with brownie.reverts("Not accepted"):
        env.notional.safeBatchTransferFrom(
            lender.address,
            wrapper.address,
            [wrapper.getfCashId()],
            [100_000e8],
            "",
            {"from": lender}
        )

def test_transfer_fcash(wrapper, lender, env):
    env.notional.safeTransferFrom(
        lender.address,
        wrapper.address,
        wrapper.getfCashId(),
        100_000e8,
        "",
        {"from": lender}
    )

    assert wrapper.balanceOf(lender) == 100_000e8

# Test Redeem fCash

def test_fail_redeem_above_balance(beacon, env):
    pass

def test_redeem_fcash_pre_maturity(beacon, env):
    pass

def test_redeem_post_maturity_asset(beacon, env):
    pass

def test_redeem_post_maturity_underlying(beacon, env):
    pass