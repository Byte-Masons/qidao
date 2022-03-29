async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');

  const wantAddress = '0x985976228a4685Ac4eCb0cfdbEeD72154659B6d9';
  const tokenName = 'MAI Concerto QiDao Crypt';
  const tokenSymbol = 'rf-BPT-MAIUSDC';
  const depositFee = 50;
  const tvlCap = ethers.constants.MaxUint256;
  const options = {gasPrice: 300000000000, gasLimit: 9000000};

  const vault = await Vault.deploy(wantAddress, tokenName, tokenSymbol, depositFee, tvlCap, options);

  await vault.deployed();
  console.log('Vault deployed to:', vault.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
