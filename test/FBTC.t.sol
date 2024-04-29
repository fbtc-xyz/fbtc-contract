// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {FBTC} from "../contracts/FBTC.sol";

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
    }
}
