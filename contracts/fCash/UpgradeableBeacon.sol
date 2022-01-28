// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/// @dev Re-exporting to make available to brownie
contract nUpgradeableBeacon is UpgradeableBeacon {
    constructor(address implementation_) UpgradeableBeacon(implementation_) {}
}