// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "interfaces/notional/NotionalProxy.sol";
import "interfaces/compound/ICEther.sol";
import "interfaces/WETH9.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

library MainnetAddresses {
    NotionalProxy internal constant NotionalV2 = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    ERC20 internal constant NoteERC20 = ERC20(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
    WETH9 internal constant WETH = WETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ICEther internal constant cETH = ICEther(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
}

library KovanAddresses {
    NotionalProxy internal constant NotionalV2 = NotionalProxy(0x0EAE7BAdEF8f95De91fDDb74a89A786cF891Eb0e);
    ERC20 internal constant NoteERC20 = ERC20(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
    WETH9 internal constant WETH = WETH9(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
    ICEther internal constant cETH = ICEther(0x40575f9Eb401f63f66F4c434248ad83D3441bf61);
}

library LocalAddresses {
    NotionalProxy internal constant NotionalV2 = NotionalProxy(0xfa5f002555eb670019bD938604802f901208aE71);
    ERC20 internal constant NoteERC20 = ERC20(0x7EaEceb29Fb4eB4277E2761cE3607DF3e73f2d3e);
    WETH9 internal constant WETH = WETH9(address(0));
    ICEther internal constant cETH = ICEther(address(0));
}

library Addresses {
    uint256 internal constant MAINNET = 1;
    uint256 internal constant KOVAN = 42;
    uint256 internal constant LOCAL = 1337;

    function getNotionalV2() internal view returns (NotionalProxy) {
        uint256 chainId;
        assembly { chainId := chainid() }

        if (chainId == MAINNET) {
            return MainnetAddresses.NotionalV2;
        } else if (chainId == KOVAN) {
            return KovanAddresses.NotionalV2;
        } else if (chainId == LOCAL) {
            return LocalAddresses.NotionalV2;
        } else {
            revert();
        }
    }

    function getNOTE() internal view returns (ERC20) {
        uint256 chainId;
        assembly { chainId := chainid() }

        if (chainId == MAINNET) {
            return MainnetAddresses.NoteERC20;
        } else if (chainId == KOVAN) {
            return KovanAddresses.NoteERC20;
        } else if (chainId == LOCAL) {
            return LocalAddresses.NoteERC20;
        } else {
            revert();
        }
    }

    function getCEth() internal view returns (ICEther) {
        uint256 chainId;
        assembly { chainId := chainid() }

        if (chainId == MAINNET) {
            return MainnetAddresses.cETH;
        } else if (chainId == KOVAN) {
            return KovanAddresses.cETH;
        } else if (chainId == LOCAL) {
            return LocalAddresses.cETH;
        } else {
            revert();
        }
    }

    function getWETH() internal view returns (WETH9) {
        uint256 chainId;
        assembly { chainId := chainid() }

        if (chainId == MAINNET) {
            return MainnetAddresses.WETH;
        } else if (chainId == KOVAN) {
            return KovanAddresses.WETH;
        } else if (chainId == LOCAL) {
            return LocalAddresses.WETH;
        } else {
            revert();
        }
    }
}
