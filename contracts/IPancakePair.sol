// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IPancakePair {
    function sync() external;
    function getReserves() external view returns (uint112, uint112, uint32);
}