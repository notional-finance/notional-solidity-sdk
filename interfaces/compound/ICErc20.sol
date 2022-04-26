// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.0;

import "./IErc20.sol";

interface ICErc20 is IErc20 {

    function mint(uint mintAmount) external returns (uint);
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, ICErc20 cTokenCollateral) external returns (uint);

}