require("dotenv").config(), require("@nomicfoundation/hardhat-toolbox"), module.exports = {
	solidity: "0.8.24",
	networks: {
		holesky: {
			url: process.env.HOLESKY_RPC_URL || "",
			accounts: [process.env.PRIVATE_KEY]
		},
		sepolia: {
			url: process.env.SEPOLIA_RPC_URL || "",
			accounts: [process.env.PRIVATE_KEY]
		},
		mainnet: {
			url: process.env.MAINET_RPC_URL || "",
			accounts: [process.env.PRIVATE_KEY]
		}
	},
	sourcify: {
		enabled: !0
	},
	etherscan: {
		apiKey: {
			holesky: process.env.ETHERSCAN_API_KEY
		}
	}
};