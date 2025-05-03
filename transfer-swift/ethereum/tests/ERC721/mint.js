require("dotenv").config();
const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  const contractAddress = process.env.HOLESKY_ERC721_TOKEN_ADDRESS;

  if (!contractAddress) {
    throw new Error("Адрес контракта не найден в .env (HOLESKY_ERC721_TOKEN_ADDRESS)");
  }

  const Factory = await hre.ethers.getContractFactory("TestCOIN721Batch");
  const nft = Factory.attach(contractAddress);

  const tx = await nft.batchMint(deployer.address, 100);
  await tx.wait();

  console.log(`✅ 100 токенов успешно заминчено на адрес: ${deployer.address}`);
}

main().catch((err) => {
  console.error("❌ Ошибка минта:", err);
  process.exitCode = 1;
});
