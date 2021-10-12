// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./NotionalV2BaseLiquidator.sol";
import "../lib/SafeInt256.sol";
import "../lib/SafeToken.sol";
import "interfaces/aave/IFlashLoanReceiver.sol";
import "interfaces/aave/IFlashLender.sol";
import "interfaces/notional/NotionalProxy.sol";
import "interfaces/compound/CTokenInterface.sol";
import "interfaces/compound/CErc20Interface.sol";
import "interfaces/compound/CEtherInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

abstract contract NotionalV2FlashLiquidator is NotionalV2BaseLiquidator, IFlashLoanReceiver {
    using SafeInt256 for int256;
    using SafeMath for uint256;

    address public LENDING_POOL;
    address public ADDRESS_PROVIDER;

    constructor (
        address lendingPool_,
        address addressProvider_,
        address owner_
    ) NotionalV2BaseLiquidator(owner_) {
        LENDING_POOL = lendingPool_;
        ADDRESS_PROVIDER = addressProvider_;
    }

    function setLendingPool(address lendingPool_) external onlyOwner {
        LENDING_POOL = lendingPool_;
    }

    function setAddressProvider(address addressProvider_) external onlyOwner {
        ADDRESS_PROVIDER = addressProvider_;
    }

    function setCTokenAddress(address cToken) external onlyOwner {
        address underlying = CTokenInterface(cToken).underlying();
        // Notional V2 needs to be able to pull cTokens
        SafeToken.checkAndSetMaxAllowance(cToken, address(NotionalV2));
        // Lending pool needs to be able to pull underlying
        SafeToken.checkAndSetMaxAllowance(underlying, LENDING_POOL);
        underlyingToCToken[underlying] = cToken;
    }

    function approveToken(address token, address spender) external onlyOwner {
        SafeToken.checkAndSetMaxAllowance(token, spender);
    }

    // Profit estimation
    function flashLoan(
        address flashLender,
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external onlyOwner returns (uint256) {
        IFlashLender(flashLender).flashLoan(
            receiverAddress,
            assets,
            amounts,
            modes,
            onBehalfOf,
            params,
            referralCode
        );
        return IERC20(assets[0]).balanceOf(address(this));
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // NOTE: no check on initiator because all profits will be distributed back to the owner
        require(msg.sender == LENDING_POOL); // dev: unauthorized caller
        LiquidationAction action = LiquidationAction(abi.decode(params, (uint8)));

        // Mint cTokens for incoming assets, if required. If there are transfer fees
        // the we deposit underlying instead inside each _liquidate call instead
        if (!_hasTransferFees(action)) _mintCTokens(assets, amounts);

        if (
            action == LiquidationAction.LocalCurrency_WithTransferFee_Withdraw ||
            action == LiquidationAction.LocalCurrency_WithTransferFee_NoWithdraw ||
            action == LiquidationAction.LocalCurrency_NoTransferFee_Withdraw ||
            action == LiquidationAction.LocalCurrency_NoTransferFee_NoWithdraw
        ) {
            _liquidateLocal(action, params, assets);
        } else if (
            action == LiquidationAction.CollateralCurrency_WithTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_WithTransferFee_NoWithdraw ||
            action == LiquidationAction.CollateralCurrency_NoTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_NoTransferFee_NoWithdraw
        ) {
            _liquidateCollateral(action, params, assets);
        } else if (
            action == LiquidationAction.LocalfCash_WithTransferFee_Withdraw ||
            action == LiquidationAction.LocalfCash_WithTransferFee_NoWithdraw ||
            action == LiquidationAction.LocalfCash_NoTransferFee_Withdraw ||
            action == LiquidationAction.LocalfCash_NoTransferFee_NoWithdraw
        ) {
            _liquidateLocalfCash(action, params, assets);
        } else if (
            action == LiquidationAction.CrossCurrencyfCash_WithTransferFee_Withdraw ||
            action == LiquidationAction.CrossCurrencyfCash_WithTransferFee_NoWithdraw ||
            action == LiquidationAction.CrossCurrencyfCash_NoTransferFee_Withdraw ||
            action == LiquidationAction.CrossCurrencyfCash_NoTransferFee_NoWithdraw
        ) {
            _liquidateCrossCurrencyfCash(action, params, assets);
        }

        _redeemCTokens(assets);

        if (
            action == LiquidationAction.CollateralCurrency_WithTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_WithTransferFee_NoWithdraw ||
            action == LiquidationAction.CollateralCurrency_NoTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_NoTransferFee_NoWithdraw ||
            action == LiquidationAction.CrossCurrencyfCash_WithTransferFee_Withdraw ||
            action == LiquidationAction.CrossCurrencyfCash_WithTransferFee_NoWithdraw ||
            action == LiquidationAction.CrossCurrencyfCash_NoTransferFee_Withdraw ||
            action == LiquidationAction.CrossCurrencyfCash_NoTransferFee_NoWithdraw
        ) {
            _executeDexTrade(
                action,
                assets[0],
                amounts[0].add(premiums[0]), // Amount needed to pay back flash loan
                params
            );
        }

        if (
            action == LiquidationAction.LocalCurrency_WithTransferFee_Withdraw ||
            action == LiquidationAction.LocalCurrency_NoTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_WithTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_NoTransferFee_Withdraw ||
            action == LiquidationAction.LocalfCash_WithTransferFee_Withdraw ||
            action == LiquidationAction.LocalfCash_NoTransferFee_Withdraw ||
            action == LiquidationAction.CrossCurrencyfCash_WithTransferFee_Withdraw ||
            action == LiquidationAction.CrossCurrencyfCash_NoTransferFee_Withdraw
        ) {
            // Transfer profits to OWNER
            uint256 bal = IERC20(assets[0]).balanceOf(address(this));
            if (bal > amounts[0].add(premiums[0])) {
                IERC20(assets[0]).transfer(OWNER, bal.sub(amounts[0].add(premiums[0])));
            }
        }

        // The lending pool should have enough approval to pull the required amount from the contract
        return true;
    }

    function _executeDexTrade(
        LiquidationAction action,
        address to,
        uint256 amountOutMin,
        bytes calldata params
    ) internal {
        address collateralUnderlyingAddress;
        bytes memory tradeCallData;

        if (
            action == LiquidationAction.CollateralCurrency_WithTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_WithTransferFee_NoWithdraw ||
            action == LiquidationAction.CollateralCurrency_NoTransferFee_Withdraw ||
            action == LiquidationAction.CollateralCurrency_NoTransferFee_NoWithdraw
        ) {
            // prettier-ignore
            (
                /* uint8 action */,
                /* address liquidateAccount */,
                /* uint256 localCurrency */,
                /* address localCurrencyAddress */,
                /* uint256 collateralCurrency */,
                /* address collateralAddress, */,
                collateralUnderlyingAddress,
                /* uint128 maxCollateralLiquidation */,
                /* uint96 maxNTokenLiquidation */,
                tradeCallData
            ) = abi.decode(params, (uint8, address, uint256, address, uint256, address, address, uint128, uint96, bytes));
        } else {
            // prettier-ignore
            (
                /* uint8 action */,
                /* address liquidateAccount */,
                /* uint256 localCurrency*/,
                /* address localCurrencyAddress */,
                /* uint256 collateralCurrency */,
                /* address collateralAddress, */,
                collateralUnderlyingAddress,
                /* fCashMaturities */,
                /* maxfCashLiquidateAmounts */,
                tradeCallData
            ) = abi.decode(params, (uint8, address, uint256, address, uint256, address, address, uint256[], uint256[], bytes));
        }

        executeDexTrade(
            collateralUnderlyingAddress,
            to,
            IERC20(collateralUnderlyingAddress).balanceOf(address(this)),
            amountOutMin,
            tradeCallData
        );
    }

    function wrapToWETH() public {
        WETH9(WETH).deposit{value: address(this).balance}();
    }

    function withdraw(address token, uint256 amount) public {
        IERC20(token).transfer(OWNER, amount);
    }
    
    receive() external payable {}
}
