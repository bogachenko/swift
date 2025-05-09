const hre = require("hardhat");
const readline = require("readline");
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});
const question = (query) => new Promise((resolve) => rl.question(query, resolve));

function isValidAmount(amount) {
    if (!/^-?\d*\.?\d+$/.test(amount)) {
        return false;
    }
    if (amount.startsWith('-')) {
        return false;
    }
    return true;
}
async function main() {
    console.log("SWIFT Protocol - ERC20 multitransfer");
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
        const SWIFTProtocolAbi = ["function multiTransferERC20(address token, address[] calldata recipients, uint256[] calldata amounts) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (bool)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)", "function whitelistERC20(address) view returns (bool)"];
        const erc20Abi = ["function name() view returns (string)", "function symbol() view returns (string)", "function decimals() view returns (uint8)", "function balanceOf(address) view returns (uint256)", "function allowance(address owner, address spender) view returns (uint256)", "function approve(address spender, uint256 amount) returns (bool)"];
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
        const amountInput = await question("Enter amounts (comma separated, matching the number of recipients): ");
        const amountStrings = amountInput.split(",").map(amt => amt.trim());
        if (recipients.length !== amountStrings.length) {
            throw new Error("The number of recipients must match the number of amounts");
        }
        if (recipients.length === 0) {
            throw new Error("At least one recipient is required");
        }
        const totalEthFeePerToken = taxFee * BigInt(recipients.length);
        if (walletBalance < totalEthFeePerToken) {
            throw new Error(`Insufficient ETH balance for fees. You have ${ethers.formatEther(walletBalance)} ETH but need at least ${ethers.formatEther(totalEthFeePerToken)} ETH for fees`);
        }
        const transactions = [];
        let continueWithAnotherToken = true;
        let totalEthFeeUsed = BigInt(0);
        while (continueWithAnotherToken) {
            const tokenAddress = await question("\nEnter ERC20 token contract address: ");
            if (!ethers.isAddress(tokenAddress)) {
                throw new Error(`Invalid token address format: ${tokenAddress}`);
            }
            try {
                const isWhitelisted = await contract.whitelistERC20(tokenAddress);
                if (!isWhitelisted) {
                    console.log(`\n⚠️ WARNING: Token ${tokenAddress} is NOT whitelisted! Transaction will fail. ⚠️\n`);
                }
            } catch (error) {
                console.log("Could not check if token is whitelisted.");
            }
            const tokenContract = new ethers.Contract(tokenAddress, erc20Abi, signer);
            let tokenName, tokenSymbol, tokenDecimals;
            try {
                tokenName = await tokenContract.name();
                tokenSymbol = await tokenContract.symbol();
                tokenDecimals = await tokenContract.decimals();
                console.log(`\nToken: ${tokenName} (${tokenSymbol})`);
                console.log(`Decimals: ${tokenDecimals}`);
            } catch (error) {
                console.log("Could not fetch token information. This might not be a valid ERC20 token.");
                tokenName = "Unknown Token";
                tokenSymbol = "???";
                tokenDecimals = 18;
            }
            let tokenBalance;
            try {
                tokenBalance = await tokenContract.balanceOf(signer.address);
                console.log(`Your token balance: ${ethers.formatUnits(tokenBalance, tokenDecimals)} ${tokenSymbol}`);
            } catch (error) {
                console.error("Error fetching token balance:", error);
                throw new Error("Could not fetch token balance. Make sure this is a valid ERC20 token.");
            }
            for (let i = 0; i < amountStrings.length; i++) {
                if (!isValidAmount(amountStrings[i])) {
                    throw new Error(`Invalid amount format at position ${i+1}: "${amountStrings[i]}". Please use a valid number format (e.g., 0.01, 1.5).`);
                }
            }
            let amounts;
            try {
                amounts = amountStrings.map(amt => ethers.parseUnits(amt, tokenDecimals));
            } catch (error) {
                if (error.message.includes("invalid FixedNumber string value")) {
                    throw new Error(`Invalid amount format. Please check your input and ensure all values are valid numbers.`);
                }
                throw error;
            }
            let totalTokenAmount = ethers.parseUnits("0", tokenDecimals);
            for (const amount of amounts) {
                totalTokenAmount = totalTokenAmount + amount;
            }
            if (tokenBalance < totalTokenAmount) {
                console.log(`\n⚠️ WARNING: Insufficient token balance. You have ${ethers.formatUnits(tokenBalance, tokenDecimals)} ${tokenSymbol} but need ${ethers.formatUnits(totalTokenAmount, tokenDecimals)} ${tokenSymbol}`);
                console.log("Skipping this token...");
                continue;
            }
            const allowance = await tokenContract.allowance(signer.address, contractAddress);
            console.log(`Current allowance: ${ethers.formatUnits(allowance, tokenDecimals)} ${tokenSymbol}`);
            if (allowance < totalTokenAmount) {
                console.log(`\nNeed to approve ${ethers.formatUnits(totalTokenAmount, tokenDecimals)} ${tokenSymbol} to be spent by the contract`);
                const approveConfirmation = await question("Approve tokens? (yes/no): ");
                if (approveConfirmation.toLowerCase() !== "yes") {
                    console.log("Skipping this token...");
                    continue;
                }
                try {
                    console.log("Approving tokens...");
                    const approveTx = await tokenContract.approve(contractAddress, totalTokenAmount);
                    console.log(`Approval transaction sent! Hash: ${approveTx.hash}`);
                    console.log("Waiting for confirmation...");
                    const approveReceipt = await approveTx.wait();
                    console.log(`Approval confirmed in block ${approveReceipt.blockNumber}`);
                } catch (error) {
                    console.error("Error approving tokens:", error);
                    console.log("Skipping this token...");
                    continue;
                }
            }
            console.log("\nToken Transfer Summary:");
            for (let i = 0; i < recipients.length; i++) {
                console.log(`${i + 1}. ${recipients[i]}: ${ethers.formatUnits(amounts[i], tokenDecimals)} ${tokenSymbol}`);
            }
            console.log(`Total tokens: ${ethers.formatUnits(totalTokenAmount, tokenDecimals)} ${tokenSymbol}`);
            console.log(`Tax Fee: ${ethers.formatEther(totalEthFeePerToken)} ETH (${ethers.formatEther(taxFee)} ETH per recipient)`);
            if (walletBalance < totalEthFeeUsed + totalEthFeePerToken) {
                console.log(`\n⚠️ WARNING: Insufficient ETH balance for fees. You have ${ethers.formatEther(walletBalance)} ETH but need ${ethers.formatEther(totalEthFeeUsed + totalEthFeePerToken)} ETH for all fees`);
                console.log("Skipping this token...");
                continue;
            }
            const transferConfirmation = await question("\nConfirm this token transfer? (yes/no): ");
            if (transferConfirmation.toLowerCase() !== "yes") {
                console.log("Skipping this token...");
                continue;
            }
            console.log("Sending transaction...");
            try {
                const tx = await contract.multiTransferERC20(tokenAddress, recipients, amounts, {
                    value: totalEthFeePerToken,
                    gasLimit: 3000000
                });
                console.log(`Transaction sent! Hash: ${tx.hash}`);
                console.log("Waiting for confirmation...");
                const receipt = await tx.wait();
                console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
                console.log(`Gas used: ${receipt.gasUsed.toString()}`);
                transactions.push({
                    token: tokenSymbol,
                    tokenName,
                    tokenAddress,
                    recipients: recipients.length,
                    totalAmount: ethers.formatUnits(totalTokenAmount, tokenDecimals),
                    txHash: tx.hash,
                    blockNumber: receipt.blockNumber
                });
                totalEthFeeUsed = totalEthFeeUsed + totalEthFeePerToken;
            } catch (error) {
                console.error("Error sending transaction:", error);
                if (error.message && error.message.includes("execution reverted")) {
                    const revertReason = error.message.split("reason=")[1]?.split('"')[1] || "Unknown reason";
                    console.error(`Transaction reverted: ${revertReason}`);
                }
                console.log("Failed to send this token. Moving to next token...");
            }
            const anotherToken = await question("\nDo you want to send another ERC20 token? (yes/no): ");
            continueWithAnotherToken = anotherToken.toLowerCase() === "yes";
        }
        if (transactions.length > 0) {
            console.log("\n=== Final Transaction Summary ===");
            console.log(`Total tokens transferred: ${transactions.length}`);
            console.log(`Total ETH fees paid: ${ethers.formatEther(totalEthFeeUsed)} ETH`);
            console.log("\nTransactions:");
            transactions.forEach((tx, index) => {
                console.log(`${index + 1}. ${tx.tokenName} (${tx.token}): ${tx.totalAmount} tokens to ${tx.recipients} recipients`);
                console.log(` TX Hash: ${tx.txHash}`);
                console.log(` Block: ${tx.blockNumber}`);
            });
            console.log("\nAll transfers completed successfully!");
        } else {
            console.log("\nNo tokens were transferred.");
        }
    } catch (error) {
        console.error("Error:");
        if (error.message && error.message.includes("invalid FixedNumber string value")) {
            console.error("Invalid amount format. Please ensure all amounts are valid numbers (e.g., 0.01, 1.5).");
            console.error("Common issues:");
            console.error("- Using commas instead of periods for decimal points");
            console.error("- Including currency symbols");
            console.error("- Using spaces or other non-numeric characters");
        } else if (error.message && error.message.includes("execution reverted")) {
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