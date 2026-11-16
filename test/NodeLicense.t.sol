// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest} from "./Base.t.sol";
import {NodeLicense} from "../src/NodeLicense.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract NodeLicenseTest is BaseTest {
    function test_MaxSupplyIs5000() public view {
        assertEq(nodes.MAX_SUPPLY(), 5_000);
    }

    function test_PausedAtDeploy() public {
        NodeLicense fresh = new NodeLicense(admin, usdc, compliance, treasury, START_PRICE, PRICE_STEP, STEP_SIZE, 10);
        assertTrue(fresh.paused());

        vm.startPrank(scoutA);
        usdc.approve(address(fresh), type(uint256).max);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        fresh.buy(1);
        vm.stopPrank();
    }

    function test_BuyChargesTierPriceToTreasury() public {
        uint256 before = usdc.balanceOf(treasury);
        uint256 firstId = _buyNodes(scoutA, 3);
        assertEq(firstId, 1);
        assertEq(nodes.ownerOf(3), scoutA);
        assertEq(nodes.totalMinted(), 3);
        assertEq(usdc.balanceOf(treasury) - before, 1_500 * USDC); // 3 x $500
    }

    function test_PriceCurve() public view {
        assertEq(nodes.priceOf(1), 500 * USDC);
        assertEq(nodes.priceOf(100), 500 * USDC);
        assertEq(nodes.priceOf(101), 600 * USDC);
        assertEq(nodes.priceOf(200), 600 * USDC);
        assertEq(nodes.priceOf(201), 700 * USDC);
        assertEq(nodes.priceOf(5_000), 5_400 * USDC);
    }

    function test_QuoteSpansPriceSteps() public {
        vm.prank(admin);
        nodes.setMaxPerWallet(5_000);
        _buyNodes(scoutA, 99);
        // ids 100 ($500) + 101 ($600) + 102 ($600)
        assertEq(nodes.quote(3), 1_700 * USDC);
    }

    function test_FullSellOutRaises14_75M() public view {
        assertEq(nodes.quote(5_000), 14_750_000 * USDC);
    }

    function test_CannotExceed5000() public {
        vm.prank(admin);
        nodes.setMaxPerWallet(type(uint256).max);
        // full sell-out costs 14,750,000 USDC; scoutA already holds 20M
        _buyNodes(scoutA, 5_000);
        assertEq(nodes.totalMinted(), 5_000);

        vm.startPrank(scoutB);
        usdc.approve(address(nodes), type(uint256).max);
        vm.expectRevert(NodeLicense.SoldOut.selector);
        nodes.buy(1);
        vm.stopPrank();
    }

    function test_WalletCap() public {
        _buyNodes(scoutA, 10);
        vm.prank(scoutA);
        vm.expectRevert(NodeLicense.WalletCapExceeded.selector);
        nodes.buy(1);
    }

    function test_NonCompliantBuyerReverts() public {
        vm.startPrank(outsider);
        usdc.approve(address(nodes), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(NodeLicense.NotCompliant.selector, outsider));
        nodes.buy(1);
        vm.stopPrank();
    }

    function test_ExpiredKycReverts() public {
        vm.warp(block.timestamp + 366 days);
        vm.startPrank(scoutA);
        usdc.approve(address(nodes), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(NodeLicense.NotCompliant.selector, scoutA));
        nodes.buy(1);
        vm.stopPrank();
    }

    function test_BlockedCountryReverts() public {
        vm.prank(admin);
        compliance.setCountryBlocked("US", true);
        vm.startPrank(scoutA);
        usdc.approve(address(nodes), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(NodeLicense.NotCompliant.selector, scoutA));
        nodes.buy(1);
        vm.stopPrank();
    }

    function test_TransfersLockedUntilUnlocked() public {
        _buyNodes(scoutA, 1);
        vm.prank(scoutA);
        vm.expectRevert(NodeLicense.TransfersLocked.selector);
        nodes.transferFrom(scoutA, scoutB, 1);

        vm.prank(admin);
        nodes.unlockTransfers();
        vm.prank(scoutA);
        nodes.transferFrom(scoutA, scoutB, 1);
        assertEq(nodes.ownerOf(1), scoutB);
    }

    function test_UnlockedTransferToNonCompliantReverts() public {
        _buyNodes(scoutA, 1);
        vm.prank(admin);
        nodes.unlockTransfers();
        vm.prank(scoutA);
        vm.expectRevert(abi.encodeWithSelector(NodeLicense.NotCompliant.selector, outsider));
        nodes.transferFrom(scoutA, outsider, 1);
    }

    function test_SetPricingOnlyWhilePausedAndValid() public {
        vm.prank(admin);
        vm.expectRevert(Pausable.ExpectedPause.selector);
        nodes.setPricing(250 * USDC, 50 * USDC, 100);

        vm.startPrank(admin);
        nodes.pause();
        vm.expectRevert(NodeLicense.BadPricing.selector);
        nodes.setPricing(250 * USDC, 50 * USDC, 0);
        nodes.setPricing(250 * USDC, 50 * USDC, 100);
        vm.stopPrank();
        assertEq(nodes.priceOf(101), 300 * USDC);
    }
}
