const {
  BN,
  expectRevert,
  expectEvent,
  ether,
} = require('@openzeppelin/test-helpers');
const { upgrades } = require('hardhat');
const { deployAllContracts } = require('../../deployments');
const {
  preparePoolUpgrade,
  preparePoolUpgradeData,
  upgradePool,
} = require('../../deployments/collectors');
const { initialSettings } = require('../../deployments/settings');
const { deployAndInitializeVRC, vrcAbi } = require('../../deployments/vrc');
const {
  checkCollectorBalance,
  checkPoolTotalActivatingAmount,
  getDepositAmount,
} = require('../utils');
const { validatorParams } = require('./validatorParams');

const Pool = artifacts.require('Pool');
const Validators = artifacts.require('Validators');

const validatorDeposit = ether('32');
const withdrawalCredentials =
  '0x0072ea0cf49536e3c66c787f705186df9a4378083753ae9536d65b3ad7fcddc4';
const validator = validatorParams[0];

contract('Pool (register validator)', ([_, oracles, ...accounts]) => {
  let vrc, pool;
  let [admin, operator, sender1, sender2, other] = accounts;

  before(async () => {
    vrc = new web3.eth.Contract(vrcAbi, await deployAndInitializeVRC());
  });

  beforeEach(async () => {
    let {
      pool: poolContractAddress,
      validators: validatorsContractAddress,
    } = await deployAllContracts({
      initialAdmin: admin,
      vrcContractAddress: vrc.options.address,
    });
    pool = await Pool.at(poolContractAddress);

    let validators = await Validators.at(validatorsContractAddress);
    await validators.addOperator(operator, { from: admin });

    // register pool
    let amount1 = getDepositAmount({
      max: validatorDeposit.div(new BN(2)),
    });
    await pool.addDeposit({
      from: sender1,
      value: amount1,
    });

    let amount2 = validatorDeposit.sub(amount1);
    await pool.addDeposit({
      from: sender2,
      value: amount2,
    });

    const proxyAdmin = await upgrades.admin.getInstance();
    await pool.addAdmin(proxyAdmin.address, { from: admin });
    await pool.pause({ from: admin });
    const poolImplementation = await preparePoolUpgrade(poolContractAddress);
    const poolUpgradeData = await preparePoolUpgradeData(
      oracles,
      initialSettings.activationDuration,
      initialSettings.beaconActivatingAmount,
      initialSettings.minActivatingDeposit,
      initialSettings.minActivatingShare
    );
    await upgradePool(poolContractAddress, poolImplementation, poolUpgradeData);
    await pool.unpause({ from: admin });
  });

  it('fails to register validator with callers other than operator', async () => {
    await expectRevert(
      pool.registerValidator(validator, {
        from: other,
      }),
      'Pool: access denied'
    );
  });

  it('fails to register validator with paused pool', async () => {
    await pool.pause({ from: admin });
    expect(await pool.paused()).equal(true);

    await expectRevert(
      pool.registerValidator(validator, {
        from: other,
      }),
      'Pausable: paused'
    );
  });

  it('fails to register validator with used public key', async () => {
    await pool.setWithdrawalCredentials(withdrawalCredentials, {
      from: admin,
    });

    // create new deposit
    await pool.addDeposit({
      from: sender1,
      value: validatorDeposit,
    });

    // Register 1 validator
    await pool.registerValidator(validator, {
      from: operator,
    });

    // Register 2 validator with the same validator public key
    await expectRevert(
      pool.registerValidator(validator, {
        from: operator,
      }),
      'Validators: invalid public key'
    );
    await checkCollectorBalance(pool, validatorDeposit);
    await checkPoolTotalActivatingAmount(
      pool,
      new BN(initialSettings.beaconActivatingAmount).add(
        validatorDeposit.mul(new BN(2))
      )
    );
  });

  it('fails to register validator when validator deposit amount is not collect', async () => {
    await pool.setWithdrawalCredentials(withdrawalCredentials, {
      from: admin,
    });

    // Register 1 validator
    await pool.registerValidator(validator, {
      from: operator,
    });

    await expectRevert.unspecified(
      pool.registerValidator(validatorParams[1], {
        from: operator,
      })
    );

    await checkCollectorBalance(pool, new BN(0));
    await checkPoolTotalActivatingAmount(
      pool,
      new BN(initialSettings.beaconActivatingAmount).add(validatorDeposit)
    );
  });

  it('registers validator', async () => {
    await pool.setWithdrawalCredentials(withdrawalCredentials, {
      from: admin,
    });

    // one validator is already created
    let totalAmount = validatorDeposit;

    for (let i = 1; i < validatorParams.length; i++) {
      await pool.addDeposit({
        from: sender1,
        value: validatorDeposit,
      });
      totalAmount = totalAmount.add(validatorDeposit);
    }

    let totalActivatingAmount = new BN(
      initialSettings.beaconActivatingAmount
    ).add(totalAmount);

    // check balance increased correctly
    await checkCollectorBalance(pool, totalAmount);
    await checkPoolTotalActivatingAmount(pool, totalActivatingAmount);

    // register validators
    for (let i = 0; i < validatorParams.length; i++) {
      const receipt = await pool.registerValidator(validatorParams[i], {
        from: operator,
      });
      await expectEvent(receipt, 'ValidatorRegistered', {
        publicKey: validatorParams[i].publicKey,
        operator,
      });
      totalAmount = totalAmount.sub(validatorDeposit);
    }

    // check balance empty
    await checkCollectorBalance(pool);
    await checkPoolTotalActivatingAmount(pool, totalActivatingAmount);
  });
});
