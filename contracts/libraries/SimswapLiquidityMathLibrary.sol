// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import { ISimswapERC20 } from '@simswap/core/contracts/interfaces/ISimswapERC20.sol';
import { ISimswapFactory } from '@simswap/core/contracts/interfaces/ISimswapFactory.sol';
import { ISimswapPool } from '@simswap/core/contracts/interfaces/ISimswapPool.sol';

import { FullMath } from './FullMath.sol';
import { SimswapLibrary } from './SimswapLibrary.sol';

error ComputeLiquidityValue_LIQUIDITY_AMOUNT(uint256 totalSupply, uint256 liquidityAmount);
error SimswapArbitrageLibrary_ZERO_POOL_RESERVES();

// library containing some math for dealing with the liquidity shares of a pool, e.g. computing their exact value
// in terms of the underlying tokens
library SimswapLiquidityMathLibrary {
    /// @dev Computes the direction and magnitude of the profit-maximizing trade
    function computeProfitMaximizingTrade(
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 reserveA,
        uint256 reserveB
    ) pure internal returns (bool aToB, uint256 amountIn) {
        aToB = FullMath.mulDiv(reserveA, truePriceTokenB, reserveB) < truePriceTokenA;

        uint256 invariant = reserveA * reserveB;

        uint256 leftSide = FullMath.sqrt(
            FullMath.mulDiv(
                invariant * 1000,
                aToB ? truePriceTokenA : truePriceTokenB,
                (aToB ? truePriceTokenB : truePriceTokenA) * 997
            )
        );
        uint256 rightSide = (aToB ? reserveA * 1000 : reserveB * 1000);
        unchecked {
            rightSide /= 997;
        }

        if (leftSide < rightSide) return (false, 0);

        // compute the amount that must be sent to move the price to the profit-maximizing price
        amountIn = leftSide - rightSide;
    }

    /// @dev Gets the reserves after an arbitrage moves the price to the profit-maximizing ratio given an externally observed true price
    function getReservesAfterArbitrage(
        address factory,
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB
    ) view internal returns (uint256 reserveA, uint256 reserveB) {
        // first get reserves before the swap
        (reserveA, reserveB) = SimswapLibrary.getReserves(factory, tokenA, tokenB);

        if (reserveA == 0 || reserveB == 0)
            revert SimswapArbitrageLibrary_ZERO_POOL_RESERVES();

        // then compute how much to swap to arb to the true price
        (bool aToB, uint256 amountIn) = computeProfitMaximizingTrade(truePriceTokenA, truePriceTokenB, reserveA, reserveB);

        if (amountIn == 0) {
            return (reserveA, reserveB);
        }

        unchecked {
            // now affect the trade to the reserves
            if (aToB) {
                uint256 amountOut = SimswapLibrary.getAmountOut(amountIn, reserveA, reserveB);
                reserveA += amountIn;
                reserveB -= amountOut;
            } else {
                uint256 amountOut = SimswapLibrary.getAmountOut(amountIn, reserveB, reserveA);
                reserveB += amountIn;
                reserveA -= amountOut;
            }
        }
    }

    /// @dev Computes liquidity value given all the parameters of the pool
    function computeLiquidityValue(
        uint256 reservesA,
        uint256 reservesB,
        uint256 totalSupply,
        uint256 liquidityAmount,
        bool feeOn,
        uint256 kLast
    ) internal pure returns (uint256 tokenAAmount, uint256 tokenBAmount) {
        if (feeOn && kLast != 0) {
            uint256 rootK = FullMath.sqrt(reservesA * reservesB);
            uint256 rootKLast = FullMath.sqrt(kLast);
            if (rootK > rootKLast) {
                uint256 numerator1 = totalSupply;
                uint256 numerator2 = rootK - rootKLast;
                uint256 denominator = rootK * 5 + rootKLast;
                uint256 feeLiquidity = FullMath.mulDiv(numerator1, numerator2, denominator);
                totalSupply = totalSupply + feeLiquidity;
            }
        }
        tokenAAmount = reservesA * liquidityAmount;
        tokenBAmount = reservesB * liquidityAmount;
        unchecked {
            tokenAAmount /= totalSupply;
            tokenBAmount /= totalSupply;
        }
    }

    /// @dev Get all current parameters from the pool and compute value of a liquidity amount
    // **note this is subject to manipulation, e.g. sandwich attacks**. prefer passing a manipulation resistant price to
    // #getLiquidityValueAfterArbitrageToPrice
    function getLiquidityValue(
        address factory,
        address tokenA,
        address tokenB,
        uint256 liquidityAmount
    ) internal view returns (uint256 tokenAAmount, uint256 tokenBAmount) {
        (uint256 reservesA, uint256 reservesB) = SimswapLibrary.getReserves(factory, tokenA, tokenB);
        address poolAddress = SimswapLibrary.poolFor(factory, tokenA, tokenB);
        ISimswapPool pool = ISimswapPool(poolAddress);
        bool feeOn = ISimswapFactory(factory).feeTo() != address(0);
        uint256 kLast = feeOn ? pool.kLast() : 0;
        uint256 totalSupply = ISimswapERC20(poolAddress).totalSupply();
        return computeLiquidityValue(reservesA, reservesB, totalSupply, liquidityAmount, feeOn, kLast);
    }

    /// @dev Given two tokens, tokenA and tokenB, and their "true price", i.e. the observed ratio of value of token A to token B,
    // and a liquidity amount, returns the value of the liquidity in terms of tokenA and tokenB
    function getLiquidityValueAfterArbitrageToPrice(
        address factory,
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 liquidityAmount
    ) internal view returns (
        uint256 tokenAAmount,
        uint256 tokenBAmount
    ) {
        bool feeOn = ISimswapFactory(factory).feeTo() != address(0);
        address poolAddress = SimswapLibrary.poolFor(factory, tokenA, tokenB);
        ISimswapPool pool = ISimswapPool(poolAddress);
        uint256 kLast = feeOn ? pool.kLast() : 0;
        uint256 totalSupply = ISimswapERC20(poolAddress).totalSupply();

        // this also checks that totalSupply > 0
        if (totalSupply < liquidityAmount || liquidityAmount == 0)
            revert ComputeLiquidityValue_LIQUIDITY_AMOUNT(totalSupply, liquidityAmount);

        (uint256 reservesA, uint256 reservesB) = getReservesAfterArbitrage(factory, tokenA, tokenB, truePriceTokenA, truePriceTokenB);

        return computeLiquidityValue(reservesA, reservesB, totalSupply, liquidityAmount, feeOn, kLast);
    }
}