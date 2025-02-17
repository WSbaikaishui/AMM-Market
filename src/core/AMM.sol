// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import {Errors} from "../libraries/Errors.sol";
import {IAMM} from "../interfaces/IAMM.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract AMM is 
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IAMM
{
// 与 ETH 配对的 ERC20 代币地址
    IERC20 public token;
    uint256 public totalLiquidity;
    uint256 public reserveETH;
    uint256 public reserveToken;
    uint256 public feeNumerator;
    uint256 public feeDenominator;
    mapping(address => uint256) public liquidity;
    /**
     * @dev 初始化函数，替代构造函数
     * @param tokenAddr ERC20 代币地址，与 ETH 配对
     * @param _feeNumerator 手续费分子（例如 997）
     * @param _feeDenom 手续费分母（例如 1000）
     */
    function initialize(
        address tokenAddr,
        uint256 _feeNumerator,
        uint256 _feeDenom
    ) public initializer {
        __Ownable_init(_msgSender());
        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        if (tokenAddr == address(0)) revert Errors.ZeroAddress();
        token = IERC20(tokenAddr);

        if (_feeDenom == 0) revert Errors.FeeDenomZero();
        if (_feeNumerator >= _feeDenom) revert Errors.FeeExceedsHundredPercent();

        feeNumerator = _feeNumerator;
        feeDenominator = _feeDenom;
    }

    /**
     * @dev UUPS 升级时的权限检查，仅允许合约拥有者升级合约实现。
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /// @dev 允许合约直接接收 ETH
    receive() external payable {}

    /**
     * @dev 暂停合约，仅限拥有者调用。
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev 恢复合约，仅限拥有者调用。
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev 添加流动性。
     * 用户通过发送 ETH（msg.value）和预先 approve 的代币添加流动性。
     * 初次添加时池中无资产，可任意设置比例；本示例将投入 ETH 数额作为初始 LP 份额。
     * 后续添加时，要求按当前储备比例提供，tokenAmount 应满足：
     *      tokenRequired = (msg.value * reserveToken) / reserveETH
     *
     * 添加操作加上 whenNotPaused 与 nonReentrant 修饰，确保暂停状态下不能操作且防止重入。
     *
     * @param tokenAmount 用户期望投入的代币数量（实际按比例使用）
     * @return liquidityMinted 本次获得的 LP 份额数量
     */
    function addLiquidity(uint256 tokenAmount)
        external
        override
        payable
        whenNotPaused
        nonReentrant
        returns (uint256 liquidityMinted)
    {
        if (msg.value == 0 || tokenAmount == 0) revert Errors.MustProvideEthAndTokens();

        if (totalLiquidity == 0) {
            // 初次添加流动性：由提供者自行决定比例
            reserveETH = msg.value;
            reserveToken = tokenAmount;
            totalLiquidity = msg.value; // 简单处理：初始 LP 份额等于投入的 ETH 数额
            liquidity[msg.sender] = totalLiquidity;
            if (!token.transferFrom(msg.sender, address(this), tokenAmount))
                revert Errors.TokenTransferFailed();
            liquidityMinted = totalLiquidity;
        } else {
            // 后续添加流动性：必须按现有储备比例存入
            uint256 tokenRequired = (msg.value * reserveToken) / reserveETH;
            if (tokenAmount < tokenRequired) revert Errors.InsufficientTokenAmountProvided();

            liquidityMinted = (msg.value * totalLiquidity) / reserveETH;
            liquidity[msg.sender] += liquidityMinted;
            totalLiquidity += liquidityMinted;
            reserveETH += msg.value;
            reserveToken += tokenRequired;
            if (!token.transferFrom(msg.sender, address(this), tokenRequired))
                revert Errors.TokenTransferFailed();
        }
        emit LiquidityAdded(msg.sender, msg.value, tokenAmount, liquidityMinted);
    }

    /**
     * @dev 移除流动性。
     * 用户销毁一定数量的 LP 份额，根据当前池中储备比例返还相应数量的 ETH 与代币。
     * 此操作同样受到 whenNotPaused 与 nonReentrant 修饰保护。
     *
     * @param lpAmount 要销毁的 LP 份额数量
     * @return ethAmount 返还的 ETH 数量
     * @return tokenAmount 返还的代币数量
     */
    function removeLiquidity(uint256 lpAmount)
        external
        override
        whenNotPaused
        nonReentrant
        returns (uint256 ethAmount, uint256 tokenAmount)
    {
        if (liquidity[msg.sender] < lpAmount) revert Errors.InsufficientLiquidityBalance();

        ethAmount = (lpAmount * reserveETH) / totalLiquidity;
        tokenAmount = (lpAmount * reserveToken) / totalLiquidity;

        liquidity[msg.sender] -= lpAmount;
        totalLiquidity -= lpAmount;
        reserveETH -= ethAmount;
        reserveToken -= tokenAmount;

        (bool success, ) = msg.sender.call{value: ethAmount}("");
        if (!success) revert Errors.EthTransferFailed();
        if (!token.transfer(msg.sender, tokenAmount))
            revert Errors.TokenTransferFailed();

        emit LiquidityRemoved(msg.sender, ethAmount, tokenAmount, lpAmount);
    }

    /**
     * @dev ETH 兑换代币（ETH -> Token）。
     * 用户发送 ETH，并指定最少可接受的代币数量（用于防止滑点）。
     *
     * 根据公式：
     *      tokensOut = (dx * feeNumerator * reserveToken) / (reserveETH * feeDenominator + dx * feeNumerator)
     * 其中 dx = msg.value。
     *
     * 此函数加上 whenNotPaused 与 nonReentrant 修饰。
     *
     * @param minTokens 用户预期的最少代币数量
     */
    function ethToTokenSwap(uint256 minTokens)
        external
        override
        payable
        whenNotPaused
        nonReentrant
    {
        if (msg.value == 0) revert Errors.NoEthSent();

        uint256 ethInput = msg.value;
        uint256 effectiveInput = ethInput * feeNumerator;
        uint256 numerator = effectiveInput * reserveToken;
        uint256 denominator = (reserveETH * feeDenominator) + effectiveInput;
        uint256 tokensOut = numerator / denominator;
        if (tokensOut < minTokens) revert Errors.SlippageLimitReached();

        reserveETH += ethInput;
        reserveToken -= tokensOut;
        if (!token.transfer(msg.sender, tokensOut))
            revert Errors.TokenTransferFailed();

        emit EthToTokenSwap(msg.sender, ethInput, tokensOut);
    }

    /**
     * @dev 代币兑换 ETH（Token -> ETH）。
     * 用户出售一定数量代币（需预先 approve），并指定最少可接受的 ETH 数量。
     *
     * 根据公式：
     *      ethOut = (dx * feeNumerator * reserveETH) / (reserveToken * feeDenominator + dx * feeNumerator)
     * 其中 dx = tokenSold。
     *
     * 同样，此函数加上 whenNotPaused 与 nonReentrant 修饰。
     *
     * @param tokenSold 用户出售的代币数量
     * @param minEth 用户预期获得的最少 ETH 数量
     */
    function tokenToEthSwap(uint256 tokenSold, uint256 minEth)
        external
        override
        whenNotPaused
        nonReentrant
    {
        if (tokenSold == 0) revert Errors.MustSellTokens();
        uint256 _reserveETH = reserveETH;
        uint256 _reserveToken = reserveToken;
        
        if (!token.transferFrom(msg.sender, address(this), tokenSold))
            revert Errors.TokenTransferFailed();

        uint256 effectiveInput = tokenSold * feeNumerator;
        uint256 numerator = effectiveInput * _reserveETH;
        uint256 denominator = (_reserveToken * feeDenominator) + effectiveInput;
        uint256 ethOut = numerator / denominator;
        
        if (ethOut < minEth) revert Errors.SlippageLimitReached();

        reserveToken += tokenSold;
        reserveETH = _reserveETH - ethOut;
        
        (bool success, ) = msg.sender.call{value: ethOut}("");
        if (!success) revert Errors.EthTransferFailed();

        emit TokenToEthSwap(msg.sender, tokenSold, ethOut);
    }

    /**
     * @dev 修改手续费参数，仅允许合约拥有者调用。
     * @param _feeNumerator 新的手续费分子
     * @param _feeDenom 新的手续费分母
     */
    function setFeeParameters(uint256 _feeNumerator, uint256 _feeDenom)
        external
        override
        onlyOwner
        whenPaused
    {
        if (_feeDenom == 0) revert Errors.FeeDenomZero();
        if (_feeNumerator >= _feeDenom) revert Errors.FeeExceedsHundredPercent();
        feeNumerator = _feeNumerator;
        feeDenominator = _feeDenom;
        emit FeeParametersUpdated(_feeNumerator, _feeDenom);
    }
} 