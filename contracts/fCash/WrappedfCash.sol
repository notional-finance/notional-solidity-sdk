// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
pragma experimental ABIEncoderV2;

import "../lib/EncodeDecode.sol";
import "../lib/DateTime.sol";
import "../abstract/AllowfCashReceiver.sol";
import "interfaces/notional/NotionalProxy.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin-upgradeable/contracts/token/ERC777/ERC777Upgradeable.sol";

contract WrappedfCash is ERC777Upgradeable, AllowfCashReceiver {
    using SafeERC20 for IERC20;

    address internal constant ETH_ADDRESS = address(0);
    /// address to the NotionalV2 system
    NotionalProxy public immutable NotionalV2;

    /// @dev Storage slot for fCash id. Read only and set on initialization
    uint256 private _fCashId;

    /// @notice Constructor is called only on deployment to set the Notional address, rest of state
    /// is initialized on the proxy.
    /// @dev Ensure initializer modifier is on the constructor to prevent an attack on UUPSUpgradeable contracts
    constructor(NotionalProxy _notional) initializer {
        NotionalV2 = _notional;
    }

    /// @notice Initializes a proxy for a specific fCash asset
    function initialize(
        uint16 currencyId,
        uint40 maturity
    ) external initializer {
        (CashGroupSettings memory cashGroup) = NotionalV2.getCashGroup(currencyId);
        require(cashGroup.maxMarketIndex > 0, "Invalid currency");
        // This includes idiosyncratic fCash maturities
        require(DateTime.isValidMaturity(cashGroup.maxMarketIndex, maturity, block.timestamp), "Invalid maturity");

        _fCashId = EncodeDecode.encodeERC1155Id(currencyId, maturity, Constants.FCASH_ASSET_TYPE);
        (IERC20 underlyingToken, /* */) = _getUnderlyingToken(currencyId);
        string memory _symbol = IERC20Metadata(address(underlyingToken)).symbol();
        string memory _maturity = Strings.toString(maturity);

        __ERC777_init(
            // name
            string(abi.encodePacked("Wrapped f", _symbol, " @ ", _maturity)),
            // symbol
            string(abi.encodePacked("wf", _symbol, ":", _maturity)),
            // no default operators
            new address[](0)
        );
    }

    /***** Mint Methods *****/

    // TODO: add method for market lending to mint fCash

    /// @notice This hook will be called every time this contract receives fCash, will validate that
    /// this is the correct fCash and then mint the corresponding amount of wrapped fCash tokens
    /// back to the user.
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
        uint256 fCashID = getfCashId();
        require(_id == fCashID, "Invalid fCash asset");
        // Protect against signed value underflows
        require(int256(_value) > 0, "Invalid value");

        // Double check the account's position, these are not strictly necessary and add gas costs
        // but might be good safe guards
        AccountContext memory ac = NotionalV2.getAccountContext(address(this));
        require(ac.hasDebt == 0x00, "Incurred debt");
        PortfolioAsset[] memory assets = NotionalV2.getAccountPortfolio(
            address(this)
        );
        require(assets.length == 1, "Invalid assets");
        require(
            EncodeDecode.encodeERC1155Id(
                assets[0].currencyId,
                assets[0].maturity,
                assets[0].assetType
            ) == fCashID,
            "Invalid portfolio asset"
        );

        // Update per account fCash balance, calldata from the ERC1155 call is
        // passed via the ERC777 interface.
        bytes memory userData;
        bytes memory operatorData;
        if (_operator == _from) userData = _data;
        else operatorData = _data;

        // We don't require a recipient ack here to maintain compatibility
        // with contracts that don't support ERC777
        _mint(_from, _value, userData, operatorData, false);

        // This will allow the fCash to be accepted
        return ERC1155_ACCEPTED;
    }

    /// @dev Do not accept batches of fCash
    function onERC1155BatchReceived(
        address, /* _operator */
        address, /* _from */
        uint256[] calldata, /* _ids */
        uint256[] calldata, /* _values */
        bytes calldata /* _data */
    ) external pure override returns (bytes4) {
        return 0;
    }

    /***** Redeem (Burn) Methods *****/

    /// @notice Provide a less dangerous sounding alias for `burn`
    function redeem(uint256 amount, bytes memory data) external {
        burn(amount, data);
    }

    /// @notice Provide a less dangerous sounding alias for `operatorBurn`
    function operatorRedeem(
        address account,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) external {
        operatorBurn(account, amount, data, operatorData);
    }

    /// @notice Called before tokens are burned (redemption) and so we will handle
    /// the fCash properly before and after maturity.
    function _burn(
        address from,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal override {
        // Save the total supply value before burning to calculate the cash claim share
        uint256 initialTotalSupply = totalSupply();
        // This will validate that the account has sufficient tokens to burn and make
        // any relevant underlying stateful changes to balances.
        super._burn(from, amount, userData, operatorData);

        if (hasMatured()) {
            // If the fCash has matured, then we need to ensure that the account is settled
            // and then we will transfer back the account's share of asset tokens.

            // This is a noop if the account is already settled
            NotionalV2.settleAccount(address(this));
            uint16 currencyId = getCurrencyId();

            (int256 cashBalance, /* */, /* */) = NotionalV2.getAccountBalance(currencyId, address(this));
            require(0 < cashBalance, "Negative Cash Balance");

            // This always rounds down in favor of the wrapped fCash contract.
            uint256 assetInternalCashClaim = (uint256(cashBalance) * amount) / initialTotalSupply;
            require(assetInternalCashClaim <= uint256(type(uint88).max));

            // By default will redeem to asset tokens
            bool redeemToUnderlying = false;
            if (userData.length > 0) {
                (redeemToUnderlying) = abi.decode(userData, (bool));
            }

            // Transfer withdrawn tokens to the `from` address
            _withdrawCashToAccount(currencyId, from, uint88(assetInternalCashClaim), redeemToUnderlying);
        } else {
            // If the fCash has not matured, then we can transfer it via ERC1155.
            // NOTE: this will fail if the destination is a contract because the ERC1155 contract
            // does a callback to the `onERC1155Received` hook. If that is the case it is possible
            // to use a regular ERC20 transfer on this contract instead.
            NotionalV2.safeTransferFrom(
                address(this), // Sending from this contract
                from,          // Destination is the address burning the fCash
                getfCashId(),  // fCash identifier
                amount,        // Amount of fCash to send
                userData
            );
        }
    }

    /// @notice After maturity, withdraw cash back to account
    function _withdrawCashToAccount(
        uint16 currencyId,
        address receiver,
        uint88 assetInternalCashClaim,
        bool redeemToUnderlying
    ) private returns (uint256 tokensTransferred) {
        IERC20 token;

        if (redeemToUnderlying) {
            (token, /* */) = getUnderlyingToken();
        } else {
            (token, /* */) = getAssetToken();
        }

        uint256 balanceBefore = token.balanceOf(address(this));
        NotionalV2.withdraw(currencyId, assetInternalCashClaim, redeemToUnderlying);
        uint256 balanceAfter = token.balanceOf(address(this));
        tokensTransferred = balanceAfter - balanceBefore;

        token.safeTransfer(receiver, tokensTransferred);
    }

    /***** View Methods  *****/

    /// @notice Returns the underlying fCash ID of the token
    function getfCashId() public view returns (uint256) {
        return _fCashId;
    }

    /// @notice Returns the underlying fCash maturity of the token
    function getMaturity() public view returns (uint40 maturity) {
        (/* */, maturity, /* */) = EncodeDecode.decodeERC1155Id(_fCashId);
    }

    /// @notice True if the fCash has matured, assets mature exactly on the block time
    function hasMatured() public view returns (bool) {
        return getMaturity() <= block.timestamp;
    }

    /// @notice Returns the underlying fCash currency
    function getCurrencyId() public view returns (uint16 currencyId) {
        (currencyId, /* */, /* */) = EncodeDecode.decodeERC1155Id(_fCashId);
    }

    /// @notice Returns the components of the fCash idd
    function getDecodedID() public view returns (uint16 currencyId, uint40 maturity) {
        (currencyId, maturity, /* */) = EncodeDecode.decodeERC1155Id(_fCashId);
    }

    /// @notice fCash is always denominated in 8 decimal places
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /// @notice Returns the token and precision of the token that this token settles
    /// to. For example, fUSDC will return the USDC token address and 1e6. The zero
    /// address will represent ETH.
    function getUnderlyingToken()
        public
        view
        returns (IERC20 underlyingToken, int256 underlyingPrecision)
    {
        uint16 currencyId = getCurrencyId();
        return _getUnderlyingToken(currencyId);
    }

    /// @dev Called during initialization to set token name and symbol
    function _getUnderlyingToken(uint16 currencyId)
        private
        view
        returns (IERC20 underlyingToken, int256 underlyingPrecision)
    {
        (Token memory asset, Token memory underlying) = NotionalV2.getCurrency(
            currencyId
        );

        if (asset.tokenType == TokenType.NonMintable) {
            // In this case the asset token is the underlying
            return (IERC20(asset.tokenAddress), asset.decimals);
        } else {
            return (IERC20(underlying.tokenAddress), underlying.decimals);
        }
    }

    /// @notice Returns the asset token which the fCash settles to. This will be an interest
    /// bearing token like a cToken or aToken.
    function getAssetToken()
        public
        view
        returns (IERC20 underlyingToken, int256 underlyingPrecision)
    {
        (Token memory asset, /* Token memory underlying */) = NotionalV2.getCurrency(
            getCurrencyId()
        );

        return (IERC20(asset.tokenAddress), asset.decimals);
    }

}