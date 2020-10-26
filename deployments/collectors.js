const { ethers, upgrades } = require('@nomiclabs/buidler');

async function deployPool() {
  const Pool = await ethers.getContractFactory('Pool');
  const proxy = await upgrades.deployProxy(Pool, [], {
    initializer: false,
    unsafeAllowCustomTypes: true,
  });
  return proxy.address;
}

async function initializePool(
  poolContractAddress,
  stakingEthTokenContractAddress,
  settingsContractAddress,
  operatorsContractAddress,
  vrcContractAddress,
  validatorsContractAddress
) {
  let Pool = await ethers.getContractFactory('Pool');
  Pool = Pool.attach(poolContractAddress);

  return Pool.initialize(
    stakingEthTokenContractAddress,
    settingsContractAddress,
    operatorsContractAddress,
    vrcContractAddress,
    validatorsContractAddress
  );
}

async function deploySolos() {
  const Solos = await ethers.getContractFactory('Solos');
  const proxy = await upgrades.deployProxy(Solos, [], {
    unsafeAllowCustomTypes: true,
    initializer: false,
  });
  return proxy.address;
}

async function initializeSolos(
  solosContractAddress,
  settingsContractAddress,
  operatorsContractAddress,
  vrcContractAddress,
  validatorsContractAddress
) {
  let Solos = await ethers.getContractFactory('Solos');
  Solos = Solos.attach(solosContractAddress);

  return Solos.initialize(
    settingsContractAddress,
    operatorsContractAddress,
    vrcContractAddress,
    validatorsContractAddress
  );
}

module.exports = {
  deployPool,
  initializePool,
  deploySolos,
  initializeSolos,
};
