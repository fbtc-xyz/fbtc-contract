// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Test, console2 as console} from "forge-std/Test.sol";
import {FBTC} from "../contracts/FBTC.sol";
import {FBTCMinter, FireBridge} from "../contracts/FBTCMinter.sol";
import {FeeModel} from "../contracts/FeeModel.sol";

import {Operation, Request, UserInfo, RequestLib, ChainCode, Status} from "../contracts/Common.sol";

contract FireModelTest is Test {
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

        bytes32[] memory dstChains = new bytes32[](3);
        dstChains[0] = DST_CHAIN1;
        dstChains[1] = DST_CHAIN2;
        dstChains[2] = DST_CHAIN3;
        bridge.addDstChains(dstChains);

        minter.grantRole(minter.MINT_ROLE(), OWNER);
        minter.grantRole(minter.BURN_ROLE(), OWNER);
        minter.grantRole(minter.CROSSCHAIN_ROLE(), OWNER);
    }

    function testFeeBasic() public {
        FeeModel.FeeTier memory tier = FeeModel.FeeTier(
            type(uint224).max,
            feeModel.FEE_RATE_BASE() / 10000
        );
        FeeModel.FeeTier[] memory tiers = new FeeModel.FeeTier[](1);
        tiers[0] = tier;
        FeeModel.FeeConfig memory _config = FeeModel.FeeConfig(0, tiers);

        // mint 0.01%
        feeModel.setDefaultFeeConfig(Operation.Mint, _config);

        // burn 0.1%
        tier.feeRate = feeModel.FEE_RATE_BASE() / 1000;
        feeModel.setDefaultFeeConfig(Operation.Burn, _config);

        // cross-chain 1%
        tier.feeRate = feeModel.FEE_RATE_BASE() / 100;
        feeModel.setDefaultFeeConfig(Operation.CrosschainRequest, _config);

        // test mint
        (bytes32 _hash, ) = bridge.addMintRequest(20000 ether, TX_DATA1, 1);
        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 19998 ether);
        assertEq(fbtc.balanceOf(FEE), 2 ether);

        // test burn
        bridge.addBurnRequest(1000 ether);
        assertEq(fbtc.balanceOf(OWNER), 18998 ether);
        assertEq(fbtc.balanceOf(FEE), 3 ether);

        // test cross-chain
        bridge.addCrosschainRequest(DST_CHAIN1, abi.encode(ONE), 100 ether);
        assertEq(fbtc.balanceOf(OWNER), 18898 ether);
        assertEq(fbtc.balanceOf(FEE), 4 ether);
    }

    function testMinFee() public {
        FeeModel.FeeTier[] memory tiers = new FeeModel.FeeTier[](1);
        tiers[0] = FeeModel.FeeTier(
            type(uint224).max,
            feeModel.FEE_RATE_BASE() / 100
        );
        FeeModel.FeeConfig memory _config = FeeModel.FeeConfig(1000, tiers);
        // Setup

        feeModel.setDefaultFeeConfig(Operation.Burn, _config);

        bytes32 _hash;
        Request memory r;

        // Mint
        (_hash, r) = bridge.addMintRequest(100000, TX_DATA1, 1);
        assertEq(r.fee, 0);

        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 100000);

        // Test min fee.

        vm.expectRevert("amount lower than minimal fee");
        bridge.addBurnRequest(1);

        vm.expectRevert("amount lower than minimal fee");
        bridge.addBurnRequest(1000);

        (_hash, r) = bridge.addBurnRequest(1001);
        assertEq(r.fee, 1000);
        assertEq(fbtc.balanceOf(FEE), 1000);

        (_hash, r) = bridge.addBurnRequest(2000);
        assertEq(r.fee, 1000);
        assertEq(fbtc.balanceOf(FEE), 2000);
    }

    function testChainFee() public {
        FeeModel.FeeTier memory tier = FeeModel.FeeTier(
            type(uint224).max,
            feeModel.FEE_RATE_BASE() / 10000
        );
        FeeModel.FeeTier[] memory tiers = new FeeModel.FeeTier[](1);
        tiers[0] = tier;
        FeeModel.FeeConfig memory _config = FeeModel.FeeConfig(0, tiers);

        // default 0.01% (chain3)
        feeModel.setDefaultFeeConfig(Operation.CrosschainRequest, _config);

        // chain1 0.1%
        tier.feeRate = feeModel.FEE_RATE_BASE() / 1000;
        feeModel.setChainFeeConfig(
            Operation.CrosschainRequest,
            DST_CHAIN1,
            _config
        );

        // chain2 1%
        tier.feeRate = feeModel.FEE_RATE_BASE() / 100;
        feeModel.setChainFeeConfig(
            Operation.CrosschainRequest,
            DST_CHAIN2,
            _config
        );

        bytes32 _hash;
        Request memory r;

        // Mint
        (_hash, r) = bridge.addMintRequest(30000 ether, TX_DATA1, 1);
        assertEq(r.fee, 0);

        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 30000 ether);

        // Test cross-chain fee

        (, r) = bridge.addCrosschainRequest(
            DST_CHAIN1,
            abi.encode(ONE),
            10000 ether
        );
        assertEq(r.fee, 10 ether);
        assertEq(fbtc.balanceOf(FEE), 10 ether);

        (, r) = bridge.addCrosschainRequest(
            DST_CHAIN2,
            abi.encode(ONE),
            10000 ether
        );
        assertEq(r.fee, 100 ether);
        assertEq(fbtc.balanceOf(FEE), 110 ether);

        (, r) = bridge.addCrosschainRequest(
            DST_CHAIN3,
            abi.encode(ONE),
            10000 ether
        );
        assertEq(r.fee, 1 ether);
        assertEq(fbtc.balanceOf(FEE), 111 ether);
        assertEq(fbtc.balanceOf(OWNER), 0 ether);
    }

    function testFeeTier() public {
        // Setup
        FeeModel.FeeTier[] memory tiers = new FeeModel.FeeTier[](4);
        uint224 BTC_UNIT = 1e8;
        // < 500 BTC, 0.20%
        tiers[0] = FeeModel.FeeTier(
            500 * BTC_UNIT,
            (feeModel.FEE_RATE_BASE() * 20) / 10000
        );
        // >=500 <1500 BTC, 0.16%
        tiers[1] = FeeModel.FeeTier(
            1500 * BTC_UNIT,
            (feeModel.FEE_RATE_BASE() * 16) / 10000
        );
        // >=1500 <3000 BTC, 0.12%
        tiers[2] = FeeModel.FeeTier(
            3000 * BTC_UNIT,
            (feeModel.FEE_RATE_BASE() * 12) / 10000
        );
        // >=3000 BTC, 0.10%
        tiers[3] = FeeModel.FeeTier(
            type(uint224).max,
            (feeModel.FEE_RATE_BASE() * 10) / 10000
        );

        FeeModel.FeeConfig memory _config = FeeModel.FeeConfig(
            0.03 * 1e8, // 0.03 FBTC
            tiers
        );

        feeModel.setDefaultFeeConfig(Operation.Burn, _config);

        // Mint
        bytes32 _hash;
        Request memory r;

        (_hash, r) = bridge.addMintRequest(100000 * BTC_UNIT, TX_DATA1, 1);
        assertEq(r.fee, 0);

        minter.confirmMintRequest(_hash);
        assertEq(fbtc.balanceOf(OWNER), 100000 * BTC_UNIT);

        // Test fee tier
        vm.expectRevert("amount lower than minimal fee");
        bridge.addBurnRequest((1 * BTC_UNIT) / 100);

        (, r) = bridge.addBurnRequest(10 * BTC_UNIT); // Min 0.03
        assertEq(r.fee, (3 * BTC_UNIT) / 100);

        (, r) = bridge.addBurnRequest(400 * BTC_UNIT); // 0.20 %
        assertEq(r.fee, (8 * BTC_UNIT) / 10);

        (, r) = bridge.addBurnRequest(500 * BTC_UNIT); // 0.16 %
        assertEq(r.fee, (8 * BTC_UNIT) / 10);

        (, r) = bridge.addBurnRequest(1500 * BTC_UNIT); // 0.12 %
        assertEq(r.fee, (18 * BTC_UNIT) / 10);

        (, r) = bridge.addBurnRequest(3000 * BTC_UNIT); // 0.10 %
        assertEq(r.fee, 3 * BTC_UNIT);

        (, r) = bridge.addBurnRequest(6000 * BTC_UNIT); // 0.10 %
        assertEq(r.fee, 6 * BTC_UNIT);
    }
}
