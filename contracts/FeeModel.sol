// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

import {Operation, Request} from "./Common.sol";
import {BaseOwnableUpgradeable} from "./base/BaseOwnableUpgradeable.sol";

contract FeeModel is BaseOwnableUpgradeable {
    uint32 public constant FEE_RATE_BASE = 1_000_000;

    struct FeeTier {
        uint224 amountTier; // Amount tier.
        uint32 feeRate; // Fee rate.
    }

    struct FeeConfig {
        uint256 minFee; // Minimum fee.
        FeeTier[] tiers; // Order by amount asc.
    }

    mapping(Operation op => FeeConfig cfg) defaultFeeConfig;
    mapping(bytes32 dstChain => FeeConfig cfg) crosschainFeeConfig;

    event DefaultFeeConfigSet(Operation indexed _op, FeeConfig _config);
    event CrosschainFeeConfigSet(bytes32 indexed _chain, FeeConfig _config);

    constructor(address _owner) {
        initialize(_owner);
    }

    function initialize(address _owner) public initializer {
        __BaseOwnableUpgradeable_init(_owner);
    }

    function _validateOp(Operation op) internal pure {
        require(
            op == Operation.Mint ||
                op == Operation.Burn ||
                op == Operation.CrosschainRequest,
            "Invalid op"
        );
    }

    function _getFee(
        uint256 _amount,
        FeeConfig storage _config
    ) internal view returns (uint256 _fee) {
        uint256 minFee = _config.minFee;
        require(minFee < _amount, "amount lower than minimal fee");

        uint256 length = _config.tiers.length;
        require(length > 0, "Empty fee config");

        for (uint i = 0; i < length; i++) {
            FeeTier storage tier = _config.tiers[i];
            if (i == length - 1 || _amount < uint256(tier.amountTier)) {
                // Note: Use `<` instead of `<=`, the border is not included.
                _fee = (uint256(tier.feeRate) * _amount) / FEE_RATE_BASE;
                break;
            }
        }

        if (_fee < minFee) {
            // Minimal fee
            _fee = minFee;
        }
    }

    function _validateConfig(FeeConfig calldata _config) internal pure {
        uint224 prevAmount = 0;
        require(
            _config.minFee <= 0.03 * 1e8,
            "Minimal fee should not exceed 0.03 FBTC"
        );
        require(_config.tiers.length > 0, "Empty fee config");

        for (uint i = 0; i < _config.tiers.length; i++) {
            FeeTier calldata tier = _config.tiers[i];

            uint224 amount = tier.amountTier;
            require(amount >= prevAmount, "Tiers not in order");
            prevAmount = amount;

            require(
                tier.feeRate <= FEE_RATE_BASE / 100,
                "Fee rate too high, > 1%"
            );
            if (i == _config.tiers.length - 1) {
                require(
                    amount == type(uint224).max,
                    "The last tier should be uint224.max"
                );
            }
        }
    }

    function setDefaultFeeConfig(
        Operation _op,
        FeeConfig calldata _config
    ) external onlyOwner {
        _validateOp(_op);
        _validateConfig(_config);
        defaultFeeConfig[_op] = _config;
        emit DefaultFeeConfigSet(_op, _config);
    }

    function setCrosschainFeeConfig(
        bytes32 _dstChain,
        FeeConfig calldata _config
    ) external onlyOwner {
        _validateConfig(_config);
        crosschainFeeConfig[_dstChain] = _config;
        emit CrosschainFeeConfigSet(_dstChain, _config);
    }

    // View functions.

    function getFee(Request calldata r) external view returns (uint256 _fee) {
        _validateOp(r.op);
        FeeConfig storage _config;
        if (r.op == Operation.CrosschainRequest) {
            _config = crosschainFeeConfig[r.dstChain];
            if (_config.tiers.length > 0) return _getFee(r.amount, _config);
        }
        _config = defaultFeeConfig[r.op];
        if (_config.tiers.length > 0) return _getFee(r.amount, _config);
        revert("Fee config not set");
    }

    function getDefaultFeeConfig(
        Operation _op
    ) external view returns (FeeConfig memory _config) {
        _config = defaultFeeConfig[_op];
        require(_config.tiers.length > 0, "Fee config not set");
    }

    function getCrosschainFeeConfig(
        bytes32 _dstChain
    ) external view returns (FeeConfig memory _config) {
        _config = crosschainFeeConfig[_dstChain];
        require(_config.tiers.length > 0, "Fee config not set");
    }
}
