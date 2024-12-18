require("@nomiclabs/hardhat-ethers");
import { DATA } from "./app/api/deploy/utils/constant";

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
            accounts: [DATA.PRIVATE_KEY]
        }
    }
};