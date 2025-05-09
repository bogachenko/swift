const hre = require("hardhat");
async function main() {
	var [e] = await hre.ethers.getSigners();
	console.log("Starting deployment on network:", hre.network.name), console.log("Deployer address:", e.address), e = await hre.ethers.provider.getBalance(e.address), console.log("Deployer balance:", hre.ethers.formatEther(e), "ETH");
	const t = await hre.ethers.getContractFactory("TestCOIN"),
		o = await t.deploy();
	await o.waitForDeployment(), console.log("Contract deployed at:", o.target)
}
main().catch(e => {
	console.error("Deployment failed:", e), process.exitCode = 1
});