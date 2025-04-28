require("dotenv").config();
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
    // Конфигурация
    const ERC20_TOKEN_ADDRESS = "0xa960d72F83A8A163412520A778b437AC5211A501";
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
    const AMOUNT_PER_RECIPIENT = ethers.parseUnits("1", 18); // 1 токен (18 decimals)
    
    // Получение адреса контракта TransferSWIFT для текущей сети
    const network = hre.network.name.toUpperCase();
    const SWIFT_CONTRACT_ADDRESS = process.env[`${network}_CONTRACT_ADDRESS`];
    if (!SWIFT_CONTRACT_ADDRESS) {
        throw new Error(`Contract address for ${network} not set in .env`);
    }

    // Подключение к контрактам
    const swiftContract = await ethers.getContractAt("TransferSWIFT", SWIFT_CONTRACT_ADDRESS);
    const erc20 = await ethers.getContractAt("IERC20", ERC20_TOKEN_ADDRESS);
    const [sender] = await ethers.getSigners();

    // 1. Проверка, что токен в белом списке
    const isWhitelisted = await swiftContract.whitelistERC20(ERC20_TOKEN_ADDRESS);
    if (!isWhitelisted) {
        throw new Error("Token not whitelisted");
    }

    // 2. Проверка баланса ERC-20 у отправителя
    const tokenBalance = await erc20.balanceOf(sender.address);
    const requiredTokens = AMOUNT_PER_RECIPIENT * BigInt(RECIPIENTS.length);
    console.log(`ERC20 Balance: ${ethers.formatUnits(tokenBalance, 18)}`);
    if (tokenBalance < requiredTokens) {
        throw new Error("Insufficient ERC20 balance");
    }

    // 3. Проверка allowance
    const allowance = await erc20.allowance(sender.address, SWIFT_CONTRACT_ADDRESS);
    if (allowance < requiredTokens) {
        console.log("Approving tokens for TransferSWIFT...");
        const approveTx = await erc20.approve(SWIFT_CONTRACT_ADDRESS, requiredTokens);
        await approveTx.wait();
    }

    // 4. Проверка blacklist
    const isSenderBlacklisted = await swiftContract.blacklist(sender.address);
    if (isSenderBlacklisted) throw new Error("Sender is blacklisted");

    for (const recipient of RECIPIENTS) {
        if (await swiftContract.blacklist(recipient)) {
            throw new Error(`Recipient ${recipient} is blacklisted`);
        }
    }

    // 5. Проверка extendedRecipients
    const isExtended = await swiftContract.extendedRecipients(sender.address);
    const MAX_RECIPIENTS = isExtended ? 20 : 15;
    console.log(`Max recipients allowed: ${MAX_RECIPIENTS}`);

    if (RECIPIENTS.length > MAX_RECIPIENTS) {
        throw new Error(`Too many recipients (${RECIPIENTS.length} > ${MAX_RECIPIENTS})`);
    }

    // 6. Получение taxFee и проверка баланса ETH
    const taxFee = await swiftContract.taxFee();
    const ethBalance = await ethers.provider.getBalance(sender.address);
    console.log(`ETH Balance: ${ethers.formatEther(ethBalance)}`);
    console.log(`Required ETH (tax): ${ethers.formatEther(taxFee)}`);

    if (ethBalance < taxFee) {
        throw new Error("Insufficient ETH for tax fee");
    }

    // 7. Отправка транзакции
    console.log("\nSending ERC20 transfers...");
    const tx = await swiftContract.multiTransferERC20(
        ERC20_TOKEN_ADDRESS,
        RECIPIENTS,
        new Array(RECIPIENTS.length).fill(AMOUNT_PER_RECIPIENT),
        { value: taxFee }
    );

    const receipt = await tx.wait();
    console.log(`\nSuccess! Transaction hash: ${receipt.hash}`);
    console.log(`Gas used: ${receipt.gasUsed}`);
    console.log(`Block: ${receipt.blockNumber}`);
}

main().catch((error) => {
    console.error("Error:", error.message);
    process.exit(1);
});