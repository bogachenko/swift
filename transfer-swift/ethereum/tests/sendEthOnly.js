const {
	ethers
} = require("ethers");
require("dotenv").config();
const hre = require("hardhat");
async function main() {
	console.log("Starting multiTransfer script...");
	const networkName = hre.network.name;
	console.log("Using network:", networkName);
	let rpcUrl;
	let contractAddress;
	if(networkName === "holesky") {
		rpcUrl = process.env.HOLESKY_RPC_URL;
		contractAddress = process.env.HOLESKY_CONTRACT_ADDRESS;
	} else if(networkName === "sepolia") {
		rpcUrl = process.env.SEPOLIA_RPC_URL;
		contractAddress = process.env.SEPOLIA_CONTRACT_ADDRESS;
	} else if(networkName === "mainnet") {
		rpcUrl = process.env.MAINNET_RPC_URL;
		contractAddress = process.env.MAINNET_CONTRACT_ADDRESS;
	} else {
		throw new Error(`Unknown network: ${networkName}`);
	}
	if(!contractAddress) {
		throw new Error(`Contract address not set for network: ${networkName}`);
	}
	const provider = new ethers.JsonRpcProvider(rpcUrl);
	const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
	console.log("Signer address:", await signer.getAddress());
	console.log("Contract address:", contractAddress);
	const abi = ["function multiTransfer(address[],uint256[],address[],address[],uint256[],address[],address[],uint256[],address[],address[],uint256[],uint256[],bytes32) payable"];
	const contract = new ethers.Contract(contractAddress, abi, signer);
	const ethRecipients = ["0x1111111111111111111111111111111111111111", "0x2222222222222222222222222222222222222222", "0x3333333333333333333333333333333333333333", "0x4444444444444444444444444444444444444444", "0x5555555555555555555555555555555555555555", "0x6666666666666666666666666666666666666666", "0x7777777777777777777777777777777777777777", "0x8888888888888888888888888888888888888888", "0x9999999999999999999999999999999999999999"];
	const ethAmounts = Array(ethRecipients.length).fill(1n);
	console.log(`Preparing ${ethRecipients.length} ETH transfers...`);
	const empty = [];
	const taxFee = ethers.parseEther("0.0001");
	const totalWei = ethAmounts.reduce((acc, amount) => acc + amount, 0n);
	const payableAmount = totalWei + taxFee;
	console.log("Total ETH to send (with tax):", ethers.formatEther(payableAmount), "ETH");
	const nonce = ethers.id(Date.now().toString());
	console.log("Generated nonce:", nonce);
	console.log("Sending multiTransfer transaction...");
	const tx = await contract.multiTransfer(ethRecipients, ethAmounts, empty, empty, empty, empty, empty, empty, empty, empty, empty, empty, nonce, {
		value: payableAmount
	});
	console.log("Transaction sent. Waiting for confirmation...");
	await tx.wait();
	console.log("Transaction confirmed. Tx hash:", tx.hash);
}
main().catch((error) => {
	console.error("Error occurred:", error);
	process.exit(1);
});