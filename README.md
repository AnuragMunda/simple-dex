# Simple DEX (Uniswap V1 Inspired)

A minimal decentralized exchange supporting swaps between ETH and a single ERC20 token, inspired by Uniswap V1.  
Implements liquidity provision, liquidity removal, ETH ↔ Token swaps, LP token minting and burning, and constant-product pricing.

This project is for educational and experimental purposes.

---

## Features

- Constant product (x * y = k) AMM
- Swap ETH → Token
- Swap Token → ETH
- Add liquidity to the pool
- Remove liquidity from the pool
- LP tokens representing proportional share of the pool
- 1% swap fee
- Reentrancy protection via `ReentrancyGuard`
- Safe token transfers with `SafeERC20`
- Custom errors for optimized reverts

---

## Architecture

```text
SimpleDex (ERC20, ReentrancyGuard)
├── addLiquidity()
├── removeLiquidity()
├── ethToTokenSwap()
├── tokenToEthSwap()
├── getOutputAmountFromSwap()
├── getReserve()
└── LP Token (SET)
```


The contract inherits:

- `ERC20` – LP token implementation  
- `ReentrancyGuard` – Protects state-changing functions  
- `SafeERC20` – Ensures safe ERC20 interactions  

---

## How It Works

### Liquidity Provision

Users deposit ETH and ERC20 tokens.


---

### Liquidity Removal

Removing liquidity burns LP tokens and returns underlying assets.


Supported swaps:

- `ethToTokenSwap(uint256 minTokens)`
- `tokenToEthSwap(uint256 tokens, uint256 minEth)`

Strict minimum output protects against slippage.

---

## Contract Functions

### addLiquidity(uint256 amountOfTokens) → uint256
Adds liquidity and mints LP tokens.

### removeLiquidity(uint256 lpTokens) → (uint256 eth, uint256 tokens)
Burns LP tokens and returns liquidity.

### ethToTokenSwap(uint256 minTokens)
Swaps ETH for tokens.

### tokenToEthSwap(uint256 tokens, uint256 minEth)
Swaps tokens for ETH.

### getReserve() → uint256
Returns token reserve of the pool.

### getOutputAmountFromSwap(uint256 dx, uint256 xReserve, uint256 yReserve) → uint256
Pure calculation function for swaps.

## Security

- Uses `ReentrancyGuard` for stateful functions
- Uses `SafeERC20` for robust token transfers
- Validates non-zero token address
- Enforces minimum output for slippage control
- Custom errors reduce gas overhead

---



