// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >0.7.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "interfaces/notional/NotionalProxy.sol";
import "interfaces/compound/CErc20Interface.sol";
import "interfaces/compound/CEtherInterface.sol";
import "interfaces/WETH9.sol";
import "../lib/Addresses.sol";
import "../lib/DateTime.sol";
import "../lib/SafeInt256.sol";
import "../lib/SafeToken.sol";
import "../lib/EncodeDecode.sol";

abstract contract NotionalV2BaseLiquidator {
    using SafeInt256 for int256;
    using SafeMath for uint256;

    enum LiquidationAction {
        LocalCurrency_NoTransferFee_Withdraw,
        CollateralCurrency_NoTransferFee_Withdraw,
        LocalfCash_NoTransferFee_Withdraw,
        CrossCurrencyfCash_NoTransferFee_Withdraw,
        LocalCurrency_NoTransferFee_NoWithdraw,
        CollateralCurrency_NoTransferFee_NoWithdraw,
        LocalfCash_NoTransferFee_NoWithdraw,
        CrossCurrencyfCash_NoTransferFee_NoWithdraw,
        LocalCurrency_WithTransferFee_Withdraw,
        CollateralCurrency_WithTransferFee_Withdraw,
        LocalfCash_WithTransferFee_Withdraw,
        CrossCurrencyfCash_WithTransferFee_Withdraw,
        LocalCurrency_WithTransferFee_NoWithdraw,
        CollateralCurrency_WithTransferFee_NoWithdraw,
        LocalfCash_WithTransferFee_NoWithdraw,
        CrossCurrencyfCash_WithTransferFee_NoWithdraw
    }

    NotionalProxy public immutable NotionalV2;
    mapping(address => address) underlyingToCToken;
    address public immutable WETH;
    address public immutable cETH;
    address public OWNER;

    modifier onlyOwner() {
        require(OWNER == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    constructor(
        address owner_
    ) {
        NotionalV2 = Addresses.getNotionalV2();
        WETH = address(Addresses.getWETH());
        cETH = address(Addresses.getCEth());
        OWNER = owner_;
    }

    function executeDexTrade(
        address from,
        address to,
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory params
    ) internal virtual returns(uint256);

    function _hasTransferFees(LiquidationAction action) internal pure returns (bool) {
        return action >= LiquidationAction.LocalCurrency_WithTransferFee_Withdraw;
    }

    function _transferFeeDepositTokens(
        address token,
        uint16 currencyId
    ) internal {
        uint256 amount = IERC20(token).balanceOf(address(this));
        SafeToken.checkAndSetMaxAllowance(token, address(NotionalV2));
        NotionalV2.depositUnderlyingToken(address(this), currencyId, amount);
    }

    function _mintCTokens(address[] calldata assets, uint256[] calldata amounts) internal {
        for (uint256 i; i < assets.length; i++) {
            if (assets[i] == WETH) {
                // Withdraw WETH to ETH and mint CEth
                WETH9(WETH).withdraw(amounts[i]);
                SafeToken.mintCEth(cETH, amounts[i]);
            } else {
                address cToken = underlyingToCToken[assets[i]];
                if (cToken != address(0)) {
                    SafeToken.checkAndSetMaxAllowance(assets[i], cToken);
                    SafeToken.mintCToken(cToken, amounts[i]);
                }
            }
        }
    }

    function _redeemCTokens(address[] calldata assets) internal {
        // Redeem cTokens to underlying to repay the flash loan
        for (uint256 i; i < assets.length; i++) {
            address cToken = assets[i] == WETH ? cETH : underlyingToCToken[assets[i]];
            if (cToken == address(0)) continue;

            SafeToken.redeemCTokenEntireBalance(cToken);
            // Wrap ETH into WETH for repayment
            if (assets[i] == WETH && address(this).balance > 0) _wrapToWETH();
        }
    }

    function _liquidateLocal(
        LiquidationAction action,
        bytes memory params,
        address[] memory assets
    ) internal {
        // prettier-ignore
        (
            /* uint8 action */,
            address liquidateAccount,
            uint16 localCurrency,
            uint96 maxNTokenLiquidation
        ) = abi.decode(params, (uint8, address, uint16, uint96));

        if (_hasTransferFees(action)) _transferFeeDepositTokens(assets[0], localCurrency);

        // prettier-ignore
        (
            /* int256 localAssetCashFromLiquidator */,
            int256 netNTokens
        ) = NotionalV2.liquidateLocalCurrency(liquidateAccount, localCurrency, maxNTokenLiquidation);

        // Will withdraw entire cash balance. Don't redeem local currency here because it has been flash
        // borrowed and we need to redeem the entire balance to underlying for the flash loan repayment.
        _redeemAndWithdraw(localCurrency, uint96(netNTokens), false);
    }

    function _liquidateCollateral(
        LiquidationAction action,
        bytes memory params,
        address[] memory assets
    ) internal {
        // prettier-ignore
        (
            /* uint8 action */,
            address liquidateAccount,
            uint16 localCurrency,
            /* uint256 localAddress */,
            uint16 collateralCurrency,
            address collateralAddress,
            /* address collateralUnderlyingAddress */,
            uint128 maxCollateralLiquidation,
            uint96 maxNTokenLiquidation
        ) = abi.decode(params, (uint8, address, uint16, address, uint16, address, address, uint128, uint96));

        if (_hasTransferFees(action)) _transferFeeDepositTokens(assets[0], localCurrency);

        // prettier-ignore
        (
            /* int256 localAssetCashFromLiquidator */,
            /* int256 collateralAssetCash */,
            int256 collateralNTokens
        ) = NotionalV2.liquidateCollateralCurrency(
            liquidateAccount,
            localCurrency,
            collateralCurrency,
            maxCollateralLiquidation,
            maxNTokenLiquidation,
            true, // Withdraw collateral
            false // Redeem to underlying (will happen later)
        );

        // Redeem to underlying for collateral because it needs to be traded on the DEX
        _redeemAndWithdraw(collateralCurrency, uint96(collateralNTokens), true);
        SafeToken.redeemCTokenEntireBalance(collateralAddress);

        // Wrap everything to WETH for trading
        if (collateralCurrency == Constants.ETH_CURRENCY_ID) _wrapToWETH();

        // Will withdraw all cash balance, no need to redeem local currency, it will be
        // redeemed later
        if (_hasTransferFees(action)) _redeemAndWithdraw(localCurrency, 0, false);
    }

    function _liquidateLocalfCash(
        LiquidationAction action,
        bytes memory params,
        address[] memory assets
    ) internal {
        // prettier-ignore
        (
            /* uint8 action */,
            address liquidateAccount,
            uint16 localCurrency,
            uint256[] memory fCashMaturities,
            uint256[] memory maxfCashLiquidateAmounts
        ) = abi.decode(params, (uint8, address, uint16, uint256[], uint256[]));

        if (_hasTransferFees(action)) _transferFeeDepositTokens(assets[0], localCurrency);

        // prettier-ignore
        (
            int256[] memory fCashNotionalTransfers,
            int256 localAssetCashFromLiquidator
        ) = NotionalV2.liquidatefCashLocal(
            liquidateAccount,
            localCurrency,
            fCashMaturities,
            maxfCashLiquidateAmounts
        );

        // If localAssetCashFromLiquidator is negative (meaning the liquidator has received cash)
        // then when we will need to lend in order to net off the negative fCash. In this case we
        // will deposit the local asset cash back into notional.
        _sellfCashAssets(
            localCurrency,
            fCashMaturities,
            fCashNotionalTransfers,
            localAssetCashFromLiquidator < 0 ? uint256(localAssetCashFromLiquidator.abs()) : 0,
            false // No need to redeem to underlying here
        );

        // NOTE: no withdraw if _hasTransferFees, _sellfCashAssets with withdraw everything
    }

    function _liquidateCrossCurrencyfCash(
        LiquidationAction action,
        bytes memory params,
        address[] memory assets
    ) internal {
        // prettier-ignore
        (
            /* bytes1 action */,
            address liquidateAccount,
            uint16 localCurrency,
            /* address localAddress */,
            uint16 fCashCurrency,
            /* address fCashAddress */,
            /* address fCashUnderlyingAddress */,
            uint256[] memory fCashMaturities,
            uint256[] memory maxfCashLiquidateAmounts
        ) = abi.decode(params, 
            (uint8, address, uint16, address, uint16, address, address, uint256[], uint256[])
        );

        if (_hasTransferFees(action)) _transferFeeDepositTokens(assets[0], localCurrency);

        // prettier-ignore
        (
            int256[] memory fCashNotionalTransfers,
            /* int256 localAssetCashFromLiquidator */
        ) = NotionalV2.liquidatefCashCrossCurrency(
            liquidateAccount,
            localCurrency,
            fCashCurrency,
            fCashMaturities,
            maxfCashLiquidateAmounts
        );

        // Redeem to underlying here, collateral is not specified as an input asset
        _sellfCashAssets(fCashCurrency, fCashMaturities, fCashNotionalTransfers, 0, true);
        // Wrap everything to WETH for trading
        if (fCashCurrency == Constants.ETH_CURRENCY_ID) _wrapToWETH();

        // NOTE: no withdraw if _hasTransferFees, _sellfCashAssets will withdraw everything
    }

    function _wrapToWETH() internal {
        WETH9(WETH).deposit{value: address(this).balance}();
    }

    function _sellfCashAssets(
        uint16 fCashCurrency,
        uint256[] memory fCashMaturities,
        int256[] memory fCashNotional,
        uint256 depositActionAmount,
        bool redeemToUnderlying
    ) internal {
        uint256 blockTime = block.timestamp;
        BalanceActionWithTrades[] memory action = new BalanceActionWithTrades[](1);
        action[0].actionType = depositActionAmount > 0
            ? DepositActionType.DepositAsset
            : DepositActionType.None;
        action[0].depositActionAmount = depositActionAmount;
        action[0].currencyId = fCashCurrency;
        action[0].withdrawEntireCashBalance = true;
        action[0].redeemToUnderlying = redeemToUnderlying;
        action[0].trades = EncodeDecode.encodeOffsettingTradesFromArrays(
            fCashMaturities,
            fCashNotional,
            blockTime
        );

        NotionalV2.batchBalanceAndTradeAction(address(this), action);
    }

    function _redeemAndWithdraw(
        uint256 nTokenCurrencyId,
        uint96 nTokenBalance,
        bool redeemToUnderlying
    ) internal {
        BalanceAction[] memory action = new BalanceAction[](1);
        // If nTokenBalance is zero still try to withdraw entire cash balance
        action[0].actionType = nTokenBalance == 0
            ? DepositActionType.None
            : DepositActionType.RedeemNToken;
        action[0].currencyId = uint16(nTokenCurrencyId);
        action[0].depositActionAmount = nTokenBalance;
        action[0].withdrawEntireCashBalance = true;
        action[0].redeemToUnderlying = redeemToUnderlying;
        NotionalV2.batchBalanceAction(address(this), action);
    }
}
