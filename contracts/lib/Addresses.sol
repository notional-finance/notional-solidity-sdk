// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "interfaces/notional/NotionalProxy.sol";
import "interfaces/compound/CEtherInterface.sol";
import "interfaces/WETH9.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract MainnetAddresses {
    // PENDING DEPLOYMENT
    NotionalProxy internal constant NotionalV2 = NotionalProxy(address(0));
    ERC20 internal constant noteERC20 = ERC20(address(0));
    WETH9 internal constant weth = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    CEtherInterface internal constant cETH = CEtherInterface(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
}

abstract contract KovanAddresses {
    NotionalProxy internal constant NotionalV2 = NotionalProxy(0x0EAE7BAdEF8f95De91fDDb74a89A786cF891Eb0e);
    ERC20 internal constant noteERC20 = ERC20(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
    WETH9 internal constant WETH = WETH9(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
    CEtherInterface internal constant cETH = CEtherInterface(0x40575f9Eb401f63f66F4c434248ad83D3441bf61);
}

abstract contract LocalAddresses {
    NotionalProxy internal constant NotionalV2 = NotionalProxy(0xfa5f002555eb670019bD938604802f901208aE71);
    ERC20 internal constant noteERC20 = ERC20(0x7EaEceb29Fb4eB4277E2761cE3607DF3e73f2d3e);
}