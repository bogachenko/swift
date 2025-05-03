const hre = require("hardhat");
async function main() {
	var [e] = await hre.ethers.getSigners();
	console.log("Deploying with:", e.address);
	const t = await hre.ethers.getContractFactory("TestCOIN721Batch"),
		a = await t.deploy(e.address);
	await a.waitForDeployment(), console.log("Contract deployed to:", await a.getAddress())
}
main().catch(e => {
	console.error(e), process.exitCode = 1
});