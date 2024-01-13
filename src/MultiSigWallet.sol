// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
DESIGN OF THE CONTRACT:

Owner Management: The contract allows the specification of multiple owners. Validations are in place to ensure that 
                  owners are unique and valid addresses.

Transaction Structuring: Transactions are structured with key details like recipient address, value, data payload, 
                         execution status, and the number of confirmations received.

Mechanism: Submit Transactions: Any owner can submit a transaction.
           Confirm Transactions: Owners can confirm submitted transactions. A transaction requires a predefined number of confirmations before execution.
           Execute Transactions: Once the required number of confirmations is met, the transaction can be executed by an owner.
           Revoke Confirmations: Owners have the ability to revoke their confirmations from a transaction, provided it hasn't been executed yet.
           Transaction and Owner Tracking: The contract maintains a record of all transactions and the current owners.

Modifiers for Access and Status Control: Several modifiers are used to control function access (e.g., onlyOwner) and to check 
                                         the state of transactions (e.g., txExists, notExecuted).

Error Handling: Custom errors are defined for various failure conditions, such as when a non-owner tries to perform restricted actions, 
                or if a transaction doesn't meet the required conditions for execution.

Event Emission: Events are emitted for deposits, transaction submissions, confirmations, revocations, and executions, providing transparency 
                and traceability.

Reentrancy Protection: Inherits ReentrancyGuard from OpenZeppelin to protect transaction execution from reentrancy attacks.
*/

contract MultiSigWallet is ReentrancyGuard {
    //////////Errors////////////
    error NotOwner();
    error TxDoesNotExist();
    error TxAlreadyExecuted();
    error TxAlreadyConfirmed();
    error InvalidOwner();
    error OwnerNotUnique();
    error InvalidNumConfirmations();
    error CannotExecuteTx();
    error TxFailed();
    error TxNotConfirmed();

    ///////////Events////////////

    event Deposit(address indexed sender, uint256 amount, uint256 balance);
    event SubmitTransaction(
        address indexed owner, uint256 indexed txIndex, address indexed to, uint256 value, bytes data
    );
    event ConfirmTransaction(address indexed owner, uint256 indexed txIndex);
    event RevokeConfirmation(address indexed owner, uint256 indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint256 indexed txIndex);

    ////////State Variables/////////

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public numConfirmationsRequired;
    Transaction[] public transactions;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 numConfirmations;
    }

    // mapping from tx index => owner => bool
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    ///////////Modifiers//////////

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier txExists(uint256 _txIndex) {
        if (_txIndex >= transactions.length) revert TxDoesNotExist();
        _;
    }

    modifier notExecuted(uint256 _txIndex) {
        if (transactions[_txIndex].executed) revert TxAlreadyExecuted();
        _;
    }

    modifier notConfirmed(uint256 _txIndex) {
        if (isConfirmed[_txIndex][msg.sender]) revert TxAlreadyConfirmed();
        _;
    }

    //////////////constructor//////////////

    constructor(address[] memory _owners, uint256 _numConfirmationsRequired) {
        if (_owners.length == 0) revert InvalidOwner();
        if (_numConfirmationsRequired == 0 || _numConfirmationsRequired > _owners.length) {
            revert InvalidNumConfirmations();
        }

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            if (owner == address(0)) revert InvalidOwner();
            if (isOwner[owner]) revert OwnerNotUnique();

            isOwner[owner] = true;
            owners.push(owner);
        }

        numConfirmationsRequired = _numConfirmationsRequired;
    }

    ///////////Functions/////////////

    function submitTransaction(address _to, uint256 _value, bytes memory _data) public onlyOwner {
        uint256 txIndex = transactions.length;

        transactions.push(Transaction({to: _to, value: _value, data: _data, executed: false, numConfirmations: 0}));

        emit SubmitTransaction(msg.sender, txIndex, _to, _value, _data);
    }

    function confirmTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        notConfirmed(_txIndex)
    {
        Transaction storage transaction = transactions[_txIndex];
        transaction.numConfirmations += 1;
        isConfirmed[_txIndex][msg.sender] = true;

        emit ConfirmTransaction(msg.sender, _txIndex);
    }

    function executeTransaction(uint256 _txIndex)
        public
        onlyOwner
        txExists(_txIndex)
        notExecuted(_txIndex)
        nonReentrant
    {
        Transaction storage transaction = transactions[_txIndex];

        if (transaction.numConfirmations < numConfirmationsRequired) revert CannotExecuteTx();

        transaction.executed = true;

        (bool success,) = transaction.to.call{value: transaction.value}(transaction.data);
        if (!success) revert TxFailed();

        emit ExecuteTransaction(msg.sender, _txIndex);
    }

    function revokeConfirmation(uint256 _txIndex) public onlyOwner txExists(_txIndex) notExecuted(_txIndex) {
        Transaction storage transaction = transactions[_txIndex];

        if (!isConfirmed[_txIndex][msg.sender]) revert TxNotConfirmed();

        transaction.numConfirmations -= 1;
        isConfirmed[_txIndex][msg.sender] = false;

        emit RevokeConfirmation(msg.sender, _txIndex);
    }

    function getOwners() public view returns (address[] memory) {
        return owners;
    }

    function getTransactionCount() public view returns (uint256) {
        return transactions.length;
    }

    function getTransaction(uint256 _txIndex)
        public
        view
        returns (address to, uint256 value, bytes memory data, bool executed, uint256 numConfirmations)
    {
        Transaction storage transaction = transactions[_txIndex];

        return (transaction.to, transaction.value, transaction.data, transaction.executed, transaction.numConfirmations);
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }
}
