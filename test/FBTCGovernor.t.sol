// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {FBTC} from "../contracts/FBTC.sol";
import {FBTCMinter, Operation} from "../contracts/Minter.sol";
import {FBTCGovernor} from "../contracts/FBTCGovernor.sol";
import {FeeModel} from "../contracts/FeeModel.sol";
import {FireBridge, ChainCode} from "../contracts/FireBridge.sol";

contract FBTCGovernorTest is Test {
    FireBridge public bridge;
    FBTC public fbtc;
    FBTCMinter public minter;
    FeeModel public feeModel;
    FBTCGovernor public gov;

    address constant ONE = address(1);
    address constant TWO = address(2);
    address constant THREE = address(3);

    address immutable OWNER = address(this);
    address constant FEE = address(0xfee);

    string constant BTC_ADDR1 = "address1";
    string constant BTC_ADDR2 = "address2";
    bytes32 constant TX_DATA1 = "data1";
    bytes32 constant TX_DATA2 = "data2";
    bytes32 constant TX_DATA3 = "data3";

    function setUp() public {
        bridge = new FireBridge(OWNER, ChainCode.BTC);
        bridge.addQualifiedUser(OWNER, BTC_ADDR1, BTC_ADDR2);

        feeModel = new FeeModel(OWNER);
        bridge.setFeeModel(address(feeModel));
        bridge.setFeeRecipient(FEE);

        fbtc = new FBTC(OWNER, address(bridge));
        bridge.setToken(address(fbtc));

        minter = new FBTCMinter(OWNER, address(bridge));
        bridge.setMinter(address(minter));

        minter.addOperator(Operation.Mint, OWNER);
        minter.addOperator(Operation.Burn, OWNER);
        minter.addOperator(Operation.CrosschainConfirm, OWNER);

        gov = new FBTCGovernor(OWNER);
        gov.setFBTC(address(fbtc));
        gov.setBridge(address(bridge));
        fbtc.transferOwnership(address(gov));
        bridge.transferOwnership(address(gov));

        gov.execTransaction(
            address(fbtc),
            0,
            abi.encodeCall(fbtc.acceptOwnership, ())
        );
        gov.execTransaction(
            address(bridge),
            0,
            abi.encodeCall(bridge.acceptOwnership, ())
        );
    }

    function testOwner() public {
        assertEq(fbtc.owner(), address(gov));
        assertEq(bridge.owner(), address(gov));
    }

    function testRole() public {
        // Mint some token for owner.
        (bytes32 _hash, ) = bridge.addMintRequest(100 ether, TX_DATA1, 1);
        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 100 ether);

        // Test pause FBTC
        assertEq(fbtc.paused(), false);
        fbtc.transfer(ONE, 1 ether);

        vm.expectRevert();
        gov.pauseFBTC();

        gov.grantRole(gov.FBTC_PAUSER_ROLE(), ONE);
        vm.prank(ONE);
        gov.pauseFBTC();

        assertEq(fbtc.paused(), true);
        vm.expectRevert();
        fbtc.transfer(ONE, 1);

        // unpause
        gov.execTransaction(address(fbtc), 0, abi.encodeCall(fbtc.unpause, ()));
        assertEq(fbtc.paused(), false);

        // Test lock user
        gov.grantRole(gov.LOCKER_RULE(), ONE);
        vm.prank(ONE);
        gov.lockUserFBTCTransfer(ONE);

        assertEq(fbtc.balanceOf(ONE), 1 ether);
        vm.expectRevert();
        vm.prank(ONE);
        fbtc.transfer(TWO, 1);

        // Test pause bridge.
        assertEq(bridge.paused(), false);
        gov.grantRole(gov.BRIDGE_PAUSER_RULE(), TWO);

        vm.prank(TWO);
        gov.pauseBridge();
        assertEq(bridge.paused(), true);

        vm.expectRevert();
        bridge.addMintRequest(1 ether, TX_DATA2, 1);
        gov.execTransaction(
            address(bridge),
            0,
            abi.encodeCall(bridge.unpause, ())
        );
        assertEq(bridge.paused(), false);
        bridge.addMintRequest(1 ether, TX_DATA2, 1);

        // Test add qualified user.
        gov.grantRole(gov.USER_MANAGER_RULE(), THREE);
        vm.prank(THREE);
        gov.addQualifiedUser(THREE, BTC_ADDR2, BTC_ADDR1);
        assertTrue(bridge.isQualifiedUser(THREE));
        assertEq(bridge.depositAddresses(THREE), BTC_ADDR2);
        assertEq(bridge.withdrawalAddresses(THREE), BTC_ADDR1);
    }
}
