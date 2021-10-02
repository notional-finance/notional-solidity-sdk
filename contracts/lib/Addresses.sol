// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "interfaces/notional/NotionalProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract MainnetAddresses {
    // PENDING DEPLOYMENT
    NotionalProxy internal constant NotionalV2 = NotionalProxy(address(0));
    ERC20 internal constant noteERC20 = ERC20(address(0));
}

abstract contract KovanAddresses {
    NotionalProxy internal constant NotionalV2 = NotionalProxy(0x0EAE7BAdEF8f95De91fDDb74a89A786cF891Eb0e);
    ERC20 internal constant noteERC20 = ERC20(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
}

abstract contract LocalAddresses {
    NotionalProxy internal constant NotionalV2 = NotionalProxy(0xfa5f002555eb670019bD938604802f901208aE71);
    ERC20 internal constant noteERC20 = ERC20(0x7EaEceb29Fb4eB4277E2761cE3607DF3e73f2d3e);
}