// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { ISimswapPool } from '@simswap/core/contracts/interfaces/ISimswapPool.sol';

import { ISimswapRouter } from '../interfaces/ISimswapRouter.sol';
import { SimswapLibrary } from '../libraries/SimswapLibrary.sol';
import { SimswapLiquidityMathLibrary } from '../libraries/SimswapLiquidityMathLibrary.sol';

error ExampleSwapToPrice_ZERO_AMOUNT_IN(uint256 amountIn);
error ExampleSwapToPrice_ZERO_PRICE(
    uint256 truePriceTokenA,
    uint256 truePriceTokenB
);
error ExampleSwapToPrice_ZERO_SPEND(
    uint256 maxSpendTokenA,
    uint256 maxSpendTokenB
);

contract ExampleSwapToPrice {
    using SafeERC20 for IERC20;

    ISimswapRouter public immutable router;
    address public immutable factory;

    constructor(address factory_, ISimswapRouter router_) {
        factory = factory_;
        router = router_;
    }

    // swaps an amount of either token such that the trade is profit-maximizing, given an external true price
    // true price is expressed in the ratio of token A to token B
    // caller must approve this contract to spend whichever token is intended to be swapped
    function swapToPrice(
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 maxSpendTokenA,
        uint256 maxSpendTokenB,
        address to,
        uint256 deadline
    ) public {
        // true price is expressed as a ratio, so both values must be non-zero
        if (truePriceTokenA == 0 || truePriceTokenB == 0)
            revert ExampleSwapToPrice_ZERO_PRICE(
                truePriceTokenA,
                truePriceTokenB
            );
        // caller can specify 0 for either if they wish to swap in only one direction, but not both
        if (maxSpendTokenA == 0 && maxSpendTokenB == 0)
            revert ExampleSwapToPrice_ZERO_SPEND(
                maxSpendTokenA,
                maxSpendTokenB
            );

        bool aToB;
        uint256 amountIn;
        {
            (uint256 reserveA, uint256 reserveB) = SimswapLibrary.getReserves(
                factory,
                tokenA,
                tokenB
            );
            (aToB, amountIn) = SimswapLiquidityMathLibrary
                .computeProfitMaximizingTrade(
                    truePriceTokenA,
                    truePriceTokenB,
                    reserveA,
                    reserveB
                );
        }

        if (amountIn == 0) revert ExampleSwapToPrice_ZERO_AMOUNT_IN(amountIn);

        // spend up to the allowance of the token in
        uint256 maxSpend = aToB ? maxSpendTokenA : maxSpendTokenB;
        if (amountIn > maxSpend) {
            amountIn = maxSpend;
        }

        address tokenIn = aToB ? tokenA : tokenB;
        address tokenOut = aToB ? tokenB : tokenA;
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeApprove(address(router), amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        router.swapExactTokensForTokens(
            amountIn,
            0, // amountOutMin: we can skip computing this number because the math is tested
            path,
            to,
            deadline
        );
    }
}
