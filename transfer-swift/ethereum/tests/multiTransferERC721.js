require("dotenv").config();
const hre = require("hardhat");
const { ethers } = require("hardhat");

async function main() {
    // Массив NFT передач
    const NFT_TRANSFERS = [
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 2,
            recipient: "0x2222222222222222222222222222222222222222"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 3,
            recipient: "0x3333333333333333333333333333333333333333"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 4,
            recipient: "0x4444444444444444444444444444444444444444"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 5,
            recipient: "0x5555555555555555555555555555555555555555"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 6,
            recipient: "0x6666666666666666666666666666666666666666"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 7,
            recipient: "0x7777777777777777777777777777777777777777"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 8,
            recipient: "0x8888888888888888888888888888888888888888"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 9,
            recipient: "0x9999999999999999999999999999999999999999"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 10,
            recipient: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 11,
            recipient: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 12,
            recipient: "0xcccccccccccccccccccccccccccccccccccccccc"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 13,
            recipient: "0xdddddddddddddddddddddddddddddddddddddddd"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 14,
            recipient: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 15,
            recipient: "0xffffffffffffffffffffffffffffffffffffffff"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 16,
            recipient: "0x1234567890123456789012345678901234567890"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 17,
            recipient: "0xdEAD000000000000000042069420694206942069"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 18,
            recipient: "0x000000000000000000000000000000000000dEaD"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 19,
            recipient: "0x00000000000000000000045261D4Ee77acdb3286"
        },
        {
            contract: "0xd03C5920eA3e0f69f62a761Fad94ebDf5Cea4440",
            tokenId: 20,
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
    if (!taxFee) {
        throw new Error("Tax fee is undefined or invalid");
    }

    // Убедимся, что taxFee можно безопасно преобразовать в BigNumber
    const totalTaxFee = ethers.BigNumber.from(taxFee.toString()).mul(NFT_TRANSFERS.length);  // Преобразуем в строку, чтобы избежать ошибок
    const ethBalance = await ethers.provider.getBalance(sender.address);
    console.log(`ETH Balance: ${ethers.formatEther(ethBalance)}`);
    console.log(`Required ETH (tax): ${ethers.formatEther(totalTaxFee)}`);

    if (ethBalance.lt(totalTaxFee)) {
        throw new Error("Insufficient ETH for tax fees");
    }

    // 8. Отправка транзакций для каждого NFT
    for (const transfer of NFT_TRANSFERS) {
        console.log(`\nTransferring token ${transfer.tokenId} from ${transfer.contract} to ${transfer.recipient}...`);

        const tx = await swiftContract.multiTransferERC721(
            transfer.contract,
            [transfer.recipient],
            [transfer.tokenId],
            { value: totalTaxFee }
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