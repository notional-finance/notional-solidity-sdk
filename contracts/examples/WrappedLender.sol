// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;
pragma abicoder v2;

import "../lib/AssetRate.sol";
import "../lib/Addresses.sol";
import "../lib/EncodeDecode.sol";
import "../lib/Types.sol";
import "interfaces/notional/NotionalCallback.sol";

contract WrappedLender is NotionalCallback, KovanAddresses {
    using AssetRate for AssetRateParameters;

    uint16 public immutable NOTIONAL_CURRENCY_ID;
    uint32 public immutable FCASH_MATURITY;

    uint256 public totalfCashBalance;
    mapping(address => uint256) public accountfCashBalance;

    constructor (uint16 currencyId, uint32 maturity) {
        NOTIONAL_CURRENCY_ID = currencyId;
        FCASH_MATURITY = maturity;
    }

    function withdrawCash(bool redeemToUnderlying) external {
        require(FCASH_MATURITY < block.timestamp, "fCash not matured");
        AssetRateParameters memory settlementRate = NotionalV2.getSettlementRate(
            NOTIONAL_CURRENCY_ID,
            FCASH_MATURITY
        );
        // If the settlement rate has not been set yet, anyone can call settleAccount on NotionalV2 to
        // ensure that it gets set system wide.
        require(settlementRate.rate > 0, "Settlement Rate not set");

        uint256 fCashBalance = accountfCashBalance[msg.sender];
        // This is the amount of cash that the user's fCash has settled to
        int256 notionalCashBalance = settlementRate.convertFromUnderlying(SafeInt256.toInt(fCashBalance));
        require(0 < notionalCashBalance && notionalCashBalance <= type(uint88).max);

        // If this fails, then there is some issue. If redeem to underlying fails then there is an
        // issue with Compound.
        NotionalV2.withdraw(NOTIONAL_CURRENCY_ID, uint88(notionalCashBalance), redeemToUnderlying);
    }

    /// @notice When calling this method, the contract will lend the specified fCashAmount in the corresponding
    /// market for the designated currency. Expects that the msg.sender has already approved ERC20 transfers for
    /// the NotionalV2 address (not this contract).
    /// @param depositAmount the amount of cTokens to deposit for lending in cToken decimal precision
    /// @param marketIndex the index of the market to lend on (1 = 3 months, 2 = 6 months, 3 = 1 year, etc)
    /// @param fCashAmount the amount of fCash to lend into the market, corresponds to the amount of underlying
    /// that the account will receive at maturity
    /// @param minImpliedRate the minimum interest rate that the account will lend at for slippage protection
    function lendWrappedUsingCToken(
        uint256 depositAmount,
        uint8 marketIndex, // NOTE: may want to consider limiting the wrapper to only having 1 market index
        uint88 fCashAmount,
        uint32 minImpliedRate
    ) external {
        _lendWrapped(DepositActionType.DepositAsset, depositAmount, marketIndex, fCashAmount, minImpliedRate);
    }

    /// @notice When calling this method, the contract will lend the specified fCashAmount in the corresponding
    /// market for the designated currency. Expects that the msg.sender has already approved ERC20 transfers for
    /// the NotionalV2 address (not this contract).
    /// @param depositAmount the amount of underlying to deposit in the token's native precision, will be converted
    /// to cTokens by the NotionalV2 contract
    /// @param marketIndex the index of the market to lend on (1 = 3 months, 2 = 6 months, 3 = 1 year, etc)
    /// @param fCashAmount the amount of fCash to lend into the market, corresponds to the amount of underlying
    /// that the account will receive at maturity
    /// @param minImpliedRate the minimum interest rate that the account will lend at for slippage protection
    function lendWrappedUsingUnderlying(
        uint256 depositAmount,
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 minImpliedRate
    ) external {
        _lendWrapped(DepositActionType.DepositUnderlying, depositAmount, marketIndex, fCashAmount, minImpliedRate);
    }

    /// @dev Issues a lend trade on NotionalV2. NotionalV2 will do the following:
    ///     - Transfer depositAmount ERC20 tokens from the account
    ///     - Lend fCashAmount at marketIndex, reverting if the interest rate drops below minImpliedRate
    ///     - Place the corresponding fCash asset in msg.sender's account
    ///     - Withdraw any residual depositAmount left after lending back to msg.sender's wallet
    ///     - Issue a callback to this contract
    ///     - After callback returns, will perform a free collateral check if necessary
    function _lendWrapped(
        DepositActionType actionType,
        uint256 depositAmount,
        uint8 marketIndex,
        uint88 fCashAmount,
        uint32 minImpliedRate
    ) internal {
        /**
         * A better option might be to have the wrapper take the token and hold the fCash, in this
         * case the wrapper contract gets the ERC20 token approval:
         *   token.transferFrom(msg.sender, address(this), depositAmount)
         *
         *   ... same batch action generation
         *
         *   uint256 balanceBefore = token.balanceOf(address(this))
         *   int256 fCashBalanceBefore = notionalV2.signedBalanceOf(address(this), FCASH_ID)
         *   // Maybe check this against the previously recorded balance...
         *
         *   // No callback here, the fCash asset gets put into this wrapper contract
         *   notionalV2.batchBalanceAndTradeAction(address(this), actions)
         *
         *   int256 fCashBalanceAfter = notionalV2.signedBalanceOf(address(this), FCASH_ID)
         *   uint256 balanceAfter = token.balanceOf(address(this))
         *  
         *   // Refund the residual back to the sender
         *   uint256 residual = balanceBefore - balanceAfter;
         *   token.transfer(msg.sender, residual)
         *
         *   there is no callback here, just need to validate the new fCash position and then
         *   update some internal mapping for fCash balances.
         */


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
        AccountContext memory context = NotionalV2.getAccountContext(account);
        // Likely want to ensure that the account has not borrowed
        require(context.hasDebt == 0x00);

        // TODO: maybe want to supply some callbackdata to record fCash amount or anything like that...
    }
}