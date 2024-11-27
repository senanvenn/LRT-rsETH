// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.21;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProxyFactory} from "../contracts/ProxyFactory.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {RSETH} from "../contracts/RSETH.sol";
import {LRTConfig} from "../contracts/LRTConfig.sol";
import {LRTDepositPool} from "../contracts/LRTDepositPool.sol";
import {ChainlinkPriceOracle} from "../contracts/oracles/ChainlinkPriceOracle.sol";
import {LRTOracle} from "../contracts/LRTOracle.sol";
import {LRTConstants} from "../contracts/utils/LRTConstants.sol";
import {MockPriceAggregator} from "../contracts/MockPriceAggregator.sol";

contract DeployLRTScript is Script {
    // Contract instances
    ProxyFactory public proxyFactory;
    ProxyAdmin public proxyAdmin;
    MockPriceAggregator public mockPriceAggregator;
    
    // Implementation contracts
    RSETH public rsethImpl;
    LRTConfig public lrtConfigImpl;
    LRTDepositPool public depositPoolImpl;
    ChainlinkPriceOracle public chainlinkOracleImpl;
    LRTOracle public lrtOracleImpl;

    // Proxy addresses
    address public rsethProxy;
    address public lrtConfigProxy;
    address public depositPoolProxy;
    address public chainlinkOracleProxy;
    address public lrtOracleProxy;
    address public stETH = 0x3F1c547b21f65e10480dE3ad8E19fAAC46C95034;

    // Configuration addresses
    address public admin;

    function setUp() public {
        // Load single admin address from environment
        admin = vm.envAddress("ADMIN_ADDRESS");
    }

    function run() public {
        vm.startBroadcast();

        // 1. Deploy base contracts
        proxyFactory = new ProxyFactory();
        proxyAdmin = new ProxyAdmin();
        proxyAdmin.transferOwnership(admin);

        // Deploy mock price aggregator
        mockPriceAggregator = new MockPriceAggregator();

        // 2. Deploy implementations
        rsethImpl = new RSETH();
        lrtConfigImpl = new LRTConfig();
        depositPoolImpl = new LRTDepositPool();
        chainlinkOracleImpl = new ChainlinkPriceOracle();
        lrtOracleImpl = new LRTOracle();

        // 3. Deploy proxies with implementations
        bytes32 salt = bytes32(0);
        
        // Deploy RSETH (uninitialized)
        rsethProxy = proxyFactory.create(
            address(rsethImpl),
            address(proxyAdmin),
            salt
        );

        // Deploy and initialize LRTConfig
        lrtConfigProxy = proxyFactory.create(
            address(lrtConfigImpl),
            address(proxyAdmin),
            salt
        );
        LRTConfig(lrtConfigProxy).initialize(
            admin,
            stETH,
            rsethProxy
        );

        // Initialize RSETH
        RSETH(rsethProxy).initialize(
            admin,
            lrtConfigProxy
        );

        // Deploy and initialize oracles
        chainlinkOracleProxy = proxyFactory.create(
            address(chainlinkOracleImpl),
            address(proxyAdmin),
            salt
        );
        ChainlinkPriceOracle(chainlinkOracleProxy).initialize(lrtConfigProxy);

        // Deploy and initialize LRTOracle
        lrtOracleProxy = proxyFactory.create(
            address(lrtOracleImpl),
            address(proxyAdmin),
            salt
        );
        LRTOracle(lrtOracleProxy).initialize(lrtConfigProxy);

        // Deploy and initialize deposit pool
        depositPoolProxy = proxyFactory.create(
            address(depositPoolImpl),
            address(proxyAdmin),
            salt
        );
        LRTDepositPool(payable(depositPoolProxy)).initialize(lrtConfigProxy);

        // 4. Configure LRTConfig with deployed contracts
        LRTConfig config = LRTConfig(lrtConfigProxy);

        // Fix: Use MANAGER instead of MANAGER_ROLE
        config.grantRole(LRTConstants.MANAGER, admin);

        config.setContract(LRTConstants.LRT_ORACLE, lrtOracleProxy);
        config.setContract(LRTConstants.LRT_DEPOSIT_POOL, depositPoolProxy);

        // 5. Setup oracle price feeds
        ChainlinkPriceOracle(chainlinkOracleProxy).updatePriceFeedFor(
            stETH,
            address(mockPriceAggregator)
        );

        // 6. Set up roles
        // Add necessary role assignments here

        vm.stopBroadcast();

        // Log deployed addresses
        console2.log("ProxyFactory:", address(proxyFactory));
        console2.log("ProxyAdmin:", address(proxyAdmin));
        console2.log("MockPriceAggregator:", address(mockPriceAggregator));
        console2.log("RSETH Proxy:", rsethProxy);
        console2.log("LRTConfig Proxy:", lrtConfigProxy);
        console2.log("LRTOracle Proxy:", lrtOracleProxy);
        console2.log("ChainlinkPriceOracle Proxy:", chainlinkOracleProxy);
        console2.log("LRTDepositPool Proxy:", depositPoolProxy);
    }
}