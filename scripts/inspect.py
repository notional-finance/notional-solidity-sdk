# flake8: noqa
import json

from brownie import network
from brownie.network.contract import Contract
from brownie.exceptions import ContractNotFound
from brownie.project import NotionalSoliditySdkProject

TokenType = {
    "UnderlyingToken": 0,
    "cToken": 1,
    "cETH": 2,
    "Ether": 3,
    "NonMintable": 4,
}

TokenTypeNames = {
    0: "UnderlyingToken",
    1: "cToken",
    2: "cETH",
    3: "Ether",
    4: "NonMintable",
}

env = {}

def main():
    network_name = network.show_active()
    output_file = "v2.{}.json".format(network_name)
    addresses = None
    with open(output_file, "r") as f:
        addresses = json.load(f)

    notionalInterfaceABI = NotionalSoliditySdkProject._build.get("NotionalProxy")["abi"]
    try:
        notional = Contract.from_abi("Notional", addresses["notional"], abi=notionalInterfaceABI)
        env['notional'] = notional
        for id in range(1, notional.getMaxCurrencyId() + 1):
            (assetToken, underlyingToken) = notional.getCurrency(id)
            at_token_address, _, _, at_token_type, _ = assetToken
            ut_token_address, _, _, ut_token_type, _ = underlyingToken
            print(f"Asset - {TokenTypeNames[at_token_type]} : {at_token_address}")
            print(f"Under - {TokenTypeNames[ut_token_type]} : {ut_token_address}\n")

    except ContractNotFound:
        print(f"Contract not found at address: {addresses['notional']}")