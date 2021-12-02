require("@nomiclabs/hardhat-etherscan");

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    kovan: {
      url:  "https://eth-kovan.alchemyapi.io/v2/H8E5dk64j-odPJlWF6TYnBYKjkZHYjuD"
    },
    mainnet: {
      url:  "https://eth-mainnet.alchemyapi.io/v2/nIBHAEJZlRfbR0HdgbNlxYhAtAGFOz8H"
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
    apiKey: "IUCUJU3CDUW1H8PNMTPBWSAQ9ZKYMAVUYW"
  }
}