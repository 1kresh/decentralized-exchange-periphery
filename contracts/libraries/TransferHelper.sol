// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

/// @title TransferHelper
/// @notice Contains helper methods for interacting with ERC20 tokens that do not consistently return true/false
library TransferHelper {
    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param recipient The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(
        address recipient,
        uint256 value
    ) internal {
        payable(recipient).transfer(value);
    }
}