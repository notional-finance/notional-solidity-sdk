
DEPOSIT_ACTION_TYPE = {
    "None": 0,
    "DepositAsset": 1,
    "DepositUnderlying": 2,
    "DepositAssetAndMintNToken": 3,
    "DepositUnderlyingAndMintNToken": 4,
    "RedeemNToken": 5,
    "ConvertCashToNToken": 6,
}

TRADE_ACTION_TYPE = {
    "Lend": 0,
    "Borrow": 1,
    "AddLiquidity": 2,
    "RemoveLiquidity": 3,
    "PurchaseNTokenResidual": 4,
    "SettleCashDebt": 5,
}

TRADE_CALLDATA_DEFAULTS = {
    "poolFee": 3000,
    "expiration": 20000,
    "priceLimit": 0
}
