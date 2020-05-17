pragma solidity 0.5.17;

import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/cryptography/ECDSA.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "../access/Operators.sol";
import "../validators/IValidatorRegistration.sol";
import "../validators/ValidatorsRegistry.sol";
import "../Deposits.sol";
import "../Settings.sol";

/**
 * @title PrivateIndividuals
 * PrivateIndividuals contract allows users to deposit the amount required to become a standalone validator
 * together with their own validator withdrawal key. The validator will be registered as soon as the validator
 * deposit data is approved by the user.
 */
contract PrivateIndividuals is Initializable {
    using Address for address payable;
    using SafeMath for uint256;
    using ECDSA for bytes32;

    /**
    * Structure for storing information about the private individuals deposit data.
    * @param publicKey - BLS public key of the validator, generated by the operator.
    * @param withdrawalCredentials - withdrawal credentials based on user withdrawal public key.
    * @param signature - BLS signature of the validator, generated by the operator.
    * @param amount - validator deposit amount.
    * @param depositDataRoot - hash tree root of the deposit data, generated by the operator.
    * @param submitted - indicates whether deposit data was already submitted.
    */
    struct ValidatorDeposit {
        bytes publicKey;
        bytes withdrawalCredentials;
        bytes signature;
        uint256 amount;
        bytes32 depositDataRoot;
        bool submitted;
    }

    // maps IDs of private individuals to the validator deposit data.
    mapping(bytes32 => ValidatorDeposit) public validatorDeposits;

    // total number of private individuals created.
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

    /**
    * Event for tracking added withdrawal public key by the user.
    * @param entityId - ID of the individual the deposit data was approved for.
    * @param withdrawalPublicKey - BLS public key to use for the validator withdrawal, submitted by the user.
    * @param withdrawalCredentials - withdrawal credentials based on user BLS public key.
    */
    event WithdrawalKeyAdded(
        bytes32 entityId,
        bytes withdrawalPublicKey,
        bytes withdrawalCredentials
    );

    /**
    * Event for tracking validator deposit data approvals by the user.
    * @param entityId - ID of the individual the deposit data was approved for.
    */
    event DepositDataApproved(bytes32 entityId);

    /**
    * Constructor for initializing the PrivateIndividuals contract.
    * @param _deposits - address of the Deposits contract.
    * @param _settings - address of the Settings contract.
    * @param _operators - address of the Operators contract.
    * @param _validatorRegistration - address of the VRC (deployed by Ethereum).
    * @param _validatorsRegistry - address of the ValidatorsRegistry contract.
    */
    function initialize(
        Deposits _deposits,
        Settings _settings,
        Operators _operators,
        IValidatorRegistration _validatorRegistration,
        ValidatorsRegistry _validatorsRegistry
    )
        public initializer
    {
        deposits = _deposits;
        settings = _settings;
        operators = _operators;
        validatorRegistration = _validatorRegistration;
        validatorsRegistry = _validatorsRegistry;
    }

    /**
    * Function for adding private individual deposits.
    * The deposit amount must be the same as the validator deposit amount.
    * The depositing will be disallowed in case `PrivateIndividuals` contract is paused in `Settings` contract.
    * @param _publicKey - BLS public key for performing validator withdrawal.
    * @param _recipient - address where canceled deposit amount will be sent.
    */
    function addDeposit(bytes calldata _publicKey, address payable _recipient) external payable {
        require(_recipient != address(0), "Invalid recipient address.");
        require(_publicKey.length == 48, "Invalid BLS withdrawal public key.");
        require(msg.value == settings.validatorDepositAmount(), "Invalid deposit amount.");
        require(!settings.pausedContracts(address(this)), "Depositing is currently disabled.");

        // register new private individual
        individualsCount++;
        bytes32 individualId = keccak256(abi.encodePacked(address(this), individualsCount));
        deposits.addDeposit(individualId, msg.sender, _recipient, msg.value);

        // create new deposit data
        ValidatorDeposit storage depositData = validatorDeposits[individualId];
        depositData.amount = msg.value;

        // calculate withdrawal credentials
        bytes memory withdrawalCredentials = abi.encodePacked(sha256(_publicKey));

        // set BLS withdrawal prefix
        withdrawalCredentials[0] = 0x00;
        depositData.withdrawalCredentials = withdrawalCredentials;
        emit WithdrawalKeyAdded(individualId, _publicKey, withdrawalCredentials);
    }

    /**
    * Function for canceling private individual deposits.
    * The deposit can only be canceled before it will be registered as a validator.
    * @param _individualId - ID of the individual the deposit belongs to.
    * @param _recipient - address where the canceled amount will be transferred (must be the same as when the deposit was made).
    */
    function cancelDeposit(bytes32 _individualId, address payable _recipient) external {
        uint256 depositAmount = deposits.getDeposit(_individualId, msg.sender, _recipient);
        require(depositAmount > 0, "The user does not have a deposit.");

        ValidatorDeposit memory depositData = validatorDeposits[_individualId];
        require(!depositData.submitted, "Cannot cancel deposit which has started staking.");

        // cancel individual deposit
        deposits.cancelDeposit(_individualId, msg.sender, _recipient, depositAmount);

        // remove validator deposit data
        delete validatorDeposits[_individualId];

        // transfer canceled amount to the recipient
        _recipient.sendValue(depositAmount);
    }

    /**
    * Function for approving operator signed validator deposit data by the user.
    * @param _publicKey - BLS public key of the validator, generated by the operator.
    * @param _signature - BLS signature of the validator, generated by the operator.
    * @param _depositDataRoot - hash tree root of the deposit data, generated by the operator.
    * @param _individualId - ID of the private individual the deposit belongs to.
    * @param _operatorSignature - ECDSA signature of the deposit data, signed by the operator.
    * @param _recipient - address where the canceled amount will be transferred (must be the same as when the deposit was made).
    */
    function approveDepositData(
        bytes calldata _publicKey,
        bytes calldata _signature,
        bytes32 _depositDataRoot,
        bytes32 _individualId,
        bytes calldata _operatorSignature,
        address _recipient
    )
        external
    {
        require(_publicKey.length == 48, "Invalid BLS public key.");
        require(_signature.length == 96, "Invalid BLS signature.");

        uint256 depositAmount = deposits.getDeposit(_individualId, msg.sender, _recipient);
        require(depositAmount > 0, "The user does not have a deposit.");

        ValidatorDeposit storage depositData = validatorDeposits[_individualId];
        require(depositData.publicKey.length == 0, "Deposit data has already been submitted.");

        // recreate the message that was signed by the operator
        bytes32 hash = keccak256(abi.encodePacked(_publicKey, _signature, _depositDataRoot, _individualId));
        require(operators.isOperator(hash.toEthSignedMessageHash().recover(_operatorSignature)), "Invalid operator signature.");

        // store deposit data for the operator to submit it to the VRC
        depositData.publicKey = _publicKey;
        depositData.depositDataRoot = _depositDataRoot;
        depositData.signature = _signature;

        emit DepositDataApproved(_individualId);
    }

    /**
    * Function for registering validators for the private individuals which are ready to start staking.
    * @param _individualId - ID of the private individual to register validator for.
    */
    function registerValidator(bytes32 _individualId) external {
        ValidatorDeposit storage depositData = validatorDeposits[_individualId];
        require(!depositData.submitted, "Validator already registered.");
        require(depositData.publicKey.length == 48, "Deposit data is not approved.");
        require(operators.isOperator(msg.sender), "Permission denied.");

        // mark deposit data as submitted
        depositData.submitted = true;

        // register validator
        validatorsRegistry.register(
            depositData.publicKey,
            depositData.withdrawalCredentials,
            _individualId,
            depositData.amount,
            0
        );
        validatorRegistration.deposit.value(depositData.amount)(
            depositData.publicKey,
            depositData.withdrawalCredentials,
            depositData.signature,
            depositData.depositDataRoot
        );
    }
}
