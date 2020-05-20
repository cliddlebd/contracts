pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "../access/Operators.sol";
import "../validators/IValidatorRegistration.sol";
import "../validators/ValidatorsRegistry.sol";
import "../validators/ValidatorTransfers.sol";
import "../Deposits.sol";
import "../Settings.sol";

/**
 * @title Individuals
 * Individuals contract allows users to deposit the amount required to become a standalone validator.
 * The validator can be registered as soon as deposit is added.
 */
contract Individuals is Initializable {
    using Address for address payable;
    using SafeMath for uint256;

    // maps individual ID to its manager.
    mapping(bytes32 => address) public managers;

    // total number of individuals created.
    uint256 private individualsCount;

    // address of the Deposits contract.
    Deposits private deposits;

    // address of the Settings contract.
    Settings private settings;

    // address of the Operators contract.
    Operators private operators;

    // address of the VRC (deployed by Ethereum).
    IValidatorRegistration private validatorRegistration;

    // address of the Validators Registry contract.
    ValidatorsRegistry private validatorsRegistry;

    // address of the Validator Transfers contract.
    ValidatorTransfers private validatorTransfers;

    /**
    * Constructor for initializing the Individuals contract.
    * @param _deposits - address of the Deposits contract.
    * @param _settings - address of the Settings contract.
    * @param _operators - address of the Operators contract.
    * @param _validatorRegistration - address of the VRC (deployed by Ethereum).
    * @param _validatorsRegistry - address of the Validators Registry contract.
    * @param _validatorTransfers - address of the Validator Transfers contract.
    */
    function initialize(
        Deposits _deposits,
        Settings _settings,
        Operators _operators,
        IValidatorRegistration _validatorRegistration,
        ValidatorsRegistry _validatorsRegistry,
        ValidatorTransfers _validatorTransfers
    )
        public initializer
    {
        deposits = _deposits;
        settings = _settings;
        operators = _operators;
        validatorRegistration = _validatorRegistration;
        validatorsRegistry = _validatorsRegistry;
        validatorTransfers = _validatorTransfers;
    }

    /**
    * Function for adding individual deposits.
    * The deposit amount must be the same as target validator deposit amount.
    * The depositing will be disallowed in case `Individuals` contract is paused in `Settings` contract.
    * @param _recipient - address where funds will be sent after the withdrawal or if the deposit will be canceled.
    */
    function addDeposit(address _recipient) external payable {
        require(_recipient != address(0), "Invalid recipient address.");
        require(msg.value == settings.validatorDepositAmount(), "Invalid deposit amount.");
        require(!settings.pausedContracts(address(this)), "Depositing is currently disabled.");

        // Register new individual
        individualsCount++;
        bytes32 individualId = keccak256(abi.encodePacked(address(this), individualsCount));
        managers[individualId] = msg.sender;
        deposits.addDeposit(individualId, msg.sender, _recipient, msg.value);
    }

    /**
    * Function for canceling individual deposits.
    * The deposit can only be canceled before it will be registered as a validator.
    * @param _individualId - ID of the individual the deposit belongs to.
    * @param _recipient - address where the canceled amount will be transferred (must be the same as when the deposit was made).
    */
    function cancelDeposit(bytes32 _individualId, address payable _recipient) external {
        uint256 depositAmount = deposits.getDeposit(_individualId, msg.sender, _recipient);
        require(depositAmount > 0, "The user does not have a deposit.");
        require(managers[_individualId] != address(0), "Cannot cancel deposit which has started staking.");

        // cancel individual deposit
        deposits.cancelDeposit(_individualId, msg.sender, _recipient, depositAmount);
        delete managers[_individualId];

        // transfer canceled amount to the recipient
        _recipient.sendValue(depositAmount);
    }

    /**
    * Function for registering validators for the individuals which are ready to start staking.
    * @param _pubKey - BLS public key of the validator, generated by the operator.
    * @param _signature - BLS signature of the validator, generated by the operator.
    * @param _depositDataRoot - hash tree root of the deposit data, generated by the operator.
    * @param _individualId - ID of the individual to register validator for.
    */
    function registerValidator(
        bytes calldata _pubKey,
        bytes calldata _signature,
        bytes32 _depositDataRoot,
        bytes32 _individualId
    )
        external
    {
        address manager = managers[_individualId];
        require(manager != address(0), "Invalid individual ID.");
        require(operators.isOperator(msg.sender), "Permission denied.");

        // set allowance for future transfer
        validatorTransfers.setAllowance(_individualId, manager);

        // cleanup pending individual
        delete managers[_individualId];

        // register validator
        bytes memory withdrawalCredentials = settings.withdrawalCredentials();
        uint256 depositAmount = settings.validatorDepositAmount();
        validatorsRegistry.register(
            _pubKey,
            withdrawalCredentials,
            _individualId,
            depositAmount,
            settings.maintainerFee()
        );
        validatorRegistration.deposit.value(depositAmount)(
            _pubKey,
            withdrawalCredentials,
            _signature,
            _depositDataRoot
        );
    }

    /**
    * Function for transferring validator ownership to the new individual.
    * @param _validatorId - ID of the validator to transfer.
    * @param _validatorReward - validator current reward.
    * @param _individualId - ID of the individual to register validator for.
    * @param _managerSignature - ECDSA signature of the previous entity manager if such exists.
    */
    function transferValidator(
        bytes32 _validatorId,
        uint256 _validatorReward,
        bytes32 _individualId,
        bytes calldata _managerSignature
    )
        external
    {
        address manager = managers[_individualId];
        require(manager != address(0), "Invalid individual ID.");
        require(operators.isOperator(msg.sender), "Permission denied.");

        (uint256 depositAmount, uint256 prevMaintainerFee, bytes32 prevEntityId) = validatorsRegistry.validators(_validatorId);
        require(validatorTransfers.checkAllowance(prevEntityId, _managerSignature), "Validator transfer is not allowed.");

        (uint256 prevUserDebt, uint256 prevMaintainerDebt,) = validatorTransfers.validatorDebts(_validatorId);

        // set allowance for future transfer
        validatorTransfers.setAllowance(_individualId, manager);

        // cleanup pending individual
        delete managers[_individualId];

        // transfer validator to the new individual
        validatorsRegistry.update(_validatorId, _individualId, settings.maintainerFee());

        uint256 prevEntityReward = _validatorReward.sub(prevUserDebt).sub(prevMaintainerDebt);
        uint256 maintainerDebt = (prevEntityReward.mul(prevMaintainerFee)).div(10000);
        validatorTransfers.registerTransfer.value(depositAmount)(
            _validatorId,
            prevEntityId,
            prevEntityReward.sub(maintainerDebt),
            maintainerDebt
        );
    }
}
