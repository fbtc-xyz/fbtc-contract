// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {FBTC} from "./FBTC.sol";
import {FireBridge} from "./FireBridge.sol";

contract FBTCGovernor is AccessControlDefaultAdminRules {
    bytes32 public constant FBTC_PAUSER_ROLE = "fbtc.pauser";
    bytes32 public constant LOCKER_RULE = "fbtc.locker";
    bytes32 public constant BRIDGE_PAUSER_RULE = "bridge.locker";
    bytes32 public constant USER_MANAGER_RULE = "bridge.usermanager";

    FBTC public fbtc;
    FireBridge public bridge;

    event FBTCSet(address indexed _fbtc);
    event BridgeSet(address indexed _bridge);

    constructor(address _admin) AccessControlDefaultAdminRules(0, _admin) {}

    function setFBTC(address _fbtc) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fbtc = FBTC(_fbtc);
        emit FBTCSet(_fbtc);
    }

    function setBridge(address _bridge) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bridge = FireBridge(_bridge);
        emit BridgeSet(_bridge);
    }

    function execTransaction(
        address _to,
        uint256 _value,
        bytes calldata _data
    )
        external
        payable
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (bytes memory _retData)
    {
        bool success;
        (success, _retData) = _to.call{value: _value}(_data);
        if (!success) {
            assembly {
                let size := mload(_retData)
                revert(add(32, _retData), size)
            }
        }
    }

    function lockUserFBTCTransfer(
        address _user
    ) external onlyRole(LOCKER_RULE) {
        fbtc.lockUser(_user);
    }

    function pauseFBTC() external onlyRole(FBTC_PAUSER_ROLE) {
        fbtc.pause();
    }

    function pauseBridge() external onlyRole(BRIDGE_PAUSER_RULE) {
        bridge.pause();
    }

    function addQualifiedUser(
        address _qualifiedUser,
        bytes calldata _depositAddress,
        bytes calldata _withdrawalAddress
    ) external onlyRole(USER_MANAGER_RULE) {
        bridge.addQualifiedUser(
            _qualifiedUser,
            _depositAddress,
            _withdrawalAddress
        );
    }
}
