// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import { UtilLib } from "./utils/UtilLib.sol";
import { LRTConstants } from "./utils/LRTConstants.sol";
import { LRTConfigRoleChecker, ILRTConfig } from "./utils/LRTConfigRoleChecker.sol";

import { IRSETH } from "./interfaces/IRSETH.sol";
import { IPriceFetcher } from "./interfaces/IPriceFetcher.sol";
import { ILRTOracle } from "./interfaces/ILRTOracle.sol";
import { ILRTDepositPool } from "./interfaces/ILRTDepositPool.sol";

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title LRTOracle Contract
/// @notice oracle contract that calculates the exchange rate of assets
contract LRTOracle is VennFirewallConsumer, ILRTOracle, LRTConfigRoleChecker, Initializable {
    mapping(address asset => address priceOracle) public override assetPriceOracle;

    uint256 public override rsETHPrice;
    uint256 public pricePercentageLimit;

    modifier onlySupportedOracle(address asset) {
        if (assetPriceOracle[asset] == address(0)) {
            revert AssetOracleNotSupported();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    /// @param lrtConfigAddr LRT config address
    function initialize(address lrtConfigAddr) external initializer firewallProtected {
        UtilLib.checkNonZeroAddress(lrtConfigAddr);

        lrtConfig = ILRTConfig(lrtConfigAddr);
        emit UpdatedLRTConfig(lrtConfigAddr);
    
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall")) - 1), address(0));
		_setAddressBySlot(bytes32(uint256(keccak256("eip1967.firewall.admin")) - 1), msg.sender);
	}

    /*//////////////////////////////////////////////////////////////
                            write functions
    //////////////////////////////////////////////////////////////*/

    /// @notice updates RSETH/ETH exchange rate
    /// @dev calculates based on stakedAsset value received from eigen layer
    function updateRSETHPrice() external firewallProtected {
        uint256 oldRsETHPrice = rsETHPrice;
        address rsETHTokenAddress = lrtConfig.rsETH();
        uint256 rsEthSupply = IRSETH(rsETHTokenAddress).totalSupply();

        if (rsEthSupply == 0) {
            rsETHPrice = 1 ether;
            return;
        }

        uint256 totalETHInPool;
        address lrtDepositPoolAddr = lrtConfig.getContract(LRTConstants.LRT_DEPOSIT_POOL);

        address[] memory supportedAssets = lrtConfig.getSupportedAssetList();
        uint256 supportedAssetCount = supportedAssets.length;

        for (uint16 asset_idx; asset_idx < supportedAssetCount;) {
            address asset = supportedAssets[asset_idx];
            uint256 assetER = getAssetPrice(asset);

            uint256 totalAssetAmt = ILRTDepositPool(lrtDepositPoolAddr).getTotalAssetDeposits(asset);
            totalETHInPool += totalAssetAmt * assetER;

            unchecked {
                ++asset_idx;
            }
        }

        rsETHPrice = totalETHInPool / rsEthSupply;

        if (_isNewPriceOffLimit(oldRsETHPrice, rsETHPrice)) revert RSETHPriceExceedsLimit();

        emit RsETHPriceUpdate(rsETHPrice);
    }

    /// @dev add/update the price oracle of any asset
    /// @dev only onlyLRTAdmin is allowed
    /// @param asset asset address for which oracle price needs to be added/updated
    function updatePriceOracleFor(address asset, address priceOracle) external onlyLRTAdmin firewallProtected {
        UtilLib.checkNonZeroAddress(priceOracle);
        assetPriceOracle[asset] = priceOracle;
        emit AssetPriceOracleUpdate(asset, priceOracle);
    }

    /// @dev set the price percentage limit
    /// @dev only onlyLRTAdmin is allowed
    /// @param _pricePercentageLimit price percentage limit
    function setPricePercentageLimit(uint256 _pricePercentageLimit) external onlyLRTAdmin firewallProtected {
        pricePercentageLimit = _pricePercentageLimit;
        emit PricePercentageLimitUpdate(_pricePercentageLimit);
    }

    /*//////////////////////////////////////////////////////////////
                            view functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Provides Asset/ETH exchange rate
    /// @dev reads from priceFetcher interface which may fetch price from any supported oracle
    /// @param asset the asset for which exchange rate is required
    /// @return assetPrice exchange rate of asset
    function getAssetPrice(address asset) public view onlySupportedOracle(asset) returns (uint256) {
        return IPriceFetcher(assetPriceOracle[asset]).getAssetPrice(asset);
    }

    /*//////////////////////////////////////////////////////////////
                            private functions
    //////////////////////////////////////////////////////////////*/

    /// @notice check if new price is off the price percentage limit
    /// @param oldPrice old price
    /// @param newPrice new price
    function _isNewPriceOffLimit(uint256 oldPrice, uint256 newPrice) private view returns (bool) {
        // if oldPrice == newPrice, then no need to check
        if (oldPrice == newPrice) return false;
        // if pricePercentageLimit is 0, then no need to check
        if (pricePercentageLimit == 0) return false;

        // calculate the difference between old and new price
        uint256 diff = (oldPrice > newPrice) ? oldPrice - newPrice : newPrice - oldPrice;
        uint256 percentage = (diff * 100) / oldPrice;
        return percentage > pricePercentageLimit;
    }
}
