// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript, stdJson, console} from "./Base.sol";

import {Operation} from "../contracts/Common.sol";
import {FBTC} from "../contracts/FBTC.sol";
import {FireBridge} from "../contracts/FireBridge.sol";
import {FBTCMinter} from "../contracts/FBTCMinter.sol";
import {FeeModel} from "../contracts/FeeModel.sol";

contract ConfigScript is BaseScript {
    function addMinter(
        string memory chain,
        string memory tag,
        string memory minterTag
    ) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        ContractConfig memory c = loadContractConfig(chain, tag);
        MinterConfig memory m = loadMinterConfig(minterTag);

        FBTCMinter minter = FBTCMinter(c.minter);

        minter.grantRole(minter.MINT_ROLE(), m.opMint);
        minter.grantRole(minter.BURN_ROLE(), m.opBurn);
        minter.grantRole(minter.CROSSCHAIN_ROLE(), m.opCross);

        vm.stopBroadcast();
    }

    function addMerchaint(
        string memory chain,
        string memory tag,
        string memory merchantTag
    ) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        ContractConfig memory c = loadContractConfig(chain, tag);
        MerchantConfig memory m = loadMerchantConfig(merchantTag);

        FireBridge bridge = FireBridge(c.bridge);
        bridge.addQualifiedUser(m.merchant, m.deposit, m.withdraw);
        vm.stopBroadcast();
    }

    function setupFee(string memory chain, string memory tag) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        ContractConfig memory c = loadContractConfig(chain, tag);
        FeeModel fee = FeeModel(c.feeModel);

        // Cross-chain fee: Min 0.0001 FBTC, Rate 0.01%
        FeeModel.FeeTier[] memory tiers = new FeeModel.FeeTier[](1);
        tiers[0] = FeeModel.FeeTier(
            type(uint224).max,
            fee.FEE_RATE_BASE() / 10000 // 0.01%
        );
        FeeModel.FeeConfig memory _config = FeeModel.FeeConfig(
            0.0001 * 1e8, // 0.0001 FBTC
            tiers
        );

        fee.setDefaultFeeConfig(Operation.CrosschainRequest, _config);

        // No mint fee
        _config.minFee = 0;
        tiers[0].feeRate = 0;
        fee.setDefaultFeeConfig(Operation.Mint, _config);

        // Burn fee:
        _config.minFee = 0.01 * 1e8; // 0.01 BTC
        _config.tiers = new FeeModel.FeeTier[](4);

        uint224 BTC_UNIT = 1e8;
        // < 200 BTC, 0.20%
        _config.tiers[0] = FeeModel.FeeTier(
            200 * BTC_UNIT,
            (fee.FEE_RATE_BASE() * 20) / 10000
        );
        // >=200 <500 BTC, 0.16%
        _config.tiers[1] = FeeModel.FeeTier(
            500 * BTC_UNIT,
            (fee.FEE_RATE_BASE() * 16) / 10000
        );
        // >=500 <1000 BTC, 0.12%
        _config.tiers[2] = FeeModel.FeeTier(
            1000 * BTC_UNIT,
            (fee.FEE_RATE_BASE() * 12) / 10000
        );
        // >=1000 BTC, 0.10%
        _config.tiers[3] = FeeModel.FeeTier(
            type(uint224).max,
            (fee.FEE_RATE_BASE() * 10) / 10000
        );

        fee.setDefaultFeeConfig(Operation.Burn, _config);
    }

    function setupDstChains(string memory chain, string memory tag) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);
        ContractConfig memory c = loadContractConfig(chain, tag);

        bytes32[] memory allChains = new bytes32[](10);

        // TODO: Add all chain ids

        FireBridge bridge = FireBridge(c.bridge);
        bytes32 selfChain = bridge.chain();
        bytes32[] memory dstChains = new bytes32[](allChains.length - 1);

        uint j = 0;
        for (uint i = 0; i < allChains.length; ++i) {
            bytes32 dstChain = allChains[i];
            if (dstChain != selfChain) {
                dstChains[j++] = dstChain;
            }
        }
        bridge.addDstChains(dstChains);
    }
}
