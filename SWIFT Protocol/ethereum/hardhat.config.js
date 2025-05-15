require("@nomicfoundation/hardhat-toolbox"), require("@openzeppelin/hardhat-upgrades"), require("dotenv").config(), module.exports = {
	solidity: {
		version: "0.8.20",
		settings: {
			optimizer: {
				enabled: true,
				runs: 200
			},
			viaIR: false
		}
	},
	networks: {
		holesky: {
			url: process.env.HOLESKY_RPC_URL,
			accounts: [process.env.PRIVATE_KEY]
		}
	},
	etherscan: {
		apiKey: process.env.ETHERSCAN_API_KEY
	},
	sourcify: {
  		enabled: true
	}
};