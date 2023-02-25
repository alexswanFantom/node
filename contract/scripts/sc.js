const { ethers } = require("hardhat");
require("@nomiclabs/hardhat-etherscan");
async function main() {

  // Verify the contract after deploying
  await hre.run("verify:verify", {
    address: "0xA66d2DEBE4077380fA1C969E02d5B91bEE8d7206",
    constructorArguments: [],
    libraries: {
      IterableMapping: "0x6E129D428920e5F8dd12533BF8688C927c2fB38d"
    }
  });
}
// Call the main function and catch if there is any error
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });