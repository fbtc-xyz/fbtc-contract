// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BaseScript, stdJson, console} from "./Base.sol";

import {Operation} from "../contracts/Common.sol";
import {FBTC} from "../contracts/FBTC.sol";
import {FireBridge, ChainCode} from "../contracts/FireBridge.sol";
import {FBTCMinter} from "../contracts/FBTCMinter.sol";
import {FeeModel} from "../contracts/FeeModel.sol";
import {FBTCGovernorModule} from "../contracts/FBTCGovernorModule.sol";
import {OneStepDeploy, DeployConfig} from "./OneStepDeploy.sol";

contract DeployScript is BaseScript {
    FBTCMinter public minter;
    FireBridge public bridge;
    FBTC public fbtc;
    FeeModel public feeModel;

    using stdJson for string;

    function deployOneStep(
        string memory chain,
        string memory conf,
        string memory versionSalt
    ) public {
        string memory json = vm.readFile(getPath(string.concat(conf, ".json")));

        address owner = json.readAddress(".owner");

        vm.createSelectFork(chain);
        vm.startBroadcast(owner);

        bytes32[] memory allChains = json.readBytes32Array(".dstChains");
        bytes32 selfChain = bytes32(block.chainid);
        uint length = 0;
        for (uint i = 0; i < allChains.length; ++i) {
            bytes32 dstChain = allChains[i];
            if (dstChain != selfChain) {
                ++length;
            }
        }
        bytes32[] memory dstChains = new bytes32[](length);
        uint j = 0;
        for (uint i = 0; i < allChains.length; ++i) {
            bytes32 dstChain = allChains[i];
            if (dstChain != selfChain) {
                dstChains[j++] = dstChain;
            }
        }

        bytes32 saltSeed = bytes32(bytes(versionSalt));
        DeployConfig memory c = DeployConfig({
            factory: json.readAddress(".factory"),
            tag: saltSeed,
            mainChain: json.readBytes32(".mainChain"),
            owner: json.readAddress(".owner"),
            feeRecipientAndUpdater: json.readAddress(".feeRecipientAndUpdater"),
            mintOperator: json.readAddress(".mintOperator"),
            burnOperator: json.readAddress(".burnOperator"),
            crosschainOperator: json.readAddress(".crosschainOperator"),
            pauserAndLockers: json.readAddressArray(".pauserAndLockers"),
            userManager: json.readAddress(".userManager"),
            chainMananger: json.readAddress(".chainMananger"),
            fireBridgeCode: type(FireBridge).creationCode,
            proxyCode: type(ERC1967Proxy).creationCode,
            fbtcCode: type(FBTC).creationCode,
            feeModelCode: type(FeeModel).creationCode,
            minterCode: type(FBTCMinter).creationCode,
            governorModuleCode: type(FBTCGovernorModule).creationCode,
            dstChains: dstChains
        });

        address deployer = factory.deploy(
            3,
            bytes32(uint256(saltSeed) - 1),
            type(OneStepDeploy).creationCode
        );

        OneStepDeploy(deployer).deploy(c);

        address bridgeAddress = factory.getAddress(
            3,
            bytes32(uint256(saltSeed) + 1),
            deployer,
            ""
        );

        saveContractConfig(
            string.concat(versionSalt, "_", chain, "_", conf),
            FireBridge(bridgeAddress).minter(),
            FireBridge(bridgeAddress).fbtc(),
            FireBridge(bridgeAddress).feeModel(),
            bridgeAddress
        );
    }

    function run() public {
        console.log("Nothing to do");
    }
}
