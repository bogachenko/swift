const hre = require("hardhat"),
	readline = require("readline"),
	rl = readline.createInterface({
		input: process.stdin,
		output: process.stdout
	}),
	question = e => new Promise(t => rl.question(e, t));

function isValidTokenId(e) {
	return !!/^\d+$/.test(e)
}
async function main() {
	console.log("TransferSWIFT - Multiple ERC721 Multi-Transfer Script");
	try {
		let e = hre.network.name;
		console.log(`Using network: ${e}`);
		let {
			ethers: t
		} = hre, o;
		switch(e) {
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
		if(!o) throw Error(`Contract address not found for ${e} network. Check your environment variables.`);
		let n = ["function name() view returns (string)", "function symbol() view returns (string)", "function ownerOf(uint256 tokenId) view returns (address)", "function tokenURI(uint256 tokenId) view returns (string)", "function isApprovedForAll(address owner, address operator) view returns (bool)", "function setApprovalForAll(address operator, bool approved) returns (bool)", "function getApproved(uint256 tokenId) view returns (address)", "function approve(address to, uint256 tokenId) returns (bool)"],
			[r] = await t.getSigners(),
			a = new t.Contract(o, ["function multiTransferERC721(address token, address[] calldata recipients, uint256[] calldata tokenIds) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (uint256)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)", "function whitelistERC721(address) view returns (bool)"], r);
		console.log(`Connected with address: ${r.address}`);
		let i = await t.provider.getBalance(r.address);
		console.log(`Wallet balance: ${t.formatEther(i)} ETH`), console.log(`Contract address: ${o}`);
		try {
			let s = await a.paused();
			s && console.log("\n⚠️ WARNING: Contract is currently PAUSED! Transactions will fail. ⚠️\n")
		} catch (l) {
			console.log("Could not check if contract is paused.")
		}
		try {
			let c = await a.isEmergencyStopped();
			c && console.log("\n⚠️ WARNING: Contract EMERGENCY STOP is active! Transactions will fail. ⚠️\n")
		} catch (d) {
			console.log("Could not check if emergency stop is active.")
		}
		try {
			let f = await a.blacklist(r.address);
			f && console.log("\n⚠️ WARNING: Your address is blacklisted! Transactions will fail. ⚠️\n")
		} catch (u) {
			console.log("Could not check blacklist status.")
		}
		try {
			let g = await a.lastUsed(r.address),
				h = await a.rateLimitDuration(),
				p = Math.floor(Date.now() / 1e3),
				w = Number(g) + Number(h);
			w > p && console.log(`
⚠️ WARNING: Rate limit in effect. You need to wait approximately ${Math.ceil((w-p)/60)} minute(s) before sending another transaction. ⚠️
`)
		} catch (m) {
			console.log("Could not check rate limit status.")
		}
		let k = !1;
		try {
			k = await a.extendedRecipients(r.address);
			let T = k ? 20 : 15;
			console.log(`Recipient limit: ${T} addresses (${k?"Extended":"Standard"} limit)`)
		} catch (v) {
			console.log("Could not check extended recipients status. Assuming standard limit (15).")
		}
		let E;
		try {
			E = await a.taxFee(), console.log(`Current tax fee: ${t.formatEther(E)} ETH per recipient`)
		} catch (I) {
			console.error("Error fetching tax fee:", I), console.log("Using default tax fee of 0.000001 ETH"), E = t.parseEther("0.000001")
		}
		let b = await question("Enter recipient addresses (comma separated): "),
			y = b.split(",").map(e => e.trim()),
			C = k ? 20 : 15;
		if(y.length > C) throw Error(`Too many recipients. Your limit is ${C} addresses. You provided ${y.length} addresses.`);
		for(let N of y) {
			if(!t.isAddress(N)) throw Error(`Invalid address format: ${N}`);
			try {
				let A = await a.blacklist(N);
				A && console.log(`
⚠️ WARNING: Recipient ${N} is blacklisted! Transactions will fail. ⚠️
`)
			} catch ($) {}
		}
		let R = await question("Enter token IDs (comma separated, matching the number of recipients): "),
			S = R.split(",").map(e => e.trim());
		if(y.length !== S.length) throw Error("The number of recipients must match the number of token IDs");
		if(0 === y.length) throw Error("At least one recipient is required");
		for(let _ = 0; _ < S.length; _++)
			if(!isValidTokenId(S[_])) throw Error(`Invalid token ID format at position ${_+1}: "${S[_]}". Please use a valid integer.`);
		let x = E * BigInt(y.length);
		if(i < x) throw Error(`Insufficient ETH balance for fees. You have ${t.formatEther(i)} ETH but need at least ${t.formatEther(x)} ETH for fees`);
		let F = [],
			D = !0,
			H = BigInt(0);
		for(; D;) {
			let L = await question("\nEnter ERC721 token contract address: ");
			if(!t.isAddress(L)) throw Error(`Invalid contract address format: ${L}`);
			try {
				let W = await a.whitelistERC721(L);
				W || console.log(`
⚠️ WARNING: NFT Contract ${L} is NOT whitelisted! Transaction will fail. ⚠️
`)
			} catch (U) {
				console.log("Could not check if NFT contract is whitelisted.")
			}
			let O = new t.Contract(L, n, r),
				q, G;
			try {
				q = await O.name(), G = await O.symbol(), console.log(`
NFT Collection: ${q} (${G})`)
			} catch (Y) {
				console.log("Could not fetch NFT collection information. This might not be a valid ERC721 contract."), q = "Unknown Collection", G = "???"
			}
			let M = S.map(e => BigInt(e)),
				P = [],
				B = [];
			for(let V = 0; V < M.length; V++) try {
				let j = await O.ownerOf(M[V]);
				j.toLowerCase() === r.address.toLowerCase() ? P.push({
					tokenId: M[V],
					recipient: y[V],
					index: V
				}) : B.push({
					tokenId: M[V],
					owner: j,
					index: V
				})
			} catch (K) {
				console.log(`Could not check ownership of token ID ${M[V]}. It might not exist.`), B.push({
					tokenId: M[V],
					owner: "Unknown or non-existent",
					index: V
				})
			}
			if(B.length > 0) {
				for(let X of (console.log("\n⚠️ WARNING: You don't own the following tokens:"), B)) console.log(`Token ID ${X.tokenId}: Owned by ${X.owner}`);
				if(0 === P.length) {
					console.log("You don't own any of the specified tokens. Skipping this contract...");
					continue
				}
				console.log(`
Only ${P.length} out of ${M.length} tokens will be transferred.`);
				let z = await question("Continue with partial transfer? (yes/no): ");
				if("yes" !== z.toLowerCase()) {
					console.log("Skipping this contract...");
					continue
				}
			}
			let J = !1;
			try {
				J = await O.isApprovedForAll(r.address, o)
			} catch (Q) {
				console.log("Could not check approval status.")
			}
			let Z = [];
			if(!J)
				for(let ee of P) try {
					let et = await O.getApproved(ee.tokenId);
					et.toLowerCase() !== o.toLowerCase() && Z.push(ee)
				} catch (eo) {
					console.log(`Could not check approval for token ID ${ee.tokenId}.`), Z.push(ee)
				}
			if(!J && Z.length > 0) {
				console.log(`
Need to approve ${Z.length} tokens for transfer.`);
				let en = await question("Approve all tokens at once? (yes/no): ");
				if("yes" === en.toLowerCase()) try {
					console.log("Approving all tokens...");
					let er = await O.setApprovalForAll(o, !0);
					console.log(`Approval transaction sent! Hash: ${er.hash}`), console.log("Waiting for confirmation...");
					let ea = await er.wait();
					console.log(`Approval confirmed in block ${ea.blockNumber}`), J = !0
				} catch (ei) {
					console.error("Error approving all tokens:", ei), console.log("Will try individual approvals...")
				}
				if(!J)
					for(let es of Z) try {
						console.log(`Approving token ID ${es.tokenId}...`);
						let el = await O.approve(o, es.tokenId);
						console.log(`Approval transaction sent! Hash: ${el.hash}`);
						let ec = await el.wait();
						console.log(`Approval confirmed in block ${ec.blockNumber}`)
					} catch (ed) {
						console.error(`Error approving token ID ${es.tokenId}:`, ed);
						let ef = P.findIndex(e => e.tokenId === es.tokenId); - 1 !== ef && P.splice(ef, 1)
					}
			}
			if(0 === P.length) {
				console.log("No tokens left to transfer. Skipping this contract...");
				continue
			}
			let eu = P.map(e => e.recipient),
				eg = P.map(e => e.tokenId),
				eh = E * BigInt(eu.length);
			if(i < H + eh) {
				console.log(`
⚠️ WARNING: Insufficient ETH balance for fees. You have ${t.formatEther(i)} ETH but need ${t.formatEther(H+eh)} ETH for all fees`), console.log("Skipping this contract...");
				continue
			}
			console.log("\nNFT Transfer Summary:");
			for(let ep = 0; ep < eu.length; ep++) console.log(`${ep+1}. Token ID ${eg[ep]} to ${eu[ep]}`);
			console.log(`Total NFTs: ${eg.length}`), console.log(`Tax Fee: ${t.formatEther(eh)} ETH (${t.formatEther(E)} ETH per recipient)`);
			let ew = await question("\nConfirm this NFT transfer? (yes/no): ");
			if("yes" !== ew.toLowerCase()) {
				console.log("Skipping this contract...");
				continue
			}
			console.log("Sending transaction...");
			try {
				let em = await a.multiTransferERC721(L, eu, eg, {
					value: eh,
					gasLimit: 3e6
				});
				console.log(`Transaction sent! Hash: ${em.hash}`), console.log("Waiting for confirmation...");
				let ek = await em.wait();
				console.log(`Transaction confirmed in block ${ek.blockNumber}`), console.log(`Gas used: ${ek.gasUsed.toString()}`), F.push({
					collection: q,
					symbol: G,
					contractAddress: L,
					tokenIds: eg.map(e => e.toString()),
					recipients: eu.length,
					txHash: em.hash,
					blockNumber: ek.blockNumber
				}), H += eh
			} catch (eT) {
				if(console.error("Error sending transaction:", eT), eT.message && eT.message.includes("execution reverted")) {
					let ev = eT.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
					console.error(`Transaction reverted: ${ev}`)
				}
				console.log("Failed to send NFTs. Moving to next contract...")
			}
			let e9 = await question("\nDo you want to send NFTs from another ERC721 contract? (yes/no): ");
			D = "yes" === e9.toLowerCase()
		}
		F.length > 0 ? (console.log("\n=== Final Transaction Summary ==="), console.log(`Total NFT collections transferred: ${F.length}`), console.log(`Total ETH fees paid: ${t.formatEther(H)} ETH`), console.log("\nTransactions:"), F.forEach((e, t) => {
			console.log(`${t+1}. ${e.collection} (${e.symbol}): ${e.tokenIds.length} NFTs to ${e.recipients} recipients`), console.log(`   Token IDs: ${e.tokenIds.join(", ")}`), console.log(`   TX Hash: ${e.txHash}`), console.log(`   Block: ${e.blockNumber}`)
		}), console.log("\nAll transfers completed successfully!")) : console.log("\nNo NFTs were transferred.")
	} catch (eE) {
		if(console.error("Error:"), eE.message && eE.message.includes("execution reverted")) {
			let eI = eE.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
			console.error(`Transaction reverted: ${eI}`)
		} else console.error(eE.message || eE)
	} finally {
		rl.close()
	}
}
main().then(() => process.exit(0)).catch(e => {
	console.error("Fatal error:", e), process.exit(1)
});