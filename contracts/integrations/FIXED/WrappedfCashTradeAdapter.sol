// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "interfaces/set-protocol/IExchangeAdapter.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "interfaces/notional/IWrappedfCash.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// https://docs.tokensets.com/developers/contracts/deployed/protocol

contract WrappedfCashTradeAdapter is IExchangeAdapter {

    enum TradeType {
        AssetCashTofCash,
        fCashToAssetCash,
        fCashTofCash
    }

    struct TradeOpts {
        TradeType tradeType;
        uint32 maxImpliedRate;
    }

    function getSpender() external view override returns (address) {
        return address(this);
    }

    function getTradeCalldata(
        address _fromToken,
        address _toToken,
        address _toAddress,
        uint256 _fromQuantity,
        uint256 _minToQuantity,
        bytes memory _data
    )
        external
        view
        override
        returns (address exchange, uint256 ethValue, bytes memory callData) {
        // We will never use ethValue, in the case of ETH we will always be wrapped
        // in cETH or aETH
        ethValue = 0;
        // Because the spender in this example cannot be parameterized, in every case
        // this adapter will act as the exchange.
        exchange = address(this);
        TradeOpts memory opts = abi.decode(_data, (TradeOpts));

        if (opts.tradeType == TradeType.AssetCashTofCash) {
            // In this case the wrapper will do a batch lend / erc1155 transfer via this trade adapter
            callData = abi.encodeWithSelector(
                WrappedfCashTradeAdapter.assetCashTofCash.selector,
                IWrappedfCash(_fromToken),  // assetToken
                IWrappedfCash(_toToken),    // mintWrapper
                _fromQuantity,              // depositAmountExternal
                _minToQuantity,             // fCashAmount
                _toAddress                 // receiver
            );
        } else if (opts.tradeType == TradeType.fCashToAssetCash) {
            // In this case the wrapper will unwrap via the wrapper contract
            callData = abi.encodeWithSelector(
                WrappedfCashTradeAdapter.fCashToAssetCash.selector,
                IWrappedfCash(_fromToken),  // redeemWrapper
                _fromQuantity,              // fCashToRedeem
                _toAddress,                 // receiver
                opts.maxImpliedRate         // this is slippage protection
            );
        } else if (opts.tradeType == TradeType.fCashTofCash) {
            callData = abi.encodeWithSelector(
                WrappedfCashTradeAdapter.fCashTofCash.selector,
                IWrappedfCash(_fromToken),  // redeemWrapper
                IWrappedfCash(_toToken),    // mintWrapper
                _fromQuantity,              // fCashToRedeem
                _minToQuantity,             // fCashToMint
                _toAddress,                 // receiver
                opts.maxImpliedRate
            );
        } else {
            revert("Unknown trade type");
        }
    }

    function assetCashTofCash(
        IERC20 assetToken,
        IWrappedfCash mintWrapper,
        uint256 assetCashAmount,
        uint256 fCashAmount,
        address receiver
    ) external {
        assetToken.transferFrom(msg.sender, address(this), assetCashAmount);
        assetToken.approve(address(mintWrapper), assetCashAmount);
        mintWrapper.mint(assetCashAmount, safeUint88(fCashAmount), receiver, 0, false);

        uint256 residualBalance = assetToken.balanceOf(address(this));
        if (residualBalance > 0) {
            assetToken.transfer(msg.sender, residualBalance);
        }
    }

    function fCashToAssetCash(
        IWrappedfCash redeemWrapper,
        uint256 fCashToRedeem,
        address receiver,
        uint32 maxImpliedRate
    ) external {
        IERC20(address(redeemWrapper)).transferFrom(msg.sender, address(this), fCashToRedeem);
        redeemWrapper.redeemToAsset(fCashToRedeem, receiver, maxImpliedRate);
    }

    function fCashTofCash(
        IWrappedfCash redeemWrapper,
        IWrappedfCash mintWrapper,
        uint256 fCashToRedeem,
        uint256 fCashToMint,
        address receiver,
        uint32 maxImpliedRate
    ) external {
        IERC20(address(redeemWrapper)).transferFrom(msg.sender, address(this), fCashToRedeem);
        (IERC20 assetToken, /* */, /* */) = redeemWrapper.getAssetToken();

         uint256 startingBalance = assetToken.balanceOf(address(this));
         redeemWrapper.redeemToAsset(fCashToRedeem, address(this), maxImpliedRate);
         uint256 endingBalance = assetToken.balanceOf(address(this));

        uint256 assetCashExternal = endingBalance - startingBalance;
        // No slippage protection here, will max out at lending "assetCashExternal"
        assetToken.approve(address(mintWrapper), assetCashExternal);
        mintWrapper.mint(assetCashExternal, safeUint88(fCashToMint), receiver, 0, false);

        // Transfer any residuals back to the sender
        uint256 residualBalance = assetToken.balanceOf(address(this));
        if (residualBalance > 0) {
            assetToken.transfer(msg.sender, residualBalance);
        }
    }

    function safeUint88(uint256 x) private pure returns (uint88) {
        require(x <= uint256(type(uint88).max));
        return uint88(x);
    }
}