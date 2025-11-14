// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

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
contract SimpleDex is ERC20, ReentrancyGuard {
    /*==============================================================
                                ERRORS
    ==============================================================*/
    error SimpleDex__CannotBeZeroAddress();
    error SimpleDex__InsufficientTokenAmount();
    error SimpleDex__TransferFailed();
    error SimpleDex__InvalidAmount();
    error SimpleDex__ReservesMustBeGreaterThanZero();
    error SimpleDex__TokensReceivedLessThanExpected();
    error SimpleDex__EthReceivedLessThanExpected();

    /*==============================================================
                                TYPE DECLARATION
    ==============================================================*/
    using SafeERC20 for IERC20;

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
    constructor(address _token) ERC20("SIMPLE ETH Token", "SET") verifyAddress(_token) {
        tokenAddress = _token;
    }

    /*---------------------- Write Functions ----------------------*/

    /// External Functions ///

    /**
     * @notice `addLiquidity` allows users to add liquidity to the pool
     *
     * @param _amountOfTokens Amount of tokens to add
     *
     * @return Amount of LP tokens minted
     */
    function addLiquidity(uint256 _amountOfTokens) external payable nonReentrant returns (uint256) {
        uint256 lpTokensToMint;
        uint256 ethReserveBalance = address(this).balance;
        uint256 tokenReserveBalance = getReserve();

        IERC20 token = IERC20(tokenAddress);

        // If the reserve is empty, take any user supplied value for initial liquidity
        if (tokenReserveBalance == 0) {
            // lpTokensToMint = ethReserveBalane = msg.value
            lpTokensToMint = ethReserveBalance;
            // Mint LP tokens to user
            _mint(msg.sender, lpTokensToMint);
            // Transfer tokens from user to pool
            token.safeTransferFrom(msg.sender, address(this), _amountOfTokens);

            return lpTokensToMint;
        }

        // If the reserve is not empty, calculate the amount of LP tokens to be minted
        uint256 initialEthReserveBalance = ethReserveBalance - msg.value;
        uint256 minTokenRequired = (msg.value * tokenReserveBalance) / initialEthReserveBalance;

        // Check if the provided amount of tokens in sufficient
        require(_amountOfTokens >= minTokenRequired, SimpleDex__InsufficientTokenAmount());

        // Transfer token from user to the pool
        token.safeTransferFrom(msg.sender, address(this), minTokenRequired);

        // Calculate the amount of LP tokens
        lpTokensToMint = (totalSupply() * msg.value) / initialEthReserveBalance;

        // Mint LP tokens to user
        _mint(msg.sender, lpTokensToMint);

        emit LiquidityAdded(msg.sender, _amountOfTokens, lpTokensToMint);

        return lpTokensToMint;
    }

    /**
     * @notice `removeLiquidity` allows users to remove liquidity from the pool
     *
     * @param _amountOfLpTokens Amount of tokens to remove
     *
     * @return ethToReturn Amount of eth that will be returned to user
     * @return tokenToReturn Amount of token that will be returned to user
     */
    function removeLiquidity(uint256 _amountOfLpTokens)
        external
        nonReentrant
        returns (uint256 ethToReturn, uint256 tokenToReturn)
    {
        require(_amountOfLpTokens > 0, SimpleDex__InvalidAmount());

        uint256 ethReserveBalance = address(this).balance;
        uint256 lpTokenTotalSupply = totalSupply();

        // Calculate the amount of ETH and token to return to user
        ethToReturn = (ethReserveBalance * _amountOfLpTokens) / lpTokenTotalSupply;
        tokenToReturn = (getReserve() * _amountOfLpTokens) / lpTokenTotalSupply;

        // Burn the lp tokens from the user and transfer the ETH and tokens
        _burn(msg.sender, _amountOfLpTokens);
        (bool ethSent,) = payable(msg.sender).call{value: ethToReturn}("");
        require(ethSent, SimpleDex__TransferFailed());
        IERC20(tokenAddress).safeTransfer(msg.sender, tokenToReturn);

        emit LiquidityRemoved(msg.sender, _amountOfLpTokens, ethToReturn, tokenToReturn);
    }

    /**
     * @notice `ethToTokenSwap` swaps eth for tokens
     * @param _minTokensToReceive The minimum amount of tokens to receive
     */
    function ethToTokenSwap(uint256 _minTokensToReceive) external payable nonReentrant {
        uint256 tokenReserveBalance = getReserve();
        uint256 tokensToReceive =
            getOutputAmountFromSwap(msg.value, address(this).balance - msg.value, tokenReserveBalance);
        require(tokensToReceive >= _minTokensToReceive, SimpleDex__TokensReceivedLessThanExpected());

        IERC20(tokenAddress).safeTransfer(msg.sender, tokensToReceive);
    }

    /**
     * @notice `tokenToEthSwap` swaps tokens for eth
     * @param _tokensToSwap The amount of tokens to swap
     * @param _minEthToReceive The minimum amount of eth to receive
     */
    function tokenToEthSwap(uint256 _tokensToSwap, uint256 _minEthToReceive) external nonReentrant {
        uint256 tokenReserveBalance = getReserve();
        uint256 ethToReceive = getOutputAmountFromSwap(_tokensToSwap, tokenReserveBalance, address(this).balance);
        require(ethToReceive >= _minEthToReceive, SimpleDex__EthReceivedLessThanExpected());

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), _tokensToSwap);
        (bool sent,) = payable(msg.sender).call{value: ethToReceive}("");
        require(sent, SimpleDex__TransferFailed());
    }

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

    /**
     * @notice  `getOutputAmountFromSwap` calculates the amount of output tokens to be received based on xy = (x + dx)(y - dy)
     *
     * @param _inputAmount The amount of token user want to sell
     * @param _inputReserve The reserve of the input token
     * @param _outputReserve The reserve of the output token
     *
     * @return outputAmount The ouput token amount user gets for selling the input token
     */
    function getOutputAmountFromSwap(uint256 _inputAmount, uint256 _inputReserve, uint256 _outputReserve)
        public
        pure
        returns (uint256)
    {
        require(_inputReserve > 0 && _outputReserve > 0, SimpleDex__ReservesMustBeGreaterThanZero());

        uint256 inputAmountWithFee = _inputAmount * 99;

        uint256 numerator = inputAmountWithFee * _outputReserve;
        uint256 denominator = (_inputReserve * 100) + inputAmountWithFee;

        return numerator / denominator;
    }
}
