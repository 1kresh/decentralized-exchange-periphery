// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import '@1kresh/decentralized-exchange-core/contracts/interfaces/ISimswapFactory.sol';
import '@1kresh/decentralized-exchange-core/contracts/interfaces/ISimswapPool.sol';

import '../libraries/FixedPoint.sol';
import '../libraries/SafeMath.sol';
import '../libraries/SimswapLibrary.sol';
import '../libraries/SimswapOracleLibrary.sol';

// sliding window oracle that uses observations collected over a window to provide moving price averages in the past
// `windowSize` with a precision of `windowSize / granularity`
// note this is a singleton oracle and only needs to be deployed once per desired parameters, which
// differs from the simple oracle which must be deployed once per pool.
contract ExampleSlidingWindowOracle {
    using FixedPoint for *;
    using SafeMath for uint256;

    struct Observation {
        uint256 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    address public immutable factory;
    // the desired amount of time over which the moving average should be computed, e.g. 24 hours
    uint256 public immutable windowSize;
    // the number of observations stored for each pool, i.e. how many price observations are stored for the window.
    // as granularity increases from 1, more frequent updates are needed, but moving averages become more precise.
    // averages are computed over intervals with sizes in the range:
    //   [windowSize - (windowSize / granularity) * 2, windowSize]
    // e.g. if the window size is 24 hours, and the granularity is 24, the oracle will return the average price for
    //   the period:
    //   [now - [22 hours, 24 hours], now]
    uint8 public immutable granularity;
    // this is redundant with granularity and windowSize, but stored for gas savings & informational purposes.
    uint256 public immutable periodSize;

    // mapping from pool address to a list of price observations of that pool
    mapping(address => Observation[]) public poolObservations;

    constructor(address factory_, uint256 windowSize_, uint8 granularity_) public {
        require(granularity_ > 1, 'SlidingWindowOracle: GRANULARITY');
        require(
            (periodSize = windowSize_ / granularity_) * granularity_ == windowSize_,
            'SlidingWindowOracle: WINDOW_NOT_EVENLY_DIVISIBLE'
        );
        factory = factory_;
        windowSize = windowSize_;
        granularity = granularity_;
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint256 timestamp) public view returns (uint8 index) {
        uint256 epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularity);
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow(address pool) private view returns (Observation storage firstObservation) {
        uint8 observationIndex = observationIndexOf(block.timestamp);
        // no overflow issue. if observationIndex + 1 overflows, result is still zero.
        uint8 firstObservationIndex = (observationIndex + 1) % granularity;
        firstObservation = poolObservations[pool][firstObservationIndex];
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update(address tokenA, address tokenB) external {
        address pool = SimswapLibrary.poolFor(factory, tokenA, tokenB);

        // populate the array with empty observations (first call only)
        for (uint256 i = poolObservations[pool].length; i < granularity; i++) {
            poolObservations[pool].push();
        }

        // get the observation for the current period
        uint8 observationIndex = observationIndexOf(block.timestamp);
        Observation storage observation = poolObservations[pool][observationIndex];

        // we only want to commit updates once per period (i.e. windowSize / granularity)
        uint256 timeElapsed = block.timestamp - observation.timestamp;
        if (timeElapsed > periodSize) {
            (uint256 price0Cumulative, uint256 price1Cumulative,) = SimswapOracleLibrary.currentCumulativePrices(pool);
            observation.timestamp = block.timestamp;
            observation.price0Cumulative = price0Cumulative;
            observation.price1Cumulative = price1Cumulative;
        }
    }

    // given the cumulative prices of the start and end of a period, and the length of the period, compute the average
    // price in terms of how much amount out is received for the amount in
    function computeAmountOut(
        uint256 priceCumulativeStart, uint256 priceCumulativeEnd,
        uint256 timeElapsed, uint256 amountIn
    ) private pure returns (uint256 amountOut) {
        // overflow is desired.
        FixedPoint.uq112x112 memory priceAverage = FixedPoint.uq112x112();
        priceAverage._x = uint224((priceCumulativeEnd - priceCumulativeStart) / timeElapsed);
        amountOut = (priceAverage * amountIn).decode144();
    }

    // returns the amount out corresponding to the amount in for a given token using the moving average over the time
    // range [now - [windowSize, windowSize - periodSize * 2], now]
    // update must have been called for the bucket corresponding to timestamp `now - windowSize`
    function consult(address tokenIn, uint256 amountIn, address tokenOut) external view returns (uint256 amountOut) {
        address pool = SimswapLibrary.poolFor(factory, tokenIn, tokenOut);
        Observation storage firstObservation = getFirstObservationInWindow(pool);

        uint256 timeElapsed = block.timestamp - firstObservation.timestamp;
        require(timeElapsed <= windowSize, 'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATION');
        // should never happen.
        require(timeElapsed >= windowSize - periodSize * 2, 'SlidingWindowOracle: UNEXPECTED_TIME_ELAPSED');

        (uint256 price0Cumulative, uint256 price1Cumulative,) = SimswapOracleLibrary.currentCumulativePrices(pool);
        (address token0,) = SimswapLibrary.sortTokens(tokenIn, tokenOut);

        if (token0 == tokenIn) {
            return computeAmountOut(firstObservation.price0Cumulative, price0Cumulative, timeElapsed, amountIn);
        } else {
            return computeAmountOut(firstObservation.price1Cumulative, price1Cumulative, timeElapsed, amountIn);
        }
    }
}