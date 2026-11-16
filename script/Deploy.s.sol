// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {NodeLicense} from "../src/NodeLicense.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";
import {SupportVault} from "../src/SupportVault.sol";

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

        // Placeholder tiers — confirm prices with the owner before unpausing.
        uint256[] memory caps = new uint256[](4);
        uint256[] memory prices = new uint256[](4);
        (caps[0], prices[0]) = (500, 100 * USDC_UNIT); // Founding Scouts
        (caps[1], prices[1]) = (2_000, 250 * USDC_UNIT); // Regional
        (caps[2], prices[2]) = (4_000, 500 * USDC_UNIT); // National
        (caps[3], prices[3]) = (5_000, 1_000 * USDC_UNIT); // International

        vm.startBroadcast();
        address admin = msg.sender;

        ComplianceRegistry compliance = new ComplianceRegistry(admin);
        NodeLicense nodes = new NodeLicense(admin, usdc, compliance, treasury, caps, prices, 10);
        TalentRegistry registry = new TalentRegistry(admin, nodes, compliance, 3 days, 2_000);
        SupportVault vault = new SupportVault(admin, usdc, nodes, compliance, 3 days, 2_000);

        registry.setVault(vault);
        registry.grantRole(registry.VERIFIER_ROLE(), verifier);
        vault.grantRole(vault.REGISTRY_ROLE(), address(registry));
        compliance.setExempt(address(vault), true);
        // NodeLicense stays paused until the owner approves pricing and opens the sale.
        vm.stopBroadcast();

        console2.log("ComplianceRegistry", address(compliance));
        console2.log("NodeLicense       ", address(nodes));
        console2.log("TalentRegistry    ", address(registry));
        console2.log("SupportVault      ", address(vault));
    }
}
