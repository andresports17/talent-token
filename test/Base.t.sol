// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {NodeLicense} from "../src/NodeLicense.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";
import {SupportVault} from "../src/SupportVault.sol";
import {TalentToken} from "../src/TalentToken.sol";

abstract contract BaseTest is Test {
    uint256 internal constant USDC = 1e6;
    uint256 internal constant VOTING_PERIOD = 3 days;
    uint256 internal constant QUORUM_BPS = 2_000; // 20% of nodes must vote
    uint256 internal constant START_PRICE = 500 * USDC;
    uint256 internal constant PRICE_STEP = 100 * USDC;
    uint256 internal constant STEP_SIZE = 100;

    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal verifier = makeAddr("verifier");
    address internal scoutA = makeAddr("scoutA");
    address internal scoutB = makeAddr("scoutB");
    address internal scoutC = makeAddr("scoutC");
    address internal talentWallet = makeAddr("talent");
    address internal fan1 = makeAddr("fan1");
    address internal fan2 = makeAddr("fan2");
    address internal outsider = makeAddr("outsider");

    MockUSDC internal usdc;
    ComplianceRegistry internal compliance;
    NodeLicense internal nodes;
    TalentRegistry internal registry;
    SupportVault internal vault;

    function setUp() public virtual {
        usdc = new MockUSDC();
        compliance = new ComplianceRegistry(admin);

        // $500 for nodes 1-100, +$100 every 100 nodes
        nodes = new NodeLicense(admin, usdc, compliance, treasury, START_PRICE, PRICE_STEP, STEP_SIZE, 10);
        registry = new TalentRegistry(admin, nodes, compliance, VOTING_PERIOD, QUORUM_BPS);
        vault = new SupportVault(admin, usdc, nodes, compliance, VOTING_PERIOD, QUORUM_BPS);

        vm.startPrank(admin);
        registry.setVault(vault);
        registry.grantRole(registry.VERIFIER_ROLE(), verifier);
        vault.grantRole(vault.REGISTRY_ROLE(), address(registry));
        compliance.setExempt(address(vault), true);
        nodes.unpause();
        vm.stopPrank();

        address[7] memory kyc = [scoutA, scoutB, scoutC, talentWallet, fan1, fan2, treasury];
        for (uint256 i; i < kyc.length; ++i) {
            _kyc(kyc[i]);
            usdc.mint(kyc[i], 20_000_000 * USDC);
        }
        usdc.mint(outsider, 1_000_000 * USDC);
    }

    function _kyc(address who) internal {
        vm.prank(admin);
        compliance.approve(who, "US", uint64(block.timestamp + 365 days));
    }

    function _buyNodes(address who, uint256 qty) internal returns (uint256 firstId) {
        vm.startPrank(who);
        usdc.approve(address(nodes), type(uint256).max);
        firstId = nodes.buy(qty);
        vm.stopPrank();
    }

    function _ids(uint256 first, uint256 count) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = first + i;
        }
    }

    /// @dev scoutA owns nodes 1-4, scoutB 5-7, scoutC 8-10.
    function _seedScouts() internal {
        _buyNodes(scoutA, 4);
        _buyNodes(scoutB, 3);
        _buyNodes(scoutC, 3);
    }

    /// @dev Runs a talent all the way to a launched pool. Returns talent id and token.
    function _launchTalent(uint256 priceUSDC) internal returns (uint256 id, TalentToken token) {
        _seedScouts();
        vm.prank(scoutA);
        id = registry.nominate(talentWallet, 1, "soccer", "international", "ipfs://king-david-andre");

        vm.prank(scoutA);
        registry.vote(id, _ids(1, 4), true);
        vm.prank(scoutB);
        registry.vote(id, _ids(5, 3), true);

        vm.warp(block.timestamp + VOTING_PERIOD);
        registry.finalizeNomination(id);

        vm.prank(verifier);
        registry.verifyIdentity(id, keccak256("id-check-001"), true);
        vm.prank(talentWallet);
        registry.consent(id);

        vm.prank(admin);
        token = TalentToken(registry.launch(id, "King David Andre Supporter", "KDA", 1_000_000 ether, priceUSDC));
    }
}
