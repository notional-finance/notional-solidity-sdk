// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;
pragma abicoder v2;

import "../lib/Addresses.sol";
import "../lib/EncodeDecode.sol";
import "../lib/Types.sol";
import "interfaces/notional/NotionalCallback.sol";

contract WrappedLender is NotionalCallback, KovanAddresses {
    uint16 public immutable NOTIONAL_CURRENCY_ID;

    constructor (uint16 currencyId) {
        NOTIONAL_CURRENCY_ID = currencyId;
    }

    function lendWrappedUsingCToken(
        uint256 depositAmount,
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 minImpliedRate
    ) external {
        _lendWrapped(DepositActionType.DepositAsset, depositAmount, marketIndex, fCashAmount, minImpliedRate);
    }

    function lendWrappedUsingUnderlying(
        uint256 depositAmount,
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 minImpliedRate
    ) external {
        _lendWrapped(DepositActionType.DepositUnderlying, depositAmount, marketIndex, fCashAmount, minImpliedRate);
    }

    function _lendWrapped(
        DepositActionType actionType,
        uint256 depositAmount,
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 minImpliedRate
    ) internal {
        BalanceActionWithTrades[] memory actions = new BalanceActionWithTrades[](1);
        actions[0] = BalanceActionWithTrades({
            actionType: actionType,
            currencyId: NOTIONAL_CURRENCY_ID,
            // This deposit amount should be denominated in the token's native precision
            depositActionAmount: depositAmount,
            withdrawAmountInternalPrecision: 0,
            // Withdraw any residuals from lending back to msg.sender
            withdrawEntireCashBalance: true,
            // If using the underlying, ensure that msg.sender gets the underlying back after withdraw
            redeemToUnderlying: actionType == DepositActionType.DepositUnderlying ? true : false,
            trades: new bytes32[](1)
        });
        actions[0].trades[0] = EncodeDecode.encodeLendTrade(marketIndex, fCashAmount, minImpliedRate);

        // Expect that msg.sender has authorized Notional V2 to transferFrom their wallet
        NotionalV2.batchBalanceAndTradeActionWithCallback(msg.sender, actions, "");
    }

    function notionalCallback(
        address sender,
        address account,
        bytes calldata callbackdata
    ) external override {
        require(msg.sender == address(NotionalV2) && sender == address(this), "Unauthorized callback");

        // TODO: perform any validation logic here
    }
}