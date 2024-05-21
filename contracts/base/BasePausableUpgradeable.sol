// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

import {BaseOwnableUpgradeable} from "./BaseOwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

abstract contract BasePausableUpgradeable is
    BaseOwnableUpgradeable,
    PausableUpgradeable
{
    function __BasePausableUpgradeable_init(
        address initialOwner
    ) internal onlyInitializing {
        __BaseOwnableUpgradeable_init(initialOwner);
        __Pausable_init();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
