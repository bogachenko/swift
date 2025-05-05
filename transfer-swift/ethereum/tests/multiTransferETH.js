const hre = require("hardhat"),
	readline = require("readline"),
	rl = readline.createInterface({
		input: process.stdin,
		output: process.stdout
	}),
	question = e => new Promise((o => rl.question(e, o)));
function isValidEthAmount(e) {
	return !!/^-?\d*\.?\d+$/.test(e) && !e.startsWith("-")
}
async function main() {
	console.log("TransferSWIFT - ETH Multi-Transfer Script");
	try {
		const e = hre.network.name;
		console.log(`Using network: ${e}`);
		const {
			ethers: o
		} = hre;
		let t;
		switch(e) {
			case "mainnet":
				t = process.env.MAINNET_CONTRACT_ADDRESS;
				break;
			case "sepolia":
				t = process.env.SEPOLIA_CONTRACT_ADDRESS;
				break;
			case "holesky":
				t = process.env.HOLESKY_CONTRACT_ADDRESS;
				break;
			default:
				throw new Error(`Unsupported network: ${e}. Please use mainnet, sepolia, or holesky.`)
		}
		if(!t) throw new Error(`Contract address not found for ${e} network. Check your environment variables.`);
		const n = ["function multiTransferETH(address[] calldata recipients, uint256[] calldata amounts) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (uint256)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)"],
			[r] = await o.getSigners(),
			s = new o.Contract(t, n, r);
		console.log(`Connected with address: ${r.address}`);
		const a = await o.provider.getBalance(r.address);
		console.log(`Wallet balance: ${o.formatEther(a)} ETH`), console.log(`Contract address: ${t}`);
		try {
			await s.paused() && console.log("\n⚠️ WARNING: Contract is currently PAUSED! Transaction will fail. ⚠️\n")
		}
		catch (e) {
			console.log("Could not check if contract is paused.")
		}
		try {
			await s.isEmergencyStopped() && console.log("\n⚠️ WARNING: Contract EMERGENCY STOP is active! Transaction will fail. ⚠️\n")
		}
		catch (e) {
			console.log("Could not check if emergency stop is active.")
		}
		try {
			await s.blacklist(r.address) && console.log("\n⚠️ WARNING: Your address is blacklisted! Transaction will fail. ⚠️\n")
		}
		catch (e) {
			console.log("Could not check blacklist status.")
		}
		try {
			const e = await s.lastUsed(r.address),
				o = await s.rateLimitDuration(),
				t = Math.floor(Date.now() / 1e3),
				n = Number(e) + Number(o);
			if(n > t) {
				const e = n - t,
					o = Math.ceil(e / 60);
				console.log(`\n⚠️ WARNING: Rate limit in effect. You need to wait approximately ${o} minute(s) before sending another transaction. ⚠️\n`)
			}
		}
		catch (e) {
			console.log("Could not check rate limit status.")
		}
		let i, l = !1;
		try {
			l = await s.extendedRecipients(r.address);
			const e = l ? 20 : 15;
			console.log(`Recipient limit: ${e} addresses (${l?"Extended":"Standard"} limit)`)
		}
		catch (e) {
			console.log("Could not check extended recipients status. Assuming standard limit (15).")
		}
		try {
			i = await s.taxFee(), console.log(`Current tax fee: ${o.formatEther(i)} ETH`)
		}
		catch (e) {
			console.error("Error fetching tax fee:", e), console.log("Using default tax fee of 0.000001 ETH"), i = o.parseEther("0.000001")
		}
		const c = (await question("Enter recipient addresses (comma separated): ")).split(",").map((e => e.trim())),
			d = l ? 20 : 15;
		if(c.length > d) throw new Error(`Too many recipients. Your limit is ${d} addresses. You provided ${c.length} addresses.`);
		for(const e of c) {
			if(!o.isAddress(e)) throw new Error(`Invalid address format: ${e}`);
			try {
				await s.blacklist(e) && console.log(`\n⚠️ WARNING: Recipient ${e} is blacklisted! Transaction will fail. ⚠️\n`)
			}
			catch (e) {}
		}
		const u = (await question("Enter amounts in ETH (comma separated, matching the number of recipients): ")).split(",").map((e => e.trim()));
		for(let e = 0; e < u.length; e++)
			if(!isValidEthAmount(u[e])) throw new Error(`Invalid ETH amount format at position ${e+1}: "${u[e]}". Please use a valid number format (e.g., 0.01, 1.5, 0.000000000000000001).`);
		let m;
		try {
			m = u.map((e => o.parseEther(e)))
		}
		catch (e) {
			if(e.message.includes("invalid FixedNumber string value")) throw new Error("Invalid ETH amount format. Please check your input and ensure all values are valid numbers.");
			throw e
		}
		if(c.length !== m.length) throw new Error("The number of recipients must match the number of amounts");
		if(0 === c.length) throw new Error("At least one recipient is required");
		let f = i;
		for(const e of m) f += e;
		console.log("\nTransaction Summary:"), console.log("-------------------");
		for(let e = 0; e < c.length; e++) console.log(`${e+1}. ${c[e]}: ${o.formatEther(m[e])} ETH`);
		console.log(`Tax Fee: ${o.formatEther(i)} ETH`), console.log(`Total: ${o.formatEther(f)} ETH`);
		if("yes" !== (await question("\nConfirm transaction? (yes/no): ")).toLowerCase()) return console.log("Transaction cancelled"), void rl.close();
		if(a < f) throw new Error(`Insufficient balance. You have ${o.formatEther(a)} ETH but need ${o.formatEther(f)} ETH`);
		console.log("Sending transaction...");
		const h = await s.multiTransferETH(c, m, {
			value: f,
			gasLimit: 3e6
		});
		console.log(`Transaction sent! Hash: ${h.hash}`), console.log("Waiting for confirmation...");
		const g = await h.wait();
		console.log(`Transaction confirmed in block ${g.blockNumber}`), console.log(`Gas used: ${g.gasUsed.toString()}`)
	}
	catch (e) {
		if(console.error("Error:"), e.message && e.message.includes("invalid FixedNumber string value")) console.error("Invalid ETH amount format. Please ensure all amounts are valid numbers (e.g., 0.01, 1.5, 0.000000000000000001)."), console.error("Common issues:"), console.error("- Using commas instead of periods for decimal points"), console.error("- Including currency symbols (like ETH)"), console.error("- Using spaces or other non-numeric characters");
		else if(e.message && e.message.includes("execution reverted")) {
			const o = e.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
			console.error(`Transaction reverted: ${o}`)
		}
		else console.error(e.message || e)
	}
	finally {
		rl.close()
	}
}
main().then((() => process.exit(0))).catch((e => {
	console.error("Fatal error:", e), process.exit(1)
}));