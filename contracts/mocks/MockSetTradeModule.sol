// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "interfaces/set-protocol/IExchangeAdapter.sol";

contract MockSetTradeModule {

    struct TradeInfo {
        address setToken;                             // Instance of SetToken
        IExchangeAdapter exchangeAdapter;               // Instance of exchange adapter contract
        address sendToken;                              // Address of token being sold
        address receiveToken;                           // Address of token being bought
        uint256 totalSendQuantity;                      // Total quantity of sold token (position unit x total supply)
        uint256 totalMinReceiveQuantity;                // Total minimum quantity of token to receive back
        uint256 preTradeReceiveTokenBalance;            // Total initial balance of token being bought
    }

    function executeTrade(
        TradeInfo memory _tradeInfo,
        bytes memory _data
    )
        external
    {
        _tradeInfo.preTradeReceiveTokenBalance = IERC20(_tradeInfo.receiveToken).balanceOf(_tradeInfo.setToken);
        // // Get spender address from exchange adapter and invoke approve for exact amount on SetToken
        // _tradeInfo.setToken.invokeApprove(
        //     _tradeInfo.sendToken,
        //     _tradeInfo.exchangeAdapter.getSpender(),
        //     _tradeInfo.totalSendQuantity
        // );
        IERC20(_tradeInfo.sendToken).approve(_tradeInfo.exchangeAdapter.getSpender(), _tradeInfo.totalSendQuantity);

        (
            address targetExchange,
            uint256 callValue,
            bytes memory methodData
        ) = _tradeInfo.exchangeAdapter.getTradeCalldata(
            _tradeInfo.sendToken,
            _tradeInfo.receiveToken,
            address(_tradeInfo.setToken),
            _tradeInfo.totalSendQuantity,
            _tradeInfo.totalMinReceiveQuantity,
            _data
        );

        (bool success, /* */) = targetExchange.call{value: callValue}(methodData);
        require(success, "call failed");

        _validatePostTrade(_tradeInfo);
    }

    function _validatePostTrade(TradeInfo memory _tradeInfo) internal view returns (uint256) {
        uint256 exchangedQuantity = IERC20(_tradeInfo.receiveToken)
            .balanceOf(address(_tradeInfo.setToken)) - _tradeInfo.preTradeReceiveTokenBalance;

        require(
            exchangedQuantity >= _tradeInfo.totalMinReceiveQuantity,
            "Slippage greater than allowed"
        );

        return exchangedQuantity;
    }
}