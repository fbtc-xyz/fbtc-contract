// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

import {Operation, ChainCode} from "./Common.sol";
import {FBTC} from "./FBTC.sol";
import {FireBridge} from "./FireBridge.sol";
import {FeeModel} from "./FeeModel.sol";
import {RoleBasedAccessControl} from "./base/RoleBasedAccessControl.sol";

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

contract FBTCGovernorModule is RoleBasedAccessControl {
    bytes32 public constant FBTC_PAUSER_ROLE = "1_fbtc_pauser";
    bytes32 public constant LOCKER_ROLE = "2_fbtc_locker";
    bytes32 public constant BRIDGE_PAUSER_ROLE = "3_bridge_pauser";
    bytes32 public constant USER_MANAGER_ROLE = "4_bridge_user_manager";
    bytes32 public constant CHAIN_MANAGER_ROLE = "5_bridge_chain_manager";
    bytes32 public constant FEE_UPDATER_ROLE = "6_bridge_fee_updater";

    FBTC public fbtc;
    event FBTCSet(address indexed _fbtc);

    constructor(address _owner, address _fbtc) {
        initialize(_owner, _fbtc);
    }

    function initialize(address _owner, address _fbtc) public initializer {
        __BaseOwnableUpgradeable_init(_owner);
        fbtc = FBTC(_fbtc);
    }

    function bridge() public view returns (FireBridge _bridge) {
        _bridge = FireBridge(fbtc.bridge());
    }

    function feeModel() public view returns (FeeModel _feeModel) {
        _feeModel = FeeModel(bridge().feeModel());
    }

    function _call(address _to, bytes memory _data) internal {
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
        return owner();
    }

    function setFBTC(address _fbtc) external onlyOwner {
        fbtc = FBTC(_fbtc);
        emit FBTCSet(_fbtc);
    }

    function lockUserFBTCTransfer(
        address _user
    ) external onlyRole(LOCKER_ROLE) {
        _call(address(fbtc), abi.encodeCall(fbtc.lockUser, (_user)));
    }

    function pauseFBTC() external onlyRole(FBTC_PAUSER_ROLE) {
        _call(address(fbtc), abi.encodeCall(fbtc.pause, ()));
    }

    function pauseBridge() external onlyRole(BRIDGE_PAUSER_ROLE) {
        FireBridge _bridge = bridge();
        _call(address(_bridge), abi.encodeCall(_bridge.pause, ()));
    }

    function addQualifiedUser(
        address _qualifiedUser,
        string calldata _depositAddress,
        string calldata _withdrawalAddress
    ) external onlyRole(USER_MANAGER_ROLE) {
        FireBridge _bridge = bridge();
        _call(
            address(_bridge),
            abi.encodeCall(
                _bridge.addQualifiedUser,
                (_qualifiedUser, _depositAddress, _withdrawalAddress)
            )
        );
    }

    function lockQualifiedUser(
        address _qualifiedUser
    ) external onlyRole(USER_MANAGER_ROLE) {
        FireBridge _bridge = bridge();
        _call(
            address(_bridge),
            abi.encodeCall(_bridge.lockQualifiedUser, (_qualifiedUser))
        );
    }

    function addDstChains(
        bytes32[] memory _dstChains
    ) external onlyRole(CHAIN_MANAGER_ROLE) {
        FireBridge _bridge = bridge();
        _call(
            address(_bridge),
            abi.encodeCall(_bridge.addDstChains, (_dstChains))
        );
    }

    function removeDstChains(
        bytes32[] memory _dstChains
    ) external onlyRole(CHAIN_MANAGER_ROLE) {
        FireBridge _bridge = bridge();
        _call(
            address(_bridge),
            abi.encodeCall(_bridge.removeDstChains, (_dstChains))
        );
    }

    function updateETHCrossChainMinFee(
        bytes32 chain,
        uint256 _minFee
    ) external onlyRole(FEE_UPDATER_ROLE) {
        require(
            _minFee <= 0.01 * 1e8,
            "Min fee should be lower than 0.01 FBTC"
        );
        FeeModel _feeModel = feeModel();
        FeeModel.FeeConfig memory config = _feeModel.getCrosschainFeeConfig(
            chain
        );
        require(config.tiers.length > 0, "Config not exists");
        config.minFee = _minFee;
        _call(
            address(_feeModel),
            abi.encodeCall(_feeModel.setCrosschainFeeConfig, (chain, config))
        );
    }
}
