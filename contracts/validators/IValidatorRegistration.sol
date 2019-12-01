pragma solidity 0.5.13;

/**
 * @title VRC interface
 * Interface for sending validator's deposit to the registration contract (deployed by Ethereum).
 */
contract IValidatorRegistration {
    /**
    * Function for registering an Ethereum Validator.
    * @param pubkey - BLS public key of the validator, generated by the operator.
    * @param withdraw_credentials - Validator's withdrawal credentials. Received from Settings contract.
    * @param signature - BLS signature of the validator, generated by the operator.
    * @param deposit_data_root - hash tree root of the deposit data, generated by the operator.
    */
    function deposit(
        bytes memory pubkey,
        bytes memory withdraw_credentials,
        bytes memory signature,
        bytes32 deposit_data_root
    ) public payable;
}
