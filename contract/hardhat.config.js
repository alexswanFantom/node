require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-etherscan");

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const privateKey =
  "76749f218a640fe54c2528569dc47f35f7b687f6d14a92b51a1d588eb466e220";
const testnet = "https://mainnet-rpc.memescan.io";
const mainet = "https://mainnet-rpc.memescan.io";
const chainId = 18159;

module.exports = {
  networks: {
    mainnet: {
      url: mainet,
      accounts: [privateKey],
    },
    testnet: {
      url: testnet,
      accounts: [privateKey],
    },

  },
  etherscan: {
    apiKey: "avc",
    customChains: [{
      network: "pom",
      chainId: chainId,
      urls: {
        apiURL: "https://memescan.io/api",
        browserURL: "https://memescan.io"
      }
    }],
  },
  solidity: {
    version: "0.8.4",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      evmVersion: "byzantium",
      libraries: {
        "contracts/IterableMapping.sol": {
          IterableMapping: "0x231C7F5887213d951107ad2B6E8a6CCfE8cA6EEf"
        }
      }
    },
  },
};