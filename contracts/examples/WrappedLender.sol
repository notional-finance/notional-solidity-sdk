// SPDX-License-Identifier: MIT
pragma solidity >0.7.0;
pragma abicoder v2;

import "../lib/AssetRate.sol";
import "../lib/Addresses.sol";
import "../lib/EncodeDecode.sol";
import "../lib/Types.sol";
import "../abstract/AllowfCashReceiver.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WrappedLender is AllowfCashReceiver {
    using AssetRate for AssetRateParameters;
    using SafeMath for uint256;

    NotionalProxy public immutable NotionalV2;
    uint16 public immutable CURRENCY_ID;
    uint32 public immutable FCASH_MATURITY;
    uint256 public immutable FCASH_ID;
    IERC20 internal immutable underlyingToken;
    IERC20 internal immutable assetToken;
    int256 internal immutable underlyingDecimals;
    int256 internal immutable assetDecimals;

    mapping(address => uint256) public accountfCashBalance;

    constructor (uint16 currencyId, uint32 maturity) {
        NotionalProxy proxy = Addresses.getNotionalV2();
        (Token memory underlying, Token memory asset) = proxy.getCurrency(currencyId);
        underlyingToken = IERC20(underlying.tokenAddress);
        underlyingDecimals = underlying.decimals;
        assetToken = IERC20(asset.tokenAddress);
        assetDecimals = asset.decimals;

        NotionalV2 = proxy;
        CURRENCY_ID = currencyId;
        FCASH_MATURITY = maturity;
        FCASH_ID = EncodeDecode.encodeERC1155Id(currencyId, maturity, Constants.FCASH_ASSET_TYPE);
    }

    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) external override returns (bytes4) {
        // Only accept erc1155 transfers from NotionalV2
        require(msg.sender == address(NotionalV2), "Invalid caller");
        // Only accept the fcash id that corresponds to the listed currency and maturity
        require(_id == FCASH_ID, "Invalid fCash asset");
        // Protect against signed value underflows
        require(int256(_value) > 0, "Invalid value");

        // Double check the account's position, these are not strictly necessary and add gas costs
        // but might be good safe guards
        AccountContext memory ac = NotionalV2.getAccountContext(address(this));
        require(ac.hasDebt == 0x00, "Incurred debt");
        PortfolioAsset[] memory assets = NotionalV2.getAccountPortfolio(address(this));
        require(assets.length == 1, "Invalid assets");
        require(EncodeDecode.encodeERC1155Id(
            assets[0].currencyId,
            assets[0].maturity,
            assets[0].assetType
        ) == FCASH_ID, "Invalid portfolio asset");


        // Update per account fCash balance
        uint256 fCashBalance = accountfCashBalance[_from];
        accountfCashBalance[_from] = fCashBalance.add(_value);

        // TODO: at this point the contract can accept payment for insurance
    }

    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) external override returns (bytes4) {
        // Do not accept batches of fCash
        return 0;
    }

    function withdrawCash(bool redeemToUnderlying) external {
        require(FCASH_MATURITY < block.timestamp, "fCash not matured");
        AssetRateParameters memory settlementRate = NotionalV2.getSettlementRate(
            CURRENCY_ID,
            FCASH_MATURITY
        );

        if (settlementRate.rate == 0) {
            // If the settlement rate has not been set yet, settle the account to fetch it.
            NotionalV2.settleAccount(address(this));
            // Re-fetch the settlement rate now, it has been set
            settlementRate = NotionalV2.getSettlementRate(
                CURRENCY_ID,
                FCASH_MATURITY
            );
        }
        // If this fails then we've hit some strange system error
        require(settlementRate.rate > 0, "Settlement rate error");

        uint256 fCashBalance = accountfCashBalance[msg.sender];
        // This is the amount of cash that the user's fCash has settled to
        int256 notionalCashBalance = settlementRate.convertFromUnderlying(SafeInt256.toInt(fCashBalance));
        require(1 < notionalCashBalance && notionalCashBalance <= type(uint88).max);

        // Subtract one to account for any rounding errors, we don't want dust amounts to accrue and cause
        // withdraws to fail for the last user that withdraws
        notionalCashBalance = notionalCashBalance - 1;

        // If this fails, then there is some issue. If redeem to underlying fails then there is an
        // issue with Compound.
        NotionalV2.withdraw(CURRENCY_ID, uint88(notionalCashBalance), redeemToUnderlying);

        if (redeemToUnderlying) {
            uint256 fCashBalanceExternal = SafeInt256.toUint(EncodeDecode.convertToExternal(SafeInt256.toInt(fCashBalance), underlyingDecimals));
            uint256 underlyingBalance = underlyingToken.balanceOf(address(this));
            // NOTE: If this fails, can initiate a claim...
            require(underlyingBalance >= fCashBalance, "Insufficient underlying");
            underlyingToken.transfer(msg.sender, fCashBalanceExternal);
        } else {
            // Underflow checked above
            uint256 cashBalanceExternal = SafeInt256.toUint(EncodeDecode.convertToExternal(notionalCashBalance, assetDecimals));
            uint256 assetCashBalance = assetToken.balanceOf(address(this));
            // NOTE: If this fails, can initiate a claim...
            require(cashBalanceExternal == assetCashBalance, "Insufficient asset cash");
            assetToken.transfer(msg.sender, assetCashBalance);
        }
    }
}