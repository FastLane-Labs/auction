import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import "hardhat-gas-reporter";
import "solidity-coverage";
import "hardhat-preprocessor";

dotenv.config();

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

const mnemonic = {
  testnet: `${process.env.TESTNET_MNEMONIC}`.replace(/_/g, " "),
  mainnet: `${process.env.MAINNET_MNEMONIC}`.replace(/_/g, " ")
};

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean) // remove empty lines
    .map(line => line.trim().split("="));
}

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

const config: HardhatUserConfig = {
  solidity: "0.8.4",
  networks: {
    hardhat: {
      blockGasLimit: 200000000,
      allowUnlimitedContractSize: true,
      gasPrice: 1e9,
      forking: {
        url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_APIKEY}`,
        //blockNumber: 11400000,
        timeout: 1000000
      }
    },
    mumbai: {
      url: `https://rpc-mumbai.matic.today`,
      // url: `https://rpc-mumbai.maticvigil.com/v1/${process.env.MATIC_APIKEY}`,
      // url: `https://matic-mumbai.chainstacklabs.com/`,
      gasPrice: 3e9,
      accounts: {
        mnemonic: mnemonic.testnet,
        initialIndex: 0,
        count: 10
      },
      chainId: 80001
    },
    polygon: {
      // url: `https://rpc-mainnet.maticvigil.com/v1/${process.env.MATIC_APIKEY}`,
      url: `https://matic-mainnet.chainstacklabs.com/`,
      gasPrice: 120e9,
      accounts: {
        mnemonic: mnemonic.mainnet,
        initialIndex: 0,
        count: 3
      }
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD"
  },
  etherscan: {
    apiKey: {
      polygon: process.env.POLYGONSCAN_APIKEY,
      polygonMumbai: process.env.POLYGONSCAN_APIKEY
    }
  },
  namedAccounts: {
    deployer: {
      default: 0
    },
    protocolOwner: {
      default: 1,
      1: "0x7E3e7545B4dE806F46A16D1F815Df5F1DB49841d" // PFL Gnosis Multisig
    },
    user0: {
      default: 2
    },
    user1: {
      default: 3
    },
    user2: {
      default: 4
    },
    user3: {
      default: 5
    },
    trustedForwarder: {
      default: 7, // Account 8
      137: "0x1337c0d31337c0D31337C0d31337c0d31337C0d3", // Polygon L2 Mainnet
      80001: "0x1337c0d31337c0D31337C0d31337c0d31337C0d3" // Polygon L2 Testnet - Mumbai
    }
  },
  preprocess: {
    eachLine: hre => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match('"' + find)) {
              line = line.replace('"' + find, '"' + replace);
            }
          });
        }
        return line;
      }
    })
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./build/contracts",
    deploy: "./deploy",
    deployments: "./deployments"
  },
  abiExporter: {
    path: "./abis",
    runOnCompile: true,
    // Mindful of https://github.com/ItsNickBarry/hardhat-abi-exporter/pull/29/files
    // and https://github.com/ItsNickBarry/hardhat-abi-exporter/pull/35 as they heavily change behavior around this package
    clear: true,
    flat: true,
    only: ["Universe"]
  },
  watcher: {
    compilation: {
      tasks: ["compile"],
      files: ["./contracts"],
      verbose: true
    },
    test: {
      tasks: [{ command: "test", params: { testFiles: ["{path}"] } }],
      files: ["./test/**/*"],
      verbose: true
    }
  }
};

export default config;
