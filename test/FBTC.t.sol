// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {FBTC} from "../contracts/FBTC.sol";


contract NewFBTC is FBTC {

    uint256 public value;

    constructor(address _owner, address _bridge) FBTC(_owner, _bridge) {
    }

    function setValue(uint256 v) external {
        value = v;
    }

    function getBridge() public view returns (address) {
        return bridge;
    }
    function transfer(address, uint256) public override returns (bool){
        revert("stop");
    }
}

contract FBTCTest is Test {
    FBTC public btc;

    address constant ONE = address(1);
    address immutable OWNER = address(this);

    function setUp() public {
        btc = new FBTC(OWNER, OWNER);
    }

    function testMint() public {
        assertEq(btc.owner(), OWNER);

        btc.setBridge(ONE);
        assertEq(btc.bridge(), ONE);

        btc.setBridge(OWNER);
        assertEq(btc.bridge(), OWNER);

        assertEq(btc.totalSupply(), 0);
        assertEq(btc.balanceOf(ONE), 0);
        btc.mint(ONE, 1000);

        assertEq(btc.totalSupply(), 1000);
        assertEq(btc.balanceOf(ONE), 1000);

        btc.burn(ONE, 1000);
        assertEq(btc.totalSupply(), 0);
        assertEq(btc.balanceOf(ONE), 0);
    }

    function testBlockUser() public {
        btc.mint(OWNER, 1000);
        btc.transfer(ONE, 1);

        btc.lockUser(ONE);

        vm.expectRevert("to is blocked");
        btc.transfer(ONE, 1);

        btc.unlockUser(ONE);
        btc.transfer(ONE, 1);

        btc.lockUser(OWNER);

        vm.expectRevert("from is blocked");
        btc.transfer(ONE, 1);
    }

    function testPause() public {
        btc.mint(OWNER, 1000);
        btc.transfer(ONE, 1);
        btc.burn(OWNER, 1);

        btc.pause();

        assertEq(btc.paused(), true);

        vm.expectRevert();
        btc.mint(OWNER, 1000);

        vm.expectRevert();
        btc.transfer(ONE, 1);

        vm.expectRevert();
        btc.burn(OWNER, 1);
    }

    function testRescue() public {
        address SC = address(btc);
        btc.mint(OWNER, 1000);

        btc.transfer(SC, 1000);
        assertEq(btc.balanceOf(SC), 1000);

        btc.rescue(SC, ONE);
        assertEq(btc.balanceOf(SC), 0);
        assertEq(btc.balanceOf(ONE), 1000);

        vm.deal(SC, 100);
        assertEq(SC.balance, 100);
        btc.rescue(address(0), ONE);
        assertEq(SC.balance, 0);
        assertEq(ONE.balance, 100);
    }

    function testProxy() public {
        FBTC impl = new FBTC(OWNER, ONE);
        assertEq(impl.owner(), OWNER);
        assertEq(impl.bridge(), ONE);
        assertEq(impl.symbol(), "FBTC");
        assertEq(impl.decimals(), 8);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(OWNER, ONE);

        ERC1967Proxy _proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize, (OWNER, ONE))
        );
        FBTC proxy = FBTC(address(_proxy));

        assertEq(proxy.owner(), OWNER);
        assertEq(proxy.bridge(), ONE);
        assertEq(proxy.symbol(), "FBTC");
        assertEq(proxy.decimals(), 8);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        proxy.initialize(OWNER, ONE);

        // Test proxy upgrade
        NewFBTC newImpl = new NewFBTC(OWNER, OWNER);
        proxy.upgradeToAndCall(address(newImpl), abi.encodeCall(NewFBTC.setValue, (123)));

        NewFBTC newProxy = NewFBTC(address(proxy));
        assertEq(newProxy.getBridge(), newProxy.bridge());
        assertEq(newProxy.decimals(), 10);
        assertEq(newProxy.value(), 123);

        vm.expectRevert(bytes("stop"));
        newProxy.transfer(OWNER, 0);
    }
}
