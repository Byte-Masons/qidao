async function main() {
  const vaultAddress = '0xf3327b00Bb53Bb72365E9B168526693ECeA0a1E4';
  const strategyAddress = '0xb3481031B8d3c06e0703508566aDAdF5556e4DCd';
  const options = {gasPrice: 300000000000, gasLimit: 9000000};

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
