// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;

import "https://github.com/aave/protocol-v2/blob/ice/mainnet-deployment-03-12-2020/contracts/interfaces/ILendingPool.sol";
import "https://github.com/aave/protocol-v2/blob/ice/mainnet-deployment-03-12-2020/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import "https://github.com/aave/protocol-v2/blob/ice/mainnet-deployment-03-12-2020/contracts/protocol/libraries/types/DataTypes.sol";
import "https://github.com/aave/protocol-v2/blob/ice/mainnet-deployment-03-12-2020/contracts/interfaces/IAToken.sol";
import "./ERC20.sol";

contract StrongHands
{
    struct user
    {
        uint value;
        uint lockTime;
        bool flag;
    }
    
    mapping( address => user) allUsers;
    address [] private  usernames;
    address private manager;
    uint private immutable timeToBeLocked;
    ERC20 private immutable weth;
    ILendingPoolAddressesProvider private provider;
    ILendingPool private lending_pool;
    uint public depositedAmount;
    uint constant percision = 10000;

    constructor(uint lockTime)  
    {
        manager = msg.sender;
        timeToBeLocked = lockTime;
        weth = ERC20(0xd0A1E359811322d97991E03f863a0C30C2cF029C);
        provider = ILendingPoolAddressesProvider(address(0x88757f2f99175387aB4C6a4b3067c77A695b0349));
        lending_pool = ILendingPool(provider.getLendingPool());
        depositedAmount = 0;
        weth.approve(address(lending_pool), type(uint256).max);
    } 

    /**
        * Function that returns deposited amount of ETH for the user
    **/
    function getUserData() public view returns(uint v)
    {
        return allUsers[msg.sender].value;
    }

    /**
        * Function that sends ETH to AAVE V2 Lending Pool 
    **/
    function sendEther() public payable
    {
        require(msg.value > 0, "You must send some tokens...");
        allUsers[msg.sender].value += msg.value;
        allUsers[msg.sender].lockTime = block.timestamp;
        if(allUsers[msg.sender].flag == false)
        {
            allUsers[msg.sender].flag = true;
            usernames.push(msg.sender);
        }
       depositAave(msg.value);
       depositedAmount +=msg.value;
    }

    /**
        * A function that returns ETH from AAVE Lending Pool to the user and distributes a portion
        *  to other usersif the user has withdrawn ETH before a defined time period

    **/
    function getMyEther() public payable
    {
        uint currentMoneyOfUser = allUsers[msg.sender].value;
        require(currentMoneyOfUser > 0, "User don't have deposited ETH");
        uint lockTimeOfUser = allUsers[msg.sender].lockTime;
        uint currentBlockTime = block.timestamp;
        if(currentBlockTime > lockTimeOfUser + timeToBeLocked )  
        { 
            /**
                *This part of the code returns full value 
                *of ETH to the user because lock time has expired
            **/    
            allUsers[msg.sender].value = 0;
            depositedAmount = depositedAmount - currentMoneyOfUser;
            withdrawWETH(currentMoneyOfUser);
            (bool succ, ) = msg.sender.call{value : currentMoneyOfUser}("");
            require(succ, "Transfer failed.");
            return;
        } 
        /**
            *This part of the code is giving penalty to the user due to witdrawing coins before locktime runs out
            *by taking some amount of his ETH coins and giving them to the other users proportional to how much Ether 
            *they have deposited on the contract.
        **/  
        uint spentTime = ((currentBlockTime-lockTimeOfUser)*100)/(timeToBeLocked) ; //passed time in percentage
        uint toBePayed = (currentMoneyOfUser * ((100 - spentTime)/2)) /100; //penalty for the user
        uint x = toBePayed; //x returns 1 or 2 WEI back to the user in the end, because we can't take exactly 100% of penalty. Takes 99.99%
        uint money = depositedAmount -  currentMoneyOfUser; //deposited amount of ethers, without amount of the msg.sender
        address [] memory  _usernames = usernames;
        uint perc; 
        uint toPay;
        for (uint i = 0; i < _usernames.length; i++)
        {
            uint currentMappedUserValue = allUsers[_usernames[i]].value;
            if(_usernames[i]!=msg.sender &&  currentMappedUserValue > 0)
            {
                /**
                    *Calculating the proportional amount of all users and sharing the penalty of msg.sender
                **/
                perc = (currentMappedUserValue * percision) / money; 
                toPay = (toBePayed*perc)/(percision);
                x = x - toPay;
                allUsers[_usernames[i]].value +=toPay;
            }
        }

        currentMoneyOfUser = currentMoneyOfUser - toBePayed + x ;
        depositedAmount = depositedAmount - currentMoneyOfUser;
        allUsers[msg.sender].value = 0;
        withdrawWETH(currentMoneyOfUser);
        (bool success, ) = msg.sender.call{value : currentMoneyOfUser}("");
        require(success, "Transfer failed.");
        allUsers[msg.sender].value = 0;

    }

    /**
        *A function that sends passive income to the owner of the contract.
        *manager is the owner
    **/
    function sendKajmakToOwner() public payable onlyOwner
    {
          uint income = getCurrentBalanceOfATokens() - depositedAmount;
          require(income > 0);
          withdrawWETH(income);
          (bool success, ) = msg.sender.call{value : income}("");
          require(success, "Transfer failed.");
    }

    modifier onlyOwner 
    {
        require(msg.sender == manager , "Only owner can call this function");
        _;
    }
    /**
        *Deposit val amount of ETH to WETH address
    **/
    function depositETH(uint val) internal 
    {
        weth.deposit{value : val}();
    }

    /**
        *Returns current balance of AETH tokens for this contract
    **/
    function getCurrentBalanceOfATokens() public view returns(uint a)
    {
        IAToken aWETH = IAToken(lending_pool.getReserveData(address(weth)).aTokenAddress);
        return aWETH.balanceOf(address(this));
    }
    /**
        *Lending Pool return val tokens to WETH, and they are then 
        *converted to ETH and assigned to balance of this contract 
    **/
      function withdrawWETH(uint val) internal 
      {
        lending_pool.withdraw(address(weth),val, address(this));
        bool torf = weth.approve(address(this) , val);
        if(torf)
            weth.withdraw(val);
    }
    /**
        *Depositing val WETH tokens to AAVE V2 Lending Pool
    **/
    function depositAave(uint val) internal 
    {
      require(val > 0);
      depositETH(val);
      lending_pool.deposit(address(weth),val, address(this), 0);
    }

    receive() external payable {}
    fallback() external payable {}
   
}