// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
// -- MultiSigWallet Contract --
import "forge-std/Vm.sol";

// -- Test Contract --

contract MultiSigWalletTest is DSTest {
    Vm vm = Vm(HEVM_ADDRESS);
    MultiSigWallet wallet;
    address[] owners;
    address[] emptyOwners;
    address[] notUniqueOwners;
    address[] invalidOwners;
    Utilities internal utils;
    address payable internal owner1;
    address payable internal owner2;
    address payable internal owner3;
    address payable internal user1;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(4);
        // address payable[] memory emptyUsers = new address payable[](0);
        owner1 = users[0];
        owner2 = users[1];
        owner3 = users[2];

        user1 = users[3];

        // Setup example owners
        owners.push(address(owner1));
        owners.push(address(owner2));
        owners.push(address(owner3));
        notUniqueOwners.push(address(owner1));
        notUniqueOwners.push(address(owner1));
        notUniqueOwners.push(address(owner2));
        invalidOwners.push(address(0x0));
        invalidOwners.push(address(0x0));
        invalidOwners.push(address(0x0));
        uint256 numConfirmationsRequired = 2;

        // Deploying the wallet contract should fail for empty users
        vm.expectRevert("owners required");
        wallet = new MultiSigWallet(emptyOwners, numConfirmationsRequired);

        // Deploying the wallet contract should fail for invalid number of confirmations
        vm.expectRevert("invalid number of required confirmations");
        wallet = new MultiSigWallet(owners, 0);

        // Deploying the wallet contract should fail if number of confirmations is greater than number of owners
        vm.expectRevert("invalid number of required confirmations");
        wallet = new MultiSigWallet(owners, 4);

        // Deploying the wallet contract should fail if owners are not unique
        vm.expectRevert("owner not unique");
        wallet = new MultiSigWallet(notUniqueOwners, numConfirmationsRequired);

        // Deploying the wallet contract should fail if owners is invalid
        vm.expectRevert("invalid owner");
        wallet = new MultiSigWallet(invalidOwners, numConfirmationsRequired);

        wallet = new MultiSigWallet(owners, numConfirmationsRequired);
        vm.deal(address(wallet), 10 ether);
    }

    function assertBytesEq(bytes memory a, bytes memory b) internal {
        if (a.length != b.length) {
            emit log("Data length mismatch");
            fail();
        }

        for (uint256 i = 0; i < a.length; i++) {
            if (a[i] != b[i]) {
                emit log("Data content mismatch");
                fail();
            }
        }
    }

    function testInitialOwnerSetup() public {
        for (uint256 i = 0; i < owners.length; i++) {
            assertTrue(wallet.isOwner(owners[i]), "Owner should be correctly set");
        }
    }

    // Testing testSubmitTransaction function
    function testSubmitTransaction() public {
        // Setting up a test transaction
        address to = address(this);
        uint256 value = 1 ether;
        bytes memory data = "";
        // Capturing the initial transaction count
        uint256 initialTxCount = wallet.getTransactionCount();

        // Submitting a transaction
        // only owner should sumbit the transaction
        vm.startPrank(user1);
        vm.expectRevert("not owner");
        wallet.submitTransaction(to, value, data);
        vm.stopPrank();
        //vm prank owner submits the transaction
        vm.startPrank(owner1);
        wallet.submitTransaction(to, value, data);
        vm.stopPrank();
        // Validating the transaction count increased
        assertEq(wallet.getTransactionCount(), initialTxCount + 1, "Transaction count should increase by 1");

        // Validating the transaction details
        (address txTo, uint256 txValue, bytes memory txData, bool executed, uint256 numConfirmations) =
            wallet.getTransaction(initialTxCount);
        assertEq(txTo, to, "Transaction 'to' address mismatch");
        assertEq(txValue, value, "Transaction value mismatch");
        assertBytesEq(txData, data);
        assertTrue(!executed, "Transaction should not be executed yet");
        assertEq(numConfirmations, 0, "Transaction should have 0 confirmations initially");
    }

    // Testing testConfirmTransaction function

    function testConfirmTransaction() public {
        address to = user1;
        uint256 value = 1 ether;
        bytes memory data = "";

        // Submitting a transaction
        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);

        // Confirming the transaction by owner2 should work
        vm.prank(owner2);
        wallet.confirmTransaction(0);

        // Confirming the transaction by user1 should fail
        vm.prank(user1);
        vm.expectRevert("not owner");
        wallet.confirmTransaction(0);

        // Confirming the transaction by owner2 again should fail
        vm.prank(owner2);
        vm.expectRevert("tx already confirmed");
        wallet.confirmTransaction(0);

        // Confirming the non-existent transaction should fail
        vm.prank(owner3);
        vm.expectRevert("tx does not exist");
        wallet.confirmTransaction(1);

        vm.prank(owner1);
        wallet.confirmTransaction(0);

        // Confirming the already executed transaction should fail
        vm.prank(owner1);
        // executing the transaction
        wallet.executeTransaction(0);

        vm.prank(owner3);
        vm.expectRevert("tx already executed");
        wallet.confirmTransaction(0);
    }

    // Testing testExecuteTransaction function

    function testExecuteTransaction() public {
        address to = user1;
        uint256 value = 1 ether;
        bytes memory data = "";

        // Submitting and confirming a transaction
        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);

        vm.prank(owner2);
        wallet.confirmTransaction(0);

        // Execute transaction by owner1 should work after required confirmations
        vm.prank(owner1);
        wallet.confirmTransaction(0);

        // Execute transaction by owner1 should work after required confirmations
        vm.prank(owner1);
        wallet.executeTransaction(0);

        // Attempting to execute transaction by non-owner should fail
        vm.prank(user1);
        vm.expectRevert("not owner");
        wallet.executeTransaction(0);

        // Attempting to execute non-existent transaction should fail
        vm.prank(owner1);
        vm.expectRevert("tx does not exist");
        wallet.executeTransaction(1);

        // Submitting another transaction without enough confirmations
        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);

        // Attempting to execute this new transaction should fail due to lack of confirmations
        vm.prank(owner1);
        vm.expectRevert("cannot execute tx");
        wallet.executeTransaction(1);

        // Confirm and execute the new transaction
        vm.prank(owner2);
        wallet.confirmTransaction(1);

        vm.prank(owner1);
        wallet.confirmTransaction(1);

        vm.prank(owner1);
        wallet.executeTransaction(1);

        // Attempting to re-execute the same transaction should fail
        vm.prank(owner1);
        vm.expectRevert("tx already executed");
        wallet.executeTransaction(1);
    }

    // Testing testRevokeConfirmation function

    function testRevokeConfirmation() public {
        address to = user1;
        uint256 value = 1 ether;
        bytes memory data = "";

        // Submitting and confirming a transaction
        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);

        vm.prank(owner2);
        wallet.confirmTransaction(0);

        // Successful revocation by owner2
        vm.prank(owner2);
        wallet.revokeConfirmation(0);

        // Attempting to revoke confirmation by non-owner should fail
        vm.prank(user1);
        vm.expectRevert("not owner");
        wallet.revokeConfirmation(0);

        // Attempting to revoke confirmation for non-existent transaction should fail
        vm.prank(owner1);
        vm.expectRevert("tx does not exist");
        wallet.revokeConfirmation(1);

        // Attempting to revoke confirmation by owner who did not confirm should fail
        vm.prank(owner1);
        vm.expectRevert("tx not confirmed");
        wallet.revokeConfirmation(0);

        // Confirming and executing the transaction
        vm.prank(owner2);
        wallet.confirmTransaction(0);

        vm.prank(owner1);
        wallet.confirmTransaction(0);

        vm.prank(owner1);
        wallet.executeTransaction(0);

        // Attempting to revoke confirmation for already executed transaction should fail
        vm.prank(owner2);
        vm.expectRevert("tx already executed");
        wallet.revokeConfirmation(0);
    }
}
