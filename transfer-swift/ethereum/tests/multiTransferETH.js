require("dotenv").config();
const hre = require("hardhat");
const {
	ethers
} = require("hardhat");
async function main() {
	const NETWORK = hre.network.name.toUpperCase();
	const RECIPIENTS = [{
			address: "0x1111111111111111111111111111111111111111",
			amount: "0.000000000000000001"
		},
		{
			address: "0x2222222222222222222222222222222222222222",
			amount: "0.000000000000000001"
		},
		{
			address: "0x3333333333333333333333333333333333333333",
			amount: "0.000000000000000001"
		},
		{
			address: "0x4444444444444444444444444444444444444444",
			amount: "0.000000000000000001"
		},
		{
			address: "0x5555555555555555555555555555555555555555",
			amount: "0.000000000000000001"
		},
		{
			address: "0x6666666666666666666666666666666666666666",
			amount: "0.000000000000000001"
		},
		{
			address: "0x7777777777777777777777777777777777777777",
			amount: "0.000000000000000001"
		},
		{
			address: "0x8888888888888888888888888888888888888888",
			amount: "0.000000000000000001"
		},
		{
			address: "0x9999999999999999999999999999999999999999",
			amount: "0.000000000000000001"
		},
		{
			address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			amount: "0.000000000000000001"
		},
		{
			address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			amount: "0.000000000000000001"
		},
		{
			address: "0xcccccccccccccccccccccccccccccccccccccccc",
			amount: "0.000000000000000001"
		},
		{
			address: "0xdddddddddddddddddddddddddddddddddddddddd",
			amount: "0.000000000000000001"
		},
		{
			address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
			amount: "0.000000000000000001"
		},
		{
			address: "0xffffffffffffffffffffffffffffffffffffffff",
			amount: "0.000000000000000001"
		},
		{
			address: "0x1234567890123456789012345678901234567890",
			amount: "0.000000000000000001"
		},
		{
			address: "0x0123456789012345678901234567890123456789",
			amount: "0.000000000000000001"
		},
		{
			address: "0xdEAD000000000000000042069420694206942069",
			amount: "0.000000000000000001"
		},
		{
			address: "0x000000000000000000000000000000000000dEaD",
			amount: "0.000000000000000001"
		},
		{
			address: "0x00000000000000000000045261D4Ee77acdb3286",
			amount: "0.000000000000000001"
		},
	];
	const transferSWIFT = await ethers.getContractAt("TransferSWIFT", process.env[`${NETWORK}_CONTRACT_ADDRESS`]);
	const [sender] = await ethers.getSigners();
	if (await transferSWIFT.blacklist(sender.address)) {
		throw new Error("Sender blacklisted");
	}
	for (const recipient of RECIPIENTS) {
		if (await transferSWIFT.blacklist(recipient.address)) {
			throw new Error(`Recipient ${recipient.address} blacklisted`);
		}
	}
	const amounts = RECIPIENTS.map(r => ethers.parseEther(r.amount));
	const totalTransfers = amounts.reduce((sum, val) => sum + val, 0n);
	const taxFee = await transferSWIFT.taxFee();
	const totalValue = totalTransfers + taxFee;
	const ethBalance = await ethers.provider.getBalance(sender.address);
	if (ethBalance < totalValue) {
		throw new Error(`Insufficient ETH. Required: ${ethers.formatEther(totalValue)} ETH`);
	}
	console.table({
		Network: NETWORK,
		Sender: sender.address,
		Contract: transferSWIFT.target,
		Recipients: RECIPIENTS.length,
		'Total Transfers': `${ethers.formatEther(totalTransfers)} ETH`,
		'Tax Fee': `${ethers.formatEther(taxFee)} ETH`,
		'Total Value': `${ethers.formatEther(totalValue)} ETH`,
		'Balance': `${ethers.formatEther(ethBalance)} ETH`
	});
	console.log("\nRecipients details:");
	console.table(RECIPIENTS.map((r, i) => ({
		Number: i + 1,
		Address: r.address,
		Amount: `${r.amount} ETH`
	})));
	console.log("\nSending transaction...");
	const tx = await transferSWIFT.multiTransferETH(
		RECIPIENTS.map(r => r.address),
		amounts, {
			value: totalValue
		}
	);
	const receipt = await tx.wait();
	console.table({
		Block: receipt.blockNumber,
		'Transaction Hash': tx.hash,
		'Gas used': receipt.gasUsed.toString(),
		Status: receipt.status === 1 ? "Success" : "Failed"
	});
}
main().catch((error) => {
	console.error("Execution failed:", error.message);
	process.exit(1);
});