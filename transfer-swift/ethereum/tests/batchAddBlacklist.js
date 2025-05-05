const {
  ethers
} = require("hardhat");
const readline = require("readline").createInterface({
  input: process.stdin,
  output: process.stdout,
});
require("dotenv").config();
const ETH_ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;
async function main() {
  const network = hre.network.name;
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
          throw new Error(`Unsupported network: ${network}`);
  }
  if (!ETH_ADDRESS_REGEX.test(contractAddress)) {
      throw new Error("Invalid contract address in .env");
  }
  const contract = await ethers.getContractAt("TransferSWIFT", contractAddress);
  readline.question("Enter addresses to blacklist (comma-separated): ", async (input) => {
      const addresses = input.split(",").map((addr) => addr.trim());
      const invalidAddresses = addresses.filter((addr) => !ETH_ADDRESS_REGEX.test(addr));
      if (invalidAddresses.length > 0) {
          console.error("Invalid addresses:", invalidAddresses);
          readline.close();
          return;
      }
      const uniqueAddresses = [...new Set(addresses)];
      if (uniqueAddresses.length !== addresses.length) {
          console.error("Duplicate addresses detected");
          readline.close();
          return;
      }
      const statusCheck = await Promise.all(uniqueAddresses.map(async (addr) => ({
          address: addr,
          isBlacklisted: await contract.blacklist(addr),
      })));
      const alreadyBlacklisted = statusCheck.filter((item) => item.isBlacklisted).map((item) => item.address);
      if (alreadyBlacklisted.length > 0) {
          console.log("\x1b[33m%s\x1b[0m", "Already blacklisted addresses:");
          alreadyBlacklisted.forEach((addr) => console.log(`- ${addr}`));
      }
      const validAddresses = statusCheck.filter((item) => !item.isBlacklisted).map((item) => item.address);
      if (validAddresses.length === 0) {
          console.log("No addresses to blacklist");
          readline.close();
          return;
      }
      console.log("Addresses to blacklist:");
      validAddresses.forEach((addr) => console.log(`- ${addr}`));
      readline.question("Confirm (y/n): ", async (answer) => {
          if (answer.toLowerCase() !== "y") {
              console.log("Operation cancelled");
              readline.close();
              return;
          }
          try {
              const tx = await contract.batchAddBlacklist(validAddresses);
              console.log("Transaction sent:", tx.hash);
              await tx.wait();
              console.log("Transaction confirmed. Addresses blacklisted.");
              for (const addr of validAddresses) {
                  const isBlacklisted = await contract.blacklist(addr);
                  console.log(`${addr} ${isBlacklisted ? "\x1b[32mBLACKLISTED\x1b[0m" : "\x1b[31mNOT BLACKLISTED\x1b[0m"}`);
              }
          } catch (error) {
              console.error("\x1b[31mError:\x1b[0m", error.reason || error.message);
          } finally {
              readline.close();
          }
      });
  });
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});