import pytest
import brownie
import eth_abi
from tests.helpers import get_balance_trade_action
from brownie import Contract, WrappedfCash, network
from brownie.convert.datatypes import Wei
from brownie.network import Chain
from scripts.EnvironmentConfig import getEnvironment

chain = Chain()

@pytest.fixture(autouse=True)
def run_around_tests():
    chain.snapshot()
    yield
    chain.revert()

@pytest.fixture()
def env():
    name = network.show_active()
    if name == 'mainnet-fork':
        return getEnvironment('mainnet')
    elif name == 'kovan-fork':
        return getEnvironment('kovan')

@pytest.fixture() 
def beacon(WrappedfCash, nUpgradeableBeacon, env):
    impl = WrappedfCash.deploy(env.notional.address, {"from": env.deployer})
    return nUpgradeableBeacon.deploy(impl.address, {"from": env.deployer})

@pytest.fixture() 
def factory(WrappedfCashFactory, beacon, env):
    return WrappedfCashFactory.deploy(beacon.address, {"from": env.deployer})

@pytest.fixture() 
def wrapper3Month(factory, env):
    markets = env.notional.getActiveMarkets(2)
    txn = factory.deployWrapper(2, markets[0][1])
    return Contract.from_abi("Wrapper", txn.events['WrapperDeployed']['wrapper'], WrappedfCash.abi)

@pytest.fixture() 
def wrapper6Month(factory, env):
    markets = env.notional.getActiveMarkets(2)
    txn = factory.deployWrapper(2, markets[1][1])
    return Contract.from_abi("Wrapper", txn.events['WrapperDeployed']['wrapper'], WrappedfCash.abi)

@pytest.fixture() 
def setToken(MockSetTradeModule, env, wrapper3Month, wrapper6Month):
    module = MockSetTradeModule.deploy({"from": env.deployer})

    # Put some cTokens on the set token
    env.tokens["DAI"].approve(env.tokens["cDAI"].address, 2 ** 255 - 1, {'from': env.whales["DAI_EOA"].address})
    env.tokens["cDAI"].mint(1_000_000e18, {'from': env.whales["DAI_EOA"].address})
    env.tokens["cDAI"].transfer(
        module.address,
        env.tokens["cDAI"].balanceOf(env.whales["DAI_EOA"]),
        {'from': env.whales['DAI_EOA']}
    )

    # Put some wrapped fCash on the set token
    env.tokens["DAI"].approve(wrapper3Month.address, 2 ** 255 - 1, {'from': env.whales["DAI_EOA"].address})
    wrapper3Month.mint(
        1_000_000e18,
        1_000_000e8,
        module.address,
        0,
        True,
        {'from': env.whales['DAI_EOA']}
    )

    env.tokens["DAI"].approve(wrapper6Month.address, 2 ** 255 - 1, {'from': env.whales["DAI_EOA"].address})
    wrapper6Month.mint(
        1_000_000e18,
        1_000_000e8,
        module.address,
        0,
        True,
        {'from': env.whales['DAI_EOA']}
    )

    return module

@pytest.fixture() 
def exchangeAdapter(WrappedfCashTradeAdapter, env):
    return WrappedfCashTradeAdapter.deploy({'from': env.deployer})

def test_asset_cash_to_fcash(wrapper3Month, wrapper6Month, setToken, exchangeAdapter, env):
    cTokenBefore = env.tokens['cDAI'].balanceOf(setToken.address)
    fCashBalanceBefore = wrapper3Month.balanceOf(setToken.address)
    # Gas Used: 334619
    txn = setToken.executeTrade(
        (
            setToken.address,
            exchangeAdapter.address,
            env.tokens["cDAI"].address,
            wrapper3Month.address,
            5_000_000e8, # about 100k in fCash
            100_000e8, # exactly 100k fCash
            0
        ),
        eth_abi.encode_abi(['uint8', 'uint32'], [0, 0]),
        {'from': env.deployer}
    )

    cTokenAfter = env.tokens['cDAI'].balanceOf(setToken.address)
    fCashBalanceAfter = wrapper3Month.balanceOf(setToken.address)

    assert env.tokens['cDAI'].balanceOf(exchangeAdapter.address) == 0
    assert wrapper3Month.balanceOf(exchangeAdapter.address) == 0
    assert wrapper6Month.balanceOf(exchangeAdapter.address) == 0

    assert fCashBalanceAfter - fCashBalanceBefore == 100_000e8
    assert cTokenBefore - cTokenAfter <= 5_000_000e8
    assert txn.gas_used <= 350000

def test_fcash_to_asset_cash(wrapper3Month, wrapper6Month, setToken, exchangeAdapter, env):
    cTokenBefore = env.tokens['cDAI'].balanceOf(setToken.address)
    fCashBalanceBefore = wrapper3Month.balanceOf(setToken.address)
    # Gas Used: 251135
    txn = setToken.executeTrade(
        (
            setToken.address,
            exchangeAdapter.address,
            wrapper3Month.address,
            env.tokens["cDAI"].address,
            100_000e8, # exactly 100k in fCash
            4_800_000e8, # approx 100k in cTokens (todo, do the math here)
            0
        ),
        eth_abi.encode_abi(['uint8', 'uint32'], [1, Wei(0.12e9)]),
        {'from': env.deployer}
    )

    cTokenAfter = env.tokens['cDAI'].balanceOf(setToken.address)
    fCashBalanceAfter = wrapper3Month.balanceOf(setToken.address)

    assert env.tokens['cDAI'].balanceOf(exchangeAdapter.address) == 0
    assert wrapper3Month.balanceOf(exchangeAdapter.address) == 0
    assert wrapper6Month.balanceOf(exchangeAdapter.address) == 0

    assert fCashBalanceAfter - fCashBalanceBefore == -100_000e8
    assert cTokenAfter - cTokenBefore >= 4_800_000e8
    assert txn.gas_used <= 275000

def test_fcash_to_fcash(wrapper3Month, wrapper6Month, setToken, exchangeAdapter, env):
    cTokenBefore = env.tokens['cDAI'].balanceOf(setToken.address)
    fCash3MonthBalanceBefore = wrapper3Month.balanceOf(setToken.address)
    fCash6MonthBalanceBefore = wrapper6Month.balanceOf(setToken.address)
    # gas used: 509711
    txn = setToken.executeTrade(
        (
            setToken.address,
            exchangeAdapter.address,
            wrapper3Month.address,
            wrapper6Month.address,
            100_000e8, # redeem 100k fCash
            95_000e8,  # mint 95k fCash
            0
        ),
        eth_abi.encode_abi(['uint8', 'uint32'], [2, Wei(0.12e9)]),
        {'from': env.deployer}
    )
    cTokenAfter = env.tokens['cDAI'].balanceOf(setToken.address)
    fCash3MonthBalanceAfter = wrapper3Month.balanceOf(setToken.address)
    fCash6MonthBalanceAfter = wrapper6Month.balanceOf(setToken.address)

    assert env.tokens['cDAI'].balanceOf(exchangeAdapter.address) == 0
    assert wrapper3Month.balanceOf(exchangeAdapter.address) == 0
    assert wrapper6Month.balanceOf(exchangeAdapter.address) == 0

    assert fCash3MonthBalanceAfter - fCash3MonthBalanceBefore == -100_000e8
    assert fCash6MonthBalanceAfter - fCash6MonthBalanceBefore == 95_000e8
    assert cTokenAfter - cTokenBefore >= 100_000e8
    assert txn.gas_used <= 525000