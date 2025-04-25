const { ethers, upgrades } = require("hardhat");
async function main() {
    const TransferSWIFT = await ethers.getContractFactory("TransferSWIFT");
    console.log("Deploying TransferSWIFT...");
    const transferSWIFT = await upgrades.deployProxy(TransferSWIFT, [], {
        initializer: "initialize",
    });
    await transferSWIFT.waitForDeployment();
    console.log("TransferSWIFT deployed to:", await transferSWIFT.getAddress());
}
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});