// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import { UtilLib } from "./utils/UtilLib.sol";
import { LRTConstants } from "./utils/LRTConstants.sol";
import { ILRTConfig } from "./interfaces/ILRTConfig.sol";
import { IStrategy } from "./external/eigenlayer/interfaces/IStrategy.sol";
import { ILRTDepositPool } from "./interfaces/ILRTDepositPool.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ContextUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";

/// @title LRTConfig - LRT Config Contract
/// @notice Handles LRT configuration
contract LRTConfig is VennFirewallConsumer, ILRTConfig, AccessControlUpgradeable {
    mapping(bytes32 tokenKey => address tokenAddress) public tokenMap;
    mapping(bytes32 contractKey => address contractAddress) public contractMap;
    mapping(address token => bool isSupported) public isSupportedAsset;
    mapping(address token => uint256 amount) public depositLimitByAsset;
    mapping(address token => address strategy) public override assetStrategy;

    address[] public supportedAssetList;

    address public rsETH;

    modifier onlySupportedAsset(address asset) {
        if (!isSupportedAsset[asset]) {
            revert AssetNotSupported();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param admin Admin address
    /// @param stETH stETH address
    /// @param rsETH_ rsETH address
    function initialize(address admin, address stETH, address rsETH_) external initializer firewallProtected {
        UtilLib.checkNonZeroAddress(admin);
        UtilLib.checkNonZeroAddress(rsETH_);

        __AccessControl_init();
        _setToken(LRTConstants.ST_ETH_TOKEN, stETH);
        _addNewSupportedAsset(stETH, 100_000 ether);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        rsETH = rsETH_;
    
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall")) - 1), address(0));
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall.admin")) - 1), msg.sender);
	}

    /// @dev Adds a new supported asset
    /// @param asset Asset address
    /// @param depositLimit Deposit limit for the asset
    function addNewSupportedAsset(address asset, uint256 depositLimit) external onlyRole(DEFAULT_ADMIN_ROLE) firewallProtected {
        _addNewSupportedAsset(asset, depositLimit);
    }

    /// @dev private function to add a new supported asset
    /// @param asset Asset address
    /// @param depositLimit Deposit limit for the asset
    function _addNewSupportedAsset(address asset, uint256 depositLimit) private {
        UtilLib.checkNonZeroAddress(asset);
        if (isSupportedAsset[asset]) {
            revert AssetAlreadySupported();
        }
        isSupportedAsset[asset] = true;
        supportedAssetList.push(asset);
        depositLimitByAsset[asset] = depositLimit;
        emit AddedNewSupportedAsset(asset, depositLimit);
    }

    /// @dev Updates the deposit limit for an asset
    /// @param asset Asset address
    /// @param depositLimit New deposit limit
    function updateAssetDepositLimit(
        address asset,
        uint256 depositLimit
    )
        external
        onlyRole(LRTConstants.MANAGER)
        onlySupportedAsset(asset)
        firewallProtected
    {
        depositLimitByAsset[asset] = depositLimit;
        emit AssetDepositLimitUpdate(asset, depositLimit);
    }

    /// @dev Updates the strategy for an asset
    /// @param asset Asset address
    /// @param strategy New strategy address
    function updateAssetStrategy(
        address asset,
        address strategy
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        onlySupportedAsset(asset)
        firewallProtected
    {
        UtilLib.checkNonZeroAddress(strategy);
        if (assetStrategy[asset] == strategy) {
            revert ValueAlreadyInUse();
        }
        // if strategy is already set, check if it has any funds
        if (assetStrategy[asset] != address(0)) {
            // get ndcs
            address depositPool = getContract(LRTConstants.LRT_DEPOSIT_POOL);
            address[] memory ndcs = ILRTDepositPool(depositPool).getNodeDelegatorQueue();

            uint256 length = ndcs.length;
            for (uint256 i = 0; i < length;) {
                uint256 ndcBalance = IStrategy(assetStrategy[asset]).userUnderlyingView(ndcs[i]);
                if (ndcBalance > 0) {
                    revert CannotUpdateStrategyAsItHasFundsNDCFunds(ndcs[i], ndcBalance);
                }

                unchecked {
                    ++i;
                }
            }
        }

        assetStrategy[asset] = strategy;
        emit AssetStrategyUpdate(asset, strategy);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/
    function getLSTToken(bytes32 tokenKey) external view override returns (address) {
        UtilLib.checkNonZeroAddress(tokenMap[tokenKey]);
        return tokenMap[tokenKey];
    }

    function getContract(bytes32 contractKey) public view override returns (address) {
        UtilLib.checkNonZeroAddress(contractMap[contractKey]);
        return contractMap[contractKey];
    }

    function getSupportedAssetList() external view override returns (address[] memory) {
        return supportedAssetList;
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/
    /// @dev Sets the rsETH contract address. Only callable by the admin
    /// @param rsETH_ rsETH contract address
    function setRSETH(address rsETH_) external onlyRole(DEFAULT_ADMIN_ROLE) firewallProtected {
        UtilLib.checkNonZeroAddress(rsETH_);
        rsETH = rsETH_;
        emit SetRSETH(rsETH_);
    }

    function setToken(bytes32 tokenKey, address assetAddress) external onlyRole(DEFAULT_ADMIN_ROLE) firewallProtected {
        _setToken(tokenKey, assetAddress);
    }

    /// @dev private function to set a token
    /// @param key Token key
    /// @param val Token address
    function _setToken(bytes32 key, address val) private {
        UtilLib.checkNonZeroAddress(val);
        if (tokenMap[key] == val) {
            revert ValueAlreadyInUse();
        }
        tokenMap[key] = val;
        emit SetToken(key, val);
    }

    function setContract(bytes32 contractKey, address contractAddress) external onlyRole(DEFAULT_ADMIN_ROLE) firewallProtected {
        _setContract(contractKey, contractAddress);
    }

    /// @dev private function to set a contract
    /// @param key Contract key
    /// @param val Contract address
    function _setContract(bytes32 key, address val) private {
        UtilLib.checkNonZeroAddress(val);
        if (contractMap[key] == val) {
            revert ValueAlreadyInUse();
        }
        contractMap[key] = val;
        emit SetContract(key, val);
    }

    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return ContextUpgradeable._msgSender();
    }

    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return ContextUpgradeable._msgData();
    }

}
