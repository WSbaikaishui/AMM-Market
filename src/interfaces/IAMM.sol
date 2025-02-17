// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAMM {
    // Event declarations
    event LiquidityAdded(
        address indexed provider,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidityMinted
    );
    
    event LiquidityRemoved(
        address indexed provider,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidityBurned
    );
    
    event EthToTokenSwap(
        address indexed trader,
        uint256 ethSold,
        uint256 tokensBought
    );
    
    event TokenToEthSwap(
        address indexed trader,
        uint256 tokensSold,
        uint256 ethBought
    );
    
    event FeeParametersUpdated(uint256 feeNumerator, uint256 feeDenom);

    // Initialization function
    function initialize(
        address tokenAddr,
        uint256 _feeNumerator,
        uint256 _feeDenom
    ) external;

    // Function to add liquidity
    function addLiquidity(uint256 tokenAmount)
        external
        payable
        returns (uint256 liquidityMinted);

    // Function to remove liquidity
    function removeLiquidity(uint256 lpAmount)
        external
        returns (uint256 ethAmount, uint256 tokenAmount);

    // Function for ETH to Token swap
    function ethToTokenSwap(uint256 minTokens)
        external
        payable;

    // Function for Token to ETH swap
    function tokenToEthSwap(uint256 tokenSold, uint256 minEth)
        external;

    // Function to set fee parameters
    function setFeeParameters(uint256 _feeNumerator, uint256 _feeDenom)
        external;
}
