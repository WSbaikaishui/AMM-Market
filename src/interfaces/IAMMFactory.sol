// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAMMFactory {
    // 事件声明，记录创建的 AMM 合约
    event AMMCreated(address indexed token, address indexed amm);
    event AMMUpgraded(
        address indexed tokenAddress, 
        address indexed ammAddress,
        address indexed newImplementation
    );

    // 创建 AMM 合约
    function createAMM(address tokenAddr, uint256 _feeNumerator, uint256 _feeDenom)
        external
        returns (address amm);
}
