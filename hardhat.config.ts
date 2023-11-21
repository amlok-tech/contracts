import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter"

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.17",
        settings: {
            optimizer: {
                enabled: true,
                runs: 5000
            }
        }
    },
    gasReporter: {
        enabled: false,
    },
    networks: {
        hardhat: {
            chainId: 1337,
            accounts: {
                mnemonic: `absurd anchor bullet lobster unable exclude weird lucky bar soda dumb first`
            }
        },
        goerli: {
            chainId: 5,
            url: `https://eth-goerli.nodereal.io/v1/4e9bd49fa7bc46dfa0c6e81533aacf73`,
            accounts: {
                mnemonic: `absurd anchor bullet lobster unable exclude weird lucky bar soda dumb first`
            },
            gasPrice: 1000000000,
        },
    },
    etherscan: {
        // Your API key for Etherscan
        // Obtain one at https://etherscan.io/
        apiKey: "AGT6DCH718IKJA2AYNZW71GYFAVDZN1VKV"
    }
};

export default config;
