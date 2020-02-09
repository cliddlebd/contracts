pragma solidity 0.5.16;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "../access/Admins.sol";
import "../collectors/Privates.sol";
import "../collectors/Pools.sol";
import "../Deposits.sol";
import "../validators/ValidatorsRegistry.sol";
import "../withdrawals/WalletsRegistry.sol";
import "../withdrawals/Withdrawals.sol";

/**
 * @title Validator Transfers.
 * This contract keeps track of validator transfers to other entities.
 * It should be used to match entities who would like to finish staking with entities who would like to be registered as new validators.
 * It allows for exiting entity users to withdraw their deposits and register their incomes as debts until Phase 2 release.
 * It will be used up to Phase 2 release.
 */
contract ValidatorTransfers is Initializable {
    using SafeMath for uint256;

    /**
    * Structure to store information about validator rewards debt to the entity.
    * @param userDebt - validator rewards debt to the users.
    * @param maintainerDebt - validator rewards debt to the maintainer.
    */
    struct ValidatorDebt {
        uint256 userDebt;
        uint256 maintainerDebt;
        bool resolved;
    }

    // Maps validator ID (hash of the public key) to its debt information.
    mapping(bytes32 => ValidatorDebt) public validatorDebts;

    // Maps collector entity ID to ID of the validator it belonged to.
    mapping(bytes32 => bytes32) public entityValidators;

    // Tracks whether user has withdrawn its deposit.
    mapping(bytes32 => bool) public withdrawnDeposits;

    // Tracks whether user has withdrawn its reward.
    mapping(bytes32 => bool) public withdrawnRewards;

    // Address of the transfers manager.
    address private manager;

    // Address of the Admins contract.
    Admins private admins;

    // Address of the Deposits contract.
    Deposits private deposits;

    // Address of the Pools contract.
    Pools private pools;

    // Address of the Privates contract.
    Privates private privates;

    // Address of the ValidatorsRegistry contract.
    ValidatorsRegistry private validatorsRegistry;

    // Address of the WalletsRegistry contract.
    WalletsRegistry private walletsRegistry;

    // Address of the Withdrawals contract.
    Withdrawals private withdrawals;

    /**
    * Event for tracking validator transfers.
    * @param validatorId - ID of the transferred validator.
    * @param collectorEntityId - ID of the collector's entity, the validator was transferred from.
    * @param userDebt - validator rewards debt to the users.
    * @param maintainerDebt - validator rewards debt to the maintainer.
    */
    event TransferRegistered(
        bytes32 validatorId,
        bytes32 collectorEntityId,
        uint256 userDebt,
        uint256 maintainerDebt
    );

    /**
    * Event for tracking resolved validator debt.
    * @param validatorId - ID of the validator, the debt was resolved for.
    */
    event DebtResolved(bytes32 validatorId);

    /**
    * Event for tracking user withdrawals.
    * @param sender - an address of the deposit sender.
    * @param withdrawer - an address of the deposit withdrawer.
    * @param depositAmount - withdrawn deposit amount.
    * @param rewardAmount - withdrawn reward amount.
    */
    event UserWithdrawn(
        address sender,
        address withdrawer,
        uint256 depositAmount,
        uint256 rewardAmount
    );

    /**
    * Event for tracking manager account updates.
    * @param manager - An address of the account which was assigned as a manager.
    * @param issuer - An address of the account which assigned a manager.
    */
    event ManagerUpdated(address manager, address indexed issuer);

    /**
    * Constructor for initializing the ValidatorTransfers contract.
    * @param _admins - Address of the Admins contract.
    * @param _deposits - Address of the Deposits contract.
    * @param _pools - Address of the Pools contract.
    * @param _privates - Address of the Privates contract.
    * @param _validatorsRegistry - Address of the Validators Registry contract.
    * @param _walletsRegistry - Address of the Wallets Registry contract.
    * @param _withdrawals - Address of the Withdrawals contract.
    * @param _manager - initial manager account.
    */
    function initialize(
        Admins _admins,
        Deposits _deposits,
        Pools _pools,
        Privates _privates,
        ValidatorsRegistry _validatorsRegistry,
        WalletsRegistry _walletsRegistry,
        Withdrawals _withdrawals,
        address _manager
    )
        public initializer
    {
        admins = _admins;
        deposits = _deposits;
        pools = _pools;
        privates = _privates;
        validatorsRegistry = _validatorsRegistry;
        walletsRegistry = _walletsRegistry;
        withdrawals = _withdrawals;
        manager = _manager;
    }

    /**
    * Function for registering validator transfers. Can only be called by collectors.
    * @param _validatorId - ID of the transferred validator.
    * @param _collectorEntityId - ID of the collector's entity, the validator was transferred from.
    * @param _userDebt - validator rewards debt to the users.
    * @param _maintainerDebt - validator rewards debt to the maintainer.
    */
    function registerTransfer(
        bytes32 _validatorId,
        bytes32 _collectorEntityId,
        uint256 _userDebt,
        uint256 _maintainerDebt
    )
        external payable
    {
//        require(transferRequests(_collectorEntityId), "Collector entity did not request transfer.");
        require(
            !walletsRegistry.assignedValidators(_validatorId),
            "Cannot register transfer for validator with assigned wallet."
        );
        require(msg.sender == address(pools) || msg.sender == address(privates), "Permission denied.");

        entityValidators[_collectorEntityId] = _validatorId;
        ValidatorDebt storage validatorDebt = validatorDebts[_validatorId];
        validatorDebt.userDebt = (validatorDebt.userDebt).add(_userDebt);
        validatorDebt.maintainerDebt = (validatorDebt.maintainerDebt).add(_maintainerDebt);
        emit TransferRegistered(
            _validatorId,
            _collectorEntityId,
            _userDebt,
            _maintainerDebt
        );
    }

    /**
    * Function for resolving validator debt. Can only be called by Withdrawals contract.
    * @param _validatorId - the ID of the validator to resolve debt for.
    */
    function resolveDebt(bytes32 _validatorId) external {
        require(msg.sender == address(withdrawals), "Permission denied.");

        ValidatorDebt storage validatorDebt = validatorDebts[_validatorId];
        require(!validatorDebt.resolved, "Validator debt was already resolved.");
        validatorDebt.resolved = true;
        emit DebtResolved(_validatorId);
    }

    /**
    * Function for updating a transfers manager account. Can only be called by an admin account.
    * @param _newManager - the new manager account.
    */
    function updateManager(address _newManager) external {
        require(admins.isAdmin(msg.sender), "Only admin users can update manager account.");
        manager = _newManager;
        emit ManagerUpdated(_newManager, msg.sender);
    }

    /**
    * Function for checking whether an account is a transfers manager.
    * @param _account - the account to check.
    */
    function isManager(address _account) public view returns (bool) {
        return _account == manager;
    }

    /**
    * Function for withdrawing deposits and rewards to the withdrawer address.
    * User reward is calculated based on the deposit amount.
    * @param _collectorEntityId - An ID of the collector entity, the deposit belongs to.
    * @param _withdrawer - An address of the account where reward + deposit will be transferred.
    * Must be the same as specified during deposit creation.
    */
    function withdraw(bytes32 _collectorEntityId, address payable _withdrawer) external {
        require(entityValidators[_collectorEntityId] != "", "Collector entity is not registered.");

        bytes32 userId = keccak256(abi.encodePacked(_collectorEntityId, msg.sender, _withdrawer));
        uint256 userDeposit = deposits.amounts(userId);
        require(userDeposit > 0, "User does not have a share in this collector entity.");

        uint256 depositWithdrawal;
        if (!withdrawnDeposits[userId]) {
            depositWithdrawal = userDeposit;
            withdrawnDeposits[userId] = true;
        }

        uint256 rewardWithdrawal;
        bytes32 validatorId = entityValidators[_collectorEntityId];
        ValidatorDebt memory validatorDebt = validatorDebts[validatorId];
        if (validatorDebt.resolved && !withdrawnRewards[userId]) {
            (uint256 validatorDepositAmount, ,) = validatorsRegistry.validators(validatorId);
            rewardWithdrawal = (validatorDebt.userDebt).mul(userDeposit).div(validatorDepositAmount);
            withdrawnRewards[userId] = true;
        }

        uint256 withdrawalAmount = depositWithdrawal.add(rewardWithdrawal);
        require(withdrawalAmount > 0, "Nothing to withdraw.");
        require(withdrawalAmount <= address(this).balance, "Withdrawal amount is bigger than balance.");

        emit UserWithdrawn(msg.sender, _withdrawer, depositWithdrawal, rewardWithdrawal);
        _withdrawer.transfer(withdrawalAmount);
    }

    /**
    * A fallback function to receive debt payments.
    */
    function() external payable {}
}
