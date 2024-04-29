// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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

    function setUp() public {}

    function deploy(
        string memory chain,
        string memory tag,
        bool useXTN
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address OWNER = vm.addr(deployerPrivateKey);
        console.log("owner", OWNER);

        vm.startBroadcast(deployerPrivateKey);

        bytes32 _mainChain = useXTN ? ChainCode.XTN : ChainCode.BTC;
        bridge = new FireBridge(OWNER, _mainChain);
        // bridge.addQualifiedUser(OWNER, "MockBTC1", "MockBTC2");

        feeModel = new FeeModel(OWNER);
        bridge.setFeeModel(address(feeModel));
        bridge.setFeeRecipient(OWNER);

        fbtc = new FBTC(OWNER, address(bridge));
        bridge.setToken(address(fbtc));

        minter = new FBTCMinter(OWNER, address(bridge));
        bridge.setMinter(address(minter));

        // minter.addOperator(Operation.Mint, OWNER);
        // minter.addOperator(Operation.Burn, OWNER);
        // minter.addOperator(Operation.CrosschainConfirm, OWNER);

        // gov = new FBTCGovernor(OWNER);
        // gov.setFBTC(address(fbtc));
        // gov.setBridge(address(bridge));
        // fbtc.transferOwnership(address(gov));
        // bridge.transferOwnership(address(gov));

        // gov.execTransaction(address(fbtc), 0, abi.encodeCall(fbtc.acceptOwnership, ()));
        // gov.execTransaction(address(bridge), 0, abi.encodeCall(bridge.acceptOwnership, ()));

        vm.stopBroadcast();

        saveChainConfig(
            string.concat(chain, "_", tag),
            address(minter),
            address(fbtc),
            address(feeModel),
            address(bridge)
        );
    }

    function run() public override {
        deploy("smnt", "dev", true);
    }
}
