// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import { Multicall } from '@openzeppelin/contracts/utils/Multicall.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { ISimswapFactory } from '@simswap/core/contracts/interfaces/ISimswapFactory.sol';
import { ISimswapPool } from '@simswap/core/contracts/interfaces/ISimswapPool.sol';
import { ISimswapERC20 } from '@simswap/core/contracts/interfaces/ISimswapERC20.sol';

import { ISimswapRouter } from './interfaces/ISimswapRouter.sol';
import { IWETH9 } from './interfaces/IWETH9.sol';

import { DeadlineChecker } from './modifiers/DeadlineChecker.sol';

import { SimswapLibrary } from './libraries/SimswapLibrary.sol';
import { TransferHelper } from './libraries/TransferHelper.sol';

contract SimswapRouter is ISimswapRouter, Multicall, DeadlineChecker {
    using SafeERC20 for IERC20;

    address public immutable override factory;
    address public immutable override WETH9;

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }

    receive() external payable {
        if (msg.sender != WETH9) revert SimswapRouter_Not_WETH9();
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        ISimswapFactory _factory = ISimswapFactory(factory);
        // create the pool if it doesn't exist yet
        if (_factory.getPool(tokenA, tokenB) == address(0)) {
            _factory.createPool(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = SimswapLibrary.getReserves(
            factory,
            tokenA,
            tokenB
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = SimswapLibrary.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin)
                    revert SimswapRouter_INSUFFICIENT_B_AMOUNT(
                        amountBMin,
                        amountBOptimal,
                        amountBDesired
                    );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = SimswapLibrary.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                require(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin)
                    revert SimswapRouter_INSUFFICIENT_A_AMOUNT(
                        amountAMin,
                        amountAOptimal,
                        amountADesired
                    );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        deadlineChecker(deadline)
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        (amountA, amountB) = _addLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );
        address pool = SimswapLibrary.poolFor(factory, tokenA, tokenB);
        // init because of stack too deep error
        IERC20 _token = IERC20(tokenA);
        _token.safeTransferFrom(msg.sender, pool, amountA);
        _token = IERC20(tokenB);
        _token.safeTransferFrom(msg.sender, pool, amountB);
        liquidity = ISimswapPool(pool).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        deadlineChecker(deadline)
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        )
    {
        address _WETH9 = WETH9;
        (amountToken, amountETH) = _addLiquidity(
            token,
            _WETH9,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pool = SimswapLibrary.poolFor(factory, token, _WETH9);
        IERC20(token).safeTransferFrom(msg.sender, pool, amountToken);
        IWETH9 _IWETH9 = IWETH9(_WETH9);
        _IWETH9.deposit{ value: amountETH }();
        require(_IWETH9.transfer(pool, amountETH) == true);
        liquidity = ISimswapPool(pool).mint(to);
        // refund dust eth, if any
        unchecked {
            if (msg.value > amountETH)
                TransferHelper.safeTransferETH(
                    msg.sender,
                    msg.value - amountETH
                );
        }
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        address pool = SimswapLibrary.poolFor(factory, tokenA, tokenB);
        ISimswapERC20(pool).transferFrom(msg.sender, pool, liquidity); // send liquidity to pool
        (uint256 amount0, uint256 amount1) = ISimswapPool(pool).burn(to);
        (address token0, ) = SimswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
        if (amountA < amountAMin)
            revert SimswapRouter_INSUFFICIENT_A_AMOUNT(amountAMin, amountA, 0);
        if (amountB < amountBMin)
            revert SimswapRouter_INSUFFICIENT_B_AMOUNT(amountBMin, amountB, 0);
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256 amountToken, uint256 amountETH)
    {
        address _WETH9 = WETH9;
        (amountToken, amountETH) = removeLiquidity(
            token,
            _WETH9,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        IERC20(token).safeTransfer(to, amountToken);
        IWETH9(_WETH9).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        ISimswapERC20(SimswapLibrary.poolFor(factory, tokenA, tokenB)).permit(
            msg.sender,
            address(this),
            approveMax ? type(uint256).max : liquidity,
            deadline,
            v,
            r,
            s
        );
        (amountA, amountB) = removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountToken, uint256 amountETH)
    {
        ISimswapERC20(SimswapLibrary.poolFor(factory, token, WETH9)).permit(
            msg.sender,
            address(this),
            approveMax ? type(uint256).max : liquidity,
            deadline,
            v,
            r,
            s
        );
        (amountToken, amountETH) = removeLiquidityETH(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256 amountETH)
    {
        address _WETH9 = WETH9;
        (, amountETH) = removeLiquidity(
            token,
            _WETH9,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        IERC20(token).safeTransfer(
            to,
            SimswapLibrary.balance(token, address(this))
        );
        IWETH9(_WETH9).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external virtual override returns (uint256 amountETH) {
        ISimswapERC20(SimswapLibrary.poolFor(factory, token, WETH9)).permit(
            msg.sender,
            address(this),
            approveMax ? type(uint256).max : liquidity,
            deadline,
            v,
            r,
            s
        );
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token,
            liquidity,
            amountTokenMin,
            amountETHMin,
            to,
            deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pool
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        uint256 pathLengthReduced;
        unchecked {
            pathLengthReduced = path.length - 2;
        }
        uint256 i;
        for (i; i <= pathLengthReduced; ) {
            address input = path[i];
            // increasing here to optimize future calculations
            unchecked {
                ++i;
            }
            address output = path[i];
            (address token0, ) = SimswapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to;
            unchecked {
                to = i <= pathLengthReduced
                    ? SimswapLibrary.poolFor(factory, output, path[i + 1])
                    : _to;
            }
            ISimswapPool(SimswapLibrary.poolFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SimswapLibrary.getAmountsOut(factory, amountIn, path);
        unchecked {
            if (amounts[amounts.length - 1] >= amountOutMin)
                revert SimswapRouter_INSUFFICIENT_OUTPUT_AMOUNT(
                    amountOutMin,
                    amounts
                );
        }
        address path0 = path[0];
        IERC20(path0).safeTransferFrom(
            msg.sender,
            SimswapLibrary.poolFor(factory, path0, path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SimswapLibrary.getAmountsIn(factory, amountOut, path);
        uint256 amounts0 = amounts[0];
        if (amounts0 > amountInMax)
            revert SimswapRouter_EXCESSIVE_INPUT_AMOUNT(amountInMax, amounts);
        address path0 = path[0];
        IERC20(path0).safeTransferFrom(
            msg.sender,
            SimswapLibrary.poolFor(factory, path0, path[1]),
            amounts0
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SimswapLibrary.getAmountsOut(factory, msg.value, path);
        address _WETH9 = WETH9;
        if (path[0] != _WETH9) revert SimswapRouter_INVALID_PATH(path);
        unchecked {
            if (amounts[amounts.length - 1] < amountOutMin)
                revert SimswapRouter_INSUFFICIENT_OUTPUT_AMOUNT(
                    amountOutMin,
                    amounts
                );
        }

        IWETH9 _IWETH9 = IWETH9(_WETH9);
        _IWETH9.deposit{ value: amounts[0] }();
        require(
            _IWETH9.transfer(
                SimswapLibrary.poolFor(factory, path[0], path[1]),
                amounts[0]
            ) == true
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SimswapLibrary.getAmountsIn(factory, amountOut, path);
        address _WETH9 = WETH9;
        unchecked {
            if (path[path.length - 1] != _WETH9)
                revert SimswapRouter_INVALID_PATH(path);
        }

        uint256 amountsNth = amounts[0];
        if (amountsNth > amountInMax)
            revert SimswapRouter_EXCESSIVE_INPUT_AMOUNT(amountInMax, amounts);

        address path0 = path[0];
        IERC20(path0).safeTransferFrom(
            msg.sender,
            SimswapLibrary.poolFor(factory, path0, path[1]),
            amountsNth
        );
        _swap(amounts, path, address(this));

        unchecked {
            amountsNth = amounts[amounts.length - 1];
        }
        IWETH9(_WETH9).withdraw(amountsNth);
        TransferHelper.safeTransferETH(to, amountsNth);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SimswapLibrary.getAmountsOut(factory, amountIn, path);
        address _WETH9 = WETH9;
        unchecked {
            if (path[path.length - 1] != _WETH9)
                revert SimswapRouter_INVALID_PATH(path);
        }
        uint256 amountsLast;
        unchecked {
            amountsLast = amounts[amounts.length - 1];
        }
        if (amountsLast < amountOutMin)
            revert SimswapRouter_INSUFFICIENT_OUTPUT_AMOUNT(
                amountOutMin,
                amounts
            );

        address path0 = path[0];
        IERC20(path0).safeTransferFrom(
            msg.sender,
            SimswapLibrary.poolFor(factory, path0, path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));

        IWETH9(_WETH9).withdraw(amountsLast);
        TransferHelper.safeTransferETH(to, amountsLast);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        deadlineChecker(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = SimswapLibrary.getAmountsIn(factory, amountOut, path);
        address _WETH9 = WETH9;
        if (path[0] != _WETH9) revert SimswapRouter_INVALID_PATH(path);
        uint256 amounts0 = amounts[0];
        uint256 msgValue = msg.value;
        if (amounts0 > msgValue)
            revert SimswapRouter_EXCESSIVE_INPUT_AMOUNT(0, amounts);

        IWETH9 _IWETH9 = IWETH9(WETH9);
        _IWETH9.deposit{ value: amounts0 }();
        require(
            _IWETH9.transfer(
                SimswapLibrary.poolFor(factory, path[0], path[1]),
                amounts0
            ) == true
        );
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msgValue > amounts0)
            TransferHelper.safeTransferETH(msg.sender, msgValue - amounts0);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pool
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path,
        address _to
    ) internal virtual {
        uint256 pathLengthReduced;
        unchecked {
            pathLengthReduced = path.length - 2;
        }
        uint256 i;
        for (i; i <= pathLengthReduced; ) {
            address input = path[i];
            // increasing here to optimize future calculations
            unchecked {
                ++i;
            }
            address output = path[i];
            (address token0, ) = SimswapLibrary.sortTokens(input, output);
            ISimswapPool pool = ISimswapPool(
                SimswapLibrary.poolFor(factory, input, output)
            );
            uint256 amount0Out;
            uint256 amount1Out;
            {
                (uint256 reserve0, uint256 reserve1, ) = pool.slot0();
                (reserve0, reserve1) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                uint256 amountOutput = SimswapLibrary.getAmountOut(
                    SimswapLibrary.balance(input, address(pool)) - reserve0,
                    reserve0,
                    reserve1
                );
                (amount0Out, amount1Out) = input == token0
                    ? (uint256(0), amountOutput)
                    : (amountOutput, uint256(0));
            }

            address to;
            unchecked {
                to = i <= pathLengthReduced
                    ? SimswapLibrary.poolFor(factory, output, path[i + 1])
                    : _to;
            }

            pool.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override deadlineChecker(deadline) {
        uint256 pathLength = path.length;
        if (pathLength <= 1) revert SimswapRouter_INVALID_PATH(path);

        address pathNth = path[0];
        IERC20(pathNth).safeTransferFrom(
            msg.sender,
            SimswapLibrary.poolFor(factory, pathNth, path[1]),
            amountIn
        );

        unchecked {
            pathNth = path[pathLength - 1];
        }
        uint256 balanceBefore = SimswapLibrary.balance(pathNth, to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (SimswapLibrary.balance(pathNth, to) - balanceBefore < amountOutMin)
            revert SimswapRouter_INSUFFICIENT_OUTPUT_AMOUNT(
                amountOutMin,
                new uint256[](0)
            );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override deadlineChecker(deadline) {
        uint256 pathLength = path.length;
        address _WETH9 = WETH9;
        if (pathLength <= 1 || path[0] != _WETH9)
            revert SimswapRouter_INVALID_PATH(path);

        uint256 amountIn = msg.value;
        IWETH9 _IWETH9 = IWETH9(_WETH9);
        _IWETH9.deposit{ value: amountIn }();
        require(
            _IWETH9.transfer(
                SimswapLibrary.poolFor(factory, path[0], path[1]),
                amountIn
            ) == true
        );

        address pathLast;
        unchecked {
            pathLast = path[pathLength - 1];
        }
        uint256 balanceBefore = SimswapLibrary.balance(pathLast, to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (SimswapLibrary.balance(pathLast, to) - balanceBefore < amountOutMin)
            revert SimswapRouter_INSUFFICIENT_OUTPUT_AMOUNT(
                amountOutMin,
                new uint256[](0)
            );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override deadlineChecker(deadline) {
        uint256 pathLength = path.length;
        address _WETH9 = WETH9;
        unchecked {
            if (pathLength <= 1 || path[pathLength - 1] != _WETH9)
                revert SimswapRouter_INVALID_PATH(path);
        }
        address path0 = path[0];
        IERC20(path0).safeTransferFrom(
            msg.sender,
            SimswapLibrary.poolFor(factory, path0, path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));

        uint256 amountOut = SimswapLibrary.balance(_WETH9, address(this));
        if (amountOut < amountOutMin)
            revert SimswapRouter_INSUFFICIENT_OUTPUT_AMOUNT(
                amountOutMin,
                new uint256[](0)
            );
        IWETH9(_WETH9).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return SimswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return SimswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return SimswapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return SimswapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return SimswapLibrary.getAmountsIn(factory, amountOut, path);
    }
}
