require("dotenv/config");
require("@nomiclabs/hardhat-etherscan");

const NETWORKS_KOVAN_URL = process.env.NETWORKS_KOVAN_URL;
const NETWORKS_MAINNET_URL = process.env.NETWORKS_MAINNET_URL;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    kovan: {
      url:  NETWORKS_KOVAN_URL
    },
    mainnet: {
      url:  NETWORKS_MAINNET_URL
    },
  },
  solidity: {
    version: "0.7.6",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: ETHERSCAN_API_KEY
  }
}