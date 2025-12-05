// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts@5.4.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@5.4.0/access/Ownable.sol";

contract VeilXToken is ERC20, Ownable {
    ISwapRouter immutable public SwapRouter=ISwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    AutoSwap immutable autoSwap = new AutoSwap();

    address immutable public USDTToken=0x55d398326f99059fF775485246999027B3197955;
    address public immutable basePair;
    //基金会  1%买税收款地址
    address public foundation ;
    //实验室  1%卖税收款地址
    address public labAddress ;
    //市场    5%盈利税收款地址
    address public marketAddress ;
    
    mapping(address => uint256) public tOwnedU;
    mapping(address => bool) public isWL;

    uint256 public buyFee=100;
    uint256 public sellFee=100;
    uint256 public profitFee=500;
    uint256 public sellBurnRate=10000;
    address public stakeAddress;
    uint256 public burnLimit=279000000e18;
    bool public launchBuy;
    bool public launchSell;
    bool inSwap;

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier onlyStake() {
        require(msg.sender == stakeAddress, "VeilX: onlyStake");
        _;
    }

    constructor(
        address _foundation,
        address _lab,
        address _market
    ) ERC20("VEILX", "VEILX") Ownable(msg.sender) {

        foundation=_foundation;
        labAddress=_lab;
        marketAddress=_market;
        isWL[_foundation] = true;
        isWL[_lab] = true;
        isWL[address(autoSwap)] = true;

        _mint(labAddress, 310000000e18);

        basePair = ISwapFactory(SwapRouter.factory()).createPair(
            address(this),
            USDTToken
        );
        _approve(address(this), address(SwapRouter), type(uint).max);
        IERC20(USDTToken).approve(address(SwapRouter), type(uint).max);
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (inSwap || isWL[from] || isWL[to]) {
            return super._update(from, to, amount);
        }

        if (basePair == from) {
            require(launchBuy, "un launch buy");

            // buy
            uint256 pairBalance = balanceOf(basePair);
            require(amount <= pairBalance / 10, "VeilX: max cap buy"); 
            address[] memory buyPath = new address[](2);
            buyPath[0] = USDTToken;
            buyPath[1] = address(this);
            
            uint256 amountUBuy = SwapRouter.getAmountsIn(amount, buyPath)[0];
            tOwnedU[to] = tOwnedU[to] + amountUBuy;
            uint256 buyFees = amount * buyFee / 10000;

            super._update(from, address(this), buyFees);
            super._update(from, to, amount - buyFees);
        } else if (basePair == to) {
            require(launchSell, "un launch sell");
            //sell
            uint256 pairBalance = balanceOf(basePair);
            require(amount <= pairBalance / 10, "VeilX: max cap sell");
            uint256 sellFeesAmount = amount * sellFee / 10000;
            address[] memory buyPath = new address[](2);
            
            buyPath[0] = USDTToken;
            buyPath[1] = address(this);

            uint256 amountUOut = SwapRouter.getAmountsOut(
                amount - sellFeesAmount,
                buyPath
            )[1];

            uint256 profitFeesAmount;
            if (tOwnedU[from] >= amountUOut) {
                unchecked {
                    tOwnedU[from] = tOwnedU[from] - amountUOut;
                }
            } else if (tOwnedU[from] > 0 && tOwnedU[from] < amountUOut) {
                uint256 profitU = amountUOut - tOwnedU[from];
                address[] memory sellPath = new address[](2);
                sellPath[0] = USDTToken;
                sellPath[1] = address(this);
                uint256 profitThis = SwapRouter.getAmountsOut(profitU, sellPath)[1];
                profitFeesAmount = (profitThis * profitFee) / 10000;
                tOwnedU[from] = 0;
            } else {
                profitFeesAmount = (amount * profitFee) / 10000;
                tOwnedU[from] = 0;
            }

            uint256 totalFees = sellFeesAmount + profitFeesAmount;

            burnPair(amount);

            super._update(from, address(this), totalFees);
            
            processFees(profitFeesAmount);

            super._update(from, to, amount - totalFees);
        } else {
            super._update(from, to, amount);
        }
    }

    function burnPair(uint256 amount) internal {
        if((profitFee>99||sellFee>99)&&sellBurnRate>0&&balanceOf(address(0xDead))<burnLimit){
            uint256 burnAmount=amount*sellBurnRate/10000;
            super._transfer(basePair, address(0xDead), burnAmount);
            ISwapPair(basePair).sync();
        }
    }

    function processFees(uint256 profitFeesAmount) internal swapping {
        uint256 totalAmount = balanceOf(address(this));
        if (totalAmount == 0) {
            return;
        }

        uint256 sellAmount = totalAmount - profitFeesAmount;

        uint256 profitRate = (profitFeesAmount * 1e18) / sellAmount;

        address[] memory sellPath = new address[](2);
        sellPath[0] = address(this);
        sellPath[1] = USDTToken;

        SwapRouter.swapExactTokensForTokens(
            sellAmount,
            0,
            sellPath,
            address(autoSwap),
            block.timestamp
        )[1];

        autoSwap.withdraw(
            IERC20(USDTToken),
            address(this),
            IERC20(USDTToken).balanceOf(address(autoSwap))
        );

        uint256 usdtAmount = IERC20(USDTToken).balanceOf(address(this));

        if (profitRate > 0) {
            uint256 profitUSDTAmount = (usdtAmount * profitRate) / 1e18;
            usdtAmount -= profitUSDTAmount;
            IERC20(USDTToken).transfer(marketAddress,profitUSDTAmount);
        }
        uint256 halfAmount=usdtAmount/2;
        IERC20(USDTToken).transfer(foundation, halfAmount);
        IERC20(USDTToken).transfer(labAddress, halfAmount);
    }

    function recycle(uint256 amount) external onlyStake {
        uint256 maxBurn = balanceOf(basePair) / 3;
        uint256 burn_maount = amount >= maxBurn ? maxBurn : amount;
        super._update(basePair, stakeAddress, burn_maount);
        ISwapPair(basePair).sync();
    }

    function stakeTransfer(address to,uint256 amount) external onlyStake{
        
        address[] memory buyPath = new address[](2);
        buyPath[0] = address(this);
        buyPath[1] = USDTToken;

        uint256 amountUBuy = SwapRouter.getAmountsIn(amount, buyPath)[1];
        tOwnedU[to] = tOwnedU[to] + amountUBuy;

        super._update(stakeAddress,to,amount);
    }

    //设置税率  _buy 买税，_sell 卖税  _profitFee 盈利税
    function setFee(uint256 _buy,uint256 _sell,uint256 _profitFee) external onlyOwner{
        buyFee=_buy;
        sellFee=_sell;
        profitFee=_profitFee;
    }

    //批量设置白名单
    function multisetWL(address[] memory users, bool flag) external onlyOwner {
        for (uint i; i < users.length; ) {
            isWL[users[i]] = flag;
            unchecked {
                i++;
            }
        }
    }

    //设置销毁比例
    function setBurnLimit(uint256 limit) external onlyOwner{
        burnLimit=limit;
    }

    //设置Stake地址
    function setStakeAddress(address stake) external onlyOwner {
        if (stakeAddress != address(0)) {
            isWL[stakeAddress] = false;
        }
        stakeAddress = stake;
        isWL[stakeAddress] = true;
    }

    //启动交易 _buy true 启动购买  _sell 启动卖出
    function launch(bool _buy,bool _sell) external onlyOwner {
        launchBuy = _buy;
        launchSell=_sell;
    }

    //修改地址
    function setAddress(address _foundation,address _lab,address _market) external onlyOwner{
        foundation=_foundation;
        labAddress=_lab;
        marketAddress=_market;
    }
}

contract AutoSwap is Ownable {
    constructor() Ownable(msg.sender) {}

    function withdraw(
        IERC20 token,
        address to,
        uint256 amount
    ) external onlyOwner {
        token.transfer(to, amount);
    }
}

interface ISwapPair {
    function sync() external;
}

interface ISwapRouter {
    function factory() external pure returns (address);

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

interface ISwapFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}
