const hre = require("hardhat");
async function main() {
	const [deployer] = await hre.ethers.getSigners();
	console.log("Starting deployment on network:", hre.network.name);
	console.log("Deployer address:", deployer.address);
	const balance = await hre.ethers.provider.getBalance(deployer.address);
	console.log("Deployer balance:", hre.ethers.formatEther(balance), "ETH");
	const SWIFTProtocol = await hre.ethers.getContractFactory("SWIFTProtocol");
	const contract = await SWIFTProtocol.deploy({
		value: 1
	});
	await contract.waitForDeployment();
	const address = await contract.getAddress();
	console.log("Contract deployed at:", address);
	await sleep(15000);
	try {
		await hre.run("verify:verify", {
			address: address,
			constructorArguments: []
		});
		console.log("Contract verified successfully!");
	} catch (err) {
		console.error("Verification failed:", err.message);
	}
}
function sleep(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}
main().catch((err) => {
	console.error("Deployment failed:", err);
	process.exitCode = 1;
});