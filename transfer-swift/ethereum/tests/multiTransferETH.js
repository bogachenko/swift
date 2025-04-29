require("dotenv").config();
const hre = require("hardhat"),
	{
		ethers: ethers
	} = require("hardhat");
async function main() {
	const e = hre.network.name.toUpperCase();
	console.log(`\nNetwork: ${e}`);
	const a = getContractAddress(e);
	if(!a) throw new Error(`Contract address for ${e} not set in .env`);
	const r = ["0x1111111111111111111111111111111111111111", "0x2222222222222222222222222222222222222222", "0x3333333333333333333333333333333333333333", "0x4444444444444444444444444444444444444444", "0x5555555555555555555555555555555555555555", "0x6666666666666666666666666666666666666666", "0x7777777777777777777777777777777777777777", "0x8888888888888888888888888888888888888888", "0x9999999999999999999999999999999999999999", "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "0xcccccccccccccccccccccccccccccccccccccccc", "0xdddddddddddddddddddddddddddddddddddddddd", "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", "0xffffffffffffffffffffffffffffffffffffffff", "0x1234567890123456789012345678901234567890", "0x0123456789012345678901234567890123456789", "0xdEAD000000000000000042069420694206942069", "0x000000000000000000000000000000000000dEaD", "0x00000000000000000000045261D4Ee77acdb3286"],
		o = ethers.parseUnits("1", "wei"),
		t = await ethers.getContractAt("TransferSWIFT", a),
		[c] = await ethers.getSigners(),
		n = await t.taxFee();
	if(console.log(`Tax Fee: ${ethers.formatEther(n)} ETH`), 0n === n) throw new Error("Tax fee is not set (zero value)");
	if(await t.blacklist(c.address)) throw new Error("Sender is blacklisted");
	for(const e of r)
		if(await t.blacklist(e)) throw new Error(`Recipient ${e} is blacklisted`);
	const s = await t.extendedRecipients(c.address) ? 20 : 15;
	if(console.log(`Recipient limit: ${s}`), r.length > s) throw new Error(`Too many recipients (${r.length} > ${s})`);
	const d = o * BigInt(r.length) + n,
		f = await ethers.provider.getBalance(c.address);
	if(console.log(`\nSender: ${c.address}`), console.log(`Balance: ${ethers.formatEther(f)} ETH`), console.log(`Required: ${ethers.formatEther(d)} ETH`), f < d) throw new Error("Insufficient balance");
	console.log("\nSending transaction...");
	const i = await t.multiTransferETH(r, new Array(r.length).fill(o), {
		value: d
	});
	console.log("Waiting for confirmation...");
	const l = await i.wait();
	console.log("\nTransaction confirmed!"), console.log(`Block: ${l.blockNumber}`), console.log(`Transaction Hash: ${i.hash}`), console.log(`Gas used: ${l.gasUsed.toString()}`), console.log(`Transaction fee: ${ethers.formatEther(l.gasUsed*i.gasPrice)} ETH`)
}

function getContractAddress(e) {
	return process.env[`${e}_CONTRACT_ADDRESS`]
}
main().catch((e => {
	console.error("\nError:", e.message), process.exit(1)
}));