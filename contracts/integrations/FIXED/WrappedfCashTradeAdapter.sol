// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./IExchangeAdapter.sol";
import {IWrappedfCashComplete as IWrappedfCash} from "interfaces/notional/IWrappedfCash.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WrappedfCashTradeAdapter is IExchangeAdapter {

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
        // We will use this adapter to route all the calls
        exchange = address(this);

        if (isAssetToken(_fromToken) && isfCashWrapper(_toToken)) {
            // In this case we are minting fCash on the _toToken
            callData = abi.encodeWithSelector(
                WrappedfCashTradeAdapter.mintFromAsset.selector,
                IWrappedfCash(_toToken),  // _wrapper
                _fromQuantity,            // assetTokensIn
                _minToQuantity,           // fCashToMint
                _toAddress                // receiver
            );
        } else if (isfCashWrapper(_fromToken) && isAssetToken(_toToken)) {
            // In this case we are redeeming fCash on the _fromToken
            callData = abi.encodeWithSelector(
                WrappedfCashTradeAdapter.redeemToAsset.selector,
                IWrappedfCash(_fromToken),  // _wrapper
                _fromQuantity,              // fCashToRedeem
                _toAddress                  // receiver
            );
        } else if (isfCashWrapper(_fromToken) && isfCashWrapper(_toToken)) {
            callData = abi.encodeWithSelector(
                WrappedfCashTradeAdapter.swapfCash.selector,
                IWrappedfCash(_fromToken),  // redeemWrapper
                IWrappedfCash(_toToken),    // mintWrapper
                _fromQuantity,              // fCashToRedeem
                _minToQuantity,             // fCashToMint
                _toAddress                  // receiver
            );
        } else {
            // Cannot supply two asset tokens
            revert();
        }
    }

    function mintFromAsset(
        IWrappedfCash _wrapper,
        uint256 assetTokensIn,
        uint256 fCashToMint,
        address receiver
    ) external {
        (IERC20 assetToken, /* */, /* */) = _wrapper.getAssetToken();
        assetToken.transferFrom(msg.sender, address(this), assetTokensIn);

        uint256 startingBalance = assetToken.balanceOf(address(this));
        _wrapper.mintFromAsset(fCashToMint, receiver);
        uint256 endingBalance = assetToken.balanceOf(address(this));

        assetToken.transfer(msg.sender, endingBalance - startingBalance);
    }

    function redeemToAsset(
        IWrappedfCash _wrapper,
        uint256 fCashToRedeem,
        address receiver
    ) external {
        IERC20(address(_wrapper)).transferFrom(msg.sender, address(this), fCashToRedeem);
        _wrapper.redeemToAsset(fCashToRedeem, receiver);
    }

    function swapfCash(
        IWrappedfCash _redeemWrapper,
        IWrappedfCash _mintWrapper,
        uint256 fCashToRedeem,
        uint256 fCashToMint,
        address receiver
    ) external {
        IERC20(address(_redeemWrapper)).transferFrom(msg.sender, address(this), fCashToRedeem);
        (IERC20 assetToken, /* */, /* */) = _redeemWrapper.getAssetToken();

        uint256 startingBalance = assetToken.balanceOf(address(this));
        _redeemWrapper.redeemToAsset(fCashToRedeem, address(this));
        _mintWrapper.mintFromAsset(fCashToMint, receiver);
        uint256 endingBalance = assetToken.balanceOf(address(this));

        // Transfer any residuals back to the sender
        assetToken.transfer(msg.sender, endingBalance - startingBalance);
    }

    function isAssetToken(address token) public view returns (bool) {
        // TODO: how to determine this?
        return true;
    }

    function isfCashWrapper(address token) public view returns (bool) {
        // TODO: how to determine this?
        return true;
    }
}