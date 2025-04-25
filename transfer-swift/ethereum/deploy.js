const hre = require("hardhat");
async function main() {
	const [deployer] = await hre.ethers.getSigners();
	console.log("Starting deployment on network:", hre.network.name);
	console.log("Deployer address:", deployer.address);
	const balance = await hre.ethers.provider.getBalance(deployer.address);
	console.log("Deployer balance:", hre.ethers.formatEther(balance), "ETH");
	const TransferSWIFT = await hre.ethers.getContractFactory("TransferSWIFT");
	const contract = await TransferSWIFT.deploy({
		value: 1
	});
	console.log("Contract deployed at:", contract.target);
}
main().catch((error) => {
	console.error("Deployment failed:", error);
	process.exitCode = 1;
});