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
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
        }
    }
};