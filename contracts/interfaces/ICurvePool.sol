// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICurvePool {
    function add_liquidity(uint256[] memory _amounts, uint256 _min_mint_amount) external;
}
