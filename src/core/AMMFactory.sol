// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AMM} from "../core/AMM.sol";
import {IAMMFactory} from "../interfaces/IAMMFactory.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/console.sol";

/**
 * @title AMMFactory
 * @dev Factory contract for deploying and managing AMM proxy instances.
 *
 * This contract uses a global AMM implementation to deploy proxy contracts for each token,
 * and records the deployed AMM proxy addresses. It also provides functions to update the global
 * implementation, pause/unpause the factory, and supports UUPS upgradeability.
 */
contract AMMFactory is IAMMFactory, UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable {
    // Global AMM implementation used for deploying AMM proxies
    address public ammImplementation;

    // Mapping from token address to its corresponding AMM proxy contract address
    mapping(address => address) public ammContracts;

    /**
     * @dev Initialization function (replaces constructor).
     *
     * Initializes context, ownership (including two-step ownable),
     * the pausable module, and UUPS upgradeable module.
     * Deploys the global AMM implementation only once.
     */
    function initialize() public initializer {
        __Context_init();
        __Ownable_init(_msgSender());
        __Ownable2Step_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        ammImplementation = address(new AMM());
        console.log("AMM global implementation:", ammImplementation);
    }

    /**
     * @dev Creates a new AMM proxy instance.
     * @param tokenAddr The ERC20 token address paired with ETH.
     * @param feeNumerator The fee numerator (e.g., 997).
     * @param feeDenom The fee denominator (e.g., 1000).
     * @return ammAddress The deployed AMM proxy address.
     */
    function createAMM(
        address tokenAddr,
        uint256 feeNumerator,
        uint256 feeDenom
    ) external override whenNotPaused returns (address ammAddress) {
        require(ammContracts[tokenAddr] == address(0), "AMM already exists for this token");

        // Encode initialization data for the new AMM proxy
        bytes memory initializer = abi.encodeWithSelector(
            AMM.initialize.selector,
            tokenAddr,
            feeNumerator,
            feeDenom
        );

        // Deploy a new proxy using the global AMM implementation
        ERC1967Proxy proxy = new ERC1967Proxy(
            ammImplementation,
            initializer
        );
        // Cast the proxy address to type AMM (payable)
        AMM amm = AMM(payable(address(proxy)));
        // Transfer ownership of the deployed AMM proxy to the caller
        amm.transferOwnership(msg.sender);

        ammAddress = address(amm);
        ammContracts[tokenAddr] = ammAddress;

        emit AMMCreated(tokenAddr, ammAddress);
        return ammAddress;
    }

    /**
     * @dev Retrieves the AMM contract address for the specified token.
     * @param tokenAddr The ERC20 token address.
     * @return The corresponding AMM proxy contract address.
     */
    function getAMM(address tokenAddr) external view returns (address) {
        return ammContracts[tokenAddr];
    }

    /**
     * @dev Updates the global AMM implementation address.
     *      Only callable by the contract owner.
     * @param newImplementation The new AMM implementation address.
     */
    function setAMMImplementation(address newImplementation) 
        external 
        onlyOwner 
    {
        require(newImplementation != address(0), "Invalid implementation address");
        ammImplementation = newImplementation;
    }
    
    /**
     * @dev Authorization hook for UUPS upgrades.
     *      Only the contract owner can perform upgrades.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /**
     * @dev Pauses the contract; only the owner may call this function.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract; only the owner may call this function.
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
