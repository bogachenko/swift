const hre = require("hardhat"),
	readline = require("readline"),
	rl = readline.createInterface({
		input: process.stdin,
		output: process.stdout
	}),
	question = e => new Promise((t => rl.question(e, t)));
function isValidEthAmount(e) {
	return !!/^-?\d*\.?\d+$/.test(e) && !e.startsWith("-")
}
async function main() {
	console.log("TransferSWIFT - Multiple ETH transfer script");
	try {
		let e = hre.network.name;
		console.log(`Using network: ${e}`);
		let t, {
			ethers: o
		} = hre;
		switch (e) {
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
				throw Error(`Unsupported network: ${e}. Please use mainnet, sepolia, or holesky.`)
		}
		if (!t) throw Error(`Contract address not found for ${e} network. Check your environment variables.`);
		let [r] = await o.getSigners(), n = new o.Contract(t, ["function multiTransferETH(address[] calldata recipients, uint256[] calldata amounts) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (uint256)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)"], r);
		console.log(`Connected with address: ${r.address}`);
		let a = await o.provider.getBalance(r.address);
		console.log(`Wallet balance: ${o.formatEther(a)} ETH`), console.log(`Contract address: ${t}`);
		try {
			await n.paused() && console.log("\n⚠️ WARNING: Contract is currently PAUSED! Transaction will fail. ⚠️\n")
		} catch (e) {
			console.log("Could not check if contract is paused.")
		}
		try {
			await n.isEmergencyStopped() && console.log("\n⚠️ WARNING: Contract EMERGENCY STOP is active! Transaction will fail. ⚠️\n")
		} catch (e) {
			console.log("Could not check if emergency stop is active.")
		}
		try {
			await n.blacklist(r.address) && console.log("\n⚠️ WARNING: Your address is blacklisted! Transaction will fail. ⚠️\n")
		} catch (e) {
			console.log("Could not check blacklist status.")
		}
		try {
			let e = await n.lastUsed(r.address),
				t = await n.rateLimitDuration(),
				o = Math.floor(Date.now() / 1e3),
				a = Number(e) + Number(t);
			a > o && console.log(`\n⚠️ WARNING: Rate limit in effect. You need to wait approximately ${Math.ceil((a-o)/60)} minute(s) before sending another transaction. ⚠️\n`)
		} catch (e) {
			console.log("Could not check rate limit status.")
		}
		let s, i = !1;
		try {
			i = await n.extendedRecipients(r.address);
			let e = i ? 20 : 15;
			console.log(`Recipient limit: ${e} addresses (${i?"Extended":"Standard"} limit)`)
		} catch (e) {
			console.log("Could not check extended recipients status. Assuming standard limit (15).")
		}
		try {
			s = await n.taxFee(), console.log(`Current tax fee: ${o.formatEther(s)} ETH`)
		} catch (e) {
			console.error("Error fetching tax fee:", e), console.log("Using default tax fee of 0.000001 ETH"), s = o.parseEther("0.000001")
		}
		let l = (await question("Enter recipient addresses (comma separated): ")).split(",").map((e => e.trim())),
			c = i ? 20 : 15;
		if (l.length > c) throw Error(`Too many recipients. Your limit is ${c} addresses. You provided ${l.length} addresses.`);
		for (let e of l) {
			if (!o.isAddress(e)) throw Error(`Invalid address format: ${e}`);
			try {
				await n.blacklist(e) && console.log(`\n⚠️ WARNING: Recipient ${e} is blacklisted! Transaction will fail. ⚠️\n`)
			} catch (e) {}
		}
		let d, u = (await question("Enter amounts in ETH (comma separated, matching the number of recipients): ")).split(",").map((e => e.trim()));
		for (let e = 0; e < u.length; e++)
			if (!isValidEthAmount(u[e])) throw Error(`Invalid ETH amount format at position ${e+1}: "${u[e]}". Please use a valid number format (e.g., 0.01, 1.5, 0.000000000000000001).`);
		try {
			d = u.map((e => o.parseEther(e)))
		} catch (e) {
			if (e.message.includes("invalid FixedNumber string value")) throw Error("Invalid ETH amount format. Please check your input and ensure all values are valid numbers.");
			throw e
		}
		if (l.length !== d.length) throw Error("The number of recipients must match the number of amounts");
		if (0 === l.length) throw Error("At least one recipient is required");
		let m = s;
		for (let e of d) m += e;
		console.log("\nTransaction Summary:");
		for (let e = 0; e < l.length; e++) console.log(`${e+1}. ${l[e]}: ${o.formatEther(d[e])} ETH`);
		if (console.log(`Tax Fee: ${o.formatEther(s)} ETH`), console.log(`Total: ${o.formatEther(m)} ETH`), "yes" !== (await question("\nConfirm transaction? (yes/no): ")).toLowerCase()) return console.log("Transaction cancelled"), void rl.close();
		if (a < m) throw Error(`Insufficient balance. You have ${o.formatEther(a)} ETH but need ${o.formatEther(m)} ETH`);
		console.log("Sending transaction...");
		let f = await n.multiTransferETH(l, d, {
			value: m,
			gasLimit: 3e6
		});
		console.log(`Transaction sent! Hash: ${f.hash}`), console.log("Waiting for confirmation...");
		let h = await f.wait();
		console.log(`Transaction confirmed in block ${h.blockNumber}`), console.log(`Gas used: ${h.gasUsed.toString()}`)
	} catch (e) {
		if (console.error("Error:"), e.message && e.message.includes("invalid FixedNumber string value")) console.error("Invalid ETH amount format. Please ensure all amounts are valid numbers (e.g., 0.01, 1.5, 0.000000000000000001)."), console.error("Common issues:"), console.error("- Using commas instead of periods for decimal points"), console.error("- Including currency symbols (like ETH)"), console.error("- Using spaces or other non-numeric characters");
		else if (e.message && e.message.includes("execution reverted")) {
			let t = e.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
			console.error(`Transaction reverted: ${t}`)
		} else console.error(e.message || e)
	} finally {
		rl.close()
	}
}
main().then((() => process.exit(0))).catch((e => {
	console.error("Fatal error:", e), process.exit(1)
}));