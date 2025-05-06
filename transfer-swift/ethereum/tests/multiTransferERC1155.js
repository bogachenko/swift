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

function isValidAmount(amount) {
    if (!/^\d+$/.test(amount)) {
        return false;
    }
    if (parseInt(amount) <= 0) {
        return false;
    }
    return true;
}
async function main() {
    console.log("TransferSWIFT - ERC1155 multitransfer");
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
        const transferSwiftAbi = ["function multiTransferERC1155(address token, address[] calldata recipients, uint256[] calldata ids, uint256[] calldata amounts) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (uint256)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)", "function whitelistERC1155(address) view returns (bool)"];
        const erc1155Abi = ["function uri(uint256 id) view returns (string)", "function balanceOf(address account, uint256 id) view returns (uint256)", "function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids) view returns (uint256[])", "function isApprovedForAll(address account, address operator) view returns (bool)", "function setApprovalForAll(address operator, bool approved) returns (bool)"];
        const [signer] = await ethers.getSigners();
        const contract = new ethers.Contract(contractAddress, transferSwiftAbi, signer);
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
        for (let i = 0; i < tokenIdStrings.length; i++) {
            if (!isValidTokenId(tokenIdStrings[i])) {
                throw new Error(`Invalid token ID format at position ${i+1}: "${tokenIdStrings[i]}". Please use a valid integer.`);
            }
        }
        const amountInput = await question("Enter amounts (comma separated, matching the number of recipients): ");
        const amountStrings = amountInput.split(",").map(amt => amt.trim());
        if (recipients.length !== amountStrings.length) {
            throw new Error("The number of recipients must match the number of amounts");
        }
        if (recipients.length === 0) {
            throw new Error("At least one recipient is required");
        }
        for (let i = 0; i < amountStrings.length; i++) {
            if (!isValidAmount(amountStrings[i])) {
                throw new Error(`Invalid amount format at position ${i+1}: "${amountStrings[i]}". Please use a positive integer.`);
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
            const tokenContractAddress = await question("\nEnter ERC1155 token contract address: ");
            if (!ethers.isAddress(tokenContractAddress)) {
                throw new Error(`Invalid contract address format: ${tokenContractAddress}`);
            }
            try {
                const isWhitelisted = await contract.whitelistERC1155(tokenContractAddress);
                if (!isWhitelisted) {
                    console.log(`\n⚠️ WARNING: ERC1155 Contract ${tokenContractAddress} is NOT whitelisted! Transaction will fail. ⚠️\n`);
                }
            } catch (error) {
                console.log("Could not check if ERC1155 contract is whitelisted.");
            }
            const tokenContract = new ethers.Contract(tokenContractAddress, erc1155Abi, signer);
            const tokenIds = tokenIdStrings.map(id => BigInt(id));
            const amounts = amountStrings.map(amt => BigInt(amt));
            const validTransfers = [];
            const invalidTransfers = [];
            for (let i = 0; i < tokenIds.length; i++) {
                try {
                    const balance = await tokenContract.balanceOf(signer.address, tokenIds[i]);
                    if (balance >= amounts[i]) {
                        validTransfers.push({
                            tokenId: tokenIds[i],
                            amount: amounts[i],
                            recipient: recipients[i],
                            index: i
                        });
                    } else {
                        invalidTransfers.push({
                            tokenId: tokenIds[i],
                            amount: amounts[i],
                            balance,
                            recipient: recipients[i],
                            index: i
                        });
                    }
                } catch (error) {
                    console.log(`Could not check balance of token ID ${tokenIds[i]}.`);
                    invalidTransfers.push({
                        tokenId: tokenIds[i],
                        amount: amounts[i],
                        balance: "Unknown",
                        recipient: recipients[i],
                        index: i
                    });
                }
            }
            if (invalidTransfers.length > 0) {
                console.log("\n⚠️ WARNING: You don't have enough balance for the following transfers:");
                for (const transfer of invalidTransfers) {
                    console.log(`Token ID ${transfer.tokenId}: Requested ${transfer.amount}, Balance ${transfer.balance}`);
                }
                if (validTransfers.length === 0) {
                    console.log("You don't have enough balance for any of the specified transfers. Skipping this contract...");
                    continue;
                }
                console.log(`\nOnly ${validTransfers.length} out of ${tokenIds.length} transfers can be completed.`);
                const continuePartial = await question("Continue with partial transfer? (yes/no): ");
                if (continuePartial.toLowerCase() !== "yes") {
                    console.log("Skipping this contract...");
                    continue;
                }
            }
            let isApprovedForAll = false;
            try {
                isApprovedForAll = await tokenContract.isApprovedForAll(signer.address, contractAddress);
            } catch (error) {
                console.log("Could not check approval status.");
            }
            if (!isApprovedForAll) {
                console.log(`\nNeed to approve the contract to transfer your ERC1155 tokens.`);
                const approveConfirmation = await question("Approve tokens? (yes/no): ");
                if (approveConfirmation.toLowerCase() !== "yes") {
                    console.log("Skipping this contract...");
                    continue;
                }
                try {
                    console.log("Approving tokens...");
                    const approveTx = await tokenContract.setApprovalForAll(contractAddress, true);
                    console.log(`Approval transaction sent! Hash: ${approveTx.hash}`);
                    console.log("Waiting for confirmation...");
                    const approveReceipt = await approveTx.wait();
                    console.log(`Approval confirmed in block ${approveReceipt.blockNumber}`);
                    isApprovedForAll = true;
                } catch (error) {
                    console.error("Error approving tokens:", error);
                    console.log("Skipping this contract...");
                    continue;
                }
            }
            if (validTransfers.length === 0) {
                console.log("No tokens left to transfer. Skipping this contract...");
                continue;
            }
            const transferRecipients = validTransfers.map(transfer => transfer.recipient);
            const transferTokenIds = validTransfers.map(transfer => transfer.tokenId);
            const transferAmounts = validTransfers.map(transfer => transfer.amount);
            const transferFee = taxFee * BigInt(transferRecipients.length);
            if (walletBalance < totalEthFeeUsed + transferFee) {
                console.log(`\n⚠️ WARNING: Insufficient ETH balance for fees. You have ${ethers.formatEther(walletBalance)} ETH but need ${ethers.formatEther(totalEthFeeUsed + transferFee)} ETH for all fees`);
                console.log("Skipping this contract...");
                continue;
            }
            console.log("\nERC1155 Transfer Summary:");
            for (let i = 0; i < transferRecipients.length; i++) {
                console.log(`${i + 1}. Token ID ${transferTokenIds[i]}, Amount: ${transferAmounts[i]} to ${transferRecipients[i]}`);
            }
            console.log(`Total transfers: ${transferTokenIds.length}`);
            console.log(`Tax Fee: ${ethers.formatEther(transferFee)} ETH (${ethers.formatEther(taxFee)} ETH per recipient)`);
            const transferConfirmation = await question("\nConfirm this ERC1155 transfer? (yes/no): ");
            if (transferConfirmation.toLowerCase() !== "yes") {
                console.log("Skipping this contract...");
                continue;
            }
            console.log("Sending transaction...");
            try {
                const tx = await contract.multiTransferERC1155(tokenContractAddress, transferRecipients, transferTokenIds, transferAmounts, {
                    value: transferFee,
                    gasLimit: 3000000
                });
                console.log(`Transaction sent! Hash: ${tx.hash}`);
                console.log("Waiting for confirmation...");
                const receipt = await tx.wait();
                console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
                console.log(`Gas used: ${receipt.gasUsed.toString()}`);
                transactions.push({
                    contractAddress: tokenContractAddress,
                    tokenIds: transferTokenIds.map(id => id.toString()),
                    amounts: transferAmounts.map(amt => amt.toString()),
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
                console.log("Failed to send tokens. Moving to next contract...");
            }
            const anotherContract = await question("\nDo you want to send tokens from another ERC1155 contract? (yes/no): ");
            continueWithAnotherContract = anotherContract.toLowerCase() === "yes";
        }
        if (transactions.length > 0) {
            console.log("\n=== Final Transaction Summary ===");
            console.log(`Total ERC1155 contracts used: ${transactions.length}`);
            console.log(`Total ETH fees paid: ${ethers.formatEther(totalEthFeeUsed)} ETH`);
            console.log("\nTransactions:");
            transactions.forEach((tx, index) => {
                console.log(`${index + 1}. Contract: ${tx.contractAddress}`);
                console.log(` Transfers: ${tx.recipients} recipients`);
                const tokenTransfers = {};
                for (let i = 0; i < tx.tokenIds.length; i++) {
                    const tokenId = tx.tokenIds[i];
                    const amount = tx.amounts[i];
                    if (!tokenTransfers[tokenId]) {
                        tokenTransfers[tokenId] = 0n;
                    }
                    tokenTransfers[tokenId] += BigInt(amount);
                }
                console.log(` Token IDs and Amounts:`);
                for (const [tokenId, amount] of Object.entries(tokenTransfers)) {
                    console.log(` - Token ID ${tokenId}: ${amount} units`);
                }
                console.log(` TX Hash: ${tx.txHash}`);
                console.log(` Block: ${tx.blockNumber}`);
            });
            console.log("\nAll transfers completed successfully!");
        } else {
            console.log("\nNo tokens were transferred.");
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