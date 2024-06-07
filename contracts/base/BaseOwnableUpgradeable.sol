// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

abstract contract BaseOwnableUpgradeable is
    Ownable2StepUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    function __BaseOwnableUpgradeable_init(
        address initialOwner
    ) internal onlyInitializing {
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    function renounceOwnership() public override {
        revert("Unable to renounce ownership");
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    /// @notice Rescue and transfer assets locked in this contract.
    function rescue(address token, address to) external onlyOwner {
        if (token == address(0)) {
            (bool success, ) = payable(to).call{value: address(this).balance}(
                ""
            );
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(
                to,
                IERC20(token).balanceOf(address(this))
            );
        }
    }

    uint256[50] private __gap;
}
