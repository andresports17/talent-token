// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest} from "./Base.t.sol";
import {SupportVault} from "../src/SupportVault.sol";
import {TalentToken} from "../src/TalentToken.sol";

contract SupportVaultTest is BaseTest {
    uint256 internal id;
    TalentToken internal token;

    function setUp() public override {
        super.setUp();
        (id, token) = _launchTalent(2 * USDC); // 1 supporter token = 2 USDC
    }

    function _support(address who, uint256 amount) internal returns (uint256 out) {
        vm.startPrank(who);
        usdc.approve(address(vault), type(uint256).max);
        out = vault.support(id, amount);
        vm.stopPrank();
    }

    function _assertAccounting() internal view {
        SupportVault.Pool memory p = vault.pool(id);
        assertEq(p.raised, p.released + p.pending + vault.available(id) + p.refundable);
    }

    function test_SupportGivesTokensAndEscrowsUsdc() public {
        uint256 out = _support(fan1, 100 * USDC);
        assertEq(out, 50 ether);
        assertEq(token.balanceOf(fan1), 50 ether);
        assertEq(usdc.balanceOf(address(vault)), 100 * USDC);
        assertEq(vault.available(id), 100 * USDC);
        _assertAccounting();
    }

    function test_NonCompliantSupporterReverts() public {
        vm.startPrank(outsider);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(SupportVault.NotCompliant.selector, outsider));
        vault.support(id, 10 * USDC);
        vm.stopPrank();
    }

    function test_TokenTransferToNonCompliantReverts() public {
        _support(fan1, 10 * USDC);
        vm.prank(fan1);
        vm.expectRevert(abi.encodeWithSelector(TalentToken.NotCompliant.selector, outsider));
        token.transfer(outsider, 1 ether);

        vm.prank(fan1);
        token.transfer(fan2, 1 ether);
        assertEq(token.balanceOf(fan2), 1 ether);
    }

    function test_ApprovedMilestonePaysTalent() public {
        _support(fan1, 1_000 * USDC);
        vm.prank(talentWallet);
        uint256 m = vault.proposeMilestone(id, 400 * USDC, "ipfs://training-camp-receipts");
        assertEq(vault.available(id), 600 * USDC);
        _assertAccounting();

        vm.prank(scoutA);
        vault.voteMilestone(m, _ids(1, 4), true);
        vm.warp(block.timestamp + VOTING_PERIOD);

        uint256 before = usdc.balanceOf(talentWallet);
        vault.finalizeMilestone(m);
        assertEq(usdc.balanceOf(talentWallet) - before, 400 * USDC);
        assertEq(vault.pool(id).released, 400 * USDC);
        _assertAccounting();
    }

    function test_RejectedMilestoneReturnsFundsToAvailable() public {
        _support(fan1, 1_000 * USDC);
        vm.prank(talentWallet);
        uint256 m = vault.proposeMilestone(id, 400 * USDC, "");
        vm.prank(scoutA);
        vault.voteMilestone(m, _ids(1, 4), false);
        vm.warp(block.timestamp + VOTING_PERIOD);
        vault.finalizeMilestone(m);
        assertEq(vault.available(id), 1_000 * USDC);
        assertEq(vault.pool(id).released, 0);
        _assertAccounting();
    }

    function test_CannotProposeMoreThanAvailable() public {
        _support(fan1, 100 * USDC);
        vm.prank(talentWallet);
        vm.expectRevert(SupportVault.ExceedsAvailable.selector);
        vault.proposeMilestone(id, 101 * USDC, "");
    }

    function test_OnlyTalentOrAdminCanPropose() public {
        _support(fan1, 100 * USDC);
        vm.prank(fan1);
        vm.expectRevert(SupportVault.NotAllowedToPropose.selector);
        vault.proposeMilestone(id, 10 * USDC, "");
    }

    function test_FreezeGivesProRataRefundsOfUnreleased() public {
        _support(fan1, 600 * USDC);
        _support(fan2, 400 * USDC);

        // release 500 of 1,000
        vm.prank(talentWallet);
        uint256 m = vault.proposeMilestone(id, 500 * USDC, "");
        vm.prank(scoutA);
        vault.voteMilestone(m, _ids(1, 4), true);
        vm.warp(block.timestamp + VOTING_PERIOD);
        vault.finalizeMilestone(m);

        // a second milestone is pending when the pool is frozen
        vm.prank(talentWallet);
        uint256 m2 = vault.proposeMilestone(id, 200 * USDC, "");

        vm.prank(admin);
        vault.freezePool(id);
        _assertAccounting();

        vault.finalizeMilestone(m2);
        (,,, SupportVault.MilestoneStatus status,) = vault.milestones(m2);
        assertEq(uint256(status), uint256(SupportVault.MilestoneStatus.Cancelled));

        vm.prank(fan1);
        assertEq(vault.claimRefund(id), 300 * USDC); // 600 * 500/1000
        vm.prank(fan2);
        assertEq(vault.claimRefund(id), 200 * USDC); // 400 * 500/1000
        assertEq(usdc.balanceOf(address(vault)), 0);

        vm.prank(fan1);
        vm.expectRevert(SupportVault.NothingToRefund.selector);
        vault.claimRefund(id);
    }

    function test_FrozenPoolBlocksSupport() public {
        vm.prank(admin);
        vault.freezePool(id);
        vm.startPrank(fan1);
        usdc.approve(address(vault), type(uint256).max);
        vm.expectRevert(SupportVault.PoolIsFrozen.selector);
        vault.support(id, 10 * USDC);
        vm.stopPrank();
    }

    function test_OnlyRegistryCanRegisterPool() public {
        vm.prank(admin);
        vm.expectRevert();
        vault.registerPool(99, token, talentWallet, 1 * USDC);
    }

    function testFuzz_AccountingHolds(uint96 a, uint96 b, uint96 release) public {
        uint256 amtA = bound(uint256(a), 2 * USDC, 100_000 * USDC);
        uint256 amtB = bound(uint256(b), 2 * USDC, 100_000 * USDC);
        _support(fan1, amtA);
        _support(fan2, amtB);
        uint256 rel = bound(uint256(release), 1, amtA + amtB);

        vm.prank(talentWallet);
        uint256 m = vault.proposeMilestone(id, rel, "");
        _assertAccounting();
        vm.prank(scoutA);
        vault.voteMilestone(m, _ids(1, 4), true);
        vm.warp(block.timestamp + VOTING_PERIOD);
        vault.finalizeMilestone(m);
        _assertAccounting();

        vm.prank(admin);
        vault.freezePool(id);
        _assertAccounting();

        vm.prank(fan1);
        uint256 r1 = vault.claimRefund(id);
        vm.prank(fan2);
        uint256 r2 = vault.claimRefund(id);
        // refunds never exceed what was left; rounding dust stays in the vault
        assertLe(r1 + r2, amtA + amtB - rel);
        assertLe(amtA + amtB - rel - (r1 + r2), 2);
    }
}
