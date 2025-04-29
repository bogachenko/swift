require("dotenv").config();
const hre = require("hardhat"),
	{
		ethers: ethers
	} = require("hardhat");
async function main() {
	const e = hre.network.name.toUpperCase();
	let a;
	console.log(`Network: ${e}`);
	const t = /^0x[a-fA-F0-9]{40}$/,
		r = Object.keys(process.env);
	if(a = process.env[`${e}_ERC20_TOKEN_ADDRESS`] || process.env[`${e}_ERC20_TOKEN_ADDRESS2`], !a)
		for(const e of r)
			if(t.test(process.env[e])) {
				a = process.env[e];
				break
			} if(!a || !ethers.isAddress(a)) throw new Error(`Valid ERC20 address not found for ${e}. Add ${e}_ERC20_TOKEN_ADDRESS or valid 0x... address to .env`);
	console.log(`Using ERC20 address: ${a}`);
	const o = process.env[`${e}_CONTRACT_ADDRESS`];
	if(!o || !ethers.isAddress(o)) throw new Error(`Invalid contract address for ${e}`);
	const s = ["0x1111111111111111111111111111111111111111", "0x2222222222222222222222222222222222222222", "0x3333333333333333333333333333333333333333", "0x4444444444444444444444444444444444444444", "0x5555555555555555555555555555555555555555", "0x6666666666666666666666666666666666666666", "0x7777777777777777777777777777777777777777", "0x8888888888888888888888888888888888888888", "0x9999999999999999999999999999999999999999", "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "0xcccccccccccccccccccccccccccccccccccccccc", "0xdddddddddddddddddddddddddddddddddddddddd", "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee", "0xffffffffffffffffffffffffffffffffffffffff", "0x1234567890123456789012345678901234567890", "0x0123456789012345678901234567890123456789", "0xdEAD000000000000000042069420694206942069", "0x000000000000000000000000000000000000dEaD", "0x00000000000000000000045261D4Ee77acdb3286"],
		n = ethers.parseUnits("1", 18);
	console.log(`Amount per recipient: ${ethers.formatUnits(n,18)} tokens`);
	const c = await ethers.getContractAt("TransferSWIFT", o),
		d = await ethers.getContractAt("IERC20", a),
		[i] = await ethers.getSigners();
	console.log(`Sender address: ${i.address}`);
	if(!await c.whitelistERC20(a)) throw new Error(`Token ${a} not whitelisted`);
	const f = await d.balanceOf(i.address),
		l = n * BigInt(s.length);
	if(console.log(`ERC20 Balance: ${ethers.formatUnits(f,18)}`), f < l) throw new Error(`Insufficient balance. Required: ${ethers.formatUnits(l,18)}, Available: ${ethers.formatUnits(f,18)}`);
	const b = await d.allowance(i.address, o);
	if(console.log(`Current allowance: ${ethers.formatUnits(b,18)}`), b < l) {
		console.log("Approving tokens...");
		const e = await d.approve(o, l);
		await e.wait(), console.log("Approval confirmed")
	}
	if(await c.blacklist(i.address)) throw new Error("Sender blacklisted");
	for(const e of s)
		if(await c.blacklist(e)) throw new Error(`Recipient ${e} blacklisted`);
	const h = await c.extendedRecipients(i.address) ? 20 : 15;
	if(console.log(`Recipient limit: ${h}`), s.length > h) throw new Error(`Too many recipients (${s.length} > ${h})`);
	const w = await c.taxFee(),
		E = await ethers.provider.getBalance(i.address);
	if(console.log(`ETH Balance: ${ethers.formatEther(E)}`), console.log(`Required fee: ${ethers.formatEther(w)}`), E < w) throw new Error(`Insufficient ETH. Required: ${ethers.formatEther(w)}, Available: ${ethers.formatEther(E)}`);
	console.log("\nInitiating transfers...");
	const g = await c.multiTransferERC20(a, s, new Array(s.length).fill(n), {
		value: w
	});
	console.log(`Transaction sent: ${g.hash}`);
	const $ = await g.wait();
	console.log("\nTransaction confirmed!"), console.log(`Block: ${$.blockNumber}`), console.log(`Gas used: ${$.gasUsed}`), console.log("Status: " + (1 === $.status ? "Success" : "Failed"))
}
main().catch((e => {
	console.error("\x1b[31mError:\x1b[0m", e.message), process.exit(1)
}));