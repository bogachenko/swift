require("dotenv").config();
const hre = require("hardhat");
async function main() {
	var [e] = await hre.ethers.getSigners(), r = process.env.HOLESKY_ERC721_TOKEN_ADDRESS;
	if(!r) throw new Error("Contract address not found in .env (HOLESKY_ERC721_TOKEN_ADDRESS)");
	const t = await hre.ethers.getContractFactory("TestCOIN721Batch"),
		a = t.attach(r),
		s = await a.batchMint(e.address, 100);
	await s.wait(), console.log("100 tokens successfully mined to the address: ${deployer.address}")
}
main().catch(e => {
	console.error("Mint error:", e), process.exitCode = 1
});