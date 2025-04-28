require("dotenv").config();
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
    // Конфигурация
    const NFT_TRANSFERS = [
        {
            contract: "0x52e760181Cc167Ea3069e993d676274B9572b5B5",
            tokenId: 1,
            recipient: "0x1111111111111111111111111111111111111111"
        },
        {
            contract: "0x00000000001594C61dD8a6804da9AB58eD2483ce",
            tokenId: 473297086332864274837251139270280213876704458165n,
            recipient: "0x2222222222222222222222222222222222222222"
        }
    ];

    // Получение адреса TransferSWIFT для текущей сети
    const network = hre.network.name.toUpperCase();
    const SWIFT_CONTRACT_ADDRESS = process.env[`${network}_CONTRACT_ADDRESS`];
    if (!SWIFT_CONTRACT_ADDRESS) {
        throw new Error(`Contract address for ${network} not set in .env`);
    }

    // Подключение к контрактам
    const swiftContract = await ethers.getContractAt("TransferSWIFT", SWIFT_CONTRACT_ADDRESS);
    const [sender] = await ethers.getSigners();

    // 1. Проверка отправителя в blacklist
    const isSenderBlacklisted = await swiftContract.blacklist(sender.address);
    if (isSenderBlacklisted) throw new Error("Sender is blacklisted");

    // 2. Проверка получателей в blacklist
    for (const transfer of NFT_TRANSFERS) {
        if (await swiftContract.blacklist(transfer.recipient)) {
            throw new Error(`Recipient ${transfer.recipient} is blacklisted`);
        }
    }

    // 3. Проверка extendedRecipients (даже для 2 получателей)
    const isExtended = await swiftContract.extendedRecipients(sender.address);
    const MAX_RECIPIENTS = isExtended ? 20 : 15;
    console.log(`Max recipients per tx: ${MAX_RECIPIENTS}`);

    // 4. Проверка whitelist для NFT контрактов
    for (const transfer of NFT_TRANSFERS) {
        const isWhitelisted = await swiftContract.whitelistERC721(transfer.contract);
        if (!isWhitelisted) {
            throw new Error(`NFT contract ${transfer.contract} not whitelisted`);
        }
    }

    // 5. Проверка владения токенами
    for (const transfer of NFT_TRANSFERS) {
        const nftContract = await ethers.getContractAt("IERC721", transfer.contract);
        const owner = await nftContract.ownerOf(transfer.tokenId);
        if (owner !== sender.address) {
            throw new Error(`Not owner of token ${transfer.tokenId} in ${transfer.contract}`);
        }
    }

    // 6. Проверка и установка approve
    for (const transfer of NFT_TRANSFERS) {
        const nftContract = await ethers.getContractAt("IERC721", transfer.contract);
        const isApproved = await nftContract.isApprovedForAll(sender.address, SWIFT_CONTRACT_ADDRESS);
        
        if (!isApproved) {
            console.log(`Approving NFT contract ${transfer.contract}...`);
            const tx = await nftContract.setApprovalForAll(SWIFT_CONTRACT_ADDRESS, true);
            await tx.wait();
        }
    }

    // 7. Проверка taxFee и баланса ETH
    const taxFee = await swiftContract.taxFee();
    const ethBalance = await ethers.provider.getBalance(sender.address);
    console.log(`ETH Balance: ${ethers.formatEther(ethBalance)}`);
    console.log(`Required ETH (tax): ${ethers.formatEther(taxFee * BigInt(NFT_TRANSFERS.length))}`);

    if (ethBalance < taxFee * BigInt(NFT_TRANSFERS.length)) {
        throw new Error("Insufficient ETH for tax fees");
    }

    // 8. Отправка транзакций для каждого NFT
    for (const transfer of NFT_TRANSFERS) {
        console.log(`\nTransferring token ${transfer.tokenId} from ${transfer.contract} to ${transfer.recipient}...`);

        const tx = await swiftContract.multiTransferERC721(
            transfer.contract,
            [transfer.recipient],
            [transfer.tokenId],
            { value: taxFee }
        );

        const receipt = await tx.wait();
        console.log(`Success! Tx hash: ${receipt.hash}`);
        console.log(`Gas used: ${receipt.gasUsed}`);
        console.log(`Block: ${receipt.blockNumber}\n`);
    }
}

main().catch((error) => {
    console.error("Error:", error.message);
    process.exit(1);
});