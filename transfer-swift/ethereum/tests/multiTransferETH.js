require("dotenv").config();
const hre = require("hardhat"),
	{
		ethers: ethers
	} = require("hardhat");
async function main() {
	const e = hre.network.name.toUpperCase(),
		a = process.env[`${e}_CONTRACT_ADDRESS`];
	if(!a || !/^0x[a-fA-F0-9]{40}$/.test(a)) throw new Error(`Invalid contract address for ${e}`);
	const r = [{
			address: "0x1111111111111111111111111111111111111111",
			amount: "1"
		}, {
			address: "0x2222222222222222222222222222222222222222",
			amount: "1"
		}, {
			address: "0x3333333333333333333333333333333333333333",
			amount: "1"
		}, {
			address: "0x4444444444444444444444444444444444444444",
			amount: "1"
		}, {
			address: "0x5555555555555555555555555555555555555555",
			amount: "1"
		}, {
			address: "0x6666666666666666666666666666666666666666",
			amount: "1"
		}, {
			address: "0x7777777777777777777777777777777777777777",
			amount: "1"
		}, {
			address: "0x8888888888888888888888888888888888888888",
			amount: "1"
		}, {
			address: "0x9999999999999999999999999999999999999999",
			amount: "1"
		}, {
			address: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			amount: "1"
		}, {
			address: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
			amount: "1"
		}, {
			address: "0xcccccccccccccccccccccccccccccccccccccccc",
			amount: "1"
		}, {
			address: "0xdddddddddddddddddddddddddddddddddddddddd",
			amount: "1"
		}, {
			address: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
			amount: "1"
		}, {
			address: "0xffffffffffffffffffffffffffffffffffffffff",
			amount: "1"
		}, {
			address: "0x1234567890123456789012345678901234567890",
			amount: "1"
		}, {
			address: "0x0123456789012345678901234567890123456789",
			amount: "1"
		}, {
			address: "0xdEAD000000000000000042069420694206942069",
			amount: "1"
		}, {
			address: "0x000000000000000000000000000000000000dEaD",
			amount: "1"
		}, {
			address: "0x00000000000000000000045261D4Ee77acdb3286",
			amount: "1"
		}],
		s = r.map((e => e.address)),
		d = r.map((e => ethers.parseUnits(e.amount, "wei"))),
		t = await ethers.getContractAt("TransferSWIFT", a),
		[n] = await ethers.getSigners(),
		o = await t.taxFee();
	if(await t.blacklist(n.address)) throw new Error("Sender blacklisted");
	for(const e of s)
		if(await t.blacklist(e)) throw new Error(`Recipient ${e} blacklisted`);
	const c = await t.extendedRecipients(n.address) ? 20 : 15;
	if(console.log(`\nNetwork: ${e}\nSender: ${n.address}\nContract: ${a}\nRecipient limit: ${c}`), s.length > c) throw new Error(`Too many recipients (${s.length} > ${c})`);
	const f = d.reduce(((e, a) => e + a), 0n),
		i = f + o,
		b = await ethers.provider.getBalance(n.address);
	if(console.log("\nRecipients:"), r.forEach(((e, a) => {
			console.log(`Transfer ${ethers.formatEther(d[a])} ETH → ${e.address}`)
		})), console.log(`\nTax Fee: ${ethers.formatEther(o)} ETH`), console.log(`Total value: ${ethers.formatEther(f)} ETH`), console.log(`Required (value + tax): ${ethers.formatEther(i)} ETH`), console.log(`Balance: ${ethers.formatEther(b)} ETH`), b < i) throw new Error("Insufficient balance");
	console.log("\nSending transaction...");
	const l = await t.multiTransferETH(s, d, {
			value: i
		}),
		m = await l.wait();
	console.log(`\nTransaction confirmed!\nBlock: ${m.blockNumber}\nHash: ${l.hash}\nGas used: ${m.gasUsed}\nFee: ${ethers.formatEther(m.gasUsed*l.gasPrice)} ETH`)
}
main().catch((e => {
	console.error("\nError:", e.message), process.exit(1)
}));