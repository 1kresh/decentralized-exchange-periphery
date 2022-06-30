// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

/// @title Errors reverted by a router
/// @notice Contains all errors reverted by the router
interface ISimswapRouterErrors {
    error SimswapRouter_EXCESSIVE_INPUT_AMOUNT(
        uint256 amountInMax,
        uint256[] amounts
    );
    error SimswapRouter_INVALID_PATH(address[] path);
    error SimswapRouter_INSUFFICIENT_A_AMOUNT(
        uint256 amountAMin,
        uint256 amountAOptimal,
        uint256 amountADesired
    );
    error SimswapRouter_INSUFFICIENT_B_AMOUNT(
        uint256 amountBMin,
        uint256 amountBOptimal,
        uint256 amountBDesired
    );
    error SimswapRouter_INSUFFICIENT_OUTPUT_AMOUNT(
        uint256 amountOutMin,
        uint256[] amounts
    );
    error SimswapRouter_Not_WETH9();
}
