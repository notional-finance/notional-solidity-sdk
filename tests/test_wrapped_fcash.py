import pytest
import brownie
import eth_abi
from tests.helpers import get_balance_trade_action
from brownie import Contract, WrappedfCash
from brownie.network import chain
from scripts.EnvironmentConfig import getEnvironment

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

@pytest.fixture()
def env():
    return getEnvironment()

@pytest.fixture() 
def beacon(WrappedfCash, nUpgradeableBeacon, env):
    impl = WrappedfCash.deploy(env.notional.address, {"from": env.deployer})
    return nUpgradeableBeacon.deploy(impl.address, {"from": env.deployer})

@pytest.fixture() 
def factory(WrappedfCashFactory, beacon, env):
    return WrappedfCashFactory.deploy(beacon.address, {"from": env.deployer})

@pytest.fixture() 
def wrapper(factory, env):
    markets = env.notional.getActiveMarkets(2)
    txn = factory.deployWrapper(2, markets[0][1])
    return Contract.from_abi("Wrapper", txn.events['WrapperDeployed']['wrapper'], WrappedfCash.abi)

@pytest.fixture() 
def lender(env):
    env.tokens["DAI"].approve(env.notional.address, 2**255-1, {'from': env.whales["DAI_EOA"]})
    env.notional.batchBalanceAndTradeAction(
        env.whales["DAI_EOA"],
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
        ], { "from": env.whales["DAI_EOA"] }
    )

    return env.whales["DAI_EOA"]

@pytest.fixture() 
def lender_contract(env):
    env.tokens["DAI"].approve(env.notional.address, 2**255-1, {'from': env.whales["DAI_CONTRACT"]})
    env.notional.batchBalanceAndTradeAction(
        env.whales["DAI_CONTRACT"],
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
        ], { "from": env.whales["DAI_CONTRACT"] }
    )

    return env.whales["DAI_CONTRACT"]

# Deploy and Upgrade
def test_deploy_wrapped_fcash(factory, env):
    markets = env.notional.getActiveMarkets(2)
    computedAddress = factory.computeAddress(2, markets[0][1])
    txn = factory.deployWrapper(2, markets[0][1], {"from": env.deployer})
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

def test_transfer_fcash_contract(wrapper, lender_contract, env):
    env.notional.safeTransferFrom(
        lender_contract.address,
        wrapper.address,
        wrapper.getfCashId(),
        100_000e8,
        "",
        {"from": lender_contract}
    )

    assert wrapper.balanceOf(lender_contract) == 100_000e8

# Test Redeem fCash

def test_fail_redeem_above_balance(wrapper, lender, env):
    env.notional.safeTransferFrom(
        lender.address,
        wrapper.address,
        wrapper.getfCashId(),
        100_000e8,
        "",
        {"from": lender}
    )

    with brownie.reverts():
        wrapper.redeem(105_000e8, (False, False, lender.address), {"from": lender})
        wrapper.redeemToAsset(105_000e8, lender.address, {"from": lender})
        wrapper.redeemToUnderlying(105_000e8, lender.address, {"from": lender})

def test_transfer_fcash(wrapper, lender, env):
    env.notional.safeTransferFrom(
        lender.address,
        wrapper.address,
        wrapper.getfCashId(),
        100_000e8,
        "",
        {"from": lender}
    )
    wrapper.redeem(50_000e8, (False, True, lender), {"from": lender})

    assert wrapper.balanceOf(lender.address) == 50_000e8
    assert env.notional.balanceOf(lender.address, wrapper.getfCashId()) == 50_000e8

def test_transfer_fcash_contract(wrapper, lender_contract, env):
    env.notional.safeTransferFrom(
        lender_contract.address,
        wrapper.address,
        wrapper.getfCashId(),
        100_000e8,
        "",
        {"from": lender_contract}
    )

    with brownie.reverts():
        wrapper.redeem(
            50_000e8,
            (False, True, lender_contract),
            {"from": lender_contract}
        )

    wrapper.transfer(env.deployer, 50_000e8, {"from": lender_contract})

    assert wrapper.balanceOf(lender_contract.address) == 50_000e8
    assert wrapper.balanceOf(env.deployer) == 50_000e8

def test_redeem_post_maturity_asset(wrapper, lender, env):
    env.notional.safeTransferFrom(
        lender.address,
        wrapper.address,
        wrapper.getfCashId(),
        100_000e8,
        "",
        {"from": lender}
    )

    chain.mine(1, timestamp=wrapper.getMaturity())
    wrapper.redeemToAsset(50_000e8, lender.address, {"from": lender})

    assert wrapper.balanceOf(lender.address) == 50_000e8
    assert env.tokens["cDAI"].balanceOf(lender.address) == 229452921165321

def test_redeem_post_maturity_underlying(wrapper, lender, env):
    env.notional.safeTransferFrom(
        lender.address,
        wrapper.address,
        wrapper.getfCashId(),
        100_000e8,
        "",
        {"from": lender}
    )

    chain.mine(1, timestamp=wrapper.getMaturity())
    wrapper.redeemToUnderlying(50_000e8, lender, {"from": lender})

    assert wrapper.balanceOf(lender.address) == 50_000e8
    assert env.tokens["DAI"].balanceOf(lender.address) >= 50_000e18

# Test fCash Trading
def test_mint_and_redeem_fcash_via_underlying(wrapper, env):
    env.tokens["DAI"].approve(wrapper.address, 2 ** 255 - 1, {'from': env.whales["DAI_EOA"].address})
    wrapper.mintFromUnderlying(
        10_000e8,
        env.whales["DAI_EOA"].address,
        {'from': env.whales["DAI_EOA"].address}
    )

    assert wrapper.balanceOf(env.whales["DAI_EOA"].address) == 10_000e8
    portfolio = env.notional.getAccount(wrapper.address)[2]
    assert portfolio[0][0] == wrapper.getCurrencyId()
    assert portfolio[0][1] == wrapper.getMaturity()
    assert portfolio[0][3] == 10_000e8
    assert len(portfolio) == 1

    # Now redeem the fCash
    balanceBefore = env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"].address)
    wrapper.redeemToUnderlying(
        10_000e8,
        env.whales["DAI_EOA"].address,
        {"from": env.whales["DAI_EOA"].address}
    )
    balanceAfter = env.tokens["DAI"].balanceOf(env.whales["DAI_EOA"].address)
    balanceChange = balanceAfter - balanceBefore 

    assert 9700e18 <= balanceChange and balanceChange <= 9900e18
    portfolio = env.notional.getAccount(wrapper.address)[2]
    assert len(portfolio) == 0
    assert wrapper.balanceOf(env.whales["DAI_EOA"].address) == 0

def test_mint_and_redeem_fusdc_via_underlying(factory, env):
    markets = env.notional.getActiveMarkets(2)
    txn = factory.deployWrapper(3, markets[0][1])
    wrapper = Contract.from_abi("Wrapper", txn.events['WrapperDeployed']['wrapper'], WrappedfCash.abi)

    env.tokens["USDC"].approve(wrapper.address, 2 ** 255 - 1, {'from': env.whales["USDC"].address})
    wrapper.mintFromUnderlying(
        10_000e8,
        env.whales["USDC"].address,
        {'from': env.whales["USDC"].address}
    )

    assert wrapper.balanceOf(env.whales["USDC"].address) == 10_000e8
    portfolio = env.notional.getAccount(wrapper.address)[2]
    assert portfolio[0][0] == wrapper.getCurrencyId()
    assert portfolio[0][1] == wrapper.getMaturity()
    assert portfolio[0][3] == 10_000e8
    assert len(portfolio) == 1

    # Now redeem the fCash
    balanceBefore = env.tokens["USDC"].balanceOf(env.whales["USDC"].address)
    wrapper.redeemToUnderlying(
        10_000e8,
        env.whales["USDC"].address,
        {"from": env.whales["USDC"].address}
    )
    balanceAfter = env.tokens["USDC"].balanceOf(env.whales["USDC"].address)
    balanceChange = balanceAfter - balanceBefore 

    assert 9700e6 <= balanceChange and balanceChange <= 9900e6
    portfolio = env.notional.getAccount(wrapper.address)[2]
    assert len(portfolio) == 0
    assert wrapper.balanceOf(env.whales["USDC"].address) == 0

def test_mint_and_redeem_fcash_via_asset(wrapper, env):
    env.tokens["cDAI"].approve(wrapper.address, 2 ** 255 - 1, {'from': env.whales["cDAI"].address})
    wrapper.mintFromAsset(
        10_000e8,
        env.whales["cDAI"].address,
        {'from': env.whales["cDAI"].address}
    )

    assert wrapper.balanceOf(env.whales["cDAI"].address) == 10_000e8
    portfolio = env.notional.getAccount(wrapper.address)[2]
    assert portfolio[0][0] == wrapper.getCurrencyId()
    assert portfolio[0][1] == wrapper.getMaturity()
    assert portfolio[0][3] == 10_000e8
    assert len(portfolio) == 1

    # Now redeem the fCash
    balanceBefore = env.tokens["cDAI"].balanceOf(env.whales["cDAI"].address)
    wrapper.redeemToAsset(
        10_000e8,
        env.whales["cDAI"].address,
        {"from": env.whales["cDAI"].address}
    )
    balanceAfter = env.tokens["cDAI"].balanceOf(env.whales["cDAI"].address)
    balanceChange = balanceAfter - balanceBefore 

    assert 440_000e8 <= balanceChange and balanceChange <= 450_000e8
    portfolio = env.notional.getAccount(wrapper.address)[2]
    assert len(portfolio) == 0
    assert wrapper.balanceOf(env.whales["cDAI"].address) == 0

# TODO: Test fETH specifically
