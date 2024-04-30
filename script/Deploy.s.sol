// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {BaseScript, stdJson, console} from "./Base.sol";

import {FBTC} from "../contracts/FBTC.sol";
import {FireBridge, ChainCode} from "../contracts/FireBridge.sol";
import {FBTCMinter, Operation} from "../contracts/Minter.sol";
import {FeeModel} from "../contracts/FeeModel.sol";
import {FBTCGovernor} from "../contracts/FBTCGovernor.sol";

contract DeployScript is BaseScript {
    FBTCMinter public minter;
    FireBridge public bridge;
    FBTC public fbtc;
    FeeModel public feeModel;
    FBTCGovernor public gov;

    using stdJson for string;

    function deploy(
        string memory chain,
        string memory tag,
        bool useXTN
    ) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        bytes32 _mainChain = useXTN ? ChainCode.XTN : ChainCode.BTC;
        bridge = new FireBridge(owner, _mainChain);

        // Wrap into proxy.
        bridge= FireBridge(address(new ERC1967Proxy(
            address(bridge),
            abi.encodeCall(bridge.initialize, (owner))
        )));

        feeModel = new FeeModel(owner);
        bridge.setFeeModel(address(feeModel));
        bridge.setFeeRecipient(owner);

        fbtc = new FBTC(owner, address(bridge));
        bridge.setToken(address(fbtc));

        minter = new FBTCMinter(owner, address(bridge));
        bridge.setMinter(address(minter));

        // gov = new FBTCGovernor(owner);
        // gov.setFBTC(address(fbtc));
        // gov.setBridge(address(bridge));
        // fbtc.transferOwnership(address(gov));
        // bridge.transferOwnership(address(gov));

        // gov.execTransaction(address(fbtc), 0, abi.encodeCall(fbtc.acceptOwnership, ()));
        // gov.execTransaction(address(bridge), 0, abi.encodeCall(bridge.acceptOwnership, ()));

        vm.stopBroadcast();

        saveContractConfig(
            chain, tag,
            address(minter),
            address(fbtc),
            address(feeModel),
            address(bridge)
        );
    }


    function upgradeBridge(string memory chain, string memory tag, bool useXTN) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        bytes32 _mainChain = useXTN ? ChainCode.XTN : ChainCode.BTC;
        FireBridge newImpl = new FireBridge(owner, _mainChain);

        ContractConfig memory c = loadContractConfig(chain, tag);
        FireBridge proxy = FireBridge(c.bridge);
        proxy.upgradeToAndCall(address(newImpl), "");
        console.log("Upgrade new impl");
        console.log(address(newImpl));
    }

}
