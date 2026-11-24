// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";
import {JourneyPass} from "../src/JourneyPass.sol";

/// @notice Talent Journey Pass pilot — Base Sepolia ONLY. Test data, fictional athlete, no money.
///
///   VERIFIER=0x... forge script script/DeployJourneyDemo.s.sol \
///     --rpc-url base_sepolia --account <keystore> --broadcast
///
/// Optional env: REGISTRY (link to the main TalentRegistry; leave unset for a demo-only deploy).
/// The deployer becomes admin. VERIFIER must be a DIFFERENT wallet: only it can verify/reject.
contract DeployJourneyDemo is Script {
    uint256 internal constant BASE_SEPOLIA = 84_532;

    function run() external returns (JourneyPass jp, uint256 athleteId) {
        require(block.chainid == BASE_SEPOLIA, "Base Sepolia only");
        address verifier = vm.envAddress("VERIFIER");
        TalentRegistry registry = TalentRegistry(vm.envOr("REGISTRY", address(0)));

        vm.startBroadcast();
        require(verifier != msg.sender, "verifier must differ from admin");
        jp = new JourneyPass(msg.sender, verifier, registry);

        athleteId = jp.createDemoAthlete("Jordan Reyes (fictional)", "soccer", "ipfs://demo/jordan-reyes.json");
        jp.proposeMilestone(athleteId, "Joined regional development squad", "ipfs://demo/proof-1.json", keccak256("demo-proof-1"));
        jp.proposeMilestone(athleteId, "Selected for U-21 trial", "ipfs://demo/proof-2.json", keccak256("demo-proof-2"));
        jp.proposeMilestone(athleteId, "Signed academy contract", "ipfs://demo/proof-3.json", keccak256("demo-proof-3"));
        vm.stopBroadcast();

        console2.log("JourneyPass ", address(jp));
        console2.log("Admin       ", msg.sender);
        console2.log("Verifier    ", verifier);
        console2.log("Demo athlete", athleteId);
    }
}
