const hre = require("hardhat");
async function main() {
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with:", deployer.address);
  const Factory = await hre.ethers.getContractFactory("TestCOIN721Batch");
  const contract = await Factory.deploy(deployer.address);
  await contract.waitForDeployment();
  console.log("Contract deployed to:", await contract.getAddress());
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});