/*
FEATURES: 
- ✅ Swap de cualquier token ERC20 por otro token ERC20 - swapExactTokensForTokens()
- ✅ Swap de ETH por cualquier token ERC20 - swapExactTokensForETH()
- ✅ Añadir liquidez de cualquier token ERC20 - addLiquidity()
- ✅ Retirar liquidez de cualquier token ERC20 - removeLiquidity()
- ✅ Añadir liquidez de ETH - addLiquidityETH()
- ✅ Retirar liquidez de ETH -  removeLiquidityETH()
- ✅ Cobrar una fee por cada swap - ex 0.1%
- ✅ Permitir al owner cambiar la fee - changeFee()
- ✅ Permitir al owner retirar las fees acumuladas - withdrawFees()

- ✅ Emitir eventos para cada acción
- ✅ Seguridad contra reentrancy con OpenZeppelin ReentrancyGuard --> nonReentrant
- ✅ Testing completo con fuzzing y invariants

- Frontend (React + Vite + Viem + Wagmi + TailwindCSS):
    - Interfaz sencilla para interactuar con el contrato en la red de Arbitrum
    - Conexión con wallet (MetaMask, WalletConnect, etc)
    - Swap de algunos tokens (ETH, LINK, UNI, DAI, WETH, DOT, ARB)
    - Añadir y retirar liquidez ETH
    - Ver fees acumuladas y retirarlas (sólo owner)
 */

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;


import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IV2Router.sol";
import "./interfaces/IV2Factory.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FlyDex is Ownable, ReentrancyGuard { 
    
    using SafeERC20 for IERC20;

    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH en Arbitrum
    address public immutable UniswapV2RouterAddress; // uniswap v2 router on Arbitrum
    address public immutable UniswapV2FactoryAddress; // uniswap v2 factory on Arbitrum

    uint256 public fee; // fee en basis points (bps), ex 10 = 0.1%
    uint256 public constant MAX_FEE = 500; // max fee 5%
    mapping(address => uint256) public feesCollectedPerToken; // fees collected per token

    event FeeChanged(uint256 newFee);
    event FeeCollected(uint256 fee);
    event SwapExecuted(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut); 
    event SwapETHExecuted(address user, uint256 amountIn, address tokenOut, uint256 amountOut);
    event FeesWithdrawn(address token, uint256 amount, address to);
    event LiquidityTokensAdded(address tokenA, address tokenB, uint256 lpTokens);
    event LiquidityETHAdded(uint256 amountETH, address token, uint256 amountTokenDesired, uint256 lpTokens);
    event RemoveLiquidityTokens(address tokenA, address tokenB, uint256 liquidity, address to);
    event RemoveLiquidityETH(address token, uint256 liquidity, address to);

    constructor(address _uniswapV2RouterAddress, address _uniswapV2FactoryAddress, uint256 _fee) Ownable(msg.sender) { 
        UniswapV2RouterAddress = _uniswapV2RouterAddress;
        UniswapV2FactoryAddress = _uniswapV2FactoryAddress;
        fee = _fee;
    }

    receive() external payable {}

    /**
     * @param _newFee New fee in basis points (bps)
     */
    function changeFee(uint256 _newFee) external onlyOwner {
        require(_newFee <= MAX_FEE, "Fee too high"); // max 5%
        fee = _newFee;

        emit FeeChanged(_newFee);
    }

    /**
     * @notice Function for the owner to withdraw accumulated fees
     * @param _token Address of the token to withdraw, use address(0) for ETH
     * @param _to Address to send the withdrawn fees to
     */
    function withdrawFees(address _token, address _to) external onlyOwner nonReentrant {
        uint256 amount = feesCollectedPerToken[_token];
        require(amount > 0, "No fees to withdraw");
        feesCollectedPerToken[_token] = 0;

        if (_token == address(0)) {
            // Withdraw ETH
            (bool success, ) = _to.call{value: amount}("");
            require(success, "ETH Transfer failed");
        } else {
            // Withdraw ERC20
            IERC20(_token).safeTransfer(_to, amount);
        }

        emit FeesWithdrawn(_token, amount, _to);
    }
    
    /**
     * @notice Function to swap any token ERC20 for another token ERC20
     * @param _tokenIn Address of the token to swap from
     * @param _tokenOut Address of the token to swap to
     * @param _amountIn Amount of tokenA to swap
     * @param _amountOutMin Minimum amount of tokenB to receive
     * @param _path Array of token addresses (path) for the swap
     * @param _deadline Unix timestamp after which the transaction will revert 
     */
    function swapTokens(address _tokenIn, address _tokenOut, uint256 _amountIn, uint256 _amountOutMin, address[] calldata _path, uint256 _deadline) external returns (uint256) {
        // Calculate fee and transfer tokens accordingly
        uint256 feeAmount = (_amountIn * fee) / 10000;
        uint256 amountAfterFee = _amountIn - feeAmount;
        feesCollectedPerToken[_tokenIn] += feeAmount;   

        // Swap tokens using Uniswap V2 Router  
        IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
        IERC20(_tokenIn).approve(UniswapV2RouterAddress, amountAfterFee);
        uint256[] memory amountsOut = IV2Router(UniswapV2RouterAddress).swapExactTokensForTokens(amountAfterFee, _amountOutMin, _path, msg.sender, _deadline);
     
        // Emit event
        emit SwapExecuted(_tokenIn, _tokenOut, _amountIn, amountsOut[amountsOut.length - 1]);
        emit FeeCollected(feeAmount);

        return amountsOut[amountsOut.length - 1];
    }

    /**
     * @notice Function to swap ETH for any ERC20 token 
     * @param _tokenOut Address of the token to swap to
     * @param _amountOutMin Minimum amount of token to receive
     * @param _path Array of token addresses (path) for the swap, must start with WETH
     * @param _deadline Unix timestamp after which the transaction will revert 
     */
    function swapETHForTokens(address _tokenOut, uint256 _amountOutMin, address[] calldata _path, uint256 _deadline) external payable returns (uint256) {
        require(msg.value > 0, "Must send ETH");

        // Calculate fee and transfer accordingly
        uint256 feeAmount = (msg.value * fee) / 10000;
        uint256 amountAfterFee = msg.value - feeAmount;
        feesCollectedPerToken[address(0)] += feeAmount; // address(0) for ETH

        uint256[] memory amounts = IV2Router(UniswapV2RouterAddress).swapExactETHForTokens{value: amountAfterFee}(_amountOutMin, _path, msg.sender, _deadline);

        emit SwapETHExecuted(msg.sender, msg.value, _tokenOut, amounts[amounts.length - 1]);
        emit FeeCollected(feeAmount);

        return amounts[amounts.length - 1];
    }

    /**
     * @notice Function to add liquidity for any ERC20 token pair
     * @param _tokenA Address of token A
     * @param _tokenB Address of token B
     * @param _amountADesired Amount of token A to add as liquidity
     * @param _amountBDesired Amount of token B to add as liquidity
     * @param _amountAMin Minimum amount of token A to add (slippage protection)
     * @param _amountBMin Minimum amount of token B to add (slippage protection)
     * @param _deadline Unix timestamp after which the transaction will revert 
     */
    function addLiquidityTokens(address _tokenA, address _tokenB, uint256 _amountADesired, uint256 _amountBDesired, uint256 _amountAMin, uint256 _amountBMin, uint256 _deadline) external returns (uint256) {
        require(_amountADesired > 0 && _amountBDesired > 0, "Amounts must be greater than 0"); 
        require(_tokenA != _tokenB, "Tokens must be different");

        IERC20(_tokenA).safeTransferFrom(msg.sender, address(this), _amountADesired);
        IERC20(_tokenB).safeTransferFrom(msg.sender, address(this), _amountBDesired);
        IERC20(_tokenA).approve(UniswapV2RouterAddress, _amountADesired);
        IERC20(_tokenB).approve(UniswapV2RouterAddress, _amountBDesired);
        (,, uint256 lpTokens) = IV2Router(UniswapV2RouterAddress).addLiquidity(_tokenA, _tokenB, _amountADesired, _amountBDesired, _amountAMin, _amountBMin, msg.sender, _deadline);

        emit LiquidityTokensAdded(_tokenA, _tokenB, lpTokens);

        return lpTokens;
    }

    /**
     * @notice Function to add liquidity with ETH
     * @param _token Address of the ERC20 token to pair with ETH
     * @param _amountTokenDesired Amount of the ERC20 token to add as liquidity
     * @param _amountTokenMin Minimum amount of the ERC20 token to add (slippage protection)
     * @param _amountETHMin Minimum amount of ETH to add (slippage protection)
     * @param _deadline Unix timestamp after which the transaction will revert 
     */
    function addLiquidityETH(address _token, uint256 _amountTokenDesired, uint256 _amountTokenMin, uint256 _amountETHMin, uint256 _deadline) external payable returns (uint256) {
        require(msg.value > 0, "Must send ETH");
        require(_token != WETH, "Token cannot be WETH");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountTokenDesired);
        IERC20(_token).approve(UniswapV2RouterAddress, _amountTokenDesired);
        (,, uint256 lpToken) = IV2Router(UniswapV2RouterAddress).addLiquidityETH{value: msg.value}(_token, _amountTokenDesired, _amountTokenMin, _amountETHMin, msg.sender, _deadline);

        emit LiquidityETHAdded(msg.value, _token, _amountTokenDesired, lpToken);

        return lpToken;
    }

    /**
     * @notice Function to remove liquidity for any ERC20 token pair
     * @param _tokenA Address of token A
     * @param _tokenB Address of token B
     * @param _liquidity Amount of liquidity tokens to remove
     * @param _amountAMin Minimum amount of token A to receive (slippage protection)
     * @param _amountBMin Minimum amount of token B to receive (slippage protection)
     * @param _deadline Unix timestamp after which the transaction will revert 
     */
    function removeLiquidity(address _tokenA, address _tokenB, uint256 _liquidity, uint256 _amountAMin, uint256 _amountBMin, uint256 _deadline) external {
        require(_tokenA != _tokenB, "Tokens must be different");
        
        address pairAddr = IV2Factory(UniswapV2FactoryAddress).getPair(_tokenA, _tokenB);
        IERC20(pairAddr).safeTransferFrom(msg.sender, address(this), _liquidity);
        IERC20(pairAddr).approve(UniswapV2RouterAddress, _liquidity);
        IV2Router(UniswapV2RouterAddress).removeLiquidity(_tokenA, _tokenB, _liquidity, _amountAMin, _amountBMin, msg.sender, _deadline);

        emit RemoveLiquidityTokens(_tokenA, _tokenB, _liquidity, msg.sender);
    }

    /**
     * @notice Function to remove liquidity with ETH
     * @param _token Address of the ERC20 token paired with ETH
     * @param _liquidity Amount of liquidity tokens to remove
     * @param _amountTokenMin Minimum amount of the ERC20 token to receive (slippage protection)
     * @param _amountETHMin Minimum amount of ETH to receive (slippage protection)
     * @param _deadline Unix timestamp after which the transaction will revert 
     */
    function removeLiquidityETH(address _token, uint256 _liquidity, uint256 _amountTokenMin, uint256 _amountETHMin, uint256 _deadline) external {
        require(_token != address(0), "Invalid token");

        address pairAddr = IV2Factory(UniswapV2FactoryAddress).getPair(WETH, _token);
        IERC20(pairAddr).safeTransferFrom(msg.sender, address(this), _liquidity);
        IERC20(pairAddr).approve(UniswapV2RouterAddress, _liquidity);
        IV2Router(UniswapV2RouterAddress).removeLiquidityETH(_token, _liquidity, _amountTokenMin, _amountETHMin, msg.sender, _deadline);

        emit RemoveLiquidityETH(_token, _liquidity, msg.sender);
    }
}
