// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {BaseTest} from "./Base.t.sol";
import {JourneyPass} from "../src/JourneyPass.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";

/// @notice Covers the Talent Journey Pass pilot acceptance criteria (numbered "AC") and the
///         project guardrails (18+, consent, no money, no personal data).
contract JourneyPassTest is BaseTest {
    JourneyPass internal jp;
    address internal passVerifier = makeAddr("passVerifier");
    uint256 internal demoId;
    bytes32 internal constant PROOF = keccak256("trial-report.pdf");

    function setUp() public override {
        super.setUp();
        jp = new JourneyPass(admin, passVerifier, registry);
        vm.prank(admin);
        demoId = jp.createDemoAthlete("Jordan Reyes (fictional)", "soccer", "ipfs://demo-profile");
    }

    function _propose(string memory title) internal returns (uint256 idx) {
        vm.prank(admin);
        idx = jp.proposeMilestone(demoId, title, "ipfs://demo-proof", PROOF);
    }

    function _verify(uint256 idx) internal {
        vm.prank(passVerifier);
        jp.verifyMilestone(demoId, idx, "Confirmed");
    }

    function _unauthorized(address who, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, who, role);
    }

    // ---------------------------------------------------------------- AC1: free claim, one per wallet

    function test_AC1_FreeClaimThenSecondClaimFails() public {
        uint256 ethBefore = outsider.balance;
        uint256 usdcBefore = usdc.balanceOf(outsider);

        vm.prank(outsider); // brand-new wallet, no KYC needed for a free pass
        uint256 id = jp.claim(demoId);
        assertEq(jp.ownerOf(id), outsider);
        assertEq(jp.passOf(demoId, outsider), id);
        assertEq(uint256(jp.pass(id).serial), 1);
        assertEq(outsider.balance, ethBefore);
        assertEq(usdc.balanceOf(outsider), usdcBefore);

        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(JourneyPass.AlreadyClaimed.selector, demoId, outsider));
        jp.claim(demoId);
    }

    function test_SerialsCountUp() public {
        vm.prank(fan1);
        jp.claim(demoId);
        vm.prank(fan2);
        uint256 id2 = jp.claim(demoId);
        assertEq(uint256(jp.pass(id2).serial), 2);
        assertEq(uint256(jp.athlete(demoId).passCount), 2);
    }

    function test_ClaimsCanBeClosed() public {
        vm.prank(fan1);
        uint256 id = jp.claim(demoId);
        vm.prank(admin);
        jp.setClaimsOpen(demoId, false);
        vm.prank(fan2);
        vm.expectRevert(abi.encodeWithSelector(JourneyPass.ClaimsClosed.selector, demoId));
        jp.claim(demoId);
        assertEq(jp.ownerOf(id), fan1);
    }

    function test_UnknownAthlete() public {
        vm.prank(fan1);
        vm.expectRevert(abi.encodeWithSelector(JourneyPass.UnknownAthlete.selector, 42));
        jp.claim(42);
    }

    // ---------------------------------------------------------------- AC2: non-transferable

    function test_AC2_PassCannotBeTransferred() public {
        vm.startPrank(fan1);
        uint256 id = jp.claim(demoId);
        vm.expectRevert(JourneyPass.Soulbound.selector);
        jp.transferFrom(fan1, fan2, id);
        vm.expectRevert(JourneyPass.Soulbound.selector);
        jp.safeTransferFrom(fan1, fan2, id);
        jp.approve(fan2, id);
        vm.stopPrank();

        vm.prank(fan2);
        vm.expectRevert(JourneyPass.Soulbound.selector);
        jp.transferFrom(fan1, fan2, id);
        assertTrue(jp.locked(id));
        assertTrue(jp.supportsInterface(0xb45a3c0e)); // ERC-5192
    }

    // ---------------------------------------------------------------- AC3: roles

    function test_AC3_OnlyAdminProposes() public {
        bytes32 role = jp.DEFAULT_ADMIN_ROLE();
        vm.prank(passVerifier);
        vm.expectRevert(_unauthorized(passVerifier, role));
        jp.proposeMilestone(demoId, "x", "ipfs://x", PROOF);
    }

    function test_AC3_OnlyVerifierVerifiesOrRejects() public {
        uint256 idx = _propose("Selected for U-21 trial");
        bytes32 role = jp.VERIFIER_ROLE();

        vm.prank(admin);
        vm.expectRevert(_unauthorized(admin, role));
        jp.verifyMilestone(demoId, idx, "self-approve");

        vm.prank(admin);
        vm.expectRevert(_unauthorized(admin, role));
        jp.rejectMilestone(demoId, idx, "nope");

        _verify(idx);
        assertEq(uint256(jp.milestone(demoId, idx).status), uint256(JourneyPass.MilestoneStatus.Verified));
    }

    function test_VerifierCannotCreateProfilesOrEditThem() public {
        bytes32 role = jp.DEFAULT_ADMIN_ROLE();
        vm.startPrank(passVerifier);
        vm.expectRevert(_unauthorized(passVerifier, role));
        jp.createDemoAthlete("x", "y", "z");
        vm.expectRevert(_unauthorized(passVerifier, role));
        jp.updateProfile(demoId, "ipfs://hijack");
        vm.stopPrank();
    }

    function test_RejectFlowAndNoDoubleDecision() public {
        uint256 idx = _propose("Claimed hat-trick");
        vm.prank(passVerifier);
        jp.rejectMilestone(demoId, idx, "Match report does not match");

        JourneyPass.Milestone memory m = jp.milestone(demoId, idx);
        assertEq(uint256(m.status), uint256(JourneyPass.MilestoneStatus.Rejected));
        assertEq(m.note, "Match report does not match");
        assertGt(uint256(m.decidedAt), 0);

        vm.prank(passVerifier);
        vm.expectRevert(abi.encodeWithSelector(JourneyPass.NotProposed.selector, idx));
        jp.verifyMilestone(demoId, idx, "changed my mind");
    }

    function test_UnknownMilestone() public {
        vm.prank(passVerifier);
        vm.expectRevert(abi.encodeWithSelector(JourneyPass.UnknownMilestone.selector, 0));
        jp.verifyMilestone(demoId, 0, "");
    }

    function test_ProposalNeedsTitleAndProof() public {
        vm.startPrank(admin);
        vm.expectRevert(JourneyPass.BadText.selector);
        jp.proposeMilestone(demoId, "", "ipfs://x", PROOF);
        vm.expectRevert(JourneyPass.MissingProof.selector);
        jp.proposeMilestone(demoId, "No proof", "", bytes32(0));
        vm.expectRevert(JourneyPass.BadText.selector);
        jp.proposeMilestone(demoId, 'Bad "quote"', "ipfs://x", PROOF);
        // a hash alone is enough
        jp.proposeMilestone(demoId, "Hash only", "", PROOF);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- AC4: data the web page reads

    function test_AC4_TimelineDataMatchesStatuses() public {
        uint256 a = _propose("Joined regional squad");
        uint256 b = _propose("Signed academy contract");
        _propose("First professional appearance");
        _verify(a);
        vm.prank(passVerifier);
        jp.rejectMilestone(demoId, b, "Unsigned copy");

        JourneyPass.Milestone[] memory list = jp.milestones(demoId);
        assertEq(list.length, 3);
        assertEq(uint256(list[0].status), uint256(JourneyPass.MilestoneStatus.Verified));
        assertEq(uint256(list[1].status), uint256(JourneyPass.MilestoneStatus.Rejected));
        assertEq(uint256(list[2].status), uint256(JourneyPass.MilestoneStatus.Proposed));
        assertEq(list[0].proofHash, PROOF);
        assertEq(uint256(jp.athlete(demoId).verifiedCount), 1);
    }

    function test_WitnessedCountsOnlyLaterVerifiedMilestones() public {
        _verify(_propose("Before claim"));
        vm.prank(fan1);
        uint256 early = jp.claim(demoId);
        _verify(_propose("After first claim"));
        vm.prank(fan2);
        uint256 late = jp.claim(demoId);
        _verify(_propose("After both"));
        _propose("Still pending"); // proposed only: not counted

        assertEq(jp.milestonesWitnessed(early), 2);
        assertEq(jp.milestonesWitnessed(late), 1);
    }

    function test_TokenURIIsOnChainJson() public {
        vm.prank(fan1);
        uint256 id = jp.claim(demoId);
        bytes memory uri = bytes(jp.tokenURI(id));
        bytes memory prefix = bytes("data:application/json;base64,");
        for (uint256 i; i < prefix.length; ++i) {
            assertEq(uint256(uint8(uri[i])), uint256(uint8(prefix[i])));
        }
    }

    // ---------------------------------------------------------------- AC5: no money in

    function test_AC5_NoFunctionAcceptsMoney() public {
        vm.deal(fan1, 1 ether);
        vm.prank(fan1);
        (bool ok,) = address(jp).call{value: 1 wei}(abi.encodeCall(JourneyPass.claim, (demoId)));
        assertFalse(ok, "claim must not be payable");

        vm.prank(fan1);
        (ok,) = address(jp).call{value: 1 wei}("");
        assertFalse(ok, "contract must not accept ETH");
        assertEq(address(jp).balance, 0);
        assertEq(usdc.balanceOf(address(jp)), 0);
    }

    // ---------------------------------------------------------------- guardrails: real athletes

    function test_RealProfileNeedsLaunchedTalent() public {
        _seedScouts();
        vm.prank(scoutA);
        uint256 pending = registry.nominate(fan1, 1, "soccer", "local", "ipfs://pending");
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(JourneyPass.TalentNotLaunched.selector, pending));
        jp.createAthleteFromRegistry(pending, "Real Player", "soccer", "ipfs://p");
    }

    function test_RealProfileAfterVoteIdCheckAndConsent() public {
        (uint256 talentId,) = _launchTalent(1 * USDC);
        assertEq(uint256(registry.talent(talentId).status), uint256(TalentRegistry.Status.Launched));

        vm.startPrank(admin);
        uint256 id = jp.createAthleteFromRegistry(talentId, "Verified Talent", "soccer", "ipfs://p");
        vm.expectRevert(abi.encodeWithSelector(JourneyPass.ProfileExists.selector, talentId));
        jp.createAthleteFromRegistry(talentId, "Again", "soccer", "ipfs://p");
        vm.stopPrank();

        assertFalse(jp.athlete(id).demo);
        assertEq(jp.athleteIdOfTalent(talentId), id);
    }

    function test_DemoOnlyDeploymentCannotCreateRealProfiles() public {
        JourneyPass demoOnly = new JourneyPass(admin, passVerifier, TalentRegistry(address(0)));
        vm.prank(admin);
        vm.expectRevert(JourneyPass.NoRegistry.selector);
        demoOnly.createAthleteFromRegistry(1, "x", "y", "z");
    }

    /// @notice The whole pilot story end to end. Reproduce with: forge test --mt test_PilotDemo -vv
    function test_PilotDemo_FictionalAthleteJourney() public {
        address supporter = makeAddr("demoSupporter");
        assertTrue(jp.athlete(demoId).demo);

        vm.prank(supporter);
        uint256 id = jp.claim(demoId);

        uint256 idx = _propose("Selected for U-21 trial");
        assertEq(uint256(jp.milestone(demoId, idx).status), uint256(JourneyPass.MilestoneStatus.Proposed));
        _verify(idx);

        assertEq(jp.ownerOf(id), supporter);
        assertEq(jp.milestonesWitnessed(id), 1);
    }
}
