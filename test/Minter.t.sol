// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {FBTC} from "../contracts/FBTC.sol";
import {FBTCMinter, Operation} from "../contracts/Minter.sol";
import {FeeModel} from "../contracts/FeeModel.sol";
import {FireBridge, ChainCode} from "../contracts/FireBridge.sol";

contract MinterTest is Test {
    FBTCMinter public minter;
    FireBridge public bridge;
    FBTC public fbtc;
    FeeModel public feeModel;

    address constant ONE = address(1);
    address immutable OWNER = address(this);

    function setUp() public {
        bridge = new FireBridge(OWNER, ChainCode.BTC);

        feeModel = new FeeModel(OWNER);
        bridge.setFeeModel(address(feeModel));

        fbtc = new FBTC(OWNER, address(bridge));

        bridge.setToken(address(fbtc));
        minter = new FBTCMinter(OWNER, address(bridge));
        bridge.setMinter(address(minter));
    }

    function testSetBridge() public {
        minter.setBridge(ONE);
        assertEq(address(minter.bridge()), ONE);
        minter.setBridge(address(bridge));
        assertEq(address(minter.bridge()), address(bridge));
    }

    function testOperator() public {
        assertFalse(minter.roles(OWNER, Operation.Mint));
        assertFalse(minter.roles(OWNER, Operation.Burn));

        minter.addOperator(Operation.Mint, OWNER);
        assertTrue(minter.roles(OWNER, Operation.Mint));
        assertFalse(minter.roles(OWNER, Operation.Burn));

        minter.addOperator(Operation.Mint, ONE);
        assertTrue(minter.roles(ONE, Operation.Mint));

        minter.addOperator(Operation.Burn, OWNER);
        assertTrue(minter.roles(OWNER, Operation.Burn));

        minter.removeOperator(Operation.Burn, OWNER);
        assertFalse(minter.roles(OWNER, Operation.Burn));
    }

    function testMint() public {
        bridge.addQualifiedUser(OWNER, "FakeDeposit", "FakeWithdraw");

        (bytes32 _hash1, ) = bridge.addMintRequest(1000, "FakeTx", 1);
        (bytes32 _hash2, ) = bridge.addMintRequest(1000, "FakeTx2", 1);

        minter.addOperator(Operation.Mint, OWNER);

        minter.confirmMintRequest(_hash1);

        assertEq(fbtc.balanceOf(OWNER), 1000);

        minter.removeOperator(Operation.Mint, OWNER);
        vm.expectRevert("Invalid role of caller");
        minter.confirmMintRequest(_hash2);
    }
}
