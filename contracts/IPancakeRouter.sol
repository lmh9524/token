// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice PancakeSwap V2 Router interface (精简版，够我们 addLiquidity + swapExactTokensForTokens 使用)
interface IPancakeRouter {
    /// @notice 返回工厂合约地址
    function factory() external pure returns (address);

    /// @notice 添加流动性
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);

    /// @notice 用精确输入数量兑换代币（我们买/卖 VEILX 用这个）
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /// @notice 估算给定输入数量能换出多少
    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    /// @notice 估算要得到指定输出，需要输入多少
    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}