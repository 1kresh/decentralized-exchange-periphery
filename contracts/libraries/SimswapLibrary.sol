// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import '@1kresh/decentralized-exchange-core/contracts/interfaces/ISimswapPool.sol';

import "./libraries/LowGasSafeMath.sol";

library SimswapLibrary {
    using LowGasSafeMath for uint256;

    function balance(address token, address ofToken) private view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20Minimal.balanceOf.selector, ofToken));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    function unsafe_inc(uint256 x) private pure returns (uint256) {
        unchecked { return x + 1; }
    }

    function unsafe_dec(uint256 x) private pure returns (uint256) {
        unchecked { return x - 1; }
    }

    /// @dev Returns sorted token addresses, used to handle return values from pools sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'SimswapLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SimswapLibrary: ZERO_ADDRESS');
    }

    /// @dev Calculates the CREATE2 address for a pool without making any external calls
    function poolFor(address factory, address tokenA, address tokenB) internal pure returns (address pool) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pool = address(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                0xf2f18c3dfefe7940311612c091e9167ab3a7168ef1fc7026e88b6c4f134fc2b5
            ))));
    }

    /// @dev Fetches and sorts the reserves for a pool
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ISimswapPool(poolFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @dev Given some amount of an asset and pool reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'SimswapLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'SimswapLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    /// @dev Given an input amount of an asset and pool reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'SimswapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'SimswapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @dev Given an output amount of an asset and pool reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'SimswapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'SimswapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }

    /// @dev Performs chained getAmountOut calculations on any number of pools
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        uint256 pathLength = path.length;
        require(pathLength >= 2, 'SimswapLibrary: INVALID_PATH');
        amounts = new uint256[](pathLength);
        amounts[0] = amountIn;
        for (uint256 i; i < pathLength - 1; unsafe_inc(i)) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @dev Performs chained getAmountIn calculations on any number of pools
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) internal view returns (uint256[] memory amounts) {
        uint256 pathLength = path.length;
        require(pathLength >= 2, 'SimswapLibrary: INVALID_PATH');
        amounts = new uint256[](pathLength);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = pathLength - 1; i > 0; unsafe_dec(i)) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}