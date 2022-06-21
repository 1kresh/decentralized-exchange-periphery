// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import '../interfaces/IERC20Minimal.sol';

/// @title TransferHelper
/// @notice Contains helper methods for interacting with ERC20 tokens that do not consistently return true/false
library TransferHelper {
    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Calls transfer on token contract, errors with TF if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param recipient The recipient of the transfer
    /// @param amount The amount of the transfer
    function safeTransfer(
        address token,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, recipient, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TF');
    }

    /// @notice Transfers tokens from spender to a recipient
    /// @dev Calls transfer on token contract, errors with TF if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param from The spender of the transfer
    /// @param recipient The recipient of the transfer
    /// @param amount The amount of the transfer
    function safeTransferFrom(
        address token,
        address spender,
        address recipient,
        uint256 amount
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, spender, recipient, amount));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TFF');
    }

    /// @notice Transfers ETH from msg.sender to a recipient
    /// @dev Calls transfer on token contract, errors with TF if transfer fails
    /// @param recipient The recipient of the transfer
    /// @param amount The amount of the transfer
    function safeTransferETH(
        address recipient,
        uint256 amount
    ) internal {
        bool success = recipient.send(amount);
        require(success, 'TFE');
    }
}