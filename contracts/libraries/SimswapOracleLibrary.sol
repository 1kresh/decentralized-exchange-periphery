// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import { ISimswapPool } from '@simswap/core/contracts/interfaces/ISimswapPool.sol';

import { FixedPoint } from './FixedPoint.sol';

// library with helper methods for oracles that are concerned with computing average prices
library SimswapOracleLibrary {
    using FixedPoint for *;

    /// @dev Returns the block timestamp truncated to 32 bits, i.e. mod 2**32.
    function _blockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp); // truncation is desired
    }

    /// @dev Produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(address pool)
        internal
        view
        returns (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        )
    {
        blockTimestamp = _blockTimestamp();
        price0Cumulative = ISimswapPool(pool).price0CumulativeLast();
        price1Cumulative = ISimswapPool(pool).price1CumulativeLast();

        // if time has elapsed since the last update on the pool, mock the accumulated price values
        (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        ) = ISimswapPool(pool).slot0();
        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            unchecked {
                price0Cumulative +=
                    uint256(FixedPoint.fraction(reserve1, reserve0)._x) *
                    timeElapsed;
                // counterfactual
                price1Cumulative +=
                    uint256(FixedPoint.fraction(reserve0, reserve1)._x) *
                    timeElapsed;
            }
        }
    }
}
