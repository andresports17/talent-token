// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {TalentRegistry} from "./TalentRegistry.sol";

/// @title JourneyPass — free, soulbound Talent Journey Pass with a verified milestone timeline
/// @notice
///  - Supporters claim ONE free pass per athlete. No price, no USDC, no payable function.
///  - Passes can never be transferred or sold (ERC-5192 locked).
///  - The admin creates athlete profiles and proposes milestones. Only a VERIFIER can mark a
///    milestone Verified or Rejected. The verifier cannot create profiles or passes.
///  - A real athlete's profile can only be created once the TalentRegistry has Launched them
///    (node vote + ID/18+ check + the athlete's own on-chain consent). Demo profiles are
///    flagged `demo = true` and must use fictional people and test data only.
///  - Recognition and perks only: a pass is NEVER a share of an athlete's wages, transfer fees,
///    prize money or royalties (FIFA RSTP Art. 18ter; securities risk).
///  - No personal data on-chain: profiles and proofs are links (IPFS) and hashes.
contract JourneyPass is ERC721, AccessControl {
    using Strings for uint256;

    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes4 private constant _IERC5192 = 0xb45a3c0e;

    enum MilestoneStatus {
        None,
        Proposed,
        Verified,
        Rejected
    }

    struct Athlete {
        bool exists;
        bool open; // new claims allowed
        bool demo; // fictional profile, test data only
        uint32 passCount;
        uint32 verifiedCount;
        uint64 createdAt;
        uint256 registryTalentId; // 0 for demo profiles
        string name;
        string sport;
        string profileURI; // ipfs://... JSON with photo, bio, position (no personal data)
    }

    struct Milestone {
        MilestoneStatus status;
        uint64 proposedAt;
        uint64 decidedAt;
        bytes32 proofHash;
        string title;
        string proofURI;
        string note; // verifier's reason, e.g. "Confirmed with club" or "Proof unreadable"
    }

    struct Pass {
        uint256 athleteId;
        uint64 claimedAt;
        uint32 serial; // 1 = first supporter of this athlete
        uint32 verifiedAtClaim;
    }

    /// @notice Optional link to the main Talent Token registry (zero = demo-only deployment).
    TalentRegistry public immutable registry;

    uint256 public athleteCount;
    uint256 public totalPasses;
    mapping(uint256 athleteId => Athlete) internal _athletes;
    mapping(uint256 athleteId => Milestone[]) internal _milestones;
    mapping(uint256 tokenId => Pass) internal _passes;
    mapping(uint256 athleteId => mapping(address => uint256)) public passOf;
    mapping(uint256 registryTalentId => uint256) public athleteIdOfTalent;

    event AthleteCreated(uint256 indexed athleteId, bool demo, uint256 registryTalentId, string name);
    event ProfileUpdated(uint256 indexed athleteId, string profileURI);
    event ClaimsOpen(uint256 indexed athleteId, bool open);
    event PassClaimed(uint256 indexed athleteId, address indexed supporter, uint256 indexed tokenId, uint32 serial);
    event MilestoneProposed(uint256 indexed athleteId, uint256 indexed index, string title, string proofURI, bytes32 proofHash);
    event MilestoneDecided(uint256 indexed athleteId, uint256 indexed index, MilestoneStatus status, string note);
    /// @dev ERC-5192
    event Locked(uint256 tokenId);

    error ZeroAddress();
    error NoRegistry();
    error TalentNotLaunched(uint256 talentId);
    error ProfileExists(uint256 talentId);
    error UnknownAthlete(uint256 athleteId);
    error ClaimsClosed(uint256 athleteId);
    error AlreadyClaimed(uint256 athleteId, address supporter);
    error BadText();
    error MissingProof();
    error UnknownMilestone(uint256 index);
    error NotProposed(uint256 index);
    error Soulbound();

    constructor(address admin, address verifier, TalentRegistry registry_) ERC721("Talent Journey Pass", "JOURNEY") {
        if (admin == address(0) || verifier == address(0)) revert ZeroAddress();
        registry = registry_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(VERIFIER_ROLE, verifier);
    }

    // ------------------------------------------------------------------ admin: profiles

    /// @notice Fictional athlete for demos. Test data only; never a real person.
    function createDemoAthlete(string calldata name, string calldata sport, string calldata profileURI)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 id)
    {
        id = _create(true, 0, name, sport, profileURI);
    }

    /// @notice Real athlete: only after the registry has Launched them (vote, ID/18+, own consent).
    function createAthleteFromRegistry(
        uint256 talentId,
        string calldata name,
        string calldata sport,
        string calldata profileURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 id) {
        if (address(registry) == address(0)) revert NoRegistry();
        if (registry.talent(talentId).status != TalentRegistry.Status.Launched) revert TalentNotLaunched(talentId);
        if (athleteIdOfTalent[talentId] != 0) revert ProfileExists(talentId);
        id = _create(false, talentId, name, sport, profileURI);
        athleteIdOfTalent[talentId] = id;
    }

    function updateProfile(uint256 athleteId, string calldata profileURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _athlete(athleteId).profileURI = profileURI;
        emit ProfileUpdated(athleteId, profileURI);
    }

    function setClaimsOpen(uint256 athleteId, bool open) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _athlete(athleteId).open = open;
        emit ClaimsOpen(athleteId, open);
    }

    // ------------------------------------------------------------------ supporters

    /// @notice Claim your free pass. One per wallet per athlete. Not payable: no money accepted.
    function claim(uint256 athleteId) external returns (uint256 tokenId) {
        Athlete storage a = _athlete(athleteId);
        if (!a.open) revert ClaimsClosed(athleteId);
        if (passOf[athleteId][msg.sender] != 0) revert AlreadyClaimed(athleteId, msg.sender);

        tokenId = ++totalPasses;
        uint32 serial = ++a.passCount;
        _passes[tokenId] = Pass({
            athleteId: athleteId,
            claimedAt: uint64(block.timestamp),
            serial: serial,
            verifiedAtClaim: a.verifiedCount
        });
        passOf[athleteId][msg.sender] = tokenId;

        _safeMint(msg.sender, tokenId);
        emit Locked(tokenId);
        emit PassClaimed(athleteId, msg.sender, tokenId, serial);
    }

    // ------------------------------------------------------------------ milestones

    /// @notice Admin proposes a milestone with a proof link and/or hash.
    function proposeMilestone(uint256 athleteId, string calldata title, string calldata proofURI, bytes32 proofHash)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 index)
    {
        _athlete(athleteId);
        _checkText(title);
        if (bytes(title).length == 0) revert BadText();
        if (bytes(proofURI).length == 0 && proofHash == bytes32(0)) revert MissingProof();

        index = _milestones[athleteId].length;
        Milestone storage m = _milestones[athleteId].push();
        m.status = MilestoneStatus.Proposed;
        m.proposedAt = uint64(block.timestamp);
        m.proofHash = proofHash;
        m.title = title;
        m.proofURI = proofURI;
        emit MilestoneProposed(athleteId, index, title, proofURI, proofHash);
    }

    function verifyMilestone(uint256 athleteId, uint256 index, string calldata note) external onlyRole(VERIFIER_ROLE) {
        _decide(athleteId, index, MilestoneStatus.Verified, note);
        _athletes[athleteId].verifiedCount++;
    }

    function rejectMilestone(uint256 athleteId, uint256 index, string calldata note) external onlyRole(VERIFIER_ROLE) {
        _decide(athleteId, index, MilestoneStatus.Rejected, note);
    }

    // ------------------------------------------------------------------ views

    function athlete(uint256 athleteId) external view returns (Athlete memory) {
        return _athletes[athleteId];
    }

    function milestoneCount(uint256 athleteId) external view returns (uint256) {
        return _milestones[athleteId].length;
    }

    function milestone(uint256 athleteId, uint256 index) external view returns (Milestone memory) {
        if (index >= _milestones[athleteId].length) revert UnknownMilestone(index);
        return _milestones[athleteId][index];
    }

    function milestones(uint256 athleteId) external view returns (Milestone[] memory) {
        return _milestones[athleteId];
    }

    function pass(uint256 tokenId) external view returns (Pass memory) {
        _requireOwned(tokenId);
        return _passes[tokenId];
    }

    /// @notice Milestones verified after this pass was claimed.
    function milestonesWitnessed(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        Pass storage p = _passes[tokenId];
        return _athletes[p.athleteId].verifiedCount - p.verifiedAtClaim;
    }

    /// @dev ERC-5192: every pass is permanently locked.
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        Pass storage p = _passes[tokenId];
        Athlete storage a = _athletes[p.athleteId];
        string memory name_ = a.name;
        string memory serial = uint256(p.serial).toString();
        string memory demo = a.demo ? string("yes") : string("no");

        string memory head = string.concat(
            '{"name":"Journey Pass: ',
            name_,
            " #",
            serial,
            '","description":"Free, non-transferable supporter pass. Recognition only; no financial rights.",'
        );
        string memory attrs = string.concat(
            '"attributes":[{"trait_type":"Athlete ID","value":',
            p.athleteId.toString(),
            '},{"trait_type":"Supporter number","value":',
            serial,
            '},{"trait_type":"Demo","value":"',
            demo,
            '"},'
        );
        string memory tail = string.concat(
            '{"trait_type":"Claimed at","display_type":"date","value":',
            uint256(p.claimedAt).toString(),
            '},{"trait_type":"Milestones witnessed","value":',
            milestonesWitnessed(tokenId).toString(),
            "}]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(string.concat(head, attrs, tail))));
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return interfaceId == _IERC5192 || super.supportsInterface(interfaceId);
    }

    // ------------------------------------------------------------------ internal

    function _create(bool demo, uint256 talentId, string calldata name, string calldata sport, string calldata uri)
        internal
        returns (uint256 id)
    {
        _checkText(name);
        _checkText(sport);
        if (bytes(name).length == 0) revert BadText();
        id = ++athleteCount;
        Athlete storage a = _athletes[id];
        a.exists = true;
        a.open = true;
        a.demo = demo;
        a.createdAt = uint64(block.timestamp);
        a.registryTalentId = talentId;
        a.name = name;
        a.sport = sport;
        a.profileURI = uri;
        emit AthleteCreated(id, demo, talentId, name);
    }

    function _decide(uint256 athleteId, uint256 index, MilestoneStatus status, string calldata note) internal {
        _athlete(athleteId);
        if (index >= _milestones[athleteId].length) revert UnknownMilestone(index);
        Milestone storage m = _milestones[athleteId][index];
        if (m.status != MilestoneStatus.Proposed) revert NotProposed(index);
        m.status = status;
        m.decidedAt = uint64(block.timestamp);
        m.note = note;
        emit MilestoneDecided(athleteId, index, status, note);
    }

    function _athlete(uint256 athleteId) internal view returns (Athlete storage a) {
        a = _athletes[athleteId];
        if (!a.exists) revert UnknownAthlete(athleteId);
    }

    /// @dev Keeps on-chain JSON metadata valid: no quotes, backslashes or control characters.
    function _checkText(string calldata s) internal pure {
        bytes calldata b = bytes(s);
        if (b.length > 80) revert BadText();
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            if (c == '"' || c == "\\" || uint8(c) < 0x20) revert BadText();
        }
    }

    /// @dev Mint only. Transfers and burns are blocked.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }
}
