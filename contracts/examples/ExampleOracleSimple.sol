// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import { ISimswapFactory } from '@simswap/core/contracts/interfaces/ISimswapFactory.sol';
import { ISimswapPool } from '@simswap/core/contracts/interfaces/ISimswapPool.sol';

import { FixedPoint, uq112x112 } from '../libraries/FixedPoint.sol';
import { SimswapLibrary } from '../libraries/SimswapLibrary.sol';
import { SimswapOracleLibrary } from '../libraries/SimswapOracleLibrary.sol';

error ExampleOracleSimple_INVALID_TOKEN(address token, address token1);
error ExampleOracleSimple_NO_RESERVES(uint112 reserve0, uint112 reserve1);
error ExampleOracleSimple_PERIOD_NOT_ELAPSED(uint32 timeElapsed, uint256 PERIOD);

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract ExampleOracleSimple {
    using FixedPoint for *;

    uint256 public constant PERIOD = 24 hours;

    ISimswapPool immutable pool;
    address public immutable token0;
    address public immutable token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    
    uint32 public blockTimestampLast;

    uq112x112 public price0Average;
    uq112x112 public price1Average;

    constructor(address factory, address tokenA, address tokenB) {
        ISimswapPool _pool = ISimswapPool(SimswapLibrary.poolFor(factory, tokenA, tokenB));
        pool = _pool;
        token0 = _pool.token0();
        token1 = _pool.token1();
        price0CumulativeLast = _pool.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pool.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pool.slot0();
        if (reserve0 == 0 || reserve1 == 0) // ensure that there's liquidity in the pool
            revert ExampleOracleSimple_NO_RESERVES(reserve0, reserve1);
    }

    function update() external {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            SimswapOracleLibrary.currentCumulativePrices(address(pool));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // ensure that at least one full period has passed since the last update
        if (timeElapsed < PERIOD)
            revert ExampleOracleSimple_PERIOD_NOT_ELAPSED(timeElapsed, PERIOD);

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        unchecked {
            price0Average = uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
            price1Average = uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));
        }
        
        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut) {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            if (token != token1)
                revert ExampleOracleSimple_INVALID_TOKEN(token, token1);
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }
}