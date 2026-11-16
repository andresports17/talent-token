// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest} from "./Base.t.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";
import {NodeVoting} from "../src/NodeVoting.sol";
import {TalentToken} from "../src/TalentToken.sol";

contract TalentRegistryTest is BaseTest {
    function _nominate() internal returns (uint256 id) {
        _seedScouts();
        vm.prank(scoutA);
        id = registry.nominate(talentWallet, 1, "soccer", "international", "ipfs://kda");
    }

    function test_FullFlowLaunchesToken() public {
        (uint256 id, TalentToken token) = _launchTalent(1 * USDC);
        TalentRegistry.Talent memory t = registry.talent(id);
        assertEq(uint256(t.status), uint256(TalentRegistry.Status.Launched));
        assertEq(t.token, address(token));
        assertEq(token.totalSupply(), 1_000_000 ether);
        assertEq(token.balanceOf(address(vault)), 1_000_000 ether);
        assertEq(token.talentId(), id);
    }

    function test_OnlyNodeHolderCanNominate() public {
        _seedScouts();
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(NodeVoting.NotNodeOwner.selector, 1));
        registry.nominate(talentWallet, 1, "soccer", "local", "");
    }

    function test_CannotNominateSameWalletTwice() public {
        _nominate();
        vm.prank(scoutB);
        vm.expectRevert(abi.encodeWithSelector(TalentRegistry.AlreadyNominated.selector, talentWallet));
        registry.nominate(talentWallet, 5, "soccer", "local", "");
    }

    function test_NodeCannotVoteTwice() public {
        uint256 id = _nominate();
        vm.startPrank(scoutA);
        registry.vote(id, _ids(1, 2), true);
        vm.expectRevert(abi.encodeWithSelector(NodeVoting.NodeAlreadyVoted.selector, 1));
        registry.vote(id, _ids(1, 1), false);
        vm.stopPrank();
    }

    function test_CannotVoteWithSomeoneElsesNode() public {
        uint256 id = _nominate();
        vm.prank(scoutB);
        vm.expectRevert(abi.encodeWithSelector(NodeVoting.NotNodeOwner.selector, 1));
        registry.vote(id, _ids(1, 1), true);
    }

    function test_NodeMintedAfterBallotCannotVote() public {
        uint256 id = _nominate();
        uint256 newId = _buyNodes(fan1, 1); // node 11, after snapshot of 10
        vm.prank(fan1);
        vm.expectRevert(abi.encodeWithSelector(NodeVoting.NodeNotEligible.selector, newId));
        registry.vote(id, _ids(newId, 1), true);
    }

    function test_CannotVoteAfterDeadline() public {
        uint256 id = _nominate();
        vm.warp(block.timestamp + VOTING_PERIOD);
        vm.prank(scoutA);
        vm.expectRevert(NodeVoting.VotingClosed.selector);
        registry.vote(id, _ids(1, 1), true);
    }

    function test_CannotFinalizeEarly() public {
        uint256 id = _nominate();
        vm.expectRevert(NodeVoting.VotingStillOpen.selector);
        registry.finalizeNomination(id);
    }

    function test_NoQuorumRejectsAndFreesWallet() public {
        uint256 id = _nominate();
        vm.prank(scoutA);
        registry.vote(id, _ids(1, 1), true); // 1 of 10 = 10% < 20% quorum
        vm.warp(block.timestamp + VOTING_PERIOD);
        registry.finalizeNomination(id);
        assertEq(uint256(registry.talent(id).status), uint256(TalentRegistry.Status.Rejected));
        assertEq(registry.talentIdOf(talentWallet), 0);
    }

    function test_MajorityNoRejects() public {
        uint256 id = _nominate();
        vm.prank(scoutA);
        registry.vote(id, _ids(1, 4), false);
        vm.prank(scoutB);
        registry.vote(id, _ids(5, 3), true);
        vm.warp(block.timestamp + VOTING_PERIOD);
        registry.finalizeNomination(id);
        assertEq(uint256(registry.talent(id).status), uint256(TalentRegistry.Status.Rejected));
    }

    function _approved() internal returns (uint256 id) {
        id = _nominate();
        vm.prank(scoutA);
        registry.vote(id, _ids(1, 4), true);
        vm.warp(block.timestamp + VOTING_PERIOD);
        registry.finalizeNomination(id);
    }

    function test_MinorIsNeverTokenized() public {
        uint256 id = _approved();
        vm.prank(verifier);
        vm.expectRevert(TalentRegistry.TalentIsMinor.selector);
        registry.verifyIdentity(id, keccak256("x"), false);
    }

    function test_OnlyVerifierCanVerify() public {
        uint256 id = _approved();
        vm.prank(scoutA);
        vm.expectRevert();
        registry.verifyIdentity(id, keccak256("x"), true);
    }

    function test_OnlyTalentCanConsent() public {
        uint256 id = _approved();
        vm.prank(verifier);
        registry.verifyIdentity(id, keccak256("x"), true);
        vm.prank(scoutA);
        vm.expectRevert(TalentRegistry.NotTalentWallet.selector);
        registry.consent(id);
    }

    function test_CannotLaunchWithoutConsent() public {
        uint256 id = _approved();
        vm.prank(verifier);
        registry.verifyIdentity(id, keccak256("x"), true);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                TalentRegistry.WrongStatus.selector, TalentRegistry.Status.Consented, TalentRegistry.Status.Verified
            )
        );
        registry.launch(id, "X", "X", 1 ether, 1 * USDC);
    }
}
