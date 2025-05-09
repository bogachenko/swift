const hre = require("hardhat");
const readline = require("readline");
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});
const question = (query) => new Promise((resolve) => rl.question(query, resolve));

function isValidTokenId(tokenId) {
    if (!/^\d+$/.test(tokenId)) {
        return false;
    }
    return true;
}
async function main() {
    console.log("SWIFT Protocol - ERC721 multitransfer");
    try {
        const network = hre.network.name;
        console.log(`Using network: ${network}`);
        const {
            ethers
        } = hre;
        let contractAddress;
        switch (network) {
            case "mainnet":
                contractAddress = process.env.MAINNET_CONTRACT_ADDRESS;
                break;
            case "sepolia":
                contractAddress = process.env.SEPOLIA_CONTRACT_ADDRESS;
                break;
            case "holesky":
                contractAddress = process.env.HOLESKY_CONTRACT_ADDRESS;
                break;
            default:
                throw new Error(`Unsupported network: ${network}. Please use mainnet, sepolia, or holesky.`);
        }
        if (!contractAddress) {
            throw new Error(`Contract address not found for ${network} network. Check your environment variables.`);
        }
        const SWIFTProtocolAbi = ["function multiTransferERC721(address token, address[] calldata recipients, uint256[] calldata tokenIds) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (uint256)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)", "function whitelistERC721(address) view returns (bool)"];
        const erc721Abi = ["function name() view returns (string)", "function symbol() view returns (string)", "function ownerOf(uint256 tokenId) view returns (address)", "function tokenURI(uint256 tokenId) view returns (string)", "function isApprovedForAll(address owner, address operator) view returns (bool)", "function setApprovalForAll(address operator, bool approved) returns (bool)", "function getApproved(uint256 tokenId) view returns (address)", "function approve(address to, uint256 tokenId) returns (bool)"];
        const [signer] = await ethers.getSigners();
        const contract = new ethers.Contract(contractAddress, SWIFTProtocolAbi, signer);
        console.log(`Connected with address: ${signer.address}`);
        const walletBalance = await ethers.provider.getBalance(signer.address);
        console.log(`Wallet balance: ${ethers.formatEther(walletBalance)} ETH`);
        console.log(`Contract address: ${contractAddress}`);
        try {
            const isPaused = await contract.paused();
            if (isPaused) {
                console.log("\n⚠️ WARNING: Contract is currently PAUSED! Transactions will fail. ⚠️\n");
            }
        } catch (error) {
            console.log("Could not check if contract is paused.");
        }
        try {
            const isEmergencyStopped = await contract.isEmergencyStopped();
            if (isEmergencyStopped) {
                console.log("\n⚠️ WARNING: Contract EMERGENCY STOP is active! Transactions will fail. ⚠️\n");
            }
        } catch (error) {
            console.log("Could not check if emergency stop is active.");
        }
        try {
            const isBlacklisted = await contract.blacklist(signer.address);
            if (isBlacklisted) {
                console.log("\n⚠️ WARNING: Your address is blacklisted! Transactions will fail. ⚠️\n");
            }
        } catch (error) {
            console.log("Could not check blacklist status.");
        }
        try {
            const lastUsedTime = await contract.lastUsed(signer.address);
            const rateLimitDuration = await contract.rateLimitDuration();
            const currentTimestamp = Math.floor(Date.now() / 1000);
            const nextAvailableTime = Number(lastUsedTime) + Number(rateLimitDuration);
            if (nextAvailableTime > currentTimestamp) {
                const waitTimeSeconds = nextAvailableTime - currentTimestamp;
                const waitTimeMinutes = Math.ceil(waitTimeSeconds / 60);
                console.log(`\n⚠️ WARNING: Rate limit in effect. You need to wait approximately ${waitTimeMinutes} minute(s) before sending another transaction. ⚠️\n`);
            }
        } catch (error) {
            console.log("Could not check rate limit status.");
        }
        let hasExtendedLimit = false;
        try {
            hasExtendedLimit = await contract.extendedRecipients(signer.address);
            const recipientLimit = hasExtendedLimit ? 20 : 15;
            console.log(`Recipient limit: ${recipientLimit} addresses (${hasExtendedLimit ? 'Extended' : 'Standard'} limit)`);
        } catch (error) {
            console.log("Could not check extended recipients status. Assuming standard limit (15).");
        }
        let taxFee;
        try {
            taxFee = await contract.taxFee();
            console.log(`Current tax fee: ${ethers.formatEther(taxFee)} ETH per recipient`);
        } catch (error) {
            console.error("Error fetching tax fee:", error);
            console.log("Using default tax fee of 0.000001 ETH");
            taxFee = ethers.parseEther("0.000001");
        }
        const recipientInput = await question("Enter recipient addresses (comma separated): ");
        const recipients = recipientInput.split(",").map(addr => addr.trim());
        const recipientLimit = hasExtendedLimit ? 20 : 15;
        if (recipients.length > recipientLimit) {
            throw new Error(`Too many recipients. Your limit is ${recipientLimit} addresses. You provided ${recipients.length} addresses.`);
        }
        for (const recipient of recipients) {
            if (!ethers.isAddress(recipient)) {
                throw new Error(`Invalid address format: ${recipient}`);
            }
            try {
                const isBlacklisted = await contract.blacklist(recipient);
                if (isBlacklisted) {
                    console.log(`\n⚠️ WARNING: Recipient ${recipient} is blacklisted! Transactions will fail. ⚠️\n`);
                }
            } catch (error) {}
        }
        const tokenIdInput = await question("Enter token IDs (comma separated, matching the number of recipients): ");
        const tokenIdStrings = tokenIdInput.split(",").map(id => id.trim());
        if (recipients.length !== tokenIdStrings.length) {
            throw new Error("The number of recipients must match the number of token IDs");
        }
        if (recipients.length === 0) {
            throw new Error("At least one recipient is required");
        }
        for (let i = 0; i < tokenIdStrings.length; i++) {
            if (!isValidTokenId(tokenIdStrings[i])) {
                throw new Error(`Invalid token ID format at position ${i+1}: "${tokenIdStrings[i]}". Please use a valid integer.`);
            }
        }
        const totalEthFeePerContract = taxFee * BigInt(recipients.length);
        if (walletBalance < totalEthFeePerContract) {
            throw new Error(`Insufficient ETH balance for fees. You have ${ethers.formatEther(walletBalance)} ETH but need at least ${ethers.formatEther(totalEthFeePerContract)} ETH for fees`);
        }
        const transactions = [];
        let continueWithAnotherContract = true;
        let totalEthFeeUsed = BigInt(0);
        while (continueWithAnotherContract) {
            const nftContractAddress = await question("\nEnter ERC721 token contract address: ");
            if (!ethers.isAddress(nftContractAddress)) {
                throw new Error(`Invalid contract address format: ${nftContractAddress}`);
            }
            try {
                const isWhitelisted = await contract.whitelistERC721(nftContractAddress);
                if (!isWhitelisted) {
                    console.log(`\n⚠️ WARNING: NFT Contract ${nftContractAddress} is NOT whitelisted! Transaction will fail. ⚠️\n`);
                }
            } catch (error) {
                console.log("Could not check if NFT contract is whitelisted.");
            }
            const nftContract = new ethers.Contract(nftContractAddress, erc721Abi, signer);
            let collectionName, collectionSymbol;
            try {
                collectionName = await nftContract.name();
                collectionSymbol = await nftContract.symbol();
                console.log(`\nNFT Collection: ${collectionName} (${collectionSymbol})`);
            } catch (error) {
                console.log("Could not fetch NFT collection information. This might not be a valid ERC721 contract.");
                collectionName = "Unknown Collection";
                collectionSymbol = "???";
            }
            const tokenIds = tokenIdStrings.map(id => BigInt(id));
            const ownedTokens = [];
            const notOwnedTokens = [];
            for (let i = 0; i < tokenIds.length; i++) {
                try {
                    const owner = await nftContract.ownerOf(tokenIds[i]);
                    if (owner.toLowerCase() === signer.address.toLowerCase()) {
                        ownedTokens.push({
                            tokenId: tokenIds[i],
                            recipient: recipients[i],
                            index: i
                        });
                    } else {
                        notOwnedTokens.push({
                            tokenId: tokenIds[i],
                            owner,
                            index: i
                        });
                    }
                } catch (error) {
                    console.log(`Could not check ownership of token ID ${tokenIds[i]}. It might not exist.`);
                    notOwnedTokens.push({
                        tokenId: tokenIds[i],
                        owner: "Unknown or non-existent",
                        index: i
                    });
                }
            }
            if (notOwnedTokens.length > 0) {
                console.log("\n⚠️ WARNING: You don't own the following tokens:");
                for (const token of notOwnedTokens) {
                    console.log(`Token ID ${token.tokenId}: Owned by ${token.owner}`);
                }
                if (ownedTokens.length === 0) {
                    console.log("You don't own any of the specified tokens. Skipping this contract...");
                    continue;
                }
                console.log(`\nOnly ${ownedTokens.length} out of ${tokenIds.length} tokens will be transferred.`);
                const continuePartial = await question("Continue with partial transfer? (yes/no): ");
                if (continuePartial.toLowerCase() !== "yes") {
                    console.log("Skipping this contract...");
                    continue;
                }
            }
            let isApprovedForAll = false;
            try {
                isApprovedForAll = await nftContract.isApprovedForAll(signer.address, contractAddress);
            } catch (error) {
                console.log("Could not check approval status.");
            }
            const needsApproval = [];
            if (!isApprovedForAll) {
                for (const token of ownedTokens) {
                    try {
                        const approved = await nftContract.getApproved(token.tokenId);
                        if (approved.toLowerCase() !== contractAddress.toLowerCase()) {
                            needsApproval.push(token);
                        }
                    } catch (error) {
                        console.log(`Could not check approval for token ID ${token.tokenId}.`);
                        needsApproval.push(token);
                    }
                }
            }
            if (!isApprovedForAll && needsApproval.length > 0) {
                console.log(`\nNeed to approve ${needsApproval.length} tokens for transfer.`);
                const approveAll = await question("Approve all tokens at once? (yes/no): ");
                if (approveAll.toLowerCase() === "yes") {
                    try {
                        console.log("Approving all tokens...");
                        const approveTx = await nftContract.setApprovalForAll(contractAddress, true);
                        console.log(`Approval transaction sent! Hash: ${approveTx.hash}`);
                        console.log("Waiting for confirmation...");
                        const approveReceipt = await approveTx.wait();
                        console.log(`Approval confirmed in block ${approveReceipt.blockNumber}`);
                        isApprovedForAll = true;
                    } catch (error) {
                        console.error("Error approving all tokens:", error);
                        console.log("Will try individual approvals...");
                    }
                }
                if (!isApprovedForAll) {
                    for (const token of needsApproval) {
                        try {
                            console.log(`Approving token ID ${token.tokenId}...`);
                            const approveTx = await nftContract.approve(contractAddress, token.tokenId);
                            console.log(`Approval transaction sent! Hash: ${approveTx.hash}`);
                            const approveReceipt = await approveTx.wait();
                            console.log(`Approval confirmed in block ${approveReceipt.blockNumber}`);
                        } catch (error) {
                            console.error(`Error approving token ID ${token.tokenId}:`, error);
                            const index = ownedTokens.findIndex(t => t.tokenId === token.tokenId);
                            if (index !== -1) {
                                ownedTokens.splice(index, 1);
                            }
                        }
                    }
                }
            }
            if (ownedTokens.length === 0) {
                console.log("No tokens left to transfer. Skipping this contract...");
                continue;
            }
            const transferRecipients = ownedTokens.map(token => token.recipient);
            const transferTokenIds = ownedTokens.map(token => token.tokenId);
            const transferFee = taxFee * BigInt(transferRecipients.length);
            if (walletBalance < totalEthFeeUsed + transferFee) {
                console.log(`\n⚠️ WARNING: Insufficient ETH balance for fees. You have ${ethers.formatEther(walletBalance)} ETH but need ${ethers.formatEther(totalEthFeeUsed + transferFee)} ETH for all fees`);
                console.log("Skipping this contract...");
                continue;
            }
            console.log("\nNFT Transfer Summary:");
            for (let i = 0; i < transferRecipients.length; i++) {
                console.log(`${i + 1}. Token ID ${transferTokenIds[i]} to ${transferRecipients[i]}`);
            }
            console.log(`Total NFTs: ${transferTokenIds.length}`);
            console.log(`Tax Fee: ${ethers.formatEther(transferFee)} ETH (${ethers.formatEther(taxFee)} ETH per recipient)`);
            const transferConfirmation = await question("\nConfirm this NFT transfer? (yes/no): ");
            if (transferConfirmation.toLowerCase() !== "yes") {
                console.log("Skipping this contract...");
                continue;
            }
            console.log("Sending transaction...");
            try {
                const tx = await contract.multiTransferERC721(nftContractAddress, transferRecipients, transferTokenIds, {
                    value: transferFee,
                    gasLimit: 3000000
                });
                console.log(`Transaction sent! Hash: ${tx.hash}`);
                console.log("Waiting for confirmation...");
                const receipt = await tx.wait();
                console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
                console.log(`Gas used: ${receipt.gasUsed.toString()}`);
                transactions.push({
                    collection: collectionName,
                    symbol: collectionSymbol,
                    contractAddress: nftContractAddress,
                    tokenIds: transferTokenIds.map(id => id.toString()),
                    recipients: transferRecipients.length,
                    txHash: tx.hash,
                    blockNumber: receipt.blockNumber
                });
                totalEthFeeUsed = totalEthFeeUsed + transferFee;
            } catch (error) {
                console.error("Error sending transaction:", error);
                if (error.message && error.message.includes("execution reverted")) {
                    const revertReason = error.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
                    console.error(`Transaction reverted: ${revertReason}`);
                }
                console.log("Failed to send NFTs. Moving to next contract...");
            }
            const anotherContract = await question("\nDo you want to send NFTs from another ERC721 contract? (yes/no): ");
            continueWithAnotherContract = anotherContract.toLowerCase() === "yes";
        }
        if (transactions.length > 0) {
            console.log("\n=== Final Transaction Summary ===");
            console.log(`Total NFT collections transferred: ${transactions.length}`);
            console.log(`Total ETH fees paid: ${ethers.formatEther(totalEthFeeUsed)} ETH`);
            console.log("\nTransactions:");
            transactions.forEach((tx, index) => {
                console.log(`${index + 1}. ${tx.collection} (${tx.symbol}): ${tx.tokenIds.length} NFTs to ${tx.recipients} recipients`);
                console.log(` Token IDs: ${tx.tokenIds.join(', ')}`);
                console.log(` TX Hash: ${tx.txHash}`);
                console.log(` Block: ${tx.blockNumber}`);
            });
            console.log("\nAll transfers completed successfully!");
        } else {
            console.log("\nNo NFTs were transferred.");
        }
    } catch (error) {
        console.error("Error:");
        if (error.message && error.message.includes("execution reverted")) {
            const revertReason = error.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
            console.error(`Transaction reverted: ${revertReason}`);
        } else {
            console.error(error.message || error);
        }
    } finally {
        rl.close();
    }
}
main().then(() => process.exit(0)).catch((error) => {
    console.error("Fatal error:", error);
    process.exit(1);
});