// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;

import "./Constants.sol";

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

    // function encodeLendTrade()
    // function encodeBorrowTrade()
    // function encodeAddLiquidity()
    // function encodeRemoveLiquidity()
    // function encodePurchaseNTokenResidual()
    // function encodeSettleCashDebt()
}