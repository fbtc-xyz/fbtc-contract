// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Test, console2 as console} from "forge-std/Test.sol";
import {FBTC} from "../contracts/FBTC.sol";
import {FBTCMinter, FireBridge} from "../contracts/FBTCMinter.sol";
import {FeeModel} from "../contracts/FeeModel.sol";

import {Operation, Request, UserInfo, RequestLib, ChainCode, Status} from "../contracts/Common.sol";

contract FireBridgeTest is Test {
    using RequestLib for Request;

    FBTCMinter public minter;
    FireBridge public bridge;
    FBTC public fbtc;
    FeeModel public feeModel;

    address constant ONE = address(1);
    address immutable OWNER = address(this);
    address constant FEE = address(0xfee);

    string constant BTC_ADDR1 = "address1";
    string constant BTC_ADDR2 = "address2";
    bytes32 constant TX_DATA1 = "data1";
    bytes32 constant TX_DATA2 = "data2";
    bytes32 constant TX_DATA3 = "data3";

    bytes32 DST_CHAIN1 = bytes32(uint256(0xddddd1));
    bytes32 DST_CHAIN2 = bytes32(uint256(0xddddd2));
    bytes32 DST_CHAIN3 = bytes32(uint256(0xddddd3));

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

        minter.grantRole(minter.MINT_ROLE(), OWNER);
        minter.grantRole(minter.BURN_ROLE(), OWNER);
        minter.grantRole(minter.CROSSCHAIN_ROLE(), OWNER);
    }

    function testQualifiedUser1() public {
        assertFalse(bridge.isQualifiedUser(ONE));

        bridge.addQualifiedUser(ONE, BTC_ADDR2, BTC_ADDR1);

        assertTrue(bridge.isQualifiedUser(ONE));
        UserInfo memory info = bridge.getQualifiedUserInfo(ONE);
        assertEq(info.locked, false);
        assertEq(info.depositAddress, BTC_ADDR2);
        assertEq(info.withdrawalAddress, BTC_ADDR1);

        address[] memory _users = bridge.getQualifiedUsers();
        assertEq(_users.length, 2);
        assertEq(_users[0], OWNER);
        assertEq(_users[1], ONE);

        _users = bridge.getActiveUsers();
        assertEq(_users.length, 2);
        assertEq(_users[0], OWNER);
        assertEq(_users[1], ONE);

        bridge.lockQualifiedUser(ONE);
        assertFalse(bridge.isActiveUser(ONE));

        _users = bridge.getActiveUsers();
        assertEq(_users.length, 1);
        assertEq(_users[0], OWNER);

        bridge.unlockQualifiedUser(ONE);
        assertTrue(bridge.isActiveUser(ONE));

        bridge.removeQualifiedUser(ONE);
        assertFalse(bridge.isQualifiedUser(ONE));
    }

    function testQualifiedUser2() public {
        vm.prank(ONE);
        vm.expectRevert("Caller not qualified");
        bridge.addMintRequest(1000, TX_DATA1, 1);

        bridge.lockQualifiedUser(OWNER);
        vm.expectRevert("Caller locked");
        bridge.addMintRequest(1000, TX_DATA1, 1);

        bridge.unlockQualifiedUser(OWNER);
        bridge.addMintRequest(1000, TX_DATA1, 1);
    }

    function testRequest() public {
        vm.expectRevert("Request not exists");
        bridge.getRequestById(100);

        vm.expectRevert("Request not exists");
        bridge.getRequestByHash(bytes32(uint256(100)));

        // Mint request
        (bytes32 _hash, Request memory r) = bridge.addMintRequest(
            1000,
            TX_DATA1,
            1
        );
        assertEq(r.nonce, bridge.nonce() - 1);
        assertEq(abi.encode(bridge.getRequestByHash(_hash)), abi.encode(r));

        assertEq(r.dstChain, bridge.chain());
        assertEq(r.dstAddress, abi.encode(OWNER));
        assertEq(r.amount, 1000);
        assertEq(r.srcChain, ChainCode.BTC);
        assertEq(
            r.srcAddress,
            bytes(bridge.getQualifiedUserInfo(OWNER).depositAddress)
        );
        assertEq(r.extra, abi.encode(TX_DATA1, 1));
        assertTrue(r.status == Status.Pending);

        minter.confirmMintRequest(_hash);

        // Burn request
        (_hash, r) = bridge.addBurnRequest(500);
        assertEq(r.nonce, bridge.nonce() - 1);
        assertEq(abi.encode(bridge.getRequestByHash(_hash)), abi.encode(r));
        assertEq(r.srcChain, bridge.chain());
        assertEq(r.srcAddress, abi.encode(OWNER));
        assertEq(r.amount, 500);
        assertEq(r.dstChain, ChainCode.BTC);
        assertEq(
            r.dstAddress,
            bytes(bridge.getQualifiedUserInfo(OWNER).withdrawalAddress)
        );
        assertEq(r.extra, "");
        assertTrue(r.status == Status.Pending);

        // Cross-chain request
        (_hash, r) = bridge.addCrosschainRequest(
            DST_CHAIN1,
            abi.encode(ONE),
            500
        );
        assertEq(r.nonce, bridge.nonce() - 1);
        assertEq(abi.encode(bridge.getRequestByHash(_hash)), abi.encode(r));
        assertEq(r.srcChain, bridge.chain());
        assertEq(r.srcAddress, abi.encode(OWNER));
        assertEq(r.amount, 500);
        assertEq(r.dstChain, DST_CHAIN1);
        assertEq(r.dstAddress, abi.encode(ONE));
        assertEq(r.extra, abi.encode(_hash));
        assertTrue(r.status == Status.Unused);

        // Cross-chain confirmation
        Request memory r2;
        (_hash, r2) = _confirmCrosschainRequest(r, _hash);
        assertEq(r2.nonce, bridge.nonce() - 1);
        assertEq(abi.encode(bridge.getRequestByHash(_hash)), abi.encode(r2));

        r2.op = r.op;
        r2.nonce = r.nonce;
        assertEq(abi.encode(r), abi.encode(r2));
    }

    function testMint() public {
        (bytes32 _hash1, ) = bridge.addMintRequest(1000, TX_DATA1, 1);
        (bytes32 _hash2, ) = bridge.addMintRequest(1000, TX_DATA2, 1);
        (bytes32 _hash3, ) = bridge.addMintRequest(1000, TX_DATA1, 1);

        // Test mint
        minter.confirmMintRequest(_hash1);
        Request memory r = bridge.getRequestByHash(_hash1);

        assertTrue(r.status == Status.Confirmed);
        assertEq(fbtc.balanceOf(OWNER), 1000);

        // Can NOT add request with used BTC tx
        vm.expectRevert("Used BTC deposit tx");
        bridge.addMintRequest(1000, TX_DATA1, 1);

        // Can NOT confirm request with used BTC tx
        vm.expectRevert("Used BTC deposit tx");
        minter.confirmMintRequest(_hash3);

        // Can NOT confirm request twice.
        vm.expectRevert("Invalid request status");
        minter.confirmMintRequest(_hash1);

        // Can NOT confirm rejected BTC tx
        bridge.blockDepositTx(TX_DATA2, 1);

        vm.expectRevert("Used BTC deposit tx");
        minter.confirmMintRequest(_hash2);

        // Can NOT add request with blocked BTC tx
        bridge.blockDepositTx(TX_DATA2, 2);
        vm.expectRevert("Used BTC deposit tx");
        bridge.addMintRequest(1000, TX_DATA2, 2);
    }

    function testBurn() public {
        (bytes32 _hash, Request memory r) = bridge.addMintRequest(
            1000,
            TX_DATA1,
            1
        );
        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 1000);

        (_hash, r) = bridge.addBurnRequest(500);
        assertEq(fbtc.balanceOf(OWNER), 500);

        r = bridge.getRequestByHash(_hash);
        assertTrue(r.status == Status.Pending);

        minter.confirmBurnRequest(_hash, TX_DATA2, 0);
        r = bridge.getRequestByHash(_hash);
        assertTrue(r.status == Status.Confirmed);
        assertEq(r.extra, abi.encode(TX_DATA2, 0));

        vm.expectRevert();
        bridge.addBurnRequest(1000);
    }

    function _confirmCrosschainRequest(
        Request memory _r,
        bytes32 _srcRequestHash
    ) internal returns (bytes32 _hash, Request memory _dstR) {
        // Should be correct set in source request.
        assertEq(_r.extra, abi.encode(_srcRequestHash));
        _r.op = Operation.CrosschainConfirm;

        uint256 backup = block.chainid;
        vm.chainId(uint256(_r.dstChain)); // Temperary mock bridge to dst chain.
        (_hash, _dstR) = minter.confirmCrosschainRequest(_r);
        vm.chainId(backup);
    }

    function testCrosschain() public {
        (bytes32 _hash, ) = bridge.addMintRequest(1000, TX_DATA1, 1);
        assertEq(fbtc.balanceOf(OWNER), 0);
        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 1000);

        (_hash, ) = bridge.addEVMCrosschainRequest(
            uint256(DST_CHAIN1),
            ONE,
            500
        );
        assertEq(fbtc.balanceOf(OWNER), 500, "owner token incorrect");

        Request memory r = bridge.getRequestByHash(_hash);
        _confirmCrosschainRequest(r, _hash);
        assertEq(fbtc.balanceOf(ONE), 500, "token not received");

        (bytes32 _hash1, ) = bridge.addCrosschainRequest(
            DST_CHAIN3,
            abi.encode(ONE),
            10
        );
        (bytes32 _hash2, ) = bridge.addCrosschainRequest(
            DST_CHAIN3,
            abi.encode(ONE),
            10
        );
        (bytes32 _hash3, ) = bridge.addEVMCrosschainRequest(
            uint256(DST_CHAIN3),
            ONE,
            10
        );

        Request[] memory rs = new Request[](3);
        rs[0] = bridge.getRequestByHash(_hash1);
        rs[1] = bridge.getRequestByHash(_hash2);
        rs[2] = bridge.getRequestByHash(_hash3);
        for (uint i = 0; i <= 2; i++) {
            rs[i].op = Operation.CrosschainConfirm;
        }

        uint256 chainId = block.chainid;
        vm.chainId(uint256(DST_CHAIN3));
        minter.batchConfirmCrosschainRequest(rs);
        vm.chainId(chainId);

        assertEq(fbtc.balanceOf(OWNER), 470);
        assertEq(fbtc.balanceOf(ONE), 530);

        vm.expectRevert("Source request already confirmed");
        _confirmCrosschainRequest(rs[2], _hash3);
    }

    function testFee() public {
        FeeModel.FeeConfig memory _config = FeeModel.FeeConfig(
            true,
            feeModel.FEE_RATE_BASE() / 100,
            0
        );
        feeModel.setDefaultFeeConfig(Operation.Mint, _config);

        feeModel.setDefaultFeeConfig(Operation.Burn, _config);

        feeModel.setDefaultFeeConfig(Operation.CrosschainRequest, _config);

        (bytes32 _hash, ) = bridge.addMintRequest(1000 ether, TX_DATA1, 1);
        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 990 ether);
        assertEq(fbtc.balanceOf(FEE), 10 ether);

        (_hash, ) = bridge.addBurnRequest(100 ether);

        assertEq(fbtc.balanceOf(OWNER), 890 ether);
        assertEq(fbtc.balanceOf(FEE), 11 ether);
        minter.confirmBurnRequest(_hash, TX_DATA2, 0);

        (_hash, ) = bridge.addCrosschainRequest(
            DST_CHAIN1,
            abi.encode(ONE),
            100 ether
        );

        Request memory r = bridge.getRequestByHash(_hash);
        _confirmCrosschainRequest(r, _hash);

        assertEq(fbtc.balanceOf(OWNER), 790 ether);
        assertEq(fbtc.balanceOf(FEE), 12 ether);
    }

    function testFee2() public {
        // Setup
        feeModel.setDefaultFeeConfig(
            Operation.Mint,
            FeeModel.FeeConfig(true, feeModel.FEE_RATE_BASE() / 100, 1 ether)
        );

        feeModel.setDefaultFeeConfig(
            Operation.Burn,
            FeeModel.FeeConfig(true, feeModel.FEE_RATE_BASE() / 100, 1 ether)
        );

        feeModel.setDefaultFeeConfig(
            Operation.CrosschainRequest,
            FeeModel.FeeConfig(true, feeModel.FEE_RATE_BASE() / 100, 1 ether)
        );

        feeModel.setChainFeeConfig(
            Operation.CrosschainRequest,
            DST_CHAIN2,
            FeeModel.FeeConfig(
                true,
                feeModel.FEE_RATE_BASE() / 100,
                0.001 ether
            )
        );
        feeModel.setChainFeeConfig(
            Operation.CrosschainRequest,
            DST_CHAIN3,
            FeeModel.FeeConfig(
                true,
                feeModel.FEE_RATE_BASE() / 100,
                0.001 ether
            )
        );

        // Test mint fee.
        (bytes32 _hash, Request memory r2) = bridge.addMintRequest(
            1000 ether,
            TX_DATA1,
            1
        );
        assertEq(r2.fee, 10 ether);

        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 990 ether);

        // Test bridge fee.

        vm.expectRevert("amount lower than minimal fee");
        bridge.addCrosschainRequest(DST_CHAIN1, abi.encode(ONE), 0.5 ether);
        Request memory r;
        (_hash, r) = bridge.addCrosschainRequest(
            DST_CHAIN1,
            abi.encode(ONE),
            100 ether
        );
        assertEq(r.fee, 1 ether);
        assertEq(fbtc.balanceOf(FEE), 11 ether);

        (_hash, r) = bridge.addCrosschainRequest(
            DST_CHAIN2,
            abi.encode(ONE),
            1 ether
        );
        assertEq(r.fee, 0.01 ether);
        assertEq(fbtc.balanceOf(FEE), 11.01 ether);

        (_hash, r) = bridge.addCrosschainRequest(
            DST_CHAIN3,
            abi.encode(ONE),
            0.002 ether
        );
        assertEq(r.fee, 0.001 ether);
        assertEq(fbtc.balanceOf(FEE), 11.011 ether);

        _confirmCrosschainRequest(r, _hash);
        assertEq(fbtc.balanceOf(ONE), 0.001 ether);

        (_hash, r) = bridge.addBurnRequest(100 ether);
        assertEq(r.fee, 1 ether);
        assertEq(fbtc.balanceOf(FEE), 12.011 ether);
    }
}
