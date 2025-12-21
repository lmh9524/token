// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable@5.4.0/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.4.0/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable@5.4.0/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts@5.4.0/token/ERC20/IERC20.sol";

contract StakePool is Initializable, OwnableUpgradeable, UUPSUpgradeable{

    modifier onlyAdmin{
        require(isAdmin[msg.sender],"err admin role");
        _;
    }
    
    mapping(address=>bool) public isAdmin;
    address public foundation;      //基金会地址
    uint256 public USDTWeight;      //usdt+veil 入单时  USDT比重  单位 / 10000
    uint256 public BuyVEILWeight;   //该值等于0时，不会触发买币  单位 / 100
    address public foundation2;     //todo  新增 30%比例
    ISwapRouter immutable SwapRouter=ISwapRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    IERC20 immutable USDTToken=IERC20(0x55d398326f99059fF775485246999027B3197955);

    // 主网 VEILX 代币地址
    IVEILToken immutable VEILToken=IVEILToken(0x9C79B4a12eF8176B6a61142408A54Edf8336b0A6);
    mapping(uint256 orderId=>bool used)public orderIdStatus;	
    event Reward(uint256 id,address to,address payer,address token,uint256 amount);
    event Stake(address user,uint256 amount,uint256 usdtAmount,uint256 veilAmount);

    event Reward2(uint256 id,address to,address payer,uint256 totalAmount,uint256 veilAmount);
    //入单
    function stake(uint256 amount) external {
        require(amount%100e18==0,"err stake amount");
        if(USDTWeight==10000){//纯USDT入单
            if(BuyVEILWeight==0){
                USDTToken.transferFrom(msg.sender,foundation, amount);
                emit Stake(msg.sender,amount,amount,0);
            }else{
                USDTToken.transferFrom(msg.sender,address(this), amount);

                uint256 buyAmount=amount*BuyVEILWeight/100;
                address[] memory path=new address[](2);
                path[0]=address(USDTToken);
                path[1]=address(VEILToken);
                uint256[] memory amounts=SwapRouter.swapExactTokensForTokens(buyAmount, 0, path, foundation, block.timestamp);

                uint256 foundationAmount=amount-buyAmount;
                USDTToken.transfer(foundation, foundationAmount*2/5);
                USDTToken.transfer(foundation2, foundationAmount*3/5);
                emit Stake(msg.sender, amount, amount-buyAmount, amounts[1]);
            }
            
        }else{//USDT+VEIL 入单
            uint256 uAmount=amount*USDTWeight/10000;
            USDTToken.transferFrom(msg.sender,foundation, uAmount);
            address[] memory path=new address[](2);
            path[0]=address(USDTToken);
            path[1]=address(VEILToken);
            uint256[] memory amounts=SwapRouter.getAmountsIn(amount-uAmount, path);
            uint256 foundationAmount=amounts[1];
            VEILToken.transferFrom(msg.sender, foundation, foundationAmount*2/5);
            VEILToken.transferFrom(msg.sender, foundation2, foundationAmount*3/5);
            emit Stake(msg.sender,amount,uAmount,amounts[1]);
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
    function multiSendReward(uint256 orderId,address[] memory users,address[] memory payers,address[] memory tokens,uint256[] memory amounts) external onlyAdmin{
        require(users.length==payers.length,"err u p len");
        require(users.length==tokens.length,"err u t len");
        require(users.length==amounts.length,"err u a len");
        require(!orderIdStatus[orderId],"order id used");
        orderIdStatus[orderId]=true;
        for(uint i;i<users.length;){
            if(payers[i]==address(this)||payers[i]==address(0)){
                if(tokens[i]==address(VEILToken)){
                    VEILToken.stakeTransfer(users[i], amounts[i]);
                }else{
                    IERC20(tokens[i]).transfer(users[i],amounts[i]);
                }
                
            }else{
                if(tokens[i]==address(VEILToken)){
                    VEILToken.transferFrom(payers[i], address(this), amounts[i]);
                    VEILToken.stakeTransfer(users[i], amounts[i]);
                }else{
                    IERC20(tokens[i]).transferFrom(payers[i],users[i],amounts[i]);
                }
                
            }

            emit Reward(orderId,users[i],payers[i],tokens[i],amounts[i]);
            
            unchecked{
                i++;
            }
        }
    }

    /**
        批量领取收益 2
            orderId 唯一订单ID ，为了确保业务系统数据一致性;
            users   需要发放的地址
            payers  付款地址，从哪个地址上划拨资金
            amounts 付款金额(U本位)
    */
    function multiSendReward2(uint256 orderId,address[] memory users,address[] memory payers,uint256[] memory amounts) external onlyAdmin{
        require(users.length==payers.length,"err u p len");
        require(users.length==amounts.length,"err u a len");
        require(!orderIdStatus[orderId],"order id used");
        orderIdStatus[orderId]=true;
        address []memory path=new address[](2);
        path[0]=address(VEILToken);
        path[1]=address(USDTToken);
        for(uint i;i<users.length;){
            uint256 halfAmount=amounts[i]/2;

            uint256 veilAmount=SwapRouter.getAmountsIn(halfAmount, path)[0];

            if(payers[i]!=address(this)||payers[i]!=address(0)){
                VEILToken.transferFrom(payers[i], address(this), veilAmount*2);
            }
            
            VEILToken.transfer(users[i], veilAmount);

            SwapRouter.swapExactTokensForTokens(veilAmount, halfAmount-1, path, users[i], block.timestamp);

            emit Reward2(orderId,users[i],payers[i],amounts[i],veilAmount);

            unchecked{
                i++;
            }
        }
    }


    function setAdmin(address user,bool flag) external onlyOwner{
        isAdmin[user]=flag;
    }

    function setFoundation(address user) external onlyOwner{
        foundation=user;
    }

    function setFoundation2(address user) external onlyOwner{
        foundation2=user;
    }

    function setUSDTWeight(uint256 _weight) external onlyOwner{
        USDTWeight=_weight;
    }

    function setBuyVEILWeight(uint256 _weight) external onlyOwner{
        BuyVEILWeight=_weight;
    }

    function flushApprove() external onlyOwner{
        USDTToken.approve(address(SwapRouter), type(uint).max);
        VEILToken.approve(address(SwapRouter), type(uint).max);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        USDTToken.approve(address(SwapRouter), type(uint).max);
        VEILToken.approve(address(SwapRouter), type(uint).max);
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
      
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IVEILToken is IERC20{
    function stakeTransfer(address to,uint256 amount) external;
}