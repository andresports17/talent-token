// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {NodeLicense} from "./NodeLicense.sol";
import {NodeVoting} from "./NodeVoting.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";
import {TalentToken} from "./TalentToken.sol";
import {SupportVault} from "./SupportVault.sol";
import {IIdentityVerifier} from "./identity/IIdentityVerifier.sol";

/// @title TalentRegistry
/// @notice Path from nomination to a live supporter token:
///   1. A node holder nominates a talent (category + level: local/regional/national/international).
///   2. Node holders vote (one vote per node). Quorum + majority approves.
///   3. Identity + 18+ is confirmed automatically from an on-chain credential (verifyIdentityAuto),
///      or by a human verifier as a fallback. Minors are never tokenized.
///   4. The talent consents from their own wallet.
///   5. The admin launches the TalentToken and its SupportVault pool.
contract TalentRegistry is AccessControl, ReentrancyGuard, NodeVoting {
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    enum Status {
        None,
        Nominated,
        Approved,
        Rejected,
        Verified,
        Consented,
        Launched
    }

    struct Talent {
        address wallet;
        uint256 nominatorNode;
        uint256 ballotId;
        Status status;
        bytes32 idCheckRef; // hash/reference of the off-chain ID + age check (no personal data on-chain)
        address token;
        string category; // "soccer", "music", "academics", "entrepreneurship", "ministry", ...
        string level; // "local", "regional", "national", "international"
        string metadataURI;
    }

    ComplianceRegistry public immutable compliance;
    SupportVault public vault;
    IIdentityVerifier public identityVerifier;

    uint256 public talentCount;
    mapping(uint256 => Talent) internal _talents;
    mapping(address => uint256) public talentIdOf;

    event Nominated(uint256 indexed talentId, address indexed wallet, uint256 indexed nominatorNode, uint256 ballotId);
    event NominationFinalized(uint256 indexed talentId, bool approved);
    event IdentityVerified(uint256 indexed talentId, bytes32 idCheckRef);
    event Consented(uint256 indexed talentId);
    event Launched(uint256 indexed talentId, address token, uint256 supply, uint256 priceUSDC);
    event VaultSet(address vault);
    event IdentityVerifierSet(address verifier);

    error ZeroAddress();
    error AlreadyNominated(address wallet);
    error WrongStatus(Status expected, Status actual);
    error TalentIsMinor();
    error NotTalentWallet();
    error TalentNotCompliant();
    error VaultNotSet();
    error VaultAlreadySet();
    error NoIdentityVerifier();
    error IdentityNotVerified();

    constructor(
        address admin,
        NodeLicense nodes_,
        ComplianceRegistry compliance_,
        uint256 votingPeriod_,
        uint256 quorumBps_
    ) NodeVoting(nodes_, votingPeriod_, quorumBps_) {
        if (admin == address(0) || address(compliance_) == address(0)) revert ZeroAddress();
        compliance = compliance_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ---------------------------------------------------------------- admin

    function setVault(SupportVault vault_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(vault) != address(0)) revert VaultAlreadySet();
        if (address(vault_) == address(0)) revert ZeroAddress();
        vault = vault_;
        emit VaultSet(address(vault_));
    }

    function setVotingParams(uint256 period, uint256 qBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVotingParams(period, qBps);
    }

    function setIdentityVerifier(IIdentityVerifier verifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        identityVerifier = verifier;
        emit IdentityVerifierSet(address(verifier));
    }

    // ---------------------------------------------------------------- flow

    function nominate(
        address wallet,
        uint256 nominatorNode,
        string calldata category,
        string calldata level,
        string calldata metadataURI
    ) external returns (uint256 id) {
        if (wallet == address(0)) revert ZeroAddress();
        if (nodes.ownerOf(nominatorNode) != msg.sender) revert NotNodeOwner(nominatorNode);
        if (talentIdOf[wallet] != 0) revert AlreadyNominated(wallet);

        id = ++talentCount;
        uint256 ballotId = _openBallot();
        Talent storage t = _talents[id];
        t.wallet = wallet;
        t.nominatorNode = nominatorNode;
        t.ballotId = ballotId;
        t.status = Status.Nominated;
        t.category = category;
        t.level = level;
        t.metadataURI = metadataURI;
        talentIdOf[wallet] = id;

        emit Nominated(id, wallet, nominatorNode, ballotId);
    }

    function vote(uint256 id, uint256[] calldata nodeIds, bool support) external {
        Talent storage t = _talents[id];
        _requireStatus(t, Status.Nominated);
        _castVotes(t.ballotId, nodeIds, support);
    }

    function finalizeNomination(uint256 id) external {
        Talent storage t = _talents[id];
        _requireStatus(t, Status.Nominated);
        bool approved = _result(t.ballotId);
        if (approved) {
            t.status = Status.Approved;
        } else {
            t.status = Status.Rejected;
            delete talentIdOf[t.wallet]; // allows a fresh nomination later
        }
        emit NominationFinalized(id, approved);
    }

    /// @param isAdult verifier attests the talent is 18+. A minor is rejected outright.
    function verifyIdentity(uint256 id, bytes32 idCheckRef, bool isAdult) external onlyRole(VERIFIER_ROLE) {
        Talent storage t = _talents[id];
        _requireStatus(t, Status.Approved);
        if (!isAdult) revert TalentIsMinor();
        if (!compliance.isAllowed(t.wallet)) revert TalentNotCompliant();
        t.idCheckRef = idCheckRef;
        t.status = Status.Verified;
        emit IdentityVerified(id, idCheckRef);
    }

    /// @notice Automated ID + 18+ check. Anyone can trigger it once the nomination is approved;
    ///         it passes only if the talent's wallet holds a valid verified-adult credential.
    function verifyIdentityAuto(uint256 id) external {
        Talent storage t = _talents[id];
        _requireStatus(t, Status.Approved);
        IIdentityVerifier v = identityVerifier;
        if (address(v) == address(0)) revert NoIdentityVerifier();
        (bool adult, bytes32 ref) = v.verifiedAdult(t.wallet);
        if (!adult) revert IdentityNotVerified();
        if (!compliance.isAllowed(t.wallet)) revert TalentNotCompliant();
        t.idCheckRef = ref;
        t.status = Status.Verified;
        emit IdentityVerified(id, ref);
    }

    /// @notice Must be called by the talent from their own wallet.
    function consent(uint256 id) external {
        Talent storage t = _talents[id];
        _requireStatus(t, Status.Verified);
        if (msg.sender != t.wallet) revert NotTalentWallet();
        t.status = Status.Consented;
        emit Consented(id);
    }

    /// @param priceUSDC price of one whole supporter token in USDC base units (6 decimals).
    function launch(uint256 id, string memory name_, string memory symbol_, uint256 supply, uint256 priceUSDC)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
        returns (address token)
    {
        Talent storage t = _talents[id];
        _requireStatus(t, Status.Consented);
        if (address(vault) == address(0)) revert VaultNotSet();
        if (!compliance.isAllowed(t.wallet)) revert TalentNotCompliant();

        TalentToken tkn = _deployToken(id, name_, symbol_, supply);
        token = address(tkn);
        t.token = token;
        t.status = Status.Launched;
        vault.registerPool(id, tkn, t.wallet, priceUSDC);

        emit Launched(id, token, supply, priceUSDC);
    }

    function _deployToken(uint256 id, string memory name_, string memory symbol_, uint256 supply)
        internal
        returns (TalentToken)
    {
        return new TalentToken(name_, symbol_, supply, address(vault), compliance, id);
    }

    // ---------------------------------------------------------------- views

    function talent(uint256 id) external view returns (Talent memory) {
        return _talents[id];
    }

    function _requireStatus(Talent storage t, Status expected) internal view {
        if (t.status != expected) revert WrongStatus(expected, t.status);
    }
}
