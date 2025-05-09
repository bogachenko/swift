const hre = require("hardhat");
async function main() {
	let e = hre.network.name,
		[t] = await hre.ethers.getSigners(),
		a = process.env.MY_WALLET,
		r = await hre.ethers.getContractFactory("TestNFT"),
		o = await r.deploy(a);
	await o.waitForDeployment();
	let n = await o.getAddress();
	console.log(`Deployed TestNFT to ${n} on network ${e}`)
}
main().catch(e => {
	console.error(e), process.exitCode = 1
});