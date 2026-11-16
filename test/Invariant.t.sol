// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {BaseTest} from "./Base.t.sol";
import {NodeLicense} from "../src/NodeLicense.sol";

/// @dev Random buyers hammer the node sale; supply must never pass 5,000.
contract NodeBuyHandler is CommonBase, StdUtils {
    NodeLicense internal target;
    address[] internal buyers;

    constructor(NodeLicense target_, address[] memory buyers_) {
        target = target_;
        buyers = buyers_;
    }

    function buy(uint256 who, uint256 qty) external {
        address b = buyers[who % buyers.length];
        qty = bound(qty, 1, 50);
        vm.prank(b);
        try target.buy(qty) {}
        catch {}
    }
}

contract NodeSupplyInvariantTest is BaseTest {
    NodeBuyHandler internal handler;

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        nodes.setMaxPerWallet(type(uint256).max);

        address[] memory buyers = new address[](3);
        (buyers[0], buyers[1], buyers[2]) = (scoutA, scoutB, scoutC);
        for (uint256 i; i < 3; ++i) {
            usdc.mint(buyers[i], 3_000_000 * USDC);
            vm.prank(buyers[i]);
            usdc.approve(address(nodes), type(uint256).max);
        }
        handler = new NodeBuyHandler(nodes, buyers);
        targetContract(address(handler));
    }

    function invariant_NodesNeverExceed5000() public view {
        assertLe(nodes.totalMinted(), 5_000);
    }
}
