
const { ethers } = require("hardhat");
require("@nomiclabs/hardhat-etherscan");

async function main() {
  const POG = await ethers.getContractFactory("ATOM")
  const POGCONTRACT = await POG.deploy();

  await POGCONTRACT.deployed();
  console.log("POGCONTRACT deployed to:", POGCONTRACT.address);
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });