// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import '@simswap/core/contracts/interfaces/ISimswapFactory.sol';
import '@simswap/core/contracts/interfaces/ISimswapPool.sol';
import '@simswap/core/contracts/interfaces/ISimswapERC20.sol';

import './interfaces/ISimswapRouter.sol';
import './interfaces/IWETH9.sol';

import './libraries/LowGasSafeMath.sol';
import './libraries/SimswapLibrary.sol';
import './libraries/TransferHelper.sol';

contract SimswapRouter is ISimswapRouter {
    using LowGasSafeMath for uint256;

    address public immutable override factory;
    address public immutable override WETH9;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'SimswapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH9) {
        factory = _factory;
        WETH9 = _WETH9;
    }

    receive() external payable {
        assert(msg.sender == WETH9); // only accept ETH via fallback from the WETH9 contract
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
        // create the pool if it doesn't exist yet
        if (ISimswapFactory(factory).getPool(tokenA, tokenB) == address(0)) {
            ISimswapFactory(factory).createPool(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = SimswapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = SimswapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'SimswapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = SimswapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'SimswapRouter: INSUFFICIENT_A_AMOUNT');
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
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pool = SimswapLibrary.poolFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pool, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pool, amountB);
        liquidity = ISimswapPool(pool).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH9,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pool = SimswapLibrary.poolFor(factory, token, WETH9);
        TransferHelper.safeTransferFrom(token, msg.sender, pool, amountToken);
        IWETH9(WETH9).deposit{value: amountETH}();
        assert(IWETH9(WETH9).transfer(pool, amountETH));
        liquidity = ISimswapPool(pool).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
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
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pool = SimswapLibrary.poolFor(factory, tokenA, tokenB);
        ISimswapERC20(pool).transferFrom(msg.sender, pool, liquidity); // send liquidity to pool
        (uint256 amount0, uint256 amount1) = ISimswapPool(pool).burn(to);
        (address token0,) = SimswapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'SimswapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'SimswapRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH9,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH9(WETH9).withdraw(amountETH);
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
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint256 amountA, uint256 amountB) {
        address pool = SimswapLibrary.poolFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        ISimswapERC20(pool).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint256 amountToken, uint256 amountETH) {
        address pool = SimswapLibrary.poolFor(factory, token, WETH9);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        ISimswapERC20(pool).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH9,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, SimswapLibrary.balance(token, address(this)));
        IWETH9(WETH9).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint256 amountETH) {
        address pool = SimswapLibrary.poolFor(factory, token, WETH9);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        ISimswapERC20(pool).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pool
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SimswapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? SimswapLibrary.poolFor(factory, output, path[i + 2]) : _to;
            ISimswapPool(SimswapLibrary.poolFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SimswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'SimswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SimswapLibrary.poolFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SimswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'SimswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SimswapLibrary.poolFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH9, 'SimswapRouter: INVALID_PATH');
        amounts = SimswapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'SimswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH9(WETH9).deposit{value: amounts[0]}();
        assert(IWETH9(WETH9).transfer(SimswapLibrary.poolFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, address[] calldata path, address to, uint256 deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WETH9, 'SimswapRouter: INVALID_PATH');
        amounts = SimswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'SimswapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SimswapLibrary.poolFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH9(WETH9).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[path.length - 1] == WETH9, 'SimswapRouter: INVALID_PATH');
        amounts = SimswapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'SimswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SimswapLibrary.poolFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH9(WETH9).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WETH9, 'SimswapRouter: INVALID_PATH');
        amounts = SimswapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'SimswapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWETH9(WETH9).deposit{value: amounts[0]}();
        assert(IWETH9(WETH9).transfer(SimswapLibrary.poolFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pool
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SimswapLibrary.sortTokens(input, output);
            ISimswapPool pool = ISimswapPool(SimswapLibrary.poolFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            { // scope to avoid stack too deep errors
            (uint256 reserve0, uint256 reserve1,) = pool.slot0();
            (uint256 reserveInput, uint256 reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = SimswapLibrary.balance(input, address(pool)) - reserveInput;
            amountOutput = SimswapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? SimswapLibrary.poolFor(factory, output, path[i + 2]) : _to;
            pool.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SimswapLibrary.poolFor(factory, path[0], path[1]), amountIn
        );
        uint256 balanceBefore = SimswapLibrary.balance(path[path.length - 1], to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            SimswapLibrary.balance(path[path.length - 1], to) - balanceBefore >= amountOutMin,
            'SimswapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WETH9, 'SimswapRouter: INVALID_PATH');
        uint256 amountIn = msg.value;
        IWETH9(WETH9).deposit{value: amountIn}();
        assert(IWETH9(WETH9).transfer(SimswapLibrary.poolFor(factory, path[0], path[1]), amountIn));
        uint256 balanceBefore = SimswapLibrary.balance(path[path.length - 1], to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            SimswapLibrary.balance(path[path.length - 1], to) - balanceBefore >= amountOutMin,
            'SimswapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WETH9, 'SimswapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SimswapLibrary.poolFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = SimswapLibrary.balance(WETH9, address(this));
        require(amountOut >= amountOutMin, 'SimswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH9(WETH9).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure virtual override returns (uint256 amountB) {
        return SimswapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return SimswapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        virtual
        override
        returns (uint256 amountIn)
    {
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