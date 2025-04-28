require("dotenv").config();
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
    // Определение текущей сети
    const network = hre.network.name.toUpperCase();
    console.log(`\nRunning on network: ${network}`);

    // Получение адреса контракта для выбранной сети
    const contractAddress = getContractAddress(network);
    if (!contractAddress) {
        throw new Error(`Contract address for ${network} not set in .env`);
    }

    // Конфигурация получателей
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
        "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        "0xcccccccccccccccccccccccccccccccccccccccc",
        "0xdddddddddddddddddddddddddddddddddddddddd",
        "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
        "0xffffffffffffffffffffffffffffffffffffffff",
        "0x1234567890123456789012345678901234567890",
        "0x0123456789012345678901234567890123456789",
        "0xdEAD000000000000000042069420694206942069",
        "0x000000000000000000000000000000000000dEaD",
        "0x00000000000000000000045261D4Ee77acdb3286"
    ];
    const AMOUNT_PER_RECIPIENT = ethers.parseUnits("3", "wei");

    // Подключение к контракту
    const contract = await ethers.getContractAt("TransferSWIFT", contractAddress);
    const [sender] = await ethers.getSigners();

    // 1. Проверка текущего taxFee
    const taxFee = await contract.taxFee();
    console.log(`Current taxFee: ${ethers.formatEther(taxFee)} ETH`);
    if (taxFee === 0n) throw new Error("Tax fee is not set (zero value)");

    // 2. Проверка отправителя в blacklist
    const isSenderBlacklisted = await contract.blacklist(sender.address);
    if (isSenderBlacklisted) throw new Error("Sender is blacklisted");

    // 3. Проверка получателей в blacklist
    for (const recipient of RECIPIENTS) {
        const isBlacklisted = await contract.blacklist(recipient);
        if (isBlacklisted) throw new Error(`Recipient ${recipient} is blacklisted`);
    }

    // 4. Проверка extendedRecipients и лимита получателей
    const isExtended = await contract.extendedRecipients(sender.address);
    const MAX_RECIPIENTS = isExtended ? 20 : 15; // Лимит из контракта
    console.log(`\nSender is ${isExtended ? "EXTENDED" : "STANDARD"} (max recipients: ${MAX_RECIPIENTS})`);

    if (RECIPIENTS.length > MAX_RECIPIENTS) {
        throw new Error(`Too many recipients (${RECIPIENTS.length} > ${MAX_RECIPIENTS})`);
    }

    // Расчет требуемой суммы
    const requiredValue = AMOUNT_PER_RECIPIENT * BigInt(RECIPIENTS.length) + taxFee;

    // Проверка баланса
    const balance = await ethers.provider.getBalance(sender.address);
    console.log(`\nSender: ${sender.address}`);
    console.log(`Balance: ${ethers.formatEther(balance)} ETH`);
    console.log(`Required: ${ethers.formatEther(requiredValue)} ETH`);
    if (balance < requiredValue) throw new Error("Insufficient balance");

    // Отправка транзакции
    console.log("\nSending transaction...");
    const tx = await contract.multiTransferETH(
        RECIPIENTS,
        new Array(RECIPIENTS.length).fill(AMOUNT_PER_RECIPIENT),
        { value: requiredValue }
    );

    // Ожидание подтверждения и вывод деталей
    const txReceipt = await tx.wait();
    console.log(`\nTransaction confirmed in block: ${txReceipt.blockNumber}`);
    console.log(`Gas used: ${txReceipt.gasUsed.toString()}`);
    console.log(`Transaction fee: ${ethers.formatEther(txReceipt.gasUsed * tx.gasPrice)} ETH`);
}

// Получение адреса контракта из .env
function getContractAddress(network) {
    return process.env[`${network}_CONTRACT_ADDRESS`];
}

main().catch((error) => {
    console.error("\nError:", error.message);
    process.exit(1);
});