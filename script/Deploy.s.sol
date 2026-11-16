// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {NodeLicense} from "../src/NodeLicense.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";
import {SupportVault} from "../src/SupportVault.sol";
import {CoinbaseVerifier, IEAS, ICoinbaseIndexer} from "../src/identity/CoinbaseVerifier.sol";

/// @notice Base Sepolia ONLY. Mainnet needs the owner's explicit go-ahead,
///         an outside audit in audits/, and a Safe multisig as admin.
///
/// forge script script/Deploy.s.sol --rpc-url base_sepolia --account <keystore> --broadcast
contract Deploy is Script {
    uint256 internal constant BASE_SEPOLIA = 84_532;
    uint256 internal constant USDC_UNIT = 1e6;

    function run() external {
        require(block.chainid == BASE_SEPOLIA, "Base Sepolia only");

        IERC20 usdc = IERC20(vm.envAddress("USDC"));
        address treasury = vm.envAddress("TREASURY");
        address verifier = vm.envAddress("VERIFIER");

        // Coinbase Verifications (automated KYC + ID/18+). EAS is a Base predeploy.
        IEAS eas = IEAS(vm.envOr("EAS", address(0x4200000000000000000000000000000000000021)));
        ICoinbaseIndexer cbIndexer = ICoinbaseIndexer(vm.envAddress("COINBASE_INDEXER"));
        address cbAttester = vm.envAddress("COINBASE_ATTESTER");
        bytes32 accountSchema = vm.envBytes32("COINBASE_ACCOUNT_SCHEMA");
        bytes32 countrySchema = vm.envBytes32("COINBASE_COUNTRY_SCHEMA");

        vm.startBroadcast();
        address admin = msg.sender;

        ComplianceRegistry compliance = new ComplianceRegistry(admin);
        // $500 for nodes 1-100, +$100 every 100 nodes (last 100 nodes $5,400); 10 per wallet
        NodeLicense nodes =
            new NodeLicense(admin, usdc, compliance, treasury, 500 * USDC_UNIT, 100 * USDC_UNIT, 100, 10);
        TalentRegistry registry = new TalentRegistry(admin, nodes, compliance, 3 days, 2_000);
        SupportVault vault = new SupportVault(admin, usdc, nodes, compliance, 3 days, 2_000);

        registry.setVault(vault);
        registry.grantRole(registry.VERIFIER_ROLE(), verifier);
        vault.grantRole(vault.REGISTRY_ROLE(), address(registry));
        compliance.setExempt(address(vault), true);

        CoinbaseVerifier idv = new CoinbaseVerifier(eas, cbIndexer, cbAttester, accountSchema, countrySchema);
        compliance.setIdentityVerifier(idv, 30 days);
        registry.setIdentityVerifier(idv);
        // NodeLicense stays paused until the owner approves pricing and opens the sale.
        vm.stopBroadcast();

        console2.log("ComplianceRegistry", address(compliance));
        console2.log("NodeLicense       ", address(nodes));
        console2.log("TalentRegistry    ", address(registry));
        console2.log("SupportVault      ", address(vault));
        console2.log("CoinbaseVerifier  ", address(idv));
    }
}
