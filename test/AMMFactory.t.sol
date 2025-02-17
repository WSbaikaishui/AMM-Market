// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {AMMFactory} from "../src/core/AMMFactory.sol";
import {AMM} from "../src/core/AMM.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "forge-std/console.sol";
import {Vm} from "forge-std/Vm.sol";

contract AMMFactoryTest is Test {
    AMMFactory public factory;
    MockERC20 public token1;
    MockERC20 public token2;
    
    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    
    // 设置手续费为 0.3%
    uint256 public constant FEE_NUMERATOR = 997;
    uint256 public constant FEE_DENOMINATOR = 1000;

    event AMMCreated(address indexed tokenAddress, address ammAddress);
    event AMMUpgraded(
        address indexed tokenAddress, 
        address indexed ammAddress, 
        address indexed newImplementation
    );

    function setUp() public {
        vm.startPrank(owner);
        // 部署 AMMFactory 实现合约，然后以 ERC1967Proxy 方式部署工厂
        AMMFactory factoryImpl = new AMMFactory();
        bytes memory initData = abi.encodeWithSelector(AMMFactory.initialize.selector);
        ERC1967Proxy factoryProxy = new ERC1967Proxy(address(factoryImpl), initData);
        factory = AMMFactory(address(factoryProxy));
        
        // 部署 AMM 实现合约并设置到 factory
        AMM ammImpl = new AMM();
        factory.setAMMImplementation(address(ammImpl));
        console.log("AMM global implementation:", address(ammImpl));
        vm.stopPrank();
        
        token1 = new MockERC20("Test Token 1", "TEST1");
        token2 = new MockERC20("Test Token 2", "TEST2");
    }

    function test_InitialState() public view {
        assertEq(factory.owner(), owner);
        assertTrue(!factory.paused());
    }

    function test_CreateAMM() public {
        vm.startPrank(owner);
        
        // 创建 AMM（任何人均可调用）
        address payable ammAddress = payable(factory.createAMM(
            address(token1),
            FEE_NUMERATOR,
            FEE_DENOMINATOR
        ));
        // 因为 AMM 采用 Ownable2Step（或 UUPS 模式），需要调用 acceptOwnership 完成所有权转移
        AMM(ammAddress).acceptOwnership();
        
        // Verify AMM 创建后在 Factory 中的记录
        assertEq(factory.ammContracts(address(token1)), ammAddress);
        assertEq(factory.getAMM(address(token1)), ammAddress);
        
        // Verify AMM 的初始化状态
        AMM amm = AMM(payable(ammAddress));
        assertEq(address(amm.token()), address(token1));
        assertEq(amm.feeNumerator(), FEE_NUMERATOR);
        assertEq(amm.feeDenominator(), FEE_DENOMINATOR);
        // AMM 拥有者应为创建者
        assertEq(amm.owner(), owner);
        
        vm.stopPrank();
    }

    function test_CreateMultipleAMMs() public {
        vm.startPrank(owner);
        
        address amm1 = factory.createAMM(
            address(token1),
            FEE_NUMERATOR,
            FEE_DENOMINATOR
        );
        
        address amm2 = factory.createAMM(
            address(token2),
            FEE_NUMERATOR,
            FEE_DENOMINATOR
        );
        vm.stopPrank();

        // 验证两个AMM都创建成功且地址不同
        assertTrue(amm1 != amm2);
        assertEq(factory.getAMM(address(token1)), amm1);
        assertEq(factory.getAMM(address(token2)), amm2);
    }

    function test_CannotCreateDuplicateAMM() public {
        vm.startPrank(owner);
        
        factory.createAMM(
            address(token1),
            FEE_NUMERATOR,
            FEE_DENOMINATOR
        );
        
        vm.expectRevert("AMM already exists for this token");
        factory.createAMM(
            address(token1),
            FEE_NUMERATOR,
            FEE_DENOMINATOR
        );
        vm.stopPrank();
    }

    function test_PauseAndUnpause() public {
        // 测试暂停功能
        vm.prank(owner);
        factory.pause();
        assertTrue(factory.paused());
        
        // 暂停状态下不能创建AMM
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector)
        );
        factory.createAMM(
            address(token1),
            FEE_NUMERATOR,
            FEE_DENOMINATOR
        );

        // 测试解除暂停
        vm.prank(owner);
        factory.unpause();
        assertTrue(!factory.paused());
        
        // 解除暂停后可以创建AMM
        vm.prank(owner);
        address payable ammAddress = payable(factory.createAMM(
            address(token1),
            FEE_NUMERATOR,
            FEE_DENOMINATOR
        ));
        assertTrue(ammAddress != address(0));
    }

    function test_OnlyOwnerCanPauseUnpause() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        factory.pause();

        vm.prank(owner);
        factory.pause();

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUpgradeable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        factory.unpause();
    }

    function test_GetNonExistentAMM() public view {
        assertEq(factory.getAMM(address(token1)), address(0));
    }

} 