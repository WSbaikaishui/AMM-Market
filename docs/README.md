# AMM 自动做市商系统

# AMM 自动做市商系统 - 实现状态

## ✅ 已实现功能

### 1. 智能合约开发
- **AMM 核心实现**
  - ETH/ERC20 交易对支持
  - 流动性池管理（添加/移除）
  - 基于恒定乘积公式的自动价格发现
  - 手续费系统（0.3% 交易费）
  - 交易滑点控制

- **权限控制**
  - 两步所有权转移
  - 关键功能的基于角色的访问控制

### 2. 安全特性
- **漏洞防护**
  - 使用 OpenZeppelin 的 ReentrancyGuard 防重入
  - SafeMath 运算（Solidity ^0.8.0）
  - 遵循检查-生效-交互模式
  
- **紧急控制**
  - 断路器（暂停/恢复功能）
  - 紧急提款机制

### 3. 可升级性
- **UUPS 代理模式**
  - 使用 UUPS 模式的可升级合约
  - 分离的代理和实现合约
  - AMM 部署的工厂模式

### 4. Gas 优化
- **高效实现**
  - 优化的存储使用
  - 最小化状态变更
  - 高效的数学计算

### 5. 测试
- **全面的测试套件**
  - 所有核心功能的单元测试
  - 边界情况的模糊测试
  - 完整工作流的集成测试

### 6. 部署
- **多环境支持**
  - 不同网络的部署脚本
  - 环境配置支持
  - 合约验证支持

### 7. 文档
- **技术文档**
  - 架构概述
  - 合约交互指南
  - 部署说明
  - 测试指南


## 目录

1. [项目概述](#1-项目概述)
2. [系统架构](#2-系统架构)
3. [技术实现](#3-技术实现)
4. [合约交互](#4-合约交互)
5. [开发指南](#5-开发指南)
6. [部署指南](#6-部署指南)
7. [测试指南](#7-测试指南)
8. [安全考虑](#8-安全考虑)
9. [常见问题](#9-常见问题)

## 1. 项目概述

### 1.1 项目简介

本项目实现了一个基于恒定乘积公式（Constant Product Formula）的自动做市商（AMM）系统，支持 ETH 与任意 ERC20 代币的交易对创建和自动做市交易。

### 1.2 核心功能

- ETH/ERC20 交易对的自动做市
- 流动性提供与移除
- 自动价格发现
- 交易手续费系统
- 可升级的智能合约架构
- 工厂合约模式
- 紧急暂停机制

### 1.3 特色优势

- 高度安全性：多重安全机制保护
- 可扩展性：支持合约升级
- 去中心化：完全链上操作
- 透明性：价格计算公开透明
- 灵活性：可配置的手续费参数

## 2. 系统架构

### 2.1 合约架构

```solidity
├── core/
│ ├── AMM.sol # AMM 核心合约：实现交易对和流动性管理
│ └── AMMFactory.sol # 工厂合约：管理 AMM 实例的创建和升级
├── interfaces/
│ ├── IAMM.sol # AMM 接口：定义核心功能接口
│ └── IAMMFactory.sol # 工厂接口：定义工厂合约接口
└── libraries/
└── Errors.sol # 错误信息库：统一错误处理
```
### 2.2 合约依赖

- OpenZeppelin 合约：
  - `UUPSUpgradeable`: 可升级合约基础设施
  - `Ownable2StepUpgradeable`: 双步所有权转移
  - `PausableUpgradeable`: 可暂停功能
  - `ReentrancyGuardUpgradeable`: 重入保护
  - `IERC20`: ERC20 代币接口
  - `SafeERC20`: 安全的 ERC20 操作

### 2.3 核心功能流程

1. **AMM 创建流程**
   ```mermaid
   graph LR
   A[用户] --> B[AMMFactory]
   B --> C[创建 AMM 实例]
   C --> D[初始化参数]
   D --> E[注册到工厂]
   ```

2. **交易流程**
   ```mermaid
   graph LR
   A[用户] --> B[AMM 实例]
   B --> C[检查输入]
   C --> D[计算输出]
   D --> E[执行交换]
   ```

## 3. 技术实现

### 3.1 核心算法

#### 3.1.1 恒定乘积公式

基本公式：
```
x y = k
```
其中：
- x: ETH 储备量
- y: Token 储备量
- k: 恒定乘积值

#### 3.1.2 价格计算

ETH 到 Token 的兑换：
```
tokensOut = (ethIn feeNumerator tokenReserve) / (ethReserve feeDenominator + ethIn feeNumerator)
```
Token 到 ETH 的兑换：
```
ethOut = (tokenIn feeNumerator ethReserve) / (tokenReserve feeDenominator + tokenIn feeNumerator)
```

### 3.2 流动性管理

#### 3.2.1 添加流动性

首次添加：

```
// LP 代币数量
tokens = ETH amount
liquidityMinted = msg.value;
```

后续添加：

```
liquidityMinted = (msg.value totalLiquidity) / reserveETH;
```

#### 3.2.2 移除流动性

按比例返还：

```
ethAmount = (lpAmount reserveETH) / totalLiquidity;
tokenAmount = (lpAmount reserveToken) / totalLiquidity;
```

#### 3.2.2 移除流动性

按比例返还：

```
ethAmount = (lpAmount reserveETH) / totalLiquidity;
tokenAmount = (lpAmount reserveToken) / totalLiquidity;
```
### 3.3 手续费机制

- 默认费率：0.3%
- 计算方式：`fee = 1 - (feeNumerator / feeDenominator)`
- 默认参数：
  - `feeNumerator = 997`
  - `feeDenominator = 1000`

## 4. 合约交互

### 4.1 添加流动性

```
/ 1. 批准代币使用
IERC20(tokenAddress).approve(ammAddress, tokenAmount);
// 2. 添加流动性
amm.addLiquidity{value: ethAmount}(tokenAmount);
```

### 4.2 移除流动性

```
// 移除指定数量的流动性
amm.removeLiquidity(lpAmount);
```

### 4.3 代币交换

ETH 换 Token：
```
/ 设置最小获得代币数防止滑点
amm.ethToTokenSwap{value: ethAmount}(minTokensOut);
```

Token 换 ETH：
```
// 1. 批准代币使用
IERC20(tokenAddress).approve(ammAddress, tokenAmount);
// 2. 执行交换
amm.tokenToEthSwap(tokenAmount, minEthOut);
```

## 5. 开发指南

### 5.1 开发环境设置

1. 克隆仓库：
```
git clone https://github.com/WSbaikaishui/AMM-Market.git 
cd amm-contracts
```

2. 安装依赖：

```
forge install
```

3. 编译合约：

```
forge build
```

### 5.2 本地开发

1. 启动本地节点：

```
anvil
```

2. 运行测试：

```
forge test
```

### 5.3 合约升级

1. 部署新实现：

```
forge create src/core/AMM.sol:AMM
```

2. 升级工厂合约：

```
factory.upgradeToAndCall(newImplementation, "");
```
## 6. 部署指南

### 6.1 准备工作

1. 配置环境变量：

```
cp .env.example .env
```

2. 配置网络：
```
PRIVATE_KEY=your_private_key
ETHERSCAN_API_KEY=your_api_key
RPC_URL=your_rpc_url
```


### 6.2 部署命令

部署：
```
source .env
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast --verify -vvvv

```
## 7. 测试指南

### 7.1 测试类型

1. **单元测试**
```
forge test --match-contract AMMTest
```

2.  **模糊测试**
```
forge test --match-contract AMMFuzzTest --fuzz-runs 10000
```


### 7.2 测试覆盖率

生成覆盖率报告：
```
forge coverage --rpc-url $RPC_URL --report summary
```

## 8. 安全考虑

. **重入保护**
   - 使用 ReentrancyGuard
   - 遵循 Checks-Effects-Interactions 模式

2. **权限控制**
   - 双步所有权转移
   - 细粒度权限管理

3. **紧急机制**
   - 可暂停功能
   - 紧急提取机制

4. **升级保护**
   - UUPS 升级模式
   - 严格的升级权限控制

### 8.2 安全检查清单

- [x] 数学计算溢出检查
- [x] 权限控制审查
- [x] 重入漏洞防护
- [x] 价格操纵防护
- [x] 紧急机制测试
- [x] 升级机制验证

## 9. 常见问题

### 9.1 流动性问题

Q: 如何确定首次添加流动性的比例？
A: 建议参考市场价格，确保初始价格合理。

Q: 为什么后续添加需要按比例？
A: 防止价格操纵，保护现有流动性提供者权益。

### 9.2 交易问题

Q: 如何防止滑点损失？
A: 使用 `minTokensOut`/`minEthOut` 参数设置可接受的最小输出量。

Q: 为什么要收取手续费？
A: 激励流动性提供者并补偿无常损失。

### 9.3 技术问题

Q: 如何处理代币精度不同的问题？
A: 系统会自动根据代币的 decimals 进行调整。

Q: 如何确保合约升级安全？
A: 通过严格的测试和审计流程，使用时间锁和多重签名机制。

## 10. 维护与支持

### 10.1 更新日志

- v1.0.0 (2025-02-16)
  - 初始版本发布
  - 基础 AMM 功能实现
  - 工厂合约部署

### 10.2 贡献指南

1. Fork 项目
2. 创建功能分支
3. 提交更改
4. 发起 Pull Request

### 10.3 联系方式

- GitHub Issues
- 技术支持邮箱
- 社区讨论组

## 许可证

MIT License