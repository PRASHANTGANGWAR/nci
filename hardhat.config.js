require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config({ path: __dirname + "/.env" });
/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.20",
  networks: {
    mainnet: {
      url: `https://eth-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_ID}`,
      accounts: [process.env.PRIVATE_KEY],
    },
    bscTestnet: {
      url: `https://neat-wandering-tent.bsc-testnet.discover.quiknode.pro/${process.env.TESTNET_ID}/`,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: process.env.API_KEY,
  },
  sourcify: {
    enabled: true
  }
};
