// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {FBTC} from "./FBTC.sol";
import {FireBridge} from "./FireBridge.sol";

contract Enum {
    enum Operation {
        Call,
        DelegateCall
    }
}

interface ISafe {
    /// @dev Allows a Module to execute a Safe transaction without any further confirmations and return data
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success, bytes memory returnData);
}

contract FBTCGovernorModule is AccessControlDefaultAdminRules {
    bytes32 public constant FBTC_PAUSER_ROLE = "fbtc.pauser";
    bytes32 public constant LOCKER_RULE = "fbtc.locker";
    bytes32 public constant BRIDGE_PAUSER_RULE = "bridge.locker";
    bytes32 public constant USER_MANAGER_RULE = "bridge.usermanager";

    FBTC public fbtc;
    FireBridge public bridge;

    event FBTCSet(address indexed _fbtc);
    event BridgeSet(address indexed _bridge);

    constructor(address _admin) AccessControlDefaultAdminRules(0, _admin) {}

    function _callAsSafe(address _to, bytes memory _data) internal {
        (bool success, bytes memory _retData) = ISafe(safe())
            .execTransactionFromModuleReturnData(
                _to,
                0,
                _data,
                Enum.Operation.Call
            );
        if (!success) {
            assembly {
                let size := mload(_retData)
                revert(add(32, _retData), size)
            }
        }
    }

    function safe() public view returns (address) {
        return defaultAdmin();
    }

    function setFBTC(address _fbtc) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fbtc = FBTC(_fbtc);
        emit FBTCSet(_fbtc);
    }

    function setBridge(address _bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bridge = FireBridge(_bridge);
        emit BridgeSet(_bridge);
    }

    function lockUserFBTCTransfer(
        address _user
    ) external onlyRole(LOCKER_RULE) {
        _callAsSafe(address(fbtc), abi.encodeCall(fbtc.lockUser, (_user)));
    }

    function pauseFBTC() external onlyRole(FBTC_PAUSER_ROLE) {
        _callAsSafe(address(fbtc), abi.encodeCall(fbtc.pause, ()));
    }

    function pauseBridge() external onlyRole(BRIDGE_PAUSER_RULE) {
        _callAsSafe(address(bridge), abi.encodeCall(bridge.pause, ()));
    }

    function addQualifiedUser(
        address _qualifiedUser,
        string calldata _depositAddress,
        string calldata _withdrawalAddress
    ) external onlyRole(USER_MANAGER_RULE) {
        _callAsSafe(
            address(bridge),
            abi.encodeCall(
                bridge.addQualifiedUser,
                (_qualifiedUser, _depositAddress, _withdrawalAddress)
            )
        );
    }
}
