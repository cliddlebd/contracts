// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.7.5;
pragma abicoder v2;

/**
 * @dev Interface of the PoolValidators contract.
 */
interface IPoolValidators {
    /**
    * @dev Structure for storing operator data.
    * @param initializeMerkleRoot - validators registration initialization merkle root.
    * @param finalizeMerkleRoot - validators registration finalization merkle root.
    * @param locked - defines whether operator is currently locked.
    */
    struct Operator {
        bytes32 initializeMerkleRoot;
        bytes32 finalizeMerkleRoot;
        bool locked;
    }

    /**
    * @dev Structure for passing information about the validator deposit data.
    * @param operator - address of the operator.
    * @param withdrawalCredentials - withdrawal credentials used for generating the deposit data.
    * @param depositDataRoot - hash tree root of the deposit data, generated by the operator.
    * @param publicKey - BLS public key of the validator, generated by the operator.
    * @param signature - BLS signature of the validator, generated by the operator.
    */
    struct DepositData {
        address operator;
        bytes32 withdrawalCredentials;
        bytes32 depositDataRoot;
        bytes publicKey;
        bytes signature;
    }

    /**
    * @dev Enum to track status of the validator registration.
    * @param Uninitialized - validator has not been initialized.
    * @param Initialized - 1 ether deposit has been made to the ETH2 registration contract for the public key.
    * @param Finalized - 31 ether deposit has been made to the ETH2 registration contract for the public key.
    * @param Failed - 1 ether deposit has failed as it was assigned to the different from the protocol's withdrawal key.
    */
    enum ValidatorStatus { Uninitialized, Initialized, Finalized, Failed }

    /**
    * @dev Event for tracking new operators.
    * @param operator - address of the operator.
    * @param initializeMerkleRoot - validators initialization merkle root.
    * @param initializeMerkleProofs - validators initialization merkle proofs.
    * @param finalizeMerkleRoot - validators finalization merkle root.
    * @param finalizeMerkleProofs - validators finalization merkle proofs.
    */
    event OperatorAdded(
        address indexed operator,
        bytes32 indexed initializeMerkleRoot,
        string initializeMerkleProofs,
        bytes32 indexed finalizeMerkleRoot,
        string finalizeMerkleProofs
    );

    /**
    * @dev Event for tracking operator's collateral deposit.
    * @param operator - address of the operator.
    * @param collateral - amount deposited.
    */
    event CollateralDeposited(
        address indexed operator,
        uint256 collateral
    );

    /**
    * @dev Event for tracking operator's collateral withdrawals.
    * @param operator - address of the operator.
    * @param collateralRecipient - address of the collateral recipient.
    * @param collateral - amount withdrawn.
    */
    event CollateralWithdrawn(
        address indexed operator,
        address indexed collateralRecipient,
        uint256 collateral
    );

    /**
    * @dev Event for tracking operators' removals.
    * @param sender - address of the transaction sender.
    * @param operator - address of the operator.
    */
    event OperatorRemoved(
        address indexed sender,
        address indexed operator
    );

    /**
    * @dev Event for tracking operators' slashes.
    * @param operator - address of the operator.
    * @param publicKey - public key of the slashed validator.
    * @param refundedAmount - amount refunded to the pool.
    */
    event OperatorSlashed(
        address indexed operator,
        bytes publicKey,
        uint256 refundedAmount
    );

    /**
    * @dev Constructor for initializing the PoolValidators contract.
    * @param _admin - address of the contract admin.
    * @param _pool - address of the Pool contract.
    * @param _oracles - address of the Oracles contract.
    */
    function initialize(address _admin, address _pool, address _oracles) external;

    /**
    * @dev Function for retrieving the operator.
    * @param _operator - address of the operator to retrieve the data for.
    */
    function getOperator(address _operator) external view returns (bytes32, bytes32, bool);

    /**
    * @dev Function for retrieving the collateral of the operator.
    * @param operator - address of the operator to retrieve the collateral for.
    */
    function collaterals(address operator) external view returns (uint256);

    /**
    * @dev Function for retrieving registration status of the validator.
    * @param validatorId - hash of the validator public key to receive the status for.
    */
    function validatorStatuses(bytes32 validatorId) external view returns (ValidatorStatus);

    /**
    * @dev Function for adding new operator.
    * @param _operator - address of the operator to add or update.
    * @param initializeMerkleRoot - validators initialization merkle root.
    * @param initializeMerkleProofs - validators initialization merkle proofs.
    * @param finalizeMerkleRoot - validators finalization merkle root.
    * @param finalizeMerkleProofs - validators finalization merkle proofs.
    */
    function addOperator(
        address _operator,
        bytes32 initializeMerkleRoot,
        string memory initializeMerkleProofs,
        bytes32 finalizeMerkleRoot,
        string memory finalizeMerkleProofs
    ) external;

    /**
    * @dev Function for adding operator's collateral.
    * @param _operator - address of the operator to add a collateral for.
    */
    function depositCollateral(address _operator) external payable;

    /**
    * @dev Function for withdrawing operator's collateral. Can only be called when the operator was removed.
    * @param collateralRecipient - address of the collateral recipient.
    */
    function withdrawCollateral(address payable collateralRecipient) external;

    /**
    * @dev Function for removing operator. Can be called either by operator or admin.
    * @param _operator - address of the operator to remove.
    */
    function removeOperator(address _operator) external;

    /**
    * @dev Function for slashing the operator registration.
    * @param depositData - deposit data of the validator to slash.
    * @param merkleProof - an array of hashes to verify whether the deposit data is part of the initialize merkle root.
    */
    function slashOperator(DepositData memory depositData, bytes32[] memory merkleProof) external;

    /**
    * @dev Function for initializing the operator.
    * @param depositData - deposit data of the validator to initialize.
    * @param merkleProof - an array of hashes to verify whether the deposit data is part of the initialize merkle root.
    */
    function initializeValidator(DepositData memory depositData, bytes32[] memory merkleProof) external;

    /**
    * @dev Function for finalizing the operator.
    * @param depositData - deposit data of the validator to finalize.
    * @param merkleProof - an array of hashes to verify whether the deposit data is part of the finalize merkle root.
    */
    function finalizeValidator(DepositData memory depositData, bytes32[] memory merkleProof) external;
}
