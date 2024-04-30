// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";

contract BaseScript is Script {
    using stdJson for string;

    struct MinterConfig {
        address opMint;
        address opBurn;
        address opCross;
    }

    struct MerchantConfig {
        address merchant;
        string deposit;
        string withdraw;
    }

    struct ContractConfig {
        address minter;
        address fbtc;
        address feeModel;
        address bridge;
    }


    address public owner;
    uint256 public deployerPrivateKey;

    function setUp() public {
        deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        owner = vm.addr(deployerPrivateKey);
        console.log("owner", owner);
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

    function loadMerchantConfig(
        string memory name
    ) public view returns (MerchantConfig memory i) {
        string memory path = getPath("config.json");
        string memory json = vm.readFile(path);
        bytes memory infraBytes = json.parseRaw(string.concat(".merchant.", name));
        i = abi.decode(infraBytes, (MerchantConfig));
    }

    function loadMinterConfig(
        string memory name
    ) public view returns (MinterConfig memory c) {
        string memory path = getPath("config.json");
        string memory json = vm.readFile(path);
        bytes memory _bytes = json.parseRaw(string.concat(".minter.", name));
        c = abi.decode(_bytes, (MinterConfig));
    }

    function loadContractConfig(
        string memory chain,
        string memory tag
    ) public view returns (ContractConfig memory c) {
        string memory name = string.concat(chain, "_", tag);
        string memory path = getPath(string.concat("addresses/", name, ".json"));
        string memory json = vm.readFile(path);
        bytes memory _bytes = json.parseRaw(".");
        c = abi.decode(_bytes, (ContractConfig));
    }
    function saveContractConfig(
        string memory chain,
        string memory tag,
        address minter,
        address fbtc,
        address fee,
        address bridge
    ) public {
        string memory name = string.concat(chain, "_", tag);
        string memory path = getPath(string.concat("addresses/", name, ".json"));

        string memory json = "key";
        json.serialize("1_minter", minter);
        json.serialize("2_fbtc", fbtc);
        json.serialize("3_fee", fee);
        string memory tmp = json.serialize("4_bridge", bridge);
        tmp.write(path);
    }

    function run() public virtual {
        console.log("Nothing to do");
    }
}
