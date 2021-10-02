// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;

import "./Types.sol";

library EncodeDecode {
    // function encodeERC1155ID()
    // function decodeERC1155ID()

    function encodeLendTrade(
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 minImpliedRate
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    (uint8(TradeActionType.Lend) << 248) |
                        (marketIndex << 240) |
                        (fCashAmount << 152) |
                        (minImpliedRate << 120)
                )
            );
    }

    // function decodeLendTrade()

    // function encodeBorrowTrade()
    // function decodeBorrowTrade()

    // function encodeAddLiquidity()
    // function decodeAddLiquidity()

    // function encodeRemoveLiquidity()
    // function decodeRemoveLiquidity()

    // function encodePurchaseNTokenResidual()
    // function decodePurchaseNTokenResidual()

    // function encodeSettleCashDebt()
    // function decodeSettleCashDebt()

    // function getMarketIndex()
    // function getMaturityFromMarketIndex()
}