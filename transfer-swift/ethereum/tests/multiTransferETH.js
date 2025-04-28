require("dotenv").config();
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
    const CONTRACT_ADDRESS = process.env.HOLESKY_CONTRACT_ADDRESS;
    if (!CONTRACT_ADDRESS) {
        throw new Error("HOLESKY_CONTRACT_ADDRESS not set in .env");
    }

    const RECIPIENTS = [
        "0x1111111111111111111111111111111111111111",
        "0x2222222222222222222222222222222222222222",
        "0x3333333333333333333333333333333333333333",
        "0x4444444444444444444444444444444444444444",
        "0x5555555555555555555555555555555555555555",
        "0x6666666666666666666666666666666666666666",
        "0x7777777777777777777777777777777777777777",
        "0x8888888888888888888888888888888888888888",
        "0x9999999999999999999999999999999999999999",
    ];

    const AMOUNT_PER_RECIPIENT = ethers.parseUnits("3", "wei"); // 3 wei
    const taxFee = await getTaxFee(CONTRACT_ADDRESS);
    const requiredValue = AMOUNT_PER_RECIPIENT * BigInt(RECIPIENTS.length) + taxFee;


    const contract = await ethers.getContractAt("TransferSWIFT", CONTRACT_ADDRESS);
    const [sender] = await ethers.getSigners();


    const balance = await ethers.provider.getBalance(sender.address);
    console.log(`Sender: ${sender.address}`);
    console.log(`Balance: ${ethers.formatEther(balance)} ETH`);
    console.log(`Required: ${ethers.formatEther(requiredValue)} ETH`);


    const tx = await contract.multiTransferETH(
        RECIPIENTS,
        new Array(RECIPIENTS.length).fill(AMOUNT_PER_RECIPIENT),
        { value: requiredValue }
    );

    console.log(`\nTransaction sent: ${tx.hash}`);
    await tx.wait();
    console.log("Success! Balances updated.");
}

async function getTaxFee(contractAddress) {
    const contract = await ethers.getContractAt("TransferSWIFT", contractAddress);
    return await contract.taxFee();
}

main().catch((error) => {
    console.error("Error:", error);
    process.exit(1);
});