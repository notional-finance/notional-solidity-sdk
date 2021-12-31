// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.7.0;

import "./ICErc20.sol";

interface ICEther is ICErc20 {
  function mint() external payable;
}