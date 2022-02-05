import json

from brownie import accounts
from brownie.network.contract import Contract
from brownie.project import NotionalSoliditySdkProject

with open("abi/nComptroller.json", "r") as a:
    Comptroller = json.load(a)

with open("abi/nCErc20.json") as a:
    cToken = json.load(a)

with open("abi/nCEther.json") as a:
    cEther = json.load(a)

with open("abi/ERC20.json") as a:
    ERC20ABI = json.load(a)

with open("abi/Notional.json") as a:
    NotionalABI = json.load(a)

ETH_ADDRESS = "0x0000000000000000000000000000000000000000"


class Environment:
    def __init__(self) -> None:
        self.notional = Contract.from_abi(
            "Notional", "0x1344a36a1b56144c3bc62e7757377d288fde0369", NotionalABI
        )
        self.tokens = {
            "NOTE": Contract.from_abi(
                "ERC20", "0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5", ERC20ABI
            ),
            "WETH": Contract.from_abi(
                "ERC20", "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", ERC20ABI
            ),
            "USDC": Contract.from_abi(
                "ERC20", "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", ERC20ABI
            ),
            "DAI": Contract.from_abi(
                "ERC20", "0x6b175474e89094c44da98b954eedeac495271d0f", ERC20ABI
            ),
            "WBTC": Contract.from_abi(
                "ERC20", "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", ERC20ABI
            ),
            "LINK": Contract.from_abi(
                "ERC20", "0x514910771af9ca656af840dff83e8264ecf986ca", ERC20ABI
            ),
            "COMP": Contract.from_abi(
                "ERC20", "0xc00e94cb662c3520282e6f5717214004a7f26888", ERC20ABI
            ),
            "AAVE": Contract.from_abi(
                "ERC20", "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9", ERC20ABI
            ),
            "cDAI": Contract.from_abi(
                "cToken", "0x5d3a536e4d6dbd6114cc1ead35777bab948e3643", cToken["abi"]
            ),
            "cUSDC": Contract.from_abi(
                "cToken", "0x39aa39c021dfbae8fac545936693ac917d5e7563", cToken["abi"]
            ),
            "cWBTC": Contract.from_abi(
                "cToken", "0xccf4429db6322d5c611ee964527d42e5d685dd6a", cToken["abi"]
            ),
            "cETH": Contract.from_abi(
                "cEther", "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", cEther["abi"]
            )
        }

        self.whales = {
            "DAI_CONTRACT": accounts.at("0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7", force=True),
            "DAI_EOA": accounts.at("0x1e3D6eAb4BCF24bcD04721caA11C478a2e59852D", force=True),
            "ETH_CONTRACT": accounts.at("0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5", force=True), # cETH
            "ETH_EOA": accounts.at("0xDA9dfA130Df4dE4673b89022EE50ff26f6EA73Cf", force=True), # Kraken
            "USDC": accounts.at("0x0a59649758aa4d66e25f08dd01271e891fe52199", force=True),
            "cDAI": accounts.at("0x33b890d6574172e93e58528cd99123a88c0756e9", force=True),
            "ETH": accounts.at("0x7D24796f7dDB17d73e8B1d0A3bbD103FBA2cb2FE", force=True),
            "cETH": accounts.at("0x1a1cd9c606727a7400bb2da6e4d5c70db5b4cade", force=True),
            "NOTE": accounts.at("0x22341fB5D92D3d801144aA5A925F401A91418A05", force=True),
            "COMP": accounts.at("0x7587cAefc8096f5F40ACB83A09Df031a018C66ec", force=True),
        }

        self.deployer = accounts.at("0x8B64fA5Fd129df9c755eB82dB1e16D6D0Bdf5Bc3", force=True)
        self.owner = accounts.at(self.notional.owner(), force=True)


def getEnvironment():
    return Environment()
