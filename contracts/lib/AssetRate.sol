// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;
pragma abicoder v2;

import "./SafeInt256.sol";
import "./Types.sol";

library AssetRate {
    using SafeInt256 for int256;

    // Asset rates are in 1e18 decimals (cToken exchange rates), internal balances
    // are in 1e8 decimals. Therefore we leave this as 1e18 / 1e8 = 1e10
    int256 private constant ASSET_RATE_DECIMAL_DIFFERENCE = 1e10;

    /// @notice Converts an internal asset cash value to its underlying token value.
    /// @param ar exchange rate object between asset and underlying
    /// @param assetBalance amount to convert to underlying
    function convertToUnderlying(AssetRateParameters memory ar, int256 assetBalance)
        internal
        pure
        returns (int256)
    {
        // Calculation here represents:
        // rate * balance * internalPrecision / rateDecimals * underlyingPrecision
        int256 underlyingBalance = ar.rate
            .mul(assetBalance)
            .div(ASSET_RATE_DECIMAL_DIFFERENCE)
            .div(ar.underlyingDecimals);

        return underlyingBalance;
    }

    /// @notice Converts an internal underlying cash value to its asset cash value
    /// @param ar exchange rate object between asset and underlying
    /// @param underlyingBalance amount to convert to asset cash, denominated in internal token precision
    function convertFromUnderlying(AssetRateParameters memory ar, int256 underlyingBalance)
        internal
        pure
        returns (int256)
    {
        // Calculation here represents:
        // rateDecimals * balance * underlyingPrecision / rate * internalPrecision
        int256 assetBalance = underlyingBalance
            .mul(ASSET_RATE_DECIMAL_DIFFERENCE)
            .mul(ar.underlyingDecimals)
            .div(ar.rate);

        return assetBalance;
    }

    /// @notice Returns the current per block supply rate, is used when calculating oracle rates
    /// for idiosyncratic fCash with a shorter duration than the 3 month maturity.
    function getSupplyRate(AssetRateParameters memory ar) internal view returns (uint256) {
        // If the rate oracle is not set, the asset is not interest bearing and has an oracle rate of zero.
        if (address(ar.rateOracle) == address(0)) return 0;

        uint256 rate = ar.rateOracle.getAnnualizedSupplyRate();
        // Zero supply rate is valid since this is an interest rate, we do not divide by
        // the supply rate so we do not get div by zero errors.
        require(rate >= 0); // dev: invalid supply rate

        return rate;
    }
}