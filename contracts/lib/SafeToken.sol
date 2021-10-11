// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;

import "./Constants.sol";
import "interfaces/compound/CErc20Interface.sol";
import "interfaces/compound/CEtherInterface.sol";
import "interfaces/WETH9.sol";
import "interfaces/IEIP20NonStandard.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * Helper functions for interacting with tokens
 */
library SafeToken {
    using SafeMath for uint256;
    uint256 internal constant MIN_ALLOWANCE = 2**128;

    function mintCEth(address token, uint256 ethAmount) internal {
        // Reverts on error
        CEtherInterface(token).mint{value: ethAmount}();
    }

    function mintCEthAndReturnBalance(address token, uint256 ethAmount)
        internal
        returns (uint256 cTokenBalance)
    {
        uint256 startingBalance = IERC20(token).balanceOf(address(this));
        mintCEth(token, ethAmount);
        uint256 endingBalance = IERC20(token).balanceOf(address(this));
        return endingBalance.sub(startingBalance);
    }

    function mintCToken(address token, uint256 underlyingAmount) internal {
        uint256 returnCode = CErc20Interface(token).mint(underlyingAmount);

        require(
            returnCode == Constants.COMPOUND_RETURN_CODE_NO_ERROR,
            "Error: Mint cToken"
        );
    }

    function mintCTokenAndReturnBalance(address token, uint256 underlyingAmount)
        internal
        returns (uint256 cTokenBalance)
    {
        uint256 startingBalance = IERC20(token).balanceOf(address(this));
        mintCToken(token, underlyingAmount);
        uint256 endingBalance = IERC20(token).balanceOf(address(this));
        return endingBalance.sub(startingBalance);
    }

    function redeemCToken(address token, uint256 cTokenAmount)
        internal
        returns (uint256)
    {
        uint256 success = CErc20Interface(token).redeem(cTokenAmount);
        require(
            success == Constants.COMPOUND_RETURN_CODE_NO_ERROR,
            "Error: Redeem cToken"
        );
    }

    function redeemCTokenAndReturnBalance(
        address token,
        address underlying,
        uint256 cTokenAmount
    ) internal returns (uint256 underlyingBalance) {
        uint256 startingBalance = underlying != address(0)
            ? IERC20(underlying).balanceOf(address(this))
            : address(this).balance;

        redeemCToken(token, cTokenAmount);

        uint256 endingBalance = underlying != address(0)
            ? IERC20(underlying).balanceOf(address(this))
            : address(this).balance;

        return endingBalance.sub(startingBalance);
    }

    function checkAndSetMaxAllowance(address token, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) < MIN_ALLOWANCE) {
            IEIP20NonStandard(token).approve(spender, type(uint256).max);
            checkReturnCode();
        }
    }

    function safeTransferFrom(
        address token,
        address account,
        uint256 amount
    ) internal {
        IEIP20NonStandard(token).transfer(account, amount);
        checkReturnCode();
    }

    function safeTransferIn(
        address token,
        address account,
        uint256 amount
    ) internal {
        IEIP20NonStandard(token).transferFrom(account, address(this), amount);
        checkReturnCode();
    }

    function checkReturnCode() private pure {
        bool success;
        uint256[1] memory result;
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := 1 // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(result, 0, 32)
                success := mload(result) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }

        require(success, "Token operation failed");
    }
}
