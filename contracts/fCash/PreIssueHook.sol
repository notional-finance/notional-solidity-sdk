// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "../lib/DateTime.sol";
import "./WrappedfCashFactory.sol";
import {IWrappedfCash} from "interfaces/notional/IWrappedfCash.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "interfaces/set-protocol/ISetToken.sol";

interface IManagerIssuanceHook {
    function invokePreIssueHook(ISetToken _setToken, uint256 _issueQuantity, address _sender, address _to) external;
}

contract NotionalIssuanceHook is IManagerIssuanceHook {

    /// Each byte in the bytes8 constant marks whether or not a given fCash tenor
    /// should be listed after a quarterly roll. The first index is unused, marketIndex = 0
    /// is invalid
    bytes8 public immutable requiredTenors;
    WrappedfCashFactory public immutable FACTORY;
    uint16 public immutable CURRENCY_ID;
    bytes8 internal constant BIT_ON = bytes8(0x0100000000000000);
    bytes8 internal constant BIT_OFF = bytes8(0);

    /// Sets the required tenors for the token as immutable, this is more gas efficient since
    /// invokePreIssueHook will be called after every issuance. Set Tokens with a different
    /// tenor cadence can deploy a different contract.
    /// NOTE: this only works where the FIXED token only has one currency, will need to extend
    /// this logic for multi-currency FIXED tokens
    constructor(
        bool use3MonthTenor,
        bool use6MonthTenor,
        bool use1YearTenor,
        bool use2YearTenor,
        bool use5YearTenor,
        bool use10YearTenor,
        bool use20YearTenor,
        WrappedfCashFactory _factory,
        uint16 _currencyId
    ) {
        // The zero index byte on required tenors is unused
        requiredTenors = (
            (use3MonthTenor ? BIT_ON : BIT_OFF) >>  8 |
            (use6MonthTenor ? BIT_ON : BIT_OFF) >> 16 |
            (use1YearTenor  ? BIT_ON : BIT_OFF) >> 24 |
            (use2YearTenor  ? BIT_ON : BIT_OFF) >> 32 |
            (use5YearTenor  ? BIT_ON : BIT_OFF) >> 40 |
            (use10YearTenor ? BIT_ON : BIT_OFF) >> 48 |
            (use20YearTenor ? BIT_ON : BIT_OFF) >> 56
        ); 
        FACTORY = _factory;
        CURRENCY_ID = _currencyId;
    }

  
    /// @notice PreIssuanceHook is called every time Set Tokens are minted. This hook will handle matured fCash assets
    ///   1. Check if any ERC20 wrappers need to be listed
    ///      1a. If yes, list them (and deploy them if necessary)
    ///   2. Check if any of the fCash tokens have matured
    ///      2a. For each matured fCash token, redeem the entire cash balance on the setToken
    ///      2b. Not sure where to send the cToken balance
    function invokePreIssueHook(ISetToken _setToken, uint256 _issueQuantity, address _sender, address _to) external {
        ISetToken.Position[] memory positions = _setToken.getPositions();
        bytes8 unlistedTenors = requiredTenors;
        
        for (uint256 i = 0; i < positions.length; i++) {
            IWrappedfCash wrapper = IWrappedfCash(positions[i].component);
            require(wrapper.getCurrencyId() == CURRENCY_ID, "Invalid Wrapper");
            // Turn off every tenor that is currently active, only the required tenors that are not yet
            // listed will be left at the end of the loop. Market Index will return zero when the wrapper
            // is idiosyncratic and will not have an effect here.
            unlistedTenors = _setByteToZero(unlistedTenors, wrapper.getMarketIndex());
            
            if (wrapper.hasMatured()) {
                // On maturity, we redeem the entire cash balance to asset tokens
                uint256 totalBalance = IERC777(address(wrapper)).balanceOf(address(_setToken));
                // NOTE: For this to work this contract must be listed as an operator for the _setToken
                IERC777(address(wrapper)).operatorBurn(
                    address(_setToken),
                    totalBalance,
                    abi.encode(IWrappedfCash.RedeemOpts(false, false, address(this))),
                    ""
                );

                // Not sure if this does the right thing, but we need to remove this particular
                // ERC20 now that it has matured.
                _setToken.removeComponent(address(wrapper));
            } 
        }

        if (unlistedTenors != 0) _listUnlistedTenors(_setToken, unlistedTenors);
    }

    function _listUnlistedTenors(ISetToken _setToken, bytes8 unlistedTenors) private {
        uint256 tRef = DateTime.getReferenceTime(block.timestamp);

        for (uint8 i = 1; i <= 8; i++) {
            if (unlistedTenors == 0) break;
            if (unlistedTenors[i] == 0) continue;

            // Solidity 0.8 does a conversion check here
            uint40 maturity = uint40(tRef + DateTime.getTradedMarket(i));

            // Check if the wrapper has already been deployed, else deploy it
            address wrapper = FACTORY.computeAddress(CURRENCY_ID, maturity);
            if (!Address.isContract(wrapper)) {
                wrapper = FACTORY.deployWrapper(CURRENCY_ID, maturity);
            }

            _setToken.addComponent(address(wrapper));
            unlistedTenors = _setByteToZero(unlistedTenors, i);
        }
    }

    function _setByteToZero(bytes8 unlistedTenors, uint8 index) private pure returns (bytes8) {
        return unlistedTenors & ~(BIT_ON >> (index * 8));
    }
}