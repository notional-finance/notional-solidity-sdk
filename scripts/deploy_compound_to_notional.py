import json
import subprocess

from brownie import network, accounts, CompoundToNotionalV2

# create config object with cEth address
CONFIG = {
  "kovan": {
      "cETH": "0x40575f9Eb401f63f66F4c434248ad83D3441bf61"
  },
  "mainnet": {
      "cETH": "0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5"
  }
}
def main():
  addresses = None
  network_name = network.show_active()
  config = CONFIG[network_name]
  private_key_name = network.show_active().upper() + "_DEPLOYER"
  output_file = "v2.{}.json".format(network_name)
  with open(output_file, "r") as f:
      addresses = json.load(f)

  # Load account from private key
  deployer = accounts.load(private_key_name)
  compound_to_notional = CompoundToNotionalV2.deploy(
    addresses["notional"],
    addresses["governor"],
    config["cETH"],
    {"from": deployer}
  )

  verify(
      compound_to_notional.address,
    [
        addresses["notional"],
        addresses["governor"],
        config["cETH"]
    ]
  )

def verify(address, args):
    proc = subprocess.run(
        ["npx", "hardhat", "verify", "--network",
         network.show_active(), address] + args,
        capture_output=True,
        encoding="utf8",
    )

    print(proc.stdout)
    print(proc.stderr)
