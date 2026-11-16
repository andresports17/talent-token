// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest} from "./Base.t.sol";
import {MockEAS, MockIndexer} from "./mocks/MockCoinbase.sol";
import {CoinbaseVerifier} from "../src/identity/CoinbaseVerifier.sol";
import {ComplianceRegistry} from "../src/ComplianceRegistry.sol";
import {TalentRegistry} from "../src/TalentRegistry.sol";

contract IdentityTest is BaseTest {
    bytes32 internal constant ACCOUNT = keccak256("coinbase.verified.account");
    bytes32 internal constant COUNTRY = keccak256("coinbase.verified.country");

    address internal cbAttester = makeAddr("coinbaseAttester");
    address internal newFan = makeAddr("newFan");

    MockEAS internal eas;
    MockIndexer internal indexer;
    CoinbaseVerifier internal verifierC;

    function setUp() public override {
        super.setUp();
        eas = new MockEAS();
        indexer = new MockIndexer();
        verifierC = new CoinbaseVerifier(eas, indexer, cbAttester, ACCOUNT, COUNTRY);
        vm.startPrank(admin);
        compliance.setIdentityVerifier(verifierC, 30 days);
        registry.setIdentityVerifier(verifierC);
        vm.stopPrank();
    }

    function _credential(address who, address attester, bytes32 schema, bytes memory data)
        internal
        returns (bytes32 uid)
    {
        uid = eas.attest(attester, who, schema, 0, data);
        indexer.index(who, schema, uid);
    }

    function _coinbaseVerify(address who, string memory country) internal {
        _credential(who, cbAttester, ACCOUNT, "");
        _credential(who, cbAttester, COUNTRY, abi.encode(country));
    }

    // ------------------------------------------------------------ automated KYC

    function test_SelfVerifyApprovesWithCountry() public {
        _coinbaseVerify(newFan, "US");
        assertFalse(compliance.isAllowed(newFan));
        vm.prank(newFan);
        compliance.selfVerify();
        assertTrue(compliance.isAllowed(newFan));
        (uint64 expiresAt, bytes2 country) = compliance.records(newFan);
        assertEq(country, bytes2("US"));
        assertEq(expiresAt, block.timestamp + 30 days);
    }

    function test_SelfVerifyWithoutCredentialReverts() public {
        vm.prank(newFan);
        vm.expectRevert(abi.encodeWithSelector(ComplianceRegistry.IdentityNotVerified.selector, newFan));
        compliance.selfVerify();
    }

    function test_FakeAttesterIsRejected() public {
        address faker = makeAddr("faker");
        _credential(newFan, faker, ACCOUNT, "");
        _credential(newFan, faker, COUNTRY, abi.encode("US"));
        vm.prank(newFan);
        vm.expectRevert(abi.encodeWithSelector(ComplianceRegistry.IdentityNotVerified.selector, newFan));
        compliance.selfVerify();
    }

    function test_BlockedCountryCannotSelfVerify() public {
        vm.prank(admin);
        compliance.setCountryBlocked("KP", true);
        _coinbaseVerify(newFan, "KP");
        vm.prank(newFan);
        vm.expectRevert(abi.encodeWithSelector(ComplianceRegistry.CountryIsBlocked.selector, bytes2("KP")));
        compliance.selfVerify();
    }

    function test_RevokedCredentialCanBeRemovedByAnyone() public {
        bytes32 uid = _credential(newFan, cbAttester, ACCOUNT, "");
        _credential(newFan, cbAttester, COUNTRY, abi.encode("US"));
        vm.prank(newFan);
        compliance.selfVerify();

        eas.revoke(uid);
        assertTrue(compliance.recheck(newFan));
        assertFalse(compliance.isAllowed(newFan));
    }

    function test_SelfVerifiedApprovalExpires() public {
        _coinbaseVerify(newFan, "US");
        vm.prank(newFan);
        compliance.selfVerify();
        vm.warp(block.timestamp + 30 days);
        assertFalse(compliance.isAllowed(newFan));
    }

    // ------------------------------------------------------------ automated talent ID + 18+

    function _approvedTalent() internal returns (uint256 id) {
        _seedScouts();
        vm.prank(scoutA);
        id = registry.nominate(talentWallet, 1, "soccer", "international", "ipfs://kda");
        vm.prank(scoutA);
        registry.vote(id, _ids(1, 4), true);
        vm.warp(block.timestamp + VOTING_PERIOD);
        registry.finalizeNomination(id);
    }

    function test_AutoVerifyTalentWithCredential() public {
        uint256 id = _approvedTalent();
        bytes32 uid = _credential(talentWallet, cbAttester, ACCOUNT, "");
        registry.verifyIdentityAuto(id); // anyone can trigger
        TalentRegistry.Talent memory t = registry.talent(id);
        assertEq(uint256(t.status), uint256(TalentRegistry.Status.Verified));
        assertEq(t.idCheckRef, uid);

        vm.prank(talentWallet);
        registry.consent(id);
        vm.prank(admin);
        registry.launch(id, "King David Andre Supporter", "KDA", 1_000_000 ether, 2 * USDC);
        assertEq(uint256(registry.talent(id).status), uint256(TalentRegistry.Status.Launched));
    }

    function test_AutoVerifyFailsWithoutCredential() public {
        uint256 id = _approvedTalent();
        vm.expectRevert(TalentRegistry.IdentityNotVerified.selector);
        registry.verifyIdentityAuto(id);
    }

    function test_AutoVerifyFailsWithExpiredCredential() public {
        uint256 id = _approvedTalent();
        bytes32 uid = eas.attest(cbAttester, talentWallet, ACCOUNT, uint64(block.timestamp + 1 days), "");
        indexer.index(talentWallet, ACCOUNT, uid);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(TalentRegistry.IdentityNotVerified.selector);
        registry.verifyIdentityAuto(id);
    }
}
