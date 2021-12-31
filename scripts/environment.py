import json

from brownie import network, accounts
from brownie.network.contract import Contract
from brownie.exceptions import ContractNotFound
from brownie.project import NotionalSoliditySdkProject

TokenTypeNames = {
    0: "UnderlyingToken",
    1: "cToken",
    2: "cETH",
    3: "Ether",
    4: "NonMintable",
}

TokenABI = {
  0: "IErc20",
  1: "ICToken",
  2: "ICEther",
  3: None,
  4: "IErc20"
}

def setup_env():
    env = {}
    network_name = network.show_active()
    output_file = "v2.{}.json".format(network_name)
    comptroller_path = "scripts/compound_artifacts/nComptroller.json"
    governor_path = "abi/Governor.json"
    addresses = None
    nComptrollerABI = None
    governorABI = None
    with open(output_file, "r") as f:
        addresses = json.load(f)
    with open(comptroller_path, "r") as f:
        nComptrollerABI = json.load(f)['abi']
    with open(governor_path, "r") as f:
        governorABI = json.load(f)
    notionalInterfaceABI = NotionalSoliditySdkProject._build.get("NotionalProxy")[
        "abi"]

    abi = {}
    abi[0] = NotionalSoliditySdkProject._build.get("IErc20")["abi"]
    abi[1] = NotionalSoliditySdkProject._build.get("ICToken")["abi"]
    abi[2] = NotionalSoliditySdkProject._build.get("ICEther")["abi"]
    abi[4] = NotionalSoliditySdkProject._build.get("IErc20")["abi"]

    try:
        notional = Contract.from_abi(
            "Notional", addresses["notional"], abi=notionalInterfaceABI)
        env['notional'] = notional
        env['comptroller'] = Contract.from_abi("nComptroller", addresses["comptroller"], abi=nComptrollerABI)
        env['governor'] = Contract.from_abi(
            "Governor", addresses["governor"], abi=governorABI)
        env['currencies'] = {}
        env['multisig'] = accounts[0]

        for id in range(1, notional.getMaxCurrencyId() + 1):
            (assetToken, underlyingToken) = notional.getCurrency(id)
            at_token_address, _, _, at_token_type, _ = assetToken
            ut_token_address, _, _, ut_token_type, _ = underlyingToken

            # Load the asset contract and add it to the currencies dictionary
            assetContract = Contract.from_abi(
                "Token", at_token_address, abi[at_token_type])
            env['currencies'][assetContract.symbol()] = {}
            env['currencies'][assetContract.symbol()]['asset'] = assetContract

            # if there is an underlying contract load it and add it to the currencies dictionary
            if ut_token_address != '0x0000000000000000000000000000000000000000':
              underlyingContract = Contract.from_abi("Token", ut_token_address, abi[ut_token_type])
              env['currencies'][assetContract.symbol()]['underlying'] = underlyingContract
        return env
    except ContractNotFound:
        print(f"Contract not found at address: {addresses['notional']}")
