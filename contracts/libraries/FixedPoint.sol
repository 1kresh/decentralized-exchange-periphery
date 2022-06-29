// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.15;

import { FullMath } from './FullMath.sol';

/// range: [0, 2**112 - 1]
/// resolution: 1 / 2**112
struct uq112x112 {
    uint224 _x;
}

// range: [0, 2**144 - 1]
// resolution: 1 / 2**112
struct uq144x112 {
    uint256 _x;
}

error FixedPoint_fraction_division_by_zero();
error FixedPoint_fraction_overflow(uint256 result);
error FixedPoint_mul_overflow(uq112x112 self, uint256 y);

// a library for handling binary fixed point numbers (https://en.wikipedia.org/wiki/Q_(number_format))
library FixedPoint {
    uint8 public constant RESOLUTION = 112;
    uint256 public constant Q112 = 0x10000000000000000000000000000; // 2**112

    /// @dev Decode a UQ144x112 into a uint144 by truncating after the radix point
    function decode144(uq144x112 memory self) internal pure returns (uint144) {
        return uint144(self._x >> RESOLUTION);
    }

    /// @dev Multiply a UQ112x112 by a uint, returning a UQ144x112
    /// reverts on overflow
    function mul(uq112x112 memory self, uint256 y) internal pure returns (uq144x112 memory result) {
        uint256 z = 0;
        unchecked {
            if (y != 0 && (z = self._x * y) / y != self._x)
                revert FixedPoint_mul_overflow(self, y);
        }
        result._x = z;
    }

    /// @dev Return a UQ112x112 which represents the ratio of the numerator to the denominator
    /// can be lossy
    function fraction(uint256 numerator, uint256 denominator) internal pure returns (uq112x112 memory _fraction) {
        if (denominator == 0)
            revert FixedPoint_fraction_division_by_zero();
        if (numerator == 0) {
            _fraction._x = 0;
        } else {
            uint256 result;
            if (numerator <= type(uint144).max) {
                result = (numerator << RESOLUTION) / denominator;
            } else {
                result = FullMath.mulDiv(numerator, Q112, denominator);
            }
            if (result > type(uint224).max)
                revert FixedPoint_fraction_overflow(result);
            _fraction._x = uint224(result);
        }
    }
}