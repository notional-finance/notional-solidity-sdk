import sys
import json
from brownie import accounts, network, project
from utils.scenarios import LiquidationScenarios
from utils.helpers import get_balance_trade_action

class Currency:
    def __init__(self, env, id) -> None:
        self.env = env
        self.id = id

class NotionalEnvironment:
    def __init__(self, networkName, proj) -> None:
        self.network = networkName
        f = open(f"v2.{networkName}.json")
        data = json.load(f)
        self.notional = proj.interface.NotionalProxy(data["notional"])
        self.rateOracle = {}
        self.rateOracle["DAI"] = proj.interface.MockAggregatorInterface('0x990de64bb3e1b6d99b1b50567fc9ccc0b9891a4d')
        self.noteToken = proj.interface.INoteERC20('0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5')
        

def create_local_currency_scenario(env, account, scenario):

    pass

def create_collateral_currency_scenario(env, account, scenario):
    localCurrency = Currency(env, scenario["localCurrency"]["id"])
    collateralCurrency = Currency(env, scenario["collateralCurrency"]["id"])

    collateralAction = get_balance_trade_action(collateralCurrency.id, "DepositUnderlying", [], depositActionAmount=3e18)
    borrowAction = get_balance_trade_action(
        localCurrency.id,
        "None", # Deposit action
        [{"tradeActionType": "Borrow", "marketIndex": 1, "notional": 100e8, "maxSlippage": 0}],
        withdrawEntireCashBalance=True,
        redeemToUnderlying=True,
    )
    env.notional.batchBalanceAndTradeAction(
        account, [collateralAction, borrowAction], {"from": account, "value": 3e18}
    )
    env.rateOracle['DAI'].setAnswer(0.1e18)

def create_local_fcash_scenario(env, account, scenario):
    pass

def create_cross_currency_fcash_scenario(env, account, scenario):
    pass

def create_scenario(env, account, scenario):
    type = scenario["type"]
    print(f"Creating {type} scenario for {account.address}")

    if type == "localCurrency":
        create_local_currency_scenario(env, account, scenario)
    elif type == "collateralCurrency":
        create_collateral_currency_scenario(env, account, scenario)
    elif type == "localFcash":
        create_local_fcash_scenario(env, account, scenario)
    elif type == "crossCurrencyFcash":
        create_cross_currency_fcash_scenario(env, account, scenario)

def run(networkName, accountKey, scenarioName):
    # Connect to RPC
    network.connect(networkName)

    # Load current project
    proj = project.load()

    # Load notional contracts
    env = NotionalEnvironment(networkName, proj)

    # Create scenario
    create_scenario(env, accounts.add(accountKey), LiquidationScenarios[scenarioName])


if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: liqtool <network> <account_key> <scenario>")
        exit(1)
    run(sys.argv[1], sys.argv[2], sys.argv[3])
