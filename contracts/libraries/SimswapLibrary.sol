// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { ISimswapPool } from '@simswap/core/contracts/interfaces/ISimswapPool.sol';
import { ISimswapFactory } from '@simswap/core/contracts/interfaces/ISimswapFactory.sol';

error SimswapLibrary_IDENTICAL_ADDRESSES();
error SimswapLibrary_INSUFFICIENT_AMOUNT();
error SimswapLibrary_INSUFFICIENT_INPUT_AMOUNT();
error SimswapLibrary_INSUFFICIENT_LIQUIDITY(uint256 reserveA, uint256 reserevB);
error SimswapLibrary_INSUFFICIENT_OUTPUT_AMOUNT();
error SimswapLibrary_INVALID_PATH(address[] path);
error SimswapLibrary_ZERO_ADDRESS();

library SimswapLibrary {
    // keccak256(type(SimswapPool).creationCode)
    bytes32 internal constant POOL_INIT_CODE_HASH = 0x7362feddda8b9a3d60651d4926524c6c5aa42955fa7e42aba6fc90a58912feda;
    
    function balance(address token, address ofToken) internal view returns (uint256) {
        (bool success, bytes memory data) =
            token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, ofToken));
        require(success && data.length >= 32);
        return abi.decode(data, (uint256));
    }

    /// @dev Returns sorted token addresses, used to handle return values from pools sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB)
            revert SimswapLibrary_IDENTICAL_ADDRESSES();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0))
            revert SimswapLibrary_ZERO_ADDRESS();
    }

    /// @dev Calculates the CREATE2 address for a pool without making any external calls
    function poolFor(address factory, address tokenA, address tokenB) internal pure returns (address poolAddress) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        poolAddress = address(uint160(uint(keccak256(
            abi.encodePacked(
                bytes1(0xff),
                factory,
                keccak256(abi.encode(token0, token1)),
                POOL_INIT_CODE_HASH
            )
        ))));
    }

    /// @dev Fetches and sorts the reserves for a pool
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        address poolAddr = poolFor(factory, tokenA, tokenB);
        ISimswapPool pool = ISimswapPool(poolAddr);
        (uint256 reserve0, uint256 reserve1,) = pool.slot0();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @dev Given some amount of an asset and pool reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA == 0)
            revert SimswapLibrary_INSUFFICIENT_AMOUNT();
        if (reserveA == 0 || reserveB == 0)
            revert SimswapLibrary_INSUFFICIENT_LIQUIDITY(reserveA, reserveB);
        amountB = amountA * reserveB / reserveA;
    }

    /// @dev Given an input amount of an asset and pool reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        if (amountIn == 0)
            revert SimswapLibrary_INSUFFICIENT_INPUT_AMOUNT();
        if (reserveIn == 0 || reserveOut == 0)
            revert SimswapLibrary_INSUFFICIENT_LIQUIDITY(reserveIn, reserveOut);
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        unchecked {
            amountOut = numerator / denominator;
        }
    }

    /// @dev Given an output amount of an asset and pool reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        if (amountOut == 0)
            revert SimswapLibrary_INSUFFICIENT_OUTPUT_AMOUNT();
        if (reserveIn == 0 || reserveOut == 0)
            revert SimswapLibrary_INSUFFICIENT_LIQUIDITY(reserveIn, reserveOut);
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        unchecked {
            amountIn = numerator / denominator;
        }
        amountIn += 1;
    }

    /// @dev Performs chained getAmountOut calculations on any number of pools
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        uint256 pathLengthSpecific = path.length;
        if (pathLengthSpecific <= 1)
            revert SimswapLibrary_INVALID_PATH(path);
        amounts = new uint256[](pathLengthSpecific);
        amounts[0] = amountIn;
        uint256 iUp;
        unchecked {
            pathLengthSpecific -= 2;
            for (uint256 i; i <= pathLengthSpecific;) {
                ++iUp;
                (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[iUp]);
                amounts[iUp] = getAmountOut(amounts[i], reserveIn, reserveOut);
                i = iUp;
            }   
        }
    }

    /// @dev Performs chained getAmountIn calculations on any number of pools
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) internal view returns (uint256[] memory amounts) {
        uint256 pathLengthSpecific = path.length;
        if (pathLengthSpecific <= 1)
            revert SimswapLibrary_INVALID_PATH(path);
        amounts = new uint256[](pathLengthSpecific);
        unchecked {
            pathLengthSpecific -= 1;
        }
        uint256 iDown = pathLengthSpecific;
        unchecked {
            amounts[pathLengthSpecific] = amountOut;
            for (uint256 i = pathLengthSpecific; i != 0;) {
                --iDown;
                (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[iDown], path[i]);
                amounts[iDown] = getAmountIn(amounts[i], reserveIn, reserveOut);
                i = iDown;
            }
        }
    }
}