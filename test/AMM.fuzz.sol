// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AMM} from "../src/core/AMM.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import "forge-std/console.sol";

contract AMMFuzzTest is Test {
    AMM public amm;
    MockERC20 public token;
    
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    
    uint256 public constant INITIAL_MINT = 1000000 ether;
    uint256 public constant INITIAL_ETH = 10000 ether;
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    function setUp() public {
        // Deploy a mock token
        token = new MockERC20("Test Token", "TEST");
        
        // Initialize the AMM contract using the owner account
        vm.startPrank(owner);
        amm = new AMM();
        amm.initialize(address(token), FEE_NUMERATOR, FEE_DENOMINATOR);
        vm.stopPrank();
        
        // Setup user balances with increased initial ETH
        token.mint(user, INITIAL_MINT);
        vm.deal(user, INITIAL_ETH);
    }

    // 模糊测试：添加流动性
    function testFuzz_AddLiquidity(uint256 ethAmount, uint256 tokenAmount) public {
        // 更严格的边界值
        ethAmount = bound(ethAmount, 1e16, 100 ether);  // 0.01 ETH to 100 ETH
        tokenAmount = bound(tokenAmount, 1e16, 10000 ether);  // 0.01 TOKEN to 10000 TOKEN
        
        vm.startPrank(user);
        token.approve(address(amm), tokenAmount);
        
        // 首次添加流动性
        uint256 liquidityMinted = amm.addLiquidity{value: ethAmount}(tokenAmount);
        
        // 验证基本不变量
        assertGt(liquidityMinted, 0, "Liquidity should be minted");
        assertEq(amm.totalLiquidity(), liquidityMinted, "Total liquidity should match minted amount");
        assertEq(amm.liquidity(user), liquidityMinted, "User liquidity should match minted amount");
        assertEq(amm.reserveETH(), ethAmount, "ETH reserve should match input");
        assertEq(amm.reserveToken(), tokenAmount, "Token reserve should match input");
        
        vm.stopPrank();
    }

    // 模糊测试：移除流动性
    function testFuzz_RemoveLiquidity(uint256 ethAmount, uint256 tokenAmount, uint256 removePercent) public {
        // 更合理的边界值
        ethAmount = bound(ethAmount, 1e16, 100 ether);
        tokenAmount = bound(tokenAmount, 1e16, 10000 ether);
        removePercent = bound(removePercent, 1, 99);  // 1-99% to avoid edge cases
        
        // 首先添加流动性
        vm.startPrank(user);
        token.approve(address(amm), tokenAmount);
        uint256 liquidityMinted = amm.addLiquidity{value: ethAmount}(tokenAmount);
        
        // 计算要移除的流动性数量
        uint256 liquidityToRemove = (liquidityMinted * removePercent) / 100;
        
        // 记录移除前的余额
        uint256 ethBalanceBefore = address(user).balance;
        uint256 tokenBalanceBefore = token.balanceOf(user);
        
        // 移除流动性
        (uint256 ethOut, uint256 tokenOut) = amm.removeLiquidity(liquidityToRemove);
        
        // 验证移除的比例是否正确
        assertApproxEqRel(
            ethOut,
            (ethAmount * removePercent) / 100,
            1e16, // Allow 1% relative error tolerance
            "ETH output ratio incorrect"
        );
        
        assertApproxEqRel(
            tokenOut,
            (tokenAmount * removePercent) / 100,
            1e16,
            "Token output ratio incorrect"
        );
        
        // 验证余额变化
        assertEq(
            address(user).balance,
            ethBalanceBefore + ethOut,
            "ETH balance change incorrect"
        );
        assertEq(
            token.balanceOf(user),
            tokenBalanceBefore + tokenOut,
            "Token balance change incorrect"
        );
        
        vm.stopPrank();
    }

    // 模糊测试：ETH到代币的交换
    function testFuzz_EthToTokenSwap(
        uint256 poolEthAmount,
        uint256 poolTokenAmount,
        uint256 swapAmount
    ) public {
        // Ensure sufficient initial liquidity
        poolEthAmount = bound(poolEthAmount, 10 ether, 1000 ether);      // minimum 10 ETH
        poolTokenAmount = bound(poolTokenAmount, 1000 ether, 100000 ether); // minimum 1000 tokens
        swapAmount = bound(swapAmount, 0.1 ether, poolEthAmount / 2);    // minimum 0.1 ETH, max half of pool
        
        // Add logging to verify the values
        console.log("Pool ETH Amount:", poolEthAmount);
        console.log("Pool Token Amount:", poolTokenAmount);
        console.log("Swap Amount:", swapAmount);
        
        // Setup liquidity pool using the user account
        vm.startPrank(user);
        token.approve(address(amm), poolTokenAmount);
        amm.addLiquidity{value: poolEthAmount}(poolTokenAmount);
        vm.stopPrank();
        
        // Swap as a different user
        address swapper = makeAddr("swapper");
        vm.deal(swapper, swapAmount);
        
        // Calculate expected output
        uint256 expectedOut = calculateExpectedTokenOutput(
            swapAmount,
            poolEthAmount,
            poolTokenAmount
        );
        
        // Execute swap
        vm.prank(swapper);
        amm.ethToTokenSwap{value: swapAmount}(expectedOut * 99 / 100); // Allow 1% slippage
        
        // Verify reserve changes and invariant
        assertGt(amm.reserveETH(), poolEthAmount, "ETH reserve should increase");
        assertLt(amm.reserveToken(), poolTokenAmount, "Token reserve should decrease");
        
        uint256 k1 = poolEthAmount * poolTokenAmount;
        uint256 k2 = amm.reserveETH() * amm.reserveToken();
        assertApproxEqRel(k1, k2, 1e16, "Constant product should be maintained");
    }

    // 模糊测试：代币到ETH的交换
    function testFuzz_TokenToEthSwap(
        uint256 poolEthAmount,
        uint256 poolTokenAmount,
        uint256 swapAmount
    ) public {
        // Ensure sufficient initial liquidity
        poolEthAmount = bound(poolEthAmount, 10 ether, 1000 ether);      // minimum 10 ETH
        poolTokenAmount = bound(poolTokenAmount, 1000 ether, 100000 ether); // minimum 1000 tokens
        swapAmount = bound(swapAmount, 10 ether, poolTokenAmount / 2);   // minimum 10 tokens, max half of pool
        
        // Add logging to verify the values
        console.log("Pool ETH Amount:", poolEthAmount);
        console.log("Pool Token Amount:", poolTokenAmount);
        console.log("Swap Amount:", swapAmount);
        
        // Setup liquidity pool
        vm.startPrank(user);
        token.approve(address(amm), poolTokenAmount);
        amm.addLiquidity{value: poolEthAmount}(poolTokenAmount);
        vm.stopPrank();
        
        // Mint tokens to swapper and calculate expected ETH output
        address swapper = makeAddr("swapper");
        token.mint(swapper, swapAmount);
        uint256 expectedOut = calculateExpectedEthOutput(
            swapAmount,
            poolTokenAmount,
            poolEthAmount
        );
        
        // Execute swap
        vm.startPrank(swapper);
        token.approve(address(amm), swapAmount);
        amm.tokenToEthSwap(swapAmount, expectedOut * 99 / 100); // Allow 1% slippage
        vm.stopPrank();
        
        // Validate reserve changes and constant product invariant
        assertLt(amm.reserveETH(), poolEthAmount, "ETH reserve should decrease");
        assertGt(amm.reserveToken(), poolTokenAmount, "Token reserve should increase");
        
        uint256 k1 = poolEthAmount * poolTokenAmount;
        uint256 k2 = amm.reserveETH() * amm.reserveToken();
        assertApproxEqRel(k1, k2, 1e16, "Constant product should be maintained");
    }

    // Helper function: calculates expected token output from a given ETH input
    function calculateExpectedTokenOutput(
        uint256 ethIn,
        uint256 ethReserve,
        uint256 tokenReserve
    ) internal pure returns (uint256) {
        uint256 effectiveInput = ethIn * FEE_NUMERATOR;
        uint256 numerator = effectiveInput * tokenReserve;
        uint256 denominator = (ethReserve * FEE_DENOMINATOR) + effectiveInput;
        return numerator / denominator;
    }

    // Helper function: calculates expected ETH output from a given token input
    function calculateExpectedEthOutput(
        uint256 tokenIn,
        uint256 tokenReserve,
        uint256 ethReserve
    ) internal pure returns (uint256) {
        uint256 effectiveInput = tokenIn * FEE_NUMERATOR;
        uint256 numerator = effectiveInput * ethReserve;
        uint256 denominator = (tokenReserve * FEE_DENOMINATOR) + effectiveInput;
        return numerator / denominator;
    }
} 