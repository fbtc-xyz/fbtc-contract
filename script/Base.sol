// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract BaseScript is Script {
    using stdJson for string;

    struct InfraConfig {
        address opMint;
        address opBurn;
        address opCross;
        address merchant1;
        bytes deposit1;
        bytes withdraw1;
        address merchant2;
        bytes deposit2;
        bytes withdraw2;
    }

    struct ContractConfig {
        address minter;
        address fbtc;
        address feeModel;
        address bridge;
    }

    function getChainPath(
        string memory file
    ) public view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory chainStr = vm.toString(block.chainid);
        string memory path = string.concat(
            root,
            "/script/deployments/",
            chainStr,
            "/",
            file
        );
        return path;
    }

    function getPath(string memory file) public view returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/deployments/", file);
        return path;
    }

    function loadInfraConfig(
        string memory name
    ) public view returns (InfraConfig memory i) {
        string memory path = getPath("config.json");
        string memory json = vm.readFile(path);
        bytes memory infraBytes = json.parseRaw(string.concat(".infra.", name));
        i = abi.decode(infraBytes, (InfraConfig));
    }

    function loadChainConfig(
        string memory tag
    ) public view returns (ContractConfig memory c) {
        string memory path = getPath(string.concat("addresses/", tag, ".json"));
        string memory json = vm.readFile(path);
        bytes memory _bytes = json.parseRaw(".");
        c = abi.decode(_bytes, (ContractConfig));
    }

    function saveChainConfig(
        string memory tag,
        ContractConfig memory c
    ) public {
        saveChainConfig(tag, c.minter, c.fbtc, c.feeModel, c.bridge);
    }

    function saveChainConfig(
        string memory tag,
        address minter,
        address fbtc,
        address fee,
        address bridge
    ) public {
        string memory path = getPath(string.concat("addresses/", tag, ".json"));

        string memory json = "key";
        json.serialize("1_minter", minter);
        json.serialize("2_fbtc", fbtc);
        json.serialize("3_fee", fee);
        string memory tmp = json.serialize("4_bridge", bridge);
        tmp.write(path);
    }

    function run() public virtual {
        ContractConfig memory c = loadChainConfig("seth_qa");
        console.log(c.bridge);
    }
}
