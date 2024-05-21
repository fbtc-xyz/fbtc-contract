// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.20;

import {FToken} from "./base/FToken.sol";

contract FBTC is FToken {
    constructor(address _owner, address _bridge) {
        initialize(_owner, _bridge);
    }

    function initialize(address _owner, address _bridge) public initializer {
        __FToken_init(_owner, _bridge, "Fire Bitcoin", "FBTC");
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }
}
