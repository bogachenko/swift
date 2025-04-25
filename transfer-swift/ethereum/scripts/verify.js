const { run } = require("hardhat");

async function verify() {
  const proxyAddress = "0x2b279b09df3c899aecbd79478e468c84fce38763";
  await run("verify:verify", {
    address: proxyAddress,
    constructorArguments: [],
  });
}

verify().catch(console.error);