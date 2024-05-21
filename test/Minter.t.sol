// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";

import {Operation} from "../contracts/Common.sol";
import {FBTC} from "../contracts/FBTC.sol";
import {FBTCMinter} from "../contracts/FBTCMinter.sol";
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
        FeeModel.FeeConfig memory _config;
        _config.tiers = new FeeModel.FeeTier[](1);
        _config.tiers[0].amountTier = type(uint224).max;
        feeModel.setDefaultFeeConfig(Operation.Mint, _config);
        feeModel.setDefaultFeeConfig(Operation.Burn, _config);
        feeModel.setDefaultFeeConfig(Operation.CrosschainRequest, _config);

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
        bytes32 MINT_ROLE = minter.MINT_ROLE();
        bytes32 BURN_ROLE = minter.BURN_ROLE();
        assertFalse(minter.hasRole(MINT_ROLE, OWNER));
        assertFalse(minter.hasRole(BURN_ROLE, OWNER));

        minter.grantRole(MINT_ROLE, OWNER);
        assertTrue(minter.hasRole(MINT_ROLE, OWNER));
        assertFalse(minter.hasRole(BURN_ROLE, OWNER));

        minter.grantRole(MINT_ROLE, ONE);
        assertTrue(minter.hasRole(MINT_ROLE, ONE));

        minter.grantRole(BURN_ROLE, OWNER);
        assertTrue(minter.hasRole(BURN_ROLE, OWNER));

        address[] memory members = minter.getRoleMembers(MINT_ROLE);
        assertEq(members.length, 2);
        assertEq(members[0], OWNER);
        assertEq(members[1], ONE);

        minter.revokeRole(BURN_ROLE, OWNER);
        assertFalse(minter.hasRole(BURN_ROLE, OWNER));
    }

    function testMint() public {
        bridge.addQualifiedUser(OWNER, "FakeDeposit", "FakeWithdraw");

        (bytes32 _hash1, ) = bridge.addMintRequest(1000, "FakeTx", 1);
        (bytes32 _hash2, ) = bridge.addMintRequest(1000, "FakeTx2", 1);

        minter.grantRole(minter.MINT_ROLE(), OWNER);

        minter.confirmMintRequest(_hash1);

        assertEq(fbtc.balanceOf(OWNER), 1000);

        minter.revokeRole(minter.MINT_ROLE(), OWNER);
        vm.expectRevert("Unauthorized role member");
        minter.confirmMintRequest(_hash2);
    }
}
