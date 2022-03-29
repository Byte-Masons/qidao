async function main() {
  const vaultAddress = '0xee60A1bD11f735b13812f9F76b259A1D9cC0f4F9';
  const strategyAddress = '0xEeE9De521a8B870E7bC808222A5Af202c709Ef9E';
  const options = {gasPrice: 200000000000, gasLimit: 9000000};

  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);

  await vault.initialize(strategyAddress, options);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
