require("@nomicfoundation/hardhat-toolbox"), require("@openzeppelin/hardhat-upgrades"), require("dotenv").config(), module.exports = {
	solidity: {
		version: "0.8.20",
		settings: {
			optimizer: {
				enabled: !0,
				runs: 200
			},
			viaIR: !0
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
	}
};