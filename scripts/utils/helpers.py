import eth_abi
from brownie.network.state import Chain
from eth_abi.packed import encode_abi_packed
from utils.constants import DEPOSIT_ACTION_TYPE, TRADE_ACTION_TYPE, TRADE_CALLDATA_DEFAULTS

chain = Chain()

def get_trade_calldata():
    return eth_abi.encode_abi(
        [
            "uint24", 
            "uint256", 
            "uint160"            
        ],
        [
            TRADE_CALLDATA_DEFAULTS["poolFee"],
            chain.time() + TRADE_CALLDATA_DEFAULTS["expiration"],
            TRADE_CALLDATA_DEFAULTS["priceLimit"]
        ]
    )

def get_collateral_currency_calldata(type, account, localCurrency, collateralCurrency):
    return eth_abi.encode_abi(
        [
            "uint8",
            "address",
            "uint16",
            "address",
            "uint16",
            "address",
            "address",
            "uint128",
            "uint96",
            "bytes",
        ],
        [
            type,
            account,
            localCurrency["id"],
            localCurrency["address"],
            collateralCurrency["id"],
            collateralCurrency["address"],
            collateralCurrency["underlying"]["address"],
            0, # Max collateral
            0, # Max nToken
            get_trade_calldata(),
        ],
    )

def get_balance_action(currencyId, depositActionType, **kwargs):
    depositActionAmount = (
        0 if "depositActionAmount" not in kwargs else kwargs["depositActionAmount"]
    )
    withdrawAmountInternalPrecision = (
        0
        if "withdrawAmountInternalPrecision" not in kwargs
        else kwargs["withdrawAmountInternalPrecision"]
    )
    withdrawEntireCashBalance = (
        False if "withdrawEntireCashBalance" not in kwargs else kwargs["withdrawEntireCashBalance"]
    )
    redeemToUnderlying = (
        False if "redeemToUnderlying" not in kwargs else kwargs["redeemToUnderlying"]
    )

    return (
        DEPOSIT_ACTION_TYPE[depositActionType],
        currencyId,
        int(depositActionAmount),
        int(withdrawAmountInternalPrecision),
        withdrawEntireCashBalance,
        redeemToUnderlying,
    )

def get_balance_trade_action(currencyId, depositActionType, tradeActionData, **kwargs):
    tradeActions = [get_trade_action(**t) for t in tradeActionData]
    balanceAction = list(get_balance_action(currencyId, depositActionType, **kwargs))
    balanceAction.append(tradeActions)

    return tuple(balanceAction)


def get_trade_action(**kwargs):
    tradeActionType = kwargs["tradeActionType"]

    if tradeActionType == "Lend":
        return encode_abi_packed(
            ["uint8", "uint8", "uint88", "uint32", "uint120"],
            [
                TRADE_ACTION_TYPE[tradeActionType],
                kwargs["marketIndex"],
                int(kwargs["notional"]),
                int(kwargs["minSlippage"]),
                0,
            ],
        )
    elif tradeActionType == "Borrow":
        return encode_abi_packed(
            ["uint8", "uint8", "uint88", "uint32", "uint120"],
            [
                TRADE_ACTION_TYPE[tradeActionType],
                kwargs["marketIndex"],
                int(kwargs["notional"]),
                int(kwargs["maxSlippage"]),
                0,
            ],
        )
    elif tradeActionType == "AddLiquidity":
        return encode_abi_packed(
            ["uint8", "uint8", "uint88", "uint32", "uint32", "uint88"],
            [
                TRADE_ACTION_TYPE[tradeActionType],
                kwargs["marketIndex"],
                int(kwargs["notional"]),
                int(kwargs["minSlippage"]),
                int(kwargs["maxSlippage"]),
                0,
            ],
        )
    elif tradeActionType == "RemoveLiquidity":
        return encode_abi_packed(
            ["uint8", "uint8", "uint88", "uint32", "uint32", "uint88"],
            [
                TRADE_ACTION_TYPE[tradeActionType],
                kwargs["marketIndex"],
                int(kwargs["notional"]),
                int(kwargs["minSlippage"]),
                int(kwargs["maxSlippage"]),
                0,
            ],
        )
    elif tradeActionType == "PurchaseNTokenResidual":
        return encode_abi_packed(
            ["uint8", "uint32", "int88", "uint128"],
            [
                TRADE_ACTION_TYPE[tradeActionType],
                kwargs["maturity"],
                int(kwargs["fCashAmountToPurchase"]),
                0,
            ],
        )
    elif tradeActionType == "SettleCashDebt":
        return encode_abi_packed(
            ["uint8", "address", "uint88"],
            [
                TRADE_ACTION_TYPE[tradeActionType],
                kwargs["counterparty"],
                int(kwargs["amountToSettle"]),
            ],
        )
