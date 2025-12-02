// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable@5.4.0/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.4.0/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable@5.4.0/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts@5.4.0/token/ERC20/IERC20.sol";

contract StakePoolTest is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    modifier onlyAdmin {
        require(isAdmin[msg.sender], "err admin role");
        _;
    }

    mapping(address => bool) public isAdmin;
    address public foundation;      // 基金会地址
    uint256 public USDTWeight;      // usdt+veil 入单时 USDT比重  单位 / 10000
    uint256 public BuyVEILWeight;   // 该值等于0时，不会触发买币  单位 / 100

    // 这三个从 immutable + 硬编码，改成存储变量，由 initialize 传入
    ISwapRouter public SwapRouter;
    IERC20     public USDTToken;
    IVEILToken public VEILToken;

    event Reward(uint256 id, address to, address payer, address token, uint256 amount);
    event Stake(address user, uint256 amount, uint256 usdtAmount, uint256 veilAmount);

    // 入单
    function stake(uint256 amount) external {
        require(amount % 100e18 == 0, "err stake amount");
        if (USDTWeight == 10000) { // 纯USDT入单
            if (BuyVEILWeight == 0) {
                USDTToken.transferFrom(msg.sender, foundation, amount);
                emit Stake(msg.sender, amount, amount, 0);
            } else {
                USDTToken.transferFrom(msg.sender, address(this), amount);

                uint256 buyAmount = amount * BuyVEILWeight / 100;
                address[] memory path = new address[](2);
                path[0] = address(USDTToken);
                path[1] = address(VEILToken);
                uint256[] memory amounts = SwapRouter.swapExactTokensForTokens(
                    buyAmount,
                    0,
                    path,
                    foundation,
                    block.timestamp
                );

                USDTToken.transfer(foundation, amount - buyAmount);
                emit Stake(msg.sender, amount, amount - buyAmount, amounts[1]);
            }

        } else { // USDT+VEIL 入单
            uint256 uAmount = amount * USDTWeight / 10000;
            USDTToken.transferFrom(msg.sender, foundation, uAmount);
            address[] memory path = new address[](2);
            path[0] = address(USDTToken);
            path[1] = address(VEILToken);
            uint256[] memory amounts = SwapRouter.getAmountsIn(amount - uAmount, path);
            VEILToken.transferFrom(msg.sender, foundation, amounts[1]);
            emit Stake(msg.sender, amount, uAmount, amounts[1]);
        }
    }

    /**
        批量领取收益 
            orderId 唯一订单ID ，为了确保业务系统数据一致性;
            users   需要发放的地址
            payers  付款地址，从哪个地址上划拨资金
            tokens  付款代币
            amounts 付款金额
    */
    function multiSendReward(
        uint256 orderId,
        address[] memory users,
        address[] memory payers,
        address[] memory tokens,
        uint256[] memory amounts
    ) external onlyAdmin {
        require(users.length == payers.length, "err u p len");
        require(users.length == tokens.length, "err u t len");
        require(users.length == amounts.length, "err u a len");
        for (uint i; i < users.length;) {
            if (payers[i] == address(this) || payers[i] == address(0)) {
                if (tokens[i] == address(VEILToken)) {
                    VEILToken.stakeTransfer(users[i], amounts[i]);
                } else {
                    IERC20(tokens[i]).transfer(users[i], amounts[i]);
                }
            } else {
                if (tokens[i] == address(VEILToken)) {
                    VEILToken.transferFrom(payers[i], address(this), amounts[i]);
                    VEILToken.stakeTransfer(users[i], amounts[i]);
                } else {
                    IERC20(tokens[i]).transferFrom(payers[i], users[i], amounts[i]);
                }
            }

            unchecked {
                i++;
            }

            emit Reward(orderId, users[i], payers[i], tokens[i], amounts[i]);
        }
    }

    function setAdmin(address user, bool flag) external onlyOwner {
        isAdmin[user] = flag;
    }

    function setFoundation(address user) external onlyOwner {
        foundation = user;
    }

    // 初始化时注入 Router / USDT / VEIL 地址
    function initialize(
        address initialOwner,chrome-extension://pbpjkcldjiffchgbbndmhojiacbgflha/static/images/icon-32.png
        address router,
        address usdt,
        address veil
    ) public initializer {
        __Ownable_init(initialOwner);
        SwapRouter = ISwapRouter(router);
        USDTToken  = IERC20(usdt);
        VEILToken  = IVEILToken(veil);chrome-extension://pbpjkcldjiffchgbbndmhojiacbgflha/static/images/icon-32.png

        // 给 Router 授权 USDT
        USDTToken.approve(router, type(uint).max);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

}

interface ISwapRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] calldata path
    ) external view returns (uint[] memory amounts);

    function getAmountsIn(
        uint amountOut,
        address[] calldata path
    ) external view returns (uint[] memory amounts);
}

interface IVEILToken is IERC20 {
    function stakeTransfer(address to, uint256 amount) external;
}