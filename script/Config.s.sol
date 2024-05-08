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
        fee.setDefaultFeeConfig(
            Operation.Mint,
            FeeModel.FeeConfig(false, 0, 0)
        );
        fee.setDefaultFeeConfig(
            Operation.Burn,
            FeeModel.FeeConfig(
                true,
                fee.FEE_RATE_BASE() / 1000, // 0.1%
                0.003 * 1e8 // 0.003 FBTC
            )
        );
        fee.setDefaultFeeConfig(
            Operation.CrosschainRequest,
            FeeModel.FeeConfig(
                true,
                fee.FEE_RATE_BASE() / 10000, // 0.01%
                0.0001 * 1e8 // 0.0001 FBTC
            )
        );
    }
}
