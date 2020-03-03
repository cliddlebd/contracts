pragma solidity 0.5.16;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "../collectors/Privates.sol";
import "../collectors/Pools.sol";
import "../collectors/Groups.sol";
import "../Settings.sol";


/**
 * @title Validators Registry.
 * This contract keeps track of all the registered validators.
 * Only collectors can register validators.
 */
contract ValidatorsRegistry is Initializable {
    /**
    * Structure to store information about the validator.
    * @param depositAmount - validator deposit amount.
    * @param maintainerFee - fee to pay to the maintainer after withdrawal.
    * @param entityId - ID of the entity where the deposit was accumulated in.
    */
    struct Validator {
        uint256 depositAmount;
        uint256 maintainerFee;
        bytes32 entityId;
    }

    // Maps validator ID (hash of the public key) to the Validator information.
    mapping(bytes32 => Validator) public validators;

    // Address of the Pools contract.
    Pools private pools;

    // Address of the Privates contract.
    Privates private privates;

    // Address of the Groups contract.
    Groups private groups;

    // Address of the Settings contract.
    Settings private settings;

    // Checks whether the caller is the Collector contract.
    modifier onlyCollectors() {
        require(
            msg.sender == address(pools) || msg.sender == address(privates) || msg.sender == address(groups),
            "Permission denied."
        );
        _;
    }

    /**
    * Event for tracking registered validators.
    * @param entityId - ID of the entity where the deposit was accumulated.
    * @param pubKey - Validator's public key.
    * @param withdrawalCredentials - The withdrawal credentials used to perform withdrawal for this validator.
    * @param maintainerFee - Fee to pay to the maintainer after withdrawal.
    * @param minStakingDuration - The minimal staking duration of the Validator.
    * @param stakingDuration - Staking duration of the validator.
    * @param depositAmount - Validator's deposit amount.
    */
    event ValidatorRegistered(
        bytes32 entityId,
        bytes pubKey,
        bytes withdrawalCredentials,
        uint256 maintainerFee,
        uint256 minStakingDuration,
        uint256 stakingDuration,
        uint256 depositAmount
    );

    /**
    * Constructor for initializing the ValidatorsRegistry contract.
    * @param _pools - Address of the Pools contract.
    * @param _privates - Address of the Privates contract.
    * @param _groups - Address of the Groups contract.
    * @param _settings - Address of the Settings contract.
    */
    function initialize(Pools _pools, Privates _privates, Groups _groups, Settings _settings) public initializer {
        pools = _pools;
        privates = _privates;
        groups = _groups;
        settings = _settings;
    }

    /**
    * Function for registering validators.
    * Can only be called by collectors.
    * @param _pubKey - BLS public key of the validator, generated by the operator.
    * @param _entityId - ID of the entity the validator deposit was accumulated in.
    */
    function register(bytes calldata _pubKey, bytes32 _entityId) external onlyCollectors {
        bytes32 validatorId = keccak256(abi.encodePacked(_pubKey));
        require(validators[validatorId].entityId == "", "Public key has been already used.");

        Validator memory validator = Validator(
            settings.validatorDepositAmount(),
            settings.maintainerFee(),
            _entityId
        );
        validators[validatorId] = validator;
        emit ValidatorRegistered(
            validator.entityId,
            _pubKey,
            settings.withdrawalCredentials(),
            validator.maintainerFee,
            settings.minStakingDuration(),
            settings.stakingDurations(msg.sender),
            validator.depositAmount
        );
    }

    /**
    * Function for updating existing validators.
    * Can only be called by collectors.
    * @param _validatorId - ID of the Validator to update.
    * @param _newEntityId - ID of the new entity, the Validator should be updated to.
    */
    function update(bytes32 _validatorId, bytes32 _newEntityId) external onlyCollectors {
        Validator storage validator = validators[_validatorId];
        require(validator.depositAmount == settings.validatorDepositAmount(), "Validator deposit amount cannot be updated.");

        validator.entityId = _newEntityId;
        validator.maintainerFee = settings.maintainerFee();
    }
}
