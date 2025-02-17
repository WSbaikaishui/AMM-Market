// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AMM} from "../src/core/AMM.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "forge-std/console.sol";

contract AMMTest is Test {
    // Contract instances
    AMM public amm;
    MockERC20 public token;
    
    // Test accounts
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    
    // Constants for initial setup
    uint256 public constant INITIAL_MINT = 1000000 ether;
    uint256 public constant INITIAL_ETH = 100 ether;
    
    // Fee parameters (0.3% fee)
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    // Events for testing
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 liquidityMinted);
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 liquidityBurned);
    event EthToTokenSwap(address indexed buyer, uint256 ethIn, uint256 tokenOut);
    event TokenToEthSwap(address indexed seller, uint256 tokenIn, uint256 ethOut);

    function setUp() public {
        // Deploy test token
        token = new MockERC20("Test Token", "TEST");
        assert(address(token) != address(0));
        
        // Deploy AMM
        vm.prank(owner);
        amm = new AMM();
        assert(address(amm) != address(0));
        
        // Initialize AMM
        vm.prank(owner);
        amm.initialize(address(token), FEE_NUMERATOR, FEE_DENOMINATOR);
        
        // Verify initialization
        assertEq(address(amm.token()), address(token));
        assertEq(amm.feeNumerator(), FEE_NUMERATOR);
        assertEq(amm.feeDenominator(), FEE_DENOMINATOR);
        
        // Mint tokens to test users
        token.mint(user1, INITIAL_MINT);
        token.mint(user2, INITIAL_MINT);
        
        // Verify token balances
        assertEq(token.balanceOf(user1), INITIAL_MINT);
        assertEq(token.balanceOf(user2), INITIAL_MINT);
        
        // Fund test users with ETH
        vm.deal(user1, INITIAL_ETH);
        vm.deal(user2, INITIAL_ETH);
        
        // Verify ETH balances
        assertEq(user1.balance, INITIAL_ETH);
        assertEq(user2.balance, INITIAL_ETH);
    }

    function test_InitialState() public view {
        assertEq(address(amm.token()), address(token));
        assertEq(amm.feeNumerator(), FEE_NUMERATOR);
        assertEq(amm.feeDenominator(), FEE_DENOMINATOR);
        assertEq(amm.totalLiquidity(), 0);
        assertEq(amm.reserveETH(), 0);
        assertEq(amm.reserveToken(), 0);
    }

    function test_AddInitialLiquidity() public {
        uint256 ethAmount = 10 ether;
        uint256 tokenAmount = 1000 ether;

        vm.startPrank(user1);
        token.approve(address(amm), tokenAmount);
        
        vm.expectEmit(true, false, false, true);
        emit LiquidityAdded(user1, ethAmount, tokenAmount, ethAmount);
        
        uint256 liquidityMinted = amm.addLiquidity{value: ethAmount}(tokenAmount);
        vm.stopPrank();

        assertEq(liquidityMinted, ethAmount);
        assertEq(amm.totalLiquidity(), ethAmount);
        assertEq(amm.liquidity(user1), ethAmount);
        assertEq(amm.reserveETH(), ethAmount);
        assertEq(amm.reserveToken(), tokenAmount);
    }

    function test_AddSubsequentLiquidity() public {
        // First add initial liquidity
        vm.startPrank(user1);
        token.approve(address(amm), 1000 ether);
        amm.addLiquidity{value: 10 ether}(1000 ether);
        vm.stopPrank();

        // User2 adds liquidity
        uint256 ethAmount = 5 ether;
        uint256 tokenAmount = 500 ether;

        vm.startPrank(user2);
        token.approve(address(amm), tokenAmount);
        uint256 liquidityMinted = amm.addLiquidity{value: ethAmount}(tokenAmount);
        vm.stopPrank();

        assertEq(liquidityMinted, 5 ether);
        assertEq(amm.totalLiquidity(), 15 ether);
        assertEq(amm.liquidity(user2), 5 ether);
    }

    function test_RemoveLiquidity() public {
        // First add liquidity
        vm.startPrank(user1);
        token.approve(address(amm), 1000 ether);
        amm.addLiquidity{value: 10 ether}(1000 ether);

        uint256 lpAmount = 5 ether;
        
        vm.expectEmit(true, false, false, true);
        emit LiquidityRemoved(user1, 5 ether, 500 ether, lpAmount);
        
        (uint256 ethOut, uint256 tokenOut) = amm.removeLiquidity(lpAmount);
        vm.stopPrank();

        assertEq(ethOut, 5 ether);
        assertEq(tokenOut, 500 ether);
        assertEq(amm.totalLiquidity(), 5 ether);
        assertEq(amm.liquidity(user1), 5 ether);
    }

    function test_EthToTokenSwap() public {
        // Set up initial liquidity
        vm.startPrank(user1);
        token.approve(address(amm), 1000 ether);
        amm.addLiquidity{value: 10 ether}(1000 ether);
        vm.stopPrank();

        uint256 ethIn = 1 ether;
        
        // Calculate expected output
        uint256 expectedTokenOut = calculateExpectedTokenOut(ethIn);
        console.log("Expected Token out:", expectedTokenOut);
        
        vm.startPrank(user2);
        
        // Record balance before swap
        uint256 balanceBefore = token.balanceOf(user2);
        
        // Set event expectation
        vm.expectEmit(true, false, false, true);
        emit EthToTokenSwap(user2, ethIn, expectedTokenOut);
        
        // Set minimum output with 1% slippage tolerance
        uint256 minTokenOut = expectedTokenOut * 99 / 100;
        console.log("Min Token out:", minTokenOut);
        
        amm.ethToTokenSwap{value: ethIn}(minTokenOut);
        
        // Calculate actual tokens received
        uint256 actualTokenOut = token.balanceOf(user2) - balanceBefore;
        console.log("Actual Token out:", actualTokenOut);
        
        // Verify result with 0.1% tolerance
        assertApproxEqRel(actualTokenOut, expectedTokenOut, 1e15);
        
        vm.stopPrank();
    }

    // Helper function: Calculate expected token output
    function calculateExpectedTokenOut(uint256 ethIn) internal view returns (uint256) {
        uint256 effectiveInput = ethIn * FEE_NUMERATOR;
        uint256 numerator = effectiveInput * amm.reserveToken();
        uint256 denominator = (amm.reserveETH() * FEE_DENOMINATOR) + effectiveInput;    
        return numerator / denominator;
    }

    function test_TokenToEthSwap() public {
        // Set up initial liquidity
        vm.startPrank(user1);
        token.approve(address(amm), 1000 ether);
        amm.addLiquidity{value: 10 ether}(1000 ether);
        vm.stopPrank();

        uint256 tokenIn = 100 ether;
        
        // Calculate expected output
        uint256 expectedEthOut = calculateExpectedEthOut(tokenIn);
        console.log("Expected ETH out:", expectedEthOut);
        
        vm.startPrank(user2);
        token.approve(address(amm), tokenIn);
        
        // Record balance before swap
        uint256 balanceBefore = address(user2).balance;
        
        // Set event expectation
        vm.expectEmit(true, false, false, true);
        emit TokenToEthSwap(user2, tokenIn, expectedEthOut);
        
        // Set minimum output with 1% slippage tolerance
        uint256 minEthOut = expectedEthOut * 99 / 100;
        
        amm.tokenToEthSwap(tokenIn, minEthOut);
        
        // Calculate actual ETH received
        uint256 actualEthOut = address(user2).balance - balanceBefore;
        
        // Verify result with 0.1% tolerance
        assertApproxEqRel(actualEthOut, expectedEthOut, 1e15);
        
        vm.stopPrank();
    }

    // Helper function: Calculate expected ETH output
    function calculateExpectedEthOut(uint256 tokenIn) internal view returns (uint256) {
        uint256 effectiveInput = tokenIn * FEE_NUMERATOR;
        uint256 numerator = effectiveInput * amm.reserveETH();
        uint256 denominator = (amm.reserveToken() * FEE_DENOMINATOR) + effectiveInput;    
        return numerator / denominator;
    }

    function test_PauseAndUnpause() public {
        vm.prank(owner);
        amm.pause();
        assertTrue(amm.paused());
        
        vm.startPrank(user1);
        token.approve(address(amm), 1000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        amm.addLiquidity{value: 10 ether}(1000 ether);
        vm.stopPrank();

        vm.prank(owner);
        amm.unpause();
        
        vm.startPrank(user1);
        amm.addLiquidity{value: 1 ether}(100 ether);
        vm.stopPrank();
    }

    function test_UpdateFeeParameters() public {
        vm.startPrank(owner);
        amm.pause();
        amm.setFeeParameters(995, 1000); // Update to 0.5% fee
        vm.stopPrank();

        assertEq(amm.feeNumerator(), 995);
        assertEq(amm.feeDenominator(), 1000);
    }
} 