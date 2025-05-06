const hre = require("hardhat");
const readline = require("readline");
const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
});
const question = (query) => new Promise((resolve) => rl.question(query, resolve));

function isValidEthAmount(amount) {
    if (!/^-?\d*\.?\d+$/.test(amount)) {
        return false;
    }
    if (amount.startsWith('-')) {
        return false;
    }
    return true;
}
async function main() {
    console.log("TransferSWIFT - ETH multitransfer");
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
        const abi = ["function multiTransferETH(address[] calldata recipients, uint256[] calldata amounts) external payable", "function taxFee() view returns (uint256)", "function blacklist(address) view returns (bool)", "function lastUsed(address) view returns (uint256)", "function rateLimitDuration() view returns (uint256)", "function extendedRecipients(address) view returns (bool)", "function paused() view returns (bool)", "function isEmergencyStopped() view returns (bool)"];
        const [signer] = await ethers.getSigners();
        const contract = new ethers.Contract(contractAddress, abi, signer);
        console.log(`Connected with address: ${signer.address}`);
        const walletBalance = await ethers.provider.getBalance(signer.address);
        console.log(`Wallet balance: ${ethers.formatEther(walletBalance)} ETH`);
        console.log(`Contract address: ${contractAddress}`);
        try {
            const isPaused = await contract.paused();
            if (isPaused) {
                console.log("\n⚠️ WARNING: Contract is currently PAUSED! Transaction will fail. ⚠️\n");
            }
        } catch (error) {
            console.log("Could not check if contract is paused.");
        }
        try {
            const isEmergencyStopped = await contract.isEmergencyStopped();
            if (isEmergencyStopped) {
                console.log("\n⚠️ WARNING: Contract EMERGENCY STOP is active! Transaction will fail. ⚠️\n");
            }
        } catch (error) {
            console.log("Could not check if emergency stop is active.");
        }
        try {
            const isBlacklisted = await contract.blacklist(signer.address);
            if (isBlacklisted) {
                console.log("\n⚠️ WARNING: Your address is blacklisted! Transaction will fail. ⚠️\n");
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
            console.log(`Current tax fee: ${ethers.formatEther(taxFee)} ETH`);
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
                    console.log(`\n⚠️ WARNING: Recipient ${recipient} is blacklisted! Transaction will fail. ⚠️\n`);
                }
            } catch (error) {}
        }
        const amountInput = await question("Enter amounts in ETH (comma separated, matching the number of recipients): ");
        const amountStrings = amountInput.split(",").map(amt => amt.trim());
        for (let i = 0; i < amountStrings.length; i++) {
            if (!isValidEthAmount(amountStrings[i])) {
                throw new Error(`Invalid ETH amount format at position ${i+1}: "${amountStrings[i]}". Please use a valid number format (e.g., 0.01, 1.5, 0.000000000000000001).`);
            }
        }
        let amounts;
        try {
            amounts = amountStrings.map(amt => ethers.parseEther(amt));
        } catch (error) {
            if (error.message.includes("invalid FixedNumber string value")) {
                throw new Error(`Invalid ETH amount format. Please check your input and ensure all values are valid numbers.`);
            }
            throw error;
        }
        if (recipients.length !== amounts.length) {
            throw new Error("The number of recipients must match the number of amounts");
        }
        if (recipients.length === 0) {
            throw new Error("At least one recipient is required");
        }
        let totalAmount = taxFee;
        for (const amount of amounts) {
            totalAmount = totalAmount + amount;
        }
        console.log("\nTransaction Summary:");
        for (let i = 0; i < recipients.length; i++) {
            console.log(`${i + 1}. ${recipients[i]}: ${ethers.formatEther(amounts[i])} ETH`);
        }
        console.log(`Tax Fee: ${ethers.formatEther(taxFee)} ETH`);
        console.log(`Total: ${ethers.formatEther(totalAmount)} ETH`);
        const confirmation = await question("\nConfirm transaction? (yes/no): ");
        if (confirmation.toLowerCase() !== "yes") {
            console.log("Transaction cancelled");
            rl.close();
            return;
        }
        if (walletBalance < totalAmount) {
            throw new Error(`Insufficient balance. You have ${ethers.formatEther(walletBalance)} ETH but need ${ethers.formatEther(totalAmount)} ETH`);
        }
        console.log("Sending transaction...");
        const tx = await contract.multiTransferETH(recipients, amounts, {
            value: totalAmount,
            gasLimit: 3000000
        });
        console.log(`Transaction sent! Hash: ${tx.hash}`);
        console.log("Waiting for confirmation...");
        const receipt = await tx.wait();
        console.log(`Transaction confirmed in block ${receipt.blockNumber}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
    } catch (error) {
        console.error("Error:");
        if (error.message && error.message.includes("invalid FixedNumber string value")) {
            console.error("Invalid ETH amount format. Please ensure all amounts are valid numbers (e.g., 0.01, 1.5, 0.000000000000000001).");
            console.error("Common issues:");
            console.error("- Using commas instead of periods for decimal points");
            console.error("- Including currency symbols (like ETH)");
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