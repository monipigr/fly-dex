# 🦋 FlyDex

FlyDex is a decentralized token exchange built with Solidity and Foundry. It allows users to **swap tokens**, **add/remove liquidity**, and **collect protocol fees**, integrating directly with **Uniswap V2 on Arbitrum**. It includes production-ready patterns like reentrancy protection, fee tracking, slippage, clean architecture, and comprehensive test coverage.

---

## ✨ Features

- 🔁 Swap ERC20 tokens
- 🔁 Swap ETH for ERC20 tokens
- ➕ Add liquidity to ERC20-ERC20 pools
- ➕ Add liquidity to ETH-ERC20 pools
- ➖ Remove liquidity from ERC20-ERC20 pools
- ➖ Remove liquidity from ETH-ERC20 pools
- 💰 Customizable fee mechanism (set by owner)
- 🔓 Only owner can withdraw accumulated fees
- 🛡️ Reentrancy protection on sensitive functions
- 📢 Event emission for all features
- 🧪 Complete unit tests and fuzzing with Foundry
- 🔄 Forked mainnet testing (Arbitrum One)

## 🔐 Security Measures

- Reentrancy protection using OpenZeppelin's `ReentrancyGuard` on sensitive functions like `withdrawFees`.
- Use of `SafeERC20` for all token transfers to handle non-standard ERC20 tokens.
- Owner-only functions protected with `Ownable`.
- Event logging for transparency and easier off-chain tracking.
- Fes tracked per-token to avoid mixing funds.
- Fee percentage capped at 5% to prevent excessive charges.
- ETH tracked separately via `address(0)` in fee mappings.

## 🧪 Tests

All core functionalities are tested using Foundry:

- ✅ `swapTokens()`
- ✅ `swapETHForTokens()`
- ✅ `addLiquidityTokens()`
- ✅ `addLiquidityETH()`
- ✅ `removeLiquidity()`
- ✅ `removeLiquidityETH()`
- ✅ `changeFee()`
- ✅ `withdrawFees()`
- ✅ Fuzzing tests for swap paths and amounts
- ✅ Invariant test for fee consistency
- ✅ Revert tests for negative scenarios

Run tests with:

```bash
forge test --fork-url https://arb1.arbitrum.io/rpc --match-test test_swapTokens
```

## 🧠 Technologies Used

- **Solidity** (`^0.8.24`)
- **Foundry** – Smart contract development & testing framework
- **Uniswap V2** – Token swap & liquidity router
- **OpenZeppelin Contracts** – `Ownable`, `ReentrancyGuard`, `SafeERC20`
- **Arbitrum One** – Mainnet fork for realistic tests

## 📜 License

This project is licensed under the MIT License.
