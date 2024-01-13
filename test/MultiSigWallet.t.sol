// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "ds-test/test.sol";
import {Utilities} from "./utils/Utilities.sol";
import {MultiSigWallet} from "../src/MultiSigWallet.sol";
import "forge-std/Vm.sol";

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

    //setup function
    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(4);
        owner1 = users[0];
        owner2 = users[1];
        owner3 = users[2];
        user1 = users[3];

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

        // deploying the wallet contract with empty owners
        vm.expectRevert(MultiSigWallet.InvalidOwner.selector); // Custom error for invalid owner
        wallet = new MultiSigWallet(emptyOwners, numConfirmationsRequired);

        // deploying the wallet contract with invalid number of confirmations
        vm.expectRevert(MultiSigWallet.InvalidNumConfirmations.selector); // Custom error for invalid number of confirmations
        wallet = new MultiSigWallet(owners, 0);

        // deploying the wallet contract with number of confirmations greater than number of owners
        vm.expectRevert(MultiSigWallet.InvalidNumConfirmations.selector); // Reusing custom error for invalid number of confirmations
        wallet = new MultiSigWallet(owners, 4);

        // deploying the wallet contract with owners not unique
        vm.expectRevert(MultiSigWallet.OwnerNotUnique.selector); // Custom error for non-unique owner
        wallet = new MultiSigWallet(notUniqueOwners, numConfirmationsRequired);

        // deploying the wallet contract with invalid owners
        vm.expectRevert(MultiSigWallet.InvalidOwner.selector); // Reusing custom error for invalid owner
        wallet = new MultiSigWallet(invalidOwners, numConfirmationsRequired);

        wallet = new MultiSigWallet(owners, numConfirmationsRequired);
        vm.deal(address(wallet), 10 ether);
    }

    //helper functions
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

    //testing owners
    function testInitialOwnerSetup() public {
        for (uint256 i = 0; i < owners.length; i++) {
            assertTrue(wallet.isOwner(owners[i]), "Owner should be correctly set");
        }
    }

    //testing submitTransaction function
    function testSubmitTransaction() public {
        //setting up a test transaction
        address to = address(this);
        uint256 value = 1 ether;
        bytes memory data = "";
        uint256 initialTxCount = wallet.getTransactionCount();

        //submitting a transaction
        vm.startPrank(user1);
        vm.expectRevert(MultiSigWallet.NotOwner.selector); // Updated to expect custom error
        wallet.submitTransaction(to, value, data);
        vm.stopPrank();
        //vm prank owner submits the transaction
        vm.startPrank(owner1);
        wallet.submitTransaction(to, value, data);
        vm.stopPrank();
        //validating the transaction count increased
        assertEq(wallet.getTransactionCount(), initialTxCount + 1, "Transaction count should increase by 1");

        //validating the transaction details
        (address txTo, uint256 txValue, bytes memory txData, bool executed, uint256 numConfirmations) =
            wallet.getTransaction(initialTxCount);
        assertEq(txTo, to, "Transaction 'to' address mismatch");
        assertEq(txValue, value, "Transaction value mismatch");
        assertBytesEq(txData, data);
        assertTrue(!executed, "Transaction should not be executed yet");
        assertEq(numConfirmations, 0, "Transaction should have 0 confirmations initially");
    }

    //testing confirmTransaction function

    function testConfirmTransaction() public {
        address to = user1;
        uint256 value = 1 ether;
        bytes memory data = "";

        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);
        vm.prank(owner2);
        wallet.confirmTransaction(0);

        //confirming the transaction by user1
        vm.prank(user1);
        vm.expectRevert(MultiSigWallet.NotOwner.selector);
        wallet.confirmTransaction(0);

        //confirmation from owner2 again
        vm.prank(owner2);
        vm.expectRevert(MultiSigWallet.TxAlreadyConfirmed.selector);
        wallet.confirmTransaction(0);

        //confirming the non-existent transaction
        vm.prank(owner3);
        vm.expectRevert(MultiSigWallet.TxDoesNotExist.selector);
        wallet.confirmTransaction(1);

        vm.prank(owner1);
        wallet.confirmTransaction(0);

        //confirming the already executed transaction
        vm.prank(owner1);
        wallet.executeTransaction(0);

        vm.prank(owner3);
        vm.expectRevert(MultiSigWallet.TxAlreadyExecuted.selector);
        wallet.confirmTransaction(0);
    }

    //testing executeTransaction function

    function testExecuteTransaction() public {
        address to = user1;
        uint256 value = 1 ether;
        bytes memory data = "";

        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);
        vm.prank(owner2);
        wallet.confirmTransaction(0);
        vm.prank(owner1);
        wallet.confirmTransaction(0);

        //execute transaction by owner1
        vm.prank(owner1);
        wallet.executeTransaction(0);

        //attempting to execute transaction by non-owner
        vm.prank(user1);
        vm.expectRevert(MultiSigWallet.NotOwner.selector);
        wallet.executeTransaction(0);

        //attempting to execute non-existent transaction
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.TxDoesNotExist.selector);
        wallet.executeTransaction(1);

        //submitting transaction without enough confirmations
        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.CannotExecuteTx.selector);
        wallet.executeTransaction(1);

        //confirm and execute the new transaction
        vm.prank(owner2);
        wallet.confirmTransaction(1);
        vm.prank(owner1);
        wallet.confirmTransaction(1);
        vm.prank(owner1);
        wallet.executeTransaction(1);

        //attempting to re-execute the same transaction
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.TxAlreadyExecuted.selector);
        wallet.executeTransaction(1);
    }

    //testing revokeConfirmation function

    function testRevokeConfirmation() public {
        address to = user1;
        uint256 value = 1 ether;
        bytes memory data = "";

        //submitting and confirming a transaction
        vm.prank(owner1);
        wallet.submitTransaction(to, value, data);
        vm.prank(owner2);
        wallet.confirmTransaction(0);
        //revoke transaction confirmation by owner2
        vm.prank(owner2);
        wallet.revokeConfirmation(0);

        //attempting to revoke confirmation by non-owner
        vm.prank(user1);
        vm.expectRevert(MultiSigWallet.NotOwner.selector);
        wallet.revokeConfirmation(0);

        //attempting to revoke confirmation for non-existent transaction
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.TxDoesNotExist.selector);
        wallet.revokeConfirmation(1);

        //attempting to revoke confirmation by owner who did not confirm should fail
        vm.prank(owner1);
        vm.expectRevert(MultiSigWallet.TxNotConfirmed.selector);
        wallet.revokeConfirmation(0);

        //confirming and executing the transaction
        vm.prank(owner2);
        wallet.confirmTransaction(0);
        vm.prank(owner1);
        wallet.confirmTransaction(0);
        vm.prank(owner1);
        wallet.executeTransaction(0);

        //attempting to revoke confirmation for already executed transaction
        vm.prank(owner2);
        vm.expectRevert(MultiSigWallet.TxAlreadyExecuted.selector);
        wallet.revokeConfirmation(0);
    }
}
