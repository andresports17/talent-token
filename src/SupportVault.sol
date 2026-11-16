// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {NodeLicense} from "./NodeLicense.sol";
import {NodeVoting} from "./NodeVoting.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";
import {TalentToken} from "./TalentToken.sol";

/// @title SupportVault
/// @notice Supporters pay USDC and receive the talent's supporter tokens.
///         USDC is held in escrow per talent and released to the talent only in
///         milestones approved by node vote (quorum + majority).
///         If a pool is frozen, supporters claim pro-rata refunds of unreleased USDC.
///         This vault NEVER pays token or node holders from a talent's earnings.
///
/// Accounting per pool (always holds):
///   raised == released + pending + available + refundable(after freeze)
contract SupportVault is AccessControl, ReentrancyGuard, NodeVoting {
    using SafeERC20 for IERC20;

    bytes32 public constant REGISTRY_ROLE = keccak256("REGISTRY_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    IERC20 public immutable usdc;
    ComplianceRegistry public immutable compliance;

    struct Pool {
        TalentToken token;
        address talentWallet;
        uint256 priceUSDC; // per whole supporter token (1e18 units)
        uint256 raised;
        uint256 released;
        uint256 pending; // locked in milestones being voted on
        uint256 refundBase; // `raised` at the moment of freezing
        uint256 refundable; // unreleased USDC set aside for refunds at freezing
        uint256 refunded;
        bool frozen;
        bool exists;
    }

    enum MilestoneStatus {
        None,
        Pending,
        Released,
        Rejected,
        Cancelled
    }

    struct Milestone {
        uint256 talentId;
        uint256 amount;
        uint256 ballotId;
        MilestoneStatus status;
        string proofURI;
    }

    mapping(uint256 => Pool) internal pools;
    mapping(uint256 => mapping(address => uint256)) public contributed;
    mapping(uint256 => Milestone) public milestones;
    uint256 public milestoneCount;

    event PoolRegistered(uint256 indexed talentId, address token, address talentWallet, uint256 priceUSDC);
    event Supported(uint256 indexed talentId, address indexed supporter, uint256 usdcAmount, uint256 tokensOut);
    event MilestoneProposed(uint256 indexed milestoneId, uint256 indexed talentId, uint256 amount, string proofURI);
    event MilestoneFinalized(uint256 indexed milestoneId, MilestoneStatus status);
    event PoolFrozen(uint256 indexed talentId, uint256 refundable);
    event RefundClaimed(uint256 indexed talentId, address indexed supporter, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error PoolExists();
    error NoPool();
    error PoolIsFrozen();
    error PoolNotFrozen();
    error NotCompliant(address account);
    error SoldOutForTalent();
    error ExceedsAvailable();
    error NotAllowedToPropose();
    error MilestoneNotPending();
    error NothingToRefund();

    constructor(
        address admin,
        IERC20 usdc_,
        NodeLicense nodes_,
        ComplianceRegistry compliance_,
        uint256 votingPeriod_,
        uint256 quorumBps_
    ) NodeVoting(nodes_, votingPeriod_, quorumBps_) {
        if (admin == address(0) || address(usdc_) == address(0) || address(compliance_) == address(0)) {
            revert ZeroAddress();
        }
        usdc = usdc_;
        compliance = compliance_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(GUARDIAN_ROLE, admin);
    }

    // ---------------------------------------------------------------- setup

    function registerPool(uint256 talentId, TalentToken token, address talentWallet, uint256 priceUSDC)
        external
        onlyRole(REGISTRY_ROLE)
    {
        if (address(token) == address(0) || talentWallet == address(0)) revert ZeroAddress();
        if (priceUSDC == 0) revert ZeroAmount();
        Pool storage p = pools[talentId];
        if (p.exists) revert PoolExists();
        p.token = token;
        p.talentWallet = talentWallet;
        p.priceUSDC = priceUSDC;
        p.exists = true;
        emit PoolRegistered(talentId, address(token), talentWallet, priceUSDC);
    }

    function setVotingParams(uint256 period, uint256 qBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVotingParams(period, qBps);
    }

    // ---------------------------------------------------------------- supporters

    function support(uint256 talentId, uint256 usdcAmount) external nonReentrant returns (uint256 tokensOut) {
        Pool storage p = _livePool(talentId);
        if (!compliance.isAllowed(msg.sender)) revert NotCompliant(msg.sender);
        tokensOut = (usdcAmount * 1e18) / p.priceUSDC;
        if (tokensOut == 0) revert ZeroAmount();
        if (tokensOut > p.token.balanceOf(address(this))) revert SoldOutForTalent();

        p.raised += usdcAmount;
        contributed[talentId][msg.sender] += usdcAmount;

        usdc.safeTransferFrom(msg.sender, address(this), usdcAmount);
        IERC20(address(p.token)).safeTransfer(msg.sender, tokensOut);
        emit Supported(talentId, msg.sender, usdcAmount, tokensOut);
    }

    /// @notice Refund after a freeze: your contribution x (unreleased / raised).
    ///         Keyed to the wallet that contributed, not to whoever holds the tokens now.
    function claimRefund(uint256 talentId) external nonReentrant returns (uint256 amount) {
        Pool storage p = pools[talentId];
        if (!p.frozen) revert PoolNotFrozen();
        if (!compliance.isAllowed(msg.sender)) revert NotCompliant(msg.sender);
        uint256 c = contributed[talentId][msg.sender];
        if (c == 0) revert NothingToRefund();
        contributed[talentId][msg.sender] = 0;
        amount = (c * p.refundable) / p.refundBase;
        p.refunded += amount;
        usdc.safeTransfer(msg.sender, amount);
        emit RefundClaimed(talentId, msg.sender, amount);
    }

    // ---------------------------------------------------------------- milestones

    function proposeMilestone(uint256 talentId, uint256 amount, string calldata proofURI)
        external
        returns (uint256 milestoneId)
    {
        Pool storage p = _livePool(talentId);
        if (msg.sender != p.talentWallet && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert NotAllowedToPropose();
        if (amount == 0) revert ZeroAmount();
        if (amount > available(talentId)) revert ExceedsAvailable();

        p.pending += amount;
        milestoneId = ++milestoneCount;
        Milestone storage m = milestones[milestoneId];
        m.talentId = talentId;
        m.amount = amount;
        m.ballotId = _openBallot();
        m.status = MilestoneStatus.Pending;
        m.proofURI = proofURI;
        emit MilestoneProposed(milestoneId, talentId, amount, proofURI);
    }

    function voteMilestone(uint256 milestoneId, uint256[] calldata nodeIds, bool support_) external {
        Milestone storage m = milestones[milestoneId];
        if (m.status != MilestoneStatus.Pending) revert MilestoneNotPending();
        _castVotes(m.ballotId, nodeIds, support_);
    }

    function finalizeMilestone(uint256 milestoneId) external nonReentrant {
        Milestone storage m = milestones[milestoneId];
        if (m.status != MilestoneStatus.Pending) revert MilestoneNotPending();
        Pool storage p = pools[m.talentId];

        if (p.frozen) {
            // pending amounts were moved into `refundable` at freeze time
            m.status = MilestoneStatus.Cancelled;
            emit MilestoneFinalized(milestoneId, m.status);
            return;
        }

        bool passed = _result(m.ballotId);
        p.pending -= m.amount;
        if (passed) {
            p.released += m.amount;
            m.status = MilestoneStatus.Released;
            usdc.safeTransfer(p.talentWallet, m.amount);
        } else {
            m.status = MilestoneStatus.Rejected;
        }
        emit MilestoneFinalized(milestoneId, m.status);
    }

    // ---------------------------------------------------------------- guardian

    /// @notice Stops new support and releases; all unreleased USDC becomes refundable.
    function freezePool(uint256 talentId) external onlyRole(GUARDIAN_ROLE) {
        Pool storage p = _livePool(talentId);
        p.frozen = true;
        p.refundBase = p.raised;
        p.refundable = p.raised - p.released;
        p.pending = 0;
        emit PoolFrozen(talentId, p.refundable);
    }

    // ---------------------------------------------------------------- views

    function pool(uint256 talentId) external view returns (Pool memory) {
        return pools[talentId];
    }

    function available(uint256 talentId) public view returns (uint256) {
        Pool storage p = pools[talentId];
        if (p.frozen) return 0;
        return p.raised - p.released - p.pending;
    }

    function _livePool(uint256 talentId) internal view returns (Pool storage p) {
        p = pools[talentId];
        if (!p.exists) revert NoPool();
        if (p.frozen) revert PoolIsFrozen();
    }
}
