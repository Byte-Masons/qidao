async function main() {
  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');

  const wantAddress = '0xA58F16498c288c357e28EE899873fF2b55D7C437';
  const tokenName = 'MAI3Pool-f QiDao Crypt';
  const tokenSymbol = 'rf-MAI3Pool-f';
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
