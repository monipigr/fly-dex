// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {FlyDex} from "../src/FlyDex.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IV2Factory} from "../src/interfaces/IV2Factory.sol";
import {IV2Router} from "../src/interfaces/IV2Router.sol";

contract FlyDexTest is Test {
    FlyDex public flyDex;
    address uniswapV2SwappRouterAddress = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24; // uniswap v2 router on Arbitrum
    address uniswapV2FactoryAddress = 0xf1D7CC64Fb4452F05c498126312eBE29f30Fbcf9; // uniswap v2 factory on Arbitrum

    uint256 _fee = 10; // 0.1%
    address user = 0x25431341A5800759268a6aC1d3CD91C029D7d9CA; // address with LINK on Arbitrum
    address owner = address(this);

    address LINK = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4; // LINK en Arbitrum
    address UNI = 0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0; // UNI en Arbitrum
    address WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH en Arbitrum
    address DOT = 0xE3F5a90F9cb311505cd691a46596599aA1A0AD7D; // DOT en Arbitrum
    address DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1; // DAI en Arbitrum
    address ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548; // ARB en Arbitrum

    function setUp() public {
        flyDex = new FlyDex(uniswapV2SwappRouterAddress, uniswapV2FactoryAddress, _fee);
    }
    function test_hasBeenDeployed() public view {
        assert(address(flyDex) != address(0));
        assert(flyDex.UniswapV2RouterAddress() == uniswapV2SwappRouterAddress);
    }

    /**
     * @dev @dev Enables this contract to receive ETH. Required when it is the recipient of ETH transfers (e.g. during fee withdrawals)
     */
    receive() external payable {}

    /**
     * @dev Test to change the fee by the owner
     */
    function test_changeFee() public {
        vm.startPrank(owner);
        uint256 newFee = 20; // 0.2%
        flyDex.changeFee(newFee);
        assert(flyDex.fee() == newFee);
        vm.stopPrank();
    }

    /**
     * @dev Test to change the fee by a non-owner should revert
     */
    function test_changeFee_revertNotOwner() public {
        vm.startPrank(address(user));
        uint256 newFee = 20;
        vm.expectRevert();
        flyDex.changeFee(newFee);
        vm.stopPrank();
    }

    /**
     * @dev Test to change the fee to a value too high should revert
     */
    function test_changeFee_revertTooHigh() public {
        vm.startPrank(owner);
        uint256 newFee = 600; // 6%
        vm.expectRevert(bytes("Fee too high"));
        flyDex.changeFee(newFee);
        vm.stopPrank();
    }

    /**
     * @dev Fuzz test to change the fee by the owner
     */
    function test_fuzzChangeFee(uint256 newFee) public {
        vm.assume(newFee <= 500); // max 5%
        vm.startPrank(owner);
        flyDex.changeFee(newFee);
        assert(flyDex.fee() == newFee);
        vm.stopPrank();
    }

    /**
     * @dev Invariant to ensure the fee is never set above the maximum allowed value
     */
    function invariant_feeNeverTooHigh() public view {
        assert(flyDex.fee() <= 500);
    }

    /**
     * @dev Test that withdrawFees function works correctly for ERC20 tokens
     */
    function test_withdrawTokenFees() public {
       vm.startPrank(user);
       IERC20(LINK).approve(address(flyDex), 1e18);
       address[] memory _path = new address[](2);
       _path[0] = LINK; 
         _path[1] = WETH;
       flyDex.swapTokens(LINK, WETH, 1e18, 0, _path, block.timestamp + 1 hours);
       vm.stopPrank();

        vm.startPrank(owner);
        uint256 ownerLinkBalanceBefore = IERC20(LINK).balanceOf(owner);
        flyDex.withdrawFees(LINK, owner);
        uint256 ownerLinkBalanceAfter = IERC20(LINK).balanceOf(owner);

        assert(ownerLinkBalanceAfter == ownerLinkBalanceBefore + 1e15);
        vm.stopPrank();
    }

    /**
     * @dev Test that withdrawFees function works correctly for ETH
     */
    function test_withdrawETHFees() public {
       vm.startPrank(user);
       address[] memory _path = new address[](2);
        _path[0] = WETH;
        _path[1] = LINK;
       flyDex.swapETHForTokens{value: 1 * 1e18}(LINK, 0, _path, block.timestamp + 1 hours);
       vm.stopPrank();

        vm.startPrank(owner);
        uint256 ownerEthBalanceBefore = owner.balance;
        flyDex.withdrawFees(address(0), owner);
        uint256 ownerEthBalanceAfter = owner.balance;

        assert(ownerEthBalanceAfter == ownerEthBalanceBefore + 1e15);
        vm.stopPrank();
    }



     /**
     * @dev Test that withdrawFees function reverts when called by non-owner
     */
    function test_withdrawTokenFees_revertNotOwner() public {
       vm.startPrank(user);
       IERC20(LINK).approve(address(flyDex), 1e18);
       address[] memory _path = new address[](2);
       _path[0] = LINK; 
         _path[1] = WETH;
       flyDex.swapTokens(LINK, WETH, 1e18, 0, _path, block.timestamp + 1 hours);
       vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        flyDex.withdrawFees(LINK, owner);
        vm.stopPrank();
    }

    /**
     * @notice Test that swapTokens functionality works correctly
     * @dev Test covers swapping LINK for UNI through WETH as intermediary
     * Note: The user address must have LINK on Arbitrum for this test to work
     */
    function test_swapTokens() public {
        vm.startPrank(user);

        address _tokenIn = LINK; // LINK
        address _tokenOut = UNI; // UNI
        uint256 _amountIn = 1 * 1e18; 
        uint256 _amountOutMin = 0 * 1e18; 
        address[] memory _path = new address[](3);
        _path[0] = _tokenIn;
        _path[1] = WETH;
        _path[2] = _tokenOut;
        uint256 _deadline = block.timestamp + 1 hours;

        uint256 balance = IERC20(_tokenIn).balanceOf(user);
        console.log("User LINK balance:", balance);
        IERC20(_tokenIn).approve(address(flyDex), _amountIn);

        uint256 tokenInBalance = IERC20(_tokenIn).balanceOf(user);
        uint256 tokenOutBalance = IERC20(_tokenOut).balanceOf(user);
        flyDex.swapTokens(_tokenIn, _tokenOut, _amountIn, _amountOutMin, _path, _deadline);
        uint256 tokenInBalanceAfter = IERC20(_tokenIn).balanceOf(user);
        uint256 tokenOutBalanceAfter = IERC20(_tokenOut).balanceOf(user);

        assert(tokenInBalanceAfter == tokenInBalance - _amountIn);
        assert(tokenOutBalanceAfter > tokenOutBalance);

        vm.stopPrank();
    }

    /**
     * @notice Fuzz test for swapTokens function with random tokenOut and amountIn
     * @dev Uses LINK as tokenIn and a predefined list of tokens to select tokenOut from
     * @param _randomOut Random address to help select token out
     * @param _amountIn Random amount of token in to swap
     */
    function test_fuzzSwapTokens(address _randomOut, uint256 _amountIn) public {
        address[3] memory tokens = [UNI, DAI, ARB];
        address _tokenIn = LINK;

        // Random token selection from predefined list
        address _tokenOut = tokens[uint256(uint160(_randomOut)) % tokens.length];

        vm.assume(_tokenIn != _tokenOut);
        vm.assume(_amountIn >= 1e15 && _amountIn < 10e18); // entre 0.001 y 10 tokens
        vm.assume(pairExists(LINK, WETH));
        vm.assume(pairExists(WETH, _tokenOut)); 

        uint balance = IERC20(_tokenIn).balanceOf(user);
        console.log("User LINK balance:", balance); 

        vm.startPrank(user);
        uint256 _amountOutMin = 0 * 1e18; 
        address[] memory _path = new address[](3);
        _path[0] = _tokenIn;
        _path[1] = WETH;
        _path[2] = _tokenOut;
        uint256 _deadline = block.timestamp + 1 hours;

        IERC20(_tokenIn).approve(address(flyDex), _amountIn);

        uint256 tokenInBalance = IERC20(_tokenIn).balanceOf(user);
        uint256 tokenOutBalance = IERC20(_tokenOut).balanceOf(user);
        flyDex.swapTokens(_tokenIn, _tokenOut, _amountIn, _amountOutMin, _path, _deadline);
        uint256 tokenInBalanceAfter = IERC20(_tokenIn).balanceOf(user);
        uint256 tokenOutBalanceAfter = IERC20(_tokenOut).balanceOf(user);

        assert(tokenInBalanceAfter == tokenInBalance - _amountIn);
        assert(tokenOutBalanceAfter > tokenOutBalance);

        vm.stopPrank();
    }

    /**
     * @notice Test that swapETHForTokens functionality works correctly
     * @dev Test covers swapping ETH for UNI through WETH as intermediary
     * Note: The user address must have ETH on Arbitrum for this test to work
     */
    function test_swapETHForTokens() public {
        vm.startPrank(user);

        address _tokenOut = UNI; // UNI
        uint256 _amountIn = 1 * 1e18; // 1 ETH
        uint256 _amountOutMin = 1 * 1e15; 
        address[] memory _path = new address[](2);
        _path[0] = WETH;
        _path[1] = _tokenOut;
        uint256 _deadline = block.timestamp + 1 hours;

        uint256 tokenOutBalance = IERC20(_tokenOut).balanceOf(user);
        flyDex.swapETHForTokens{value: _amountIn}(_tokenOut, _amountOutMin, _path, _deadline);
        uint256 tokenOutBalanceAfter = IERC20(_tokenOut).balanceOf(user);

        assert(tokenOutBalanceAfter > tokenOutBalance);

        vm.stopPrank();
    }

    /**
     * @notice Test that addLiquidityTokens functionality works correctly
     * @dev Test covers adding liquidity to the UNI-LINK pool
     */
    function test_addLiquidity() public {
        vm.startPrank(user);

        address _tokenA = UNI;
        address _tokenB = LINK;
        uint256 _amountA = 1e18;
        uint256 _amountB = 1e18;
        deal(_tokenA, user, _amountA);
        deal(_tokenB, user, _amountB);

        uint256 _tokenABalanceBefore = IERC20(_tokenA).balanceOf(user);
        uint256 _tokenBBalanceBefore = IERC20(_tokenB).balanceOf(user);

        IERC20(_tokenA).approve(address(flyDex), _amountA);
        IERC20(_tokenB).approve(address(flyDex), _amountB);
        uint256 lpTokens = flyDex.addLiquidityTokens(_tokenA, _tokenB, 1 * 1e18, 1 * 1e18, 0, 0, block.timestamp + 1 hours);

        uint256 _tokenABalanceAfter = IERC20(_tokenA).balanceOf(user);
        uint256 _tokenBBalanceAfter = IERC20(_tokenB).balanceOf(user);

        assert(_tokenABalanceAfter < _tokenABalanceBefore);
        assert(_tokenBBalanceAfter < _tokenBBalanceBefore);
        assert(lpTokens != 0);

        vm.stopPrank();
    }

    /**
     * @notice Test that addLiquidityTokens reverts when amounts are zero
     */
    function test_addLiquidity_revertZeroAmount() public {
        vm.startPrank(user);

        address _tokenA = UNI;
        address _tokenB = LINK;
        uint256 _amountA = 0;
        uint256 _amountB = 1e18;
        deal(_tokenA, user, _amountA);
        deal(_tokenB, user, _amountB);

        IERC20(_tokenA).approve(address(flyDex), _amountA);
        IERC20(_tokenB).approve(address(flyDex), _amountB);
        vm.expectRevert("Amounts must be greater than 0");
        flyDex.addLiquidityTokens(_tokenA, _tokenB, _amountA, _amountB, 0, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    /**
     * @notice Test that addLiquidityTokens reverts when tokens are the same
     */
    function test_addLiquidity_revertSameToken() public {
        vm.startPrank(user);

        address _tokenA = UNI;
        address _tokenB = UNI;
        uint256 _amountA = 1e18;
        uint256 _amountB = 1e18;
        deal(_tokenA, user, _amountA);
        deal(_tokenB, user, _amountB);

        IERC20(_tokenA).approve(address(flyDex), _amountA);
        IERC20(_tokenB).approve(address(flyDex), _amountB);
        vm.expectRevert("Tokens must be different");
        flyDex.addLiquidityTokens(_tokenA, _tokenB, _amountA, _amountB, 0, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }
    
    /**
     * @notice Test that addLiquidityETH functionality works correctly
     * @dev Test covers adding liquidity to the LINK-ETH pool
     */
    function test_addLiquidityETH() public {
        vm.startPrank(user);

        address _token = LINK;
        uint256 _amount = 1e18;
        vm.deal(user, 1 ether);
        deal(_token, user, _amount);

        
        uint256 _tokenETHBalanceBefore = user.balance;
        uint256 _tokenBalanceBefore = IERC20(_token).balanceOf(user);

        IERC20(_token).approve(address(flyDex), _amount);
        uint256 lpTokens = flyDex.addLiquidityETH{value: 1 ether}(_token, 1 * 1e18, 0, 0, block.timestamp + 1 hours);
        
        uint256 _tokenETHBalanceAfter = user.balance;
        uint256 _tokenBalanceAfter = IERC20(_token).balanceOf(user);

        assert(_tokenETHBalanceAfter < _tokenETHBalanceBefore);
        assert(_tokenBalanceAfter < _tokenBalanceBefore);
        assert(lpTokens != 0);

        vm.stopPrank();
    }

    /**
     * @notice Test that addLiquidityETH reverts when amount is zero
     */
    function test_addLiquidityETH_revertZeroAmount() public {
        vm.startPrank(user);

        address _token = LINK;
        uint256 _amount = 0;
        vm.deal(user, 1 ether);
        deal(_token, user, 1e18);

        IERC20(_token).approve(address(flyDex), _amount);
        vm.expectRevert("Must send ETH");
        flyDex.addLiquidityETH{value: 0}(_token, _amount, 0, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }

    /**
     * @notice Test that addLiquidityETH reverts when token is WETH
     */
    function test_addLiquidityETH_revertTokenIsWETH() public {
        vm.startPrank(user);

        address _token = WETH;
        uint256 _amount = 1e18;
        vm.deal(user, 1 ether);
        deal(_token, user, _amount);                
        IERC20(_token).approve(address(flyDex), _amount);
        vm.expectRevert("Token cannot be WETH");
        flyDex.addLiquidityETH{value: 1 ether}(_token, _amount, 0, 0, block.timestamp + 1 hours);

        vm.stopPrank();
    }


    /**
     * @dev Helper function to check if a pair exists in Uniswap V2 Factory
     * @param _tokenA Input token address
     * @param _tokenB Output token address
     * @return bool True if the pair exists, false otherwise
     */
    function pairExists(address _tokenA, address _tokenB) public view returns (bool) {
        address pairAddress = IV2Factory(uniswapV2FactoryAddress).getPair(_tokenA, _tokenB);
        return pairAddress != address(0);
    }
    
}
