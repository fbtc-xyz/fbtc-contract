// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Operation, Request} from "./Common.sol";
import {FireBridge} from "./FireBridge.sol";

contract FBTCMinter is Ownable {
    FireBridge public bridge;

    mapping(address _operator => mapping(Operation _op => bool _status))
        public roles;

    event OperatorAdded(Operation indexed _op, address indexed _operator);
    event OperatorRemoved(Operation indexed _op, address indexed _operator);
    event BridgeUpdated(address indexed newBridge, address indexed oldBridge);

    modifier onlyRole(Operation _op) {
        require(roles[msg.sender][_op], "Invalid role of caller");
        _;
    }

    constructor(address _owner, address _bridge) Ownable(_owner) {
        bridge = FireBridge(_bridge);
    }

    function addOperator(Operation _op, address _operator) external onlyOwner {
        roles[_operator][_op] = true;
        emit OperatorAdded(_op, _operator);
    }

    function removeOperator(
        Operation _op,
        address _operator
    ) external onlyOwner {
        roles[_operator][_op] = false;
        emit OperatorRemoved(_op, _operator);
    }

    function setBridge(address _bridge) external onlyOwner {
        address oldBridge = address(bridge);
        bridge = FireBridge(_bridge);
        emit BridgeUpdated(_bridge, oldBridge);
    }

    /// Operator methods.

    function confirmMintRequest(
        bytes32 _hash
    ) external onlyRole(Operation.Mint) {
        bridge.confirmMintRequest(_hash);
    }

    function confirmBurnRequest(
        bytes32 _hash,
        bytes32 _withdrawalTxid,
        uint256 _outputIndex
    ) external onlyRole(Operation.Burn) {
        bridge.confirmBurnRequest(_hash, _withdrawalTxid, _outputIndex);
    }

    function confirmCrosschainRequest(
        Request calldata r
    )
        external
        onlyRole(Operation.CrosschainConfirm)
        returns (bytes32 _hash, Request memory _r)
    {
        (_hash, _r) = bridge.confirmCrosschainRequest(r);
    }

    function batchConfirmCrosschainRequest(
        Request[] calldata rs
    ) external onlyRole(Operation.CrosschainConfirm) {
        for (uint256 i = 0; i < rs.length; i++) {
            bridge.confirmCrosschainRequest(rs[i]);
        }
    }
}
