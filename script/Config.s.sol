// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript, stdJson, console} from "./Base.sol";

import {FBTC} from "../contracts/FBTC.sol";
import {FireBridge} from "../contracts/FireBridge.sol";
import {FBTCMinter, Operation} from "../contracts/Minter.sol";

contract ConfigScript is BaseScript {

    function addMinter(string memory chain, string memory tag, string memory minterTag) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        ContractConfig memory c = loadContractConfig(chain, tag);
        MinterConfig memory m = loadMinterConfig(minterTag);

        FBTCMinter minter = FBTCMinter(c.minter);

        minter.addOperator(Operation.Mint, m.opMint);
        minter.addOperator(Operation.Burn, m.opBurn);
        minter.addOperator(Operation.CrosschainConfirm, m.opCross);

        vm.stopBroadcast();
    }

    function addMerchaint(string memory chain, string memory tag, string memory merchantTag) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        ContractConfig memory c = loadContractConfig(chain, tag);
        MerchantConfig memory m = loadMerchantConfig(merchantTag);

        FireBridge bridge = FireBridge(c.bridge);
        bridge.addQualifiedUser(
            m.merchant,
            m.deposit,
            m.withdraw
        );
        vm.stopBroadcast();
    }

}
