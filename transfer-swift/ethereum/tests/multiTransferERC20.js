const hre = require("hardhat"),
	readline = require("readline"),
	rl = readline.createInterface({
		input: process.stdin,
		output: process.stdout
	}),
	question = e => new Promise((o => rl.question(e, o)));

function isValidAmount(e) {
	return !(!/^-?\d*\.?\d+$/.test(e) || e.startsWith("-"))
}
async function main() {
	console.log("TransferSWIFT - Multiple ERC20 transfer script");
	try {
		let e = hre.network.name;
		console.log(`Using network: ${e}`);
		let o, {
			ethers: t
		} = hre;
		switch (e) {
			case "mainnet":
				o = process.env.MAINNET_CONTRACT_ADDRESS;
				break;
			case "sepolia":
				o = process.env.SEPOLIA_CONTRACT_ADDRESS;
				break;
			case "holesky":
				o = process.env.HOLESKY_CONTRACT_ADDRESS;
				break;
			default:
				throw Error(`Unsupported network: ${e}. Please use mainnet, sepolia, or holesky.`)
		}
		if (!o) throw Error(`Contract address not found for ${e} network. Check your environment variables.`);
		let n = ["function name() view returns (string)", "function symbol() view returns (string)", "function decimals() view returns (uint8)", "function balanceOf(address) view returns (uint256)", "function allowance(address owner, address spender) view returns (uint256)", "function approve(address spender, uint256 amount) returns (bool)"],
			[s] = await t.getSigners(),
			r = new t.Contract(o, ["function multiTransferERC20(address token, address[] calldata recipients, uint256[] calldata amounts) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (bool)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)", "function whitelistERC20(address) view returns (bool)"], s);
		console.log(`Connected with address: ${s.address}`);
		let a = await t.provider.getBalance(s.address);
		console.log(`Wallet balance: ${t.formatEther(a)} ETH`), console.log(`Contract address: ${o}`);
		try {
			await r.paused() && console.log("\n⚠️ WARNING: Contract is currently PAUSED! Transactions will fail. ⚠️\n")
		} catch (e) {
			console.log("Could not check if contract is paused.")
		}
		try {
			await r.isEmergencyStopped() && console.log("\n⚠️ WARNING: Contract EMERGENCY STOP is active! Transactions will fail. ⚠️\n")
		} catch (e) {
			console.log("Could not check if emergency stop is active.")
		}
		try {
			await r.blacklist(s.address) && console.log("\n⚠️ WARNING: Your address is blacklisted! Transactions will fail. ⚠️\n")
		} catch (e) {
			console.log("Could not check blacklist status.")
		}
		try {
			let e = await r.lastUsed(s.address),
				o = await r.rateLimitDuration(),
				t = Math.floor(Date.now() / 1e3),
				n = Number(e) + Number(o);
			n > t && console.log(`\n⚠️ WARNING: Rate limit in effect. You need to wait approximately ${Math.ceil((n-t)/60)} minute(s) before sending another transaction. ⚠️\n`)
		} catch (e) {
			console.log("Could not check rate limit status.")
		}
		let i, l = !1;
		try {
			l = await r.extendedRecipients(s.address);
			let e = l ? 20 : 15;
			console.log(`Recipient limit: ${e} addresses (${l?"Extended":"Standard"} limit)`)
		} catch (e) {
			console.log("Could not check extended recipients status. Assuming standard limit (15).")
		}
		try {
			i = await r.taxFee(), console.log(`Current tax fee: ${t.formatEther(i)} ETH per recipient`)
		} catch (e) {
			console.error("Error fetching tax fee:", e), console.log("Using default tax fee of 0.000001 ETH"), i = t.parseEther("0.000001")
		}
		let c = (await question("Enter recipient addresses (comma separated): ")).split(",").map((e => e.trim())),
			d = l ? 20 : 15;
		if (c.length > d) throw Error(`Too many recipients. Your limit is ${d} addresses. You provided ${c.length} addresses.`);
		for (let e of c) {
			if (!t.isAddress(e)) throw Error(`Invalid address format: ${e}`);
			try {
				await r.blacklist(e) && console.log(`\n⚠️ WARNING: Recipient ${e} is blacklisted! Transactions will fail. ⚠️\n`)
			} catch (e) {}
		}
		let u = (await question("Enter amounts (comma separated, matching the number of recipients): ")).split(",").map((e => e.trim()));
		if (c.length !== u.length) throw Error("The number of recipients must match the number of amounts");
		if (0 === c.length) throw Error("At least one recipient is required");
		let f = i * BigInt(c.length);
		if (a < f) throw Error(`Insufficient ETH balance for fees. You have ${t.formatEther(a)} ETH but need at least ${t.formatEther(f)} ETH for fees`);
		let m = [],
			g = !0,
			h = BigInt(0);
		for (; g;) {
			let e = await question("\nEnter ERC20 token contract address: ");
			if (!t.isAddress(e)) throw Error(`Invalid token address format: ${e}`);
			try {
				await r.whitelistERC20(e) || console.log(`\n⚠️ WARNING: Token ${e} is NOT whitelisted! Transaction will fail. ⚠️\n`)
			} catch (e) {
				console.log("Could not check if token is whitelisted.")
			}
			let l, d, p, w, k, E = new t.Contract(e, n, s);
			try {
				l = await E.name(), d = await E.symbol(), p = await E.decimals(), console.log(`\nToken: ${l} (${d})`), console.log(`Decimals: ${p}`)
			} catch (e) {
				console.log("Could not fetch token information. This might not be a valid ERC20 token."), l = "Unknown Token", d = "???", p = 18
			}
			try {
				w = await E.balanceOf(s.address), console.log(`Your token balance: ${t.formatUnits(w,p)} ${d}`)
			} catch (e) {
				throw console.error("Error fetching token balance:", e), Error("Could not fetch token balance. Make sure this is a valid ERC20 token.")
			}
			for (let e = 0; e < u.length; e++)
				if (!isValidAmount(u[e])) throw Error(`Invalid amount format at position ${e+1}: "${u[e]}". Please use a valid number format (e.g., 0.01, 1.5).`);
			try {
				k = u.map((e => t.parseUnits(e, p)))
			} catch (e) {
				if (e.message.includes("invalid FixedNumber string value")) throw Error("Invalid amount format. Please check your input and ensure all values are valid numbers.");
				throw e
			}
			let $ = t.parseUnits("0", p);
			for (let e of k) $ += e;
			if (w < $) {
				console.log(`\n⚠️ WARNING: Insufficient token balance. You have ${t.formatUnits(w,p)} ${d} but need ${t.formatUnits($,p)} ${d}`), console.log("Skipping this token...");
				continue
			}
			let b = await E.allowance(s.address, o);
			if (console.log(`Current allowance: ${t.formatUnits(b,p)} ${d}`), b < $) {
				if (console.log(`\nNeed to approve ${t.formatUnits($,p)} ${d} to be spent by the contract`), "yes" !== (await question("Approve tokens? (yes/no): ")).toLowerCase()) {
					console.log("Skipping this token...");
					continue
				}
				try {
					console.log("Approving tokens...");
					let e = await E.approve(o, $);
					console.log(`Approval transaction sent! Hash: ${e.hash}`), console.log("Waiting for confirmation...");
					let t = await e.wait();
					console.log(`Approval confirmed in block ${t.blockNumber}`)
				} catch (e) {
					console.error("Error approving tokens:", e), console.log("Skipping this token...");
					continue
				}
			}
			console.log("\nToken Transfer Summary:");
			for (let e = 0; e < c.length; e++) console.log(`${e+1}. ${c[e]}: ${t.formatUnits(k[e],p)} ${d}`);
			if (console.log(`Total tokens: ${t.formatUnits($,p)} ${d}`), console.log(`Tax Fee: ${t.formatEther(f)} ETH (${t.formatEther(i)} ETH per recipient)`), a < h + f) console.log(`\n⚠️ WARNING: Insufficient ETH balance for fees. You have ${t.formatEther(a)} ETH but need ${t.formatEther(h+f)} ETH for all fees`), console.log("Skipping this token...");
			else if ("yes" === (await question("\nConfirm this token transfer? (yes/no): ")).toLowerCase()) {
				console.log("Sending transaction...");
				try {
					let o = await r.multiTransferERC20(e, c, k, {
						value: f,
						gasLimit: 3e6
					});
					console.log(`Transaction sent! Hash: ${o.hash}`), console.log("Waiting for confirmation...");
					let n = await o.wait();
					console.log(`Transaction confirmed in block ${n.blockNumber}`), console.log(`Gas used: ${n.gasUsed.toString()}`), m.push({
						token: d,
						tokenName: l,
						tokenAddress: e,
						recipients: c.length,
						totalAmount: t.formatUnits($, p),
						txHash: o.hash,
						blockNumber: n.blockNumber
					}), h += f
				} catch (e) {
					if (console.error("Error sending transaction:", e), e.message && e.message.includes("execution reverted")) {
						let o = e.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
						console.error(`Transaction reverted: ${o}`)
					}
					console.log("Failed to send this token. Moving to next token...")
				}
				g = "yes" === (await question("\nDo you want to send another ERC20 token? (yes/no): ")).toLowerCase()
			} else console.log("Skipping this token...")
		}
		m.length > 0 ? (console.log("\n=== Final Transaction Summary ==="), console.log(`Total tokens transferred: ${m.length}`), console.log(`Total ETH fees paid: ${t.formatEther(h)} ETH`), console.log("\nTransactions:"), m.forEach(((e, o) => {
			console.log(`${o+1}. ${e.tokenName} (${e.token}): ${e.totalAmount} tokens to ${e.recipients} recipients`), console.log(`   TX Hash: ${e.txHash}`), console.log(`   Block: ${e.blockNumber}`)
		})), console.log("\nAll transfers completed successfully!")) : console.log("\nNo tokens were transferred.")
	} catch (e) {
		if (console.error("Error:"), e.message && e.message.includes("invalid FixedNumber string value")) console.error("Invalid amount format. Please ensure all amounts are valid numbers (e.g., 0.01, 1.5)."), console.error("Common issues:"), console.error("- Using commas instead of periods for decimal points"), console.error("- Including currency symbols"), console.error("- Using spaces or other non-numeric characters");
		else if (e.message && e.message.includes("execution reverted")) {
			let o = e.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
			console.error(`Transaction reverted: ${o}`)
		} else console.error(e.message || e)
	} finally {
		rl.close()
	}
}
main().then((() => process.exit(0))).catch((e => {
	console.error("Fatal error:", e), process.exit(1)
}));