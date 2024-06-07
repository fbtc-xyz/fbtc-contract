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
        bridge = FireBridge(
            address(
                new ERC1967Proxy(
                    address(bridge),
                    abi.encodeCall(bridge.initialize, (owner))
                )
            )
        );

        feeModel = new FeeModel(owner);
        bridge.setFeeModel(address(feeModel));
        bridge.setFeeRecipient(owner);

        fbtc = new FBTC(owner, address(bridge));
        bridge.setToken(address(fbtc));

        minter = new FBTCMinter(owner, address(bridge));
        bridge.setMinter(address(minter));

        new FBTCGovernorModule(owner, address(fbtc));

        vm.stopBroadcast();

        saveContractConfig(
            chain,
            tag,
            address(minter),
            address(fbtc),
            address(feeModel),
            address(bridge)
        );
    }

    function deploy2(
        string memory chain,
        string memory tag,
        bool useXTN
    ) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        bytes32 _mainChain = useXTN ? ChainCode.XTN : ChainCode.BTC;

        // Set salt
        salt = bytes32(bytes(tag));

        address impl = _deploy(
            abi.encodePacked(
                type(FireBridge).creationCode,
                abi.encode(owner, _mainChain)
            )
        );

        // Wrap into proxy.
        bridge = FireBridge(
            _deploy(
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(impl, abi.encodeCall(bridge.initialize, (owner)))
                )
            )
        );

        feeModel = FeeModel(
            _deploy(
                abi.encodePacked(type(FeeModel).creationCode, abi.encode(owner))
            )
        );

        bridge.setFeeModel(address(feeModel));
        bridge.setFeeRecipient(owner);

        fbtc = FBTC(
            _deploy(
                abi.encodePacked(
                    type(FBTC).creationCode,
                    abi.encode(owner, address(bridge))
                )
            )
        );

        bridge.setToken(address(fbtc));

        minter = FBTCMinter(
            _deploy(
                abi.encodePacked(
                    type(FBTCMinter).creationCode,
                    abi.encode(owner, address(bridge))
                )
            )
        );

        bridge.setMinter(address(minter));

        bytes32[] memory allChains = new bytes32[](2);
        allChains[
            0
        ] = 0x0000000000000000000000000000000000000000000000000000000000aa36a7; // SETH
        allChains[
            1
        ] = 0x000000000000000000000000000000000000000000000000000000000000138b; // SMNT
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

        _deploy(
            abi.encodePacked(
                type(FBTCGovernorModule).creationCode,
                abi.encode(owner, address(fbtc))
            )
        );

        vm.stopBroadcast();

        saveContractConfig(
            chain,
            tag,
            address(minter),
            address(fbtc),
            address(feeModel),
            address(bridge)
        );
    }

    function deployProd(
        string memory chain,
        string memory tag,
        address tokenAddress,
        bytes32 tokenSalt,
        address bridgeAddress,
        bytes32 bridgeSalt
    ) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        // Set salt
        salt = bytes32(bytes(tag));

        address impl = _deploy(
            abi.encodePacked(
                type(FireBridge).creationCode,
                abi.encode(owner, ChainCode.BTC)
            )
        );

        // Wrap into proxy.
        bridge = FireBridge(
            factory.deploy(
                3,
                bridgeSalt,
                abi.encodePacked(
                    type(ERC1967Proxy).creationCode,
                    abi.encode(impl, abi.encodeCall(bridge.initialize, (owner)))
                )
            )
        );
        require(address(bridge) == bridgeAddress, "Bridge not match");

        feeModel = FeeModel(
            _deploy(
                abi.encodePacked(type(FeeModel).creationCode, abi.encode(owner))
            )
        );

        bridge.setFeeModel(address(feeModel));
        bridge.setFeeRecipient(owner);

        fbtc = FBTC(
            factory.deploy(
                3,
                tokenSalt,
                abi.encodePacked(
                    type(FBTC).creationCode,
                    abi.encode(owner, address(bridge))
                )
            )
        );
        require(address(fbtc) == tokenAddress, "Token not match");

        bridge.setToken(address(fbtc));

        minter = FBTCMinter(
            _deploy(
                abi.encodePacked(
                    type(FBTCMinter).creationCode,
                    abi.encode(owner, address(bridge))
                )
            )
        );

        bridge.setMinter(address(minter));

        bytes32[] memory allChains = new bytes32[](2);
        allChains[
            0
        ] = 0x0000000000000000000000000000000000000000000000000000000000000001; // ETH
        allChains[
            1
        ] = 0x0000000000000000000000000000000000000000000000000000000000001388; // MNT
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

        _deploy(
            abi.encodePacked(
                type(FBTCGovernorModule).creationCode,
                abi.encode(owner, address(fbtc))
            )
        );

        vm.stopBroadcast();

        saveContractConfig(
            chain,
            tag,
            address(minter),
            address(fbtc),
            address(feeModel),
            address(bridge)
        );
    }

    function deployOneStep(
        string memory chain,
        string memory conf,
        string memory version
    ) public {
        vm.createSelectFork(chain);
        vm.startBroadcast(deployerPrivateKey);

        string memory json = vm.readFile(getPath(string.concat(conf, ".json")));

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

        bytes32 saltSeed = bytes32(bytes(version));
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
            chain,
            string.concat(version, "_", conf),
            FireBridge(bridgeAddress).minter(),
            FireBridge(bridgeAddress).fbtc(),
            FireBridge(bridgeAddress).feeModel(),
            bridgeAddress
        );
    }

    function run() public {
        // deploy2("seth", "test_v1", true);
    }

    function upgradeBridge(
        string memory chain,
        string memory tag,
        bool useXTN
    ) public {
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
