// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {NodeLicense} from "./NodeLicense.sol";

/// @title NodeVoting — one node, one vote
/// @notice Shared ballot logic for nominations and milestone releases.
///         Votes are recorded per node id, so a node cannot vote twice on the same
///         ballot even if it changes hands. Only nodes that existed when the ballot
///         opened can vote on it.
abstract contract NodeVoting {
    NodeLicense public immutable nodes;

    struct Ballot {
        uint64 deadline;
        uint32 snapshotSupply;
        uint32 yes;
        uint32 no;
    }

    uint256 public votingPeriod;
    uint256 public quorumBps; // share of nodes (at ballot open) that must vote, in basis points
    uint256 public ballotCount;

    mapping(uint256 => Ballot) public ballots;
    mapping(uint256 => mapping(uint256 => bool)) public hasVoted; // ballotId => nodeId => voted

    event BallotOpened(uint256 indexed ballotId, uint64 deadline, uint32 snapshotSupply);
    event VoteCast(uint256 indexed ballotId, address indexed voter, uint256 weight, bool support);
    event VotingParamsSet(uint256 votingPeriod, uint256 quorumBps);

    error UnknownBallot();
    error VotingClosed();
    error VotingStillOpen();
    error NoNodesGiven();
    error NodeNotEligible(uint256 nodeId);
    error NotNodeOwner(uint256 nodeId);
    error NodeAlreadyVoted(uint256 nodeId);
    error BadVotingParams();

    constructor(NodeLicense nodes_, uint256 votingPeriod_, uint256 quorumBps_) {
        nodes = nodes_;
        _setVotingParams(votingPeriod_, quorumBps_);
    }

    function _setVotingParams(uint256 period, uint256 qBps) internal {
        if (period < 1 hours || period > 30 days || qBps == 0 || qBps > 10_000) revert BadVotingParams();
        votingPeriod = period;
        quorumBps = qBps;
        emit VotingParamsSet(period, qBps);
    }

    function _openBallot() internal returns (uint256 id) {
        id = ++ballotCount;
        uint64 deadline = uint64(block.timestamp + votingPeriod);
        uint32 supply = uint32(nodes.totalMinted());
        ballots[id] = Ballot({deadline: deadline, snapshotSupply: supply, yes: 0, no: 0});
        emit BallotOpened(id, deadline, supply);
    }

    function _castVotes(uint256 id, uint256[] calldata nodeIds, bool support) internal {
        Ballot storage b = ballots[id];
        if (b.deadline == 0) revert UnknownBallot();
        if (block.timestamp >= b.deadline) revert VotingClosed();
        uint256 n = nodeIds.length;
        if (n == 0) revert NoNodesGiven();
        for (uint256 i; i < n; ++i) {
            uint256 nodeId = nodeIds[i];
            if (nodeId == 0 || nodeId > b.snapshotSupply) revert NodeNotEligible(nodeId);
            if (nodes.ownerOf(nodeId) != msg.sender) revert NotNodeOwner(nodeId);
            if (hasVoted[id][nodeId]) revert NodeAlreadyVoted(nodeId);
            hasVoted[id][nodeId] = true;
        }
        if (support) b.yes += uint32(n);
        else b.no += uint32(n);
        emit VoteCast(id, msg.sender, n, support);
    }

    /// @return passed true when quorum is met and yes votes outnumber no votes.
    function _result(uint256 id) internal view returns (bool passed) {
        Ballot memory b = ballots[id];
        if (b.deadline == 0) revert UnknownBallot();
        if (block.timestamp < b.deadline) revert VotingStillOpen();
        uint256 turnout = uint256(b.yes) + uint256(b.no);
        passed = turnout * 10_000 >= uint256(b.snapshotSupply) * quorumBps && b.yes > b.no;
    }
}
