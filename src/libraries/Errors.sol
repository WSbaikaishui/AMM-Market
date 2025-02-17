// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Errors {
    error ZeroAddress();
    error FeeDenomZero();
    error FeeExceedsHundredPercent();
    error MustProvideEthAndTokens();
    error TokenTransferFailed();
    error InsufficientTokenAmountProvided();
    error InsufficientLiquidityBalance();
    error EthTransferFailed();
    error NoEthSent();
    error SlippageLimitReached();
    error MustSellTokens();
} 