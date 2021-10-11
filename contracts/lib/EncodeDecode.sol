// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;

import "./Constants.sol";
import "./Types.sol";

library EncodeDecode {

    /// @notice Decodes asset ids
    function decodeERC1155Id(uint256 id)
        internal
        pure
        returns (
            uint256 currencyId,
            uint256 maturity,
            uint256 assetType
        )
    {
        assetType = uint8(id);
        maturity = uint40(id >> 8);
        currencyId = uint16(id >> 48);
    }

    /// @notice Encodes asset ids
    function encodeERC1155Id(
        uint256 currencyId,
        uint256 maturity,
        uint256 assetType
    ) internal pure returns (uint256) {
        require(currencyId <= Constants.MAX_CURRENCIES);
        require(maturity <= type(uint40).max);
        require(assetType <= Constants.MAX_LIQUIDITY_TOKEN_INDEX);

        return
            uint256(
                (bytes32(uint256(uint16(currencyId))) << 48) |
                (bytes32(uint256(uint40(maturity))) << 8) |
                bytes32(uint256(uint8(assetType)))
            );
    }

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

    function encodeBorrowTrade(
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 maxImpliedRate
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    (uint8(TradeActionType.Borrow) << 248) |
                        (marketIndex << 240) |
                        (fCashAmount << 152) |
                        (maxImpliedRate << 120)
                )
            );
    }

    function encodeAddLiquidity(
        uint8 marketIndex,
        uint88 assetCashAmount,
        uint32 minImpliedRate,
        uint32 maxImpliedRate
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    (uint8(TradeActionType.AddLiquidity) << 248) |
                        (marketIndex << 240) |
                        (assetCashAmount << 152) |
                        (minImpliedRate << 120) |
                        (maxImpliedRate << 88)
                )
            );
    }

    function encodeRemoveLiquidity(
        uint8 marketIndex,
        uint88 tokenAmount,
        uint32 minImpliedRate,
        uint32 maxImpliedRate
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    (uint8(TradeActionType.RemoveLiquidity) << 248) |
                        (marketIndex << 240) |
                        (tokenAmount << 152) |
                        (minImpliedRate << 120) |
                        (maxImpliedRate << 88)
                )
            );
    }

    function encodePurchaseNTokenResidual(
        uint32 maturity,
        int88 fCashResidualAmount
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    (uint8(TradeActionType.PurchaseNTokenResidual) << 248) |
                        (maturity << 216) |
                        (uint256(fCashResidualAmount) << 128)
                )
            );
    }

    function encodeSettleCashDebt(
        address counterparty,
        int88 fCashAmountToSettle
    ) internal pure returns (bytes32) {
        return
            bytes32(
                uint256(
                    (uint8(TradeActionType.SettleCashDebt) << 248) |
                        (uint256(counterparty) << 88) |
                        (uint256(fCashAmountToSettle))
                )
            );
    }
}