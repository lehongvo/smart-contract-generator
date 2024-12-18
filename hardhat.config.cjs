require("@nomiclabs/hardhat-ethers");

module.exports = {
    solidity: {
        version: "0.8.19",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200
            }
        }
    },
    networks: {
        ronin_testnet: {
            url: process.env.RPC_URL || "https://saigon-testnet.roninchain.com/rpc",
            accounts: ["51df14fb6587fe2f6e7e7b4d78c2ab6f9f125d2aba408775c3ec04153201ea1a"]
        }
    }
};