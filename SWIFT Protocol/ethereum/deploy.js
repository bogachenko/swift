const hre = require("hardhat");
async function main() {
	const [e] = await hre.ethers.getSigners();
	console.log("Starting deployment on network:", hre.network.name), console.log("Deployer address:", e.address);
	const o = await hre.ethers.provider.getBalance(e.address);
	console.log("Deployer balance:", hre.ethers.formatEther(o), "ETH");
	const r = await hre.ethers.getContractFactory("SWIFTProtocol"),
		t = await r.deploy({
			value: 1
		});
	console.log("Contract deployed at:", t.target)
}
main().catch((e => {
	console.error("Deployment failed:", e), process.exitCode = 1
}));