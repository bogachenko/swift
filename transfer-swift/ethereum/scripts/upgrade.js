const { ethers, upgrades } = require("hardhat");

async function main() {
  const PROXY_ADDRESS = "0x2b279B09Df3c899Aecbd79478E468C84fCe38763";

  const TransferSWIFT = await ethers.getContractFactory("TransferSWIFT");
  await upgrades.upgradeProxy(PROXY_ADDRESS, TransferSWIFT);
  console.log("The contract has been updated!");
}

main();