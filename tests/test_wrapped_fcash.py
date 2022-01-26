import pytest
import brownie
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
    factory.deployWrapper(2, markets[0][1])
    return Contract.from_abi("Wrapper", computedAddress, WrappedfCash.abi)

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

def test_upgrade_wrapper(factory, env):
    pass

# Test Minting fCash

@pytest.mark.only
def test_cannot_transfer_invalid_fcash(wrapper, env):
    pass

def test_cannot_transfer_negative_fcash(wrapper, env):
    pass

def test_cannot_transfer_batch_fcash(wrapper, env):
    pass

def test_transfer_fcash(wrapper, env):
    pass

# Test Redeem fCash

def test_fail_redeem_above_balance(beacon, env):
    pass

def test_redeem_fcash_pre_maturity(beacon, env):
    pass

def test_redeem_post_maturity_asset(beacon, env):
    pass

def test_redeem_post_maturity_underlying(beacon, env):
    pass