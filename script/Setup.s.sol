// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BaseScript, stdJson, console} from "./Base.sol";

import {FBTC} from "../contracts/FBTC.sol";
import {FireBridge} from "../contracts/FireBridge.sol";
import {FBTCMinter, Operation} from "../contracts/Minter.sol";

contract SetupScript is BaseScript {
    function setUp() public {}

    function setupConfig(ContractConfig memory c, InfraConfig memory i) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(deployerPrivateKey);
        console.log("owner", owner);

        vm.startBroadcast(deployerPrivateKey);

        // FBTC fbtc = FBTC(c.fbtc);
        FireBridge bridge = FireBridge(c.bridge);
        FBTCMinter minter = FBTCMinter(c.minter);

        // bridge.removeQualifiedUser(0x966D99a04Fec209cf093C67e04A1c4Db1b22bEbd);
        // bridge.removeQualifiedUser(0xe21AE59Ef02cEf7c6Aed8eEfAdf5C45714D429F0);

        bridge.addQualifiedUser(i.merchant1, i.deposit1, i.withdraw1);
        bridge.addQualifiedUser(i.merchant2, i.deposit2, i.withdraw2);
        bridge.addQualifiedUser(owner, "MockBTCAddr1", "MockBTCAddr2");

        minter.addOperator(Operation.Mint, i.opMint);
        minter.addOperator(Operation.Burn, i.opBurn);
        minter.addOperator(Operation.CrosschainConfirm, i.opCross);

        vm.stopBroadcast();
    }

    function initConfig(string memory chain, string memory tag) public {
        vm.createSelectFork(chain);
        string memory finalTag = string.concat(chain, "_", tag);
        InfraConfig memory i = loadInfraConfig(finalTag);
        ContractConfig memory c = loadChainConfig(finalTag);
        setupConfig(c, i);
    }

    function run() public override {
        // vm.createSelectFork("smnt");
        // InfraConfig memory i = loadInfraConfig("qa");
        // ContractConfig memory c = loadChainConfig("smnt_qa");
        // setupConfig(c, i);
    }
}
