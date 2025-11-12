// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Simple DEX - A Decentralised exchange inspired by Uniswap V1
 * @author Anurag Munda
 * @notice Simple DEX contract that holds reserves of ETH and a single ERC20 token.
 * @dev See Uniswap V1 whitepaper/implementation for economic behavior. Implementations must:
 *      - Swaps ETH <> SIMPLE
 *      - use safe transfers for ERC20 tokens
 *      - Charges a 1% fee on swaps
 *      - When user adds liquidity, they must be given an LP token that represents their share of the pool
 *      - LP must be able to burn their LP tokens to receive back ETH and Token
 *      - Guard against reentrancy when sending ETH
 *      - Correctly compute prices with constant-product formula
 */
contract SimpleDex is ERC20 {
    /*==============================================================
                                ERRORS
    ==============================================================*/
    error SimpleDex__CannotBeZeroAddress();
    error SimpleDex__InsufficientTokenAmount();
    error SimpleDex__TransferFailed();
    error SimpleDex__InvalidAmount();

    /*==============================================================
                            STATE VARIABLES
    ==============================================================*/
    address private tokenAddress;

    /*==============================================================
                                EVENTS
    ==============================================================*/
    event LiquidityAdded(address indexed _user, uint256 _amountOfTokens, uint256 _lpTokensMinted);
    event LiquidityRemoved(
        address indexed _user, uint256 _amountOfLpTokens, uint256 _ethReturned, uint256 _tokensReturned
    );

    /*==============================================================
                                MODIFIERS
    ==============================================================*/
    modifier verifyAddress(address _address) {
        _verifyAddress(_address);
        _;
    }

    /*==============================================================
                                FUNCTIONS
    ==============================================================*/
    constructor(address _token) ERC20("ETH LP Token", "ELT") verifyAddress(_token) {
        tokenAddress = _token;
    }

    /*---------------------- Write Functions ----------------------*/

    /// External Functions ///

    /**
     * @notice `addLiquidity` allows users to add liquidity to the pool
     * @param _amountOfTokens Amount of tokens to add
     * @return Amount of LP tokens minted
     */
    function addLiquidity(uint256 _amountOfTokens) external payable returns (uint256) {
        uint256 lpTokensToMint;
        uint256 ethReserveBalance = address(this).balance;
        uint256 tokenReserveBalance = getReserve();

        IERC20 token = IERC20(tokenAddress);

        // If the reserve is empty, take any user supplied value for initial liquidity
        if (tokenReserveBalance == 0) {
            // Transfer tokens from user to pool
            bool success = token.transferFrom(msg.sender, address(this), _amountOfTokens);
            require(success, SimpleDex__TransferFailed());
            // lpTokensToMint = ethReserveBalane = msg.value
            lpTokensToMint = ethReserveBalance;
            // Mint LP tokens to user
            _mint(msg.sender, lpTokensToMint);

            return lpTokensToMint;
        }

        // If the reserve is not empty, calculate the amount of LP tokens to be minted
        uint256 initialEthReserveBalance = ethReserveBalance = msg.value;
        uint256 minTokenRequired = (msg.value * tokenReserveBalance) / initialEthReserveBalance;

        // Check if the provided amount of tokens in sufficient
        require(_amountOfTokens >= minTokenRequired, SimpleDex__InsufficientTokenAmount());

        // Transfer token from user to the pool
        bool sent = token.transferFrom(msg.sender, address(this), minTokenRequired);
        require(sent, SimpleDex__TransferFailed());

        // Calculate the amount of LP tokens
        lpTokensToMint = (totalSupply() * msg.value) / initialEthReserveBalance;

        // Mint LP tokens to user
        _mint(msg.sender, lpTokensToMint);

        emit LiquidityAdded(msg.sender, _amountOfTokens, lpTokensToMint);

        return lpTokensToMint;
    }

    /**
     * @notice `removeLiquidity` allows users to remove liquidity from the pool
     * @param _amountOfLpTokens Amount of tokens to remove
     * @return ethToReturn Amount of eth that will be returned to user
     * @return tokenToReturn Amount of token that will be returned to user
     */
    function removeLiquidity(uint256 _amountOfLpTokens) external returns (uint256 ethToReturn, uint256 tokenToReturn) {
        require(_amountOfLpTokens > 0, SimpleDex__InvalidAmount());

        uint256 ethReserveBalance = address(this).balance;
        uint256 lpTokenTotalSupply = totalSupply();

        // Calculate the amount of ETH and token to return to user
        ethToReturn = (ethReserveBalance * _amountOfLpTokens) / lpTokenTotalSupply;
        tokenToReturn = (getReserve() * _amountOfLpTokens) / lpTokenTotalSupply;

        // Burn the lp tokens from the user and transfer the ETH and tokens
        _burn(msg.sender, _amountOfLpTokens);
        (bool ethSent,) = payable(msg.sender).call{value: ethToReturn}("");
        bool tokenSent = IERC20(tokenAddress).transfer(msg.sender, tokenToReturn);
        require(ethSent && tokenSent, SimpleDex__TransferFailed());

        emit LiquidityRemoved(msg.sender, _amountOfLpTokens, ethToReturn, tokenToReturn);
    }

    /// Internal Functions ///

    /// Private Functions ///

    /*---------------------- View/Pure Functions ----------------------*/

    /**
     * @notice `getReserve` returns the balance of `token` held by `this` contract
     */
    function getReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    /**
     * @notice `_verifyAddress` checks if an address is zero address
     * @dev This function wraps logic for `verifyAddress` modifier
     * @param _address Address that needs to be verified
     */
    function _verifyAddress(address _address) private pure {
        require(_address != address(0), SimpleDex__CannotBeZeroAddress());
    }
}
