// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library ErrorMessages {
    string internal constant E1 =
        "Campaign duration must be greater than current block number";
    string internal constant E2 = "Soft cap must be less than hard cap";
    string internal constant E3 = "The campaign has not been completed.";
    string internal constant E4 = "The soft cap has not been met.";
    string internal constant E5 = "Cannot buy tokens: Hard cap reached.";
    string internal constant E6 = "Withdrawals are disabled.";
    string internal constant E7 = "Only signer is allowed";
    string internal constant E8 = "The amount must be greater than zero.";
    string internal constant E9 =
        "Token value should be greater than network fee";
    string internal constant E10 = "Network fee exceeds token amount";
    string internal constant E11 = "Insufficient liquidity in pool";
    string internal constant E12 = "Pool doesn't have enough balance";
    string internal constant E13 = "Not enough liquidity available";
    string internal constant E14 =
        "Total token in circulation must  be greater than zero.";
    string internal constant E15 = "Insufficient allowance or balance";
    string internal constant E16 = "Insufficient liquidity in pool";
    string internal constant E17 = "Admin address cannot be zero address";
    string internal constant E18 = "Signer address cannot be zero address";
    string internal constant E19 = "The soft cap has already been reached.";
    string internal constant E20 =
        "End time must be greater than the start time";
    string internal constant E21 =
        "Purchase denied. The requested amount exceeds the available tokens in the pool. Please try with a lower amount.";
    string internal constant E22 =
        "Not enough tokens available in pool. Please try with a different amount.";
    string internal constant E23 = "Invalid nonce";
    string internal constant E24 = "Invalid data";
    string internal constant E25 =
        "Please wait for the profit to be added to pool";
    string internal constant E26 = "Insufficient balance";
    string internal constant E27 =
        "Insufficient tokens in pool. Please try with a different amount.";
}
