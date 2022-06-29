// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

error DeadlineChecker_EXPIRED(uint256 cur_timestamp, uint256 deadline);

abstract contract DeadlineChecker {
    function checkDeadline(uint256 deadline) private view {
        uint256 cur_timestamp = block.timestamp;
        if (cur_timestamp > deadline)
            revert DeadlineChecker_EXPIRED(cur_timestamp, deadline);
    }

    modifier deadlineChecker(uint256 deadline) {
        checkDeadline(deadline);
        _;
    }
}
