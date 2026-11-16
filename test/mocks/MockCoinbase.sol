// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Attestation, IEAS, ICoinbaseIndexer} from "../../src/identity/CoinbaseVerifier.sol";

/// @dev Minimal stand-ins for EAS + the Coinbase Indexer on Base.
contract MockEAS is IEAS {
    mapping(bytes32 => Attestation) internal _attestations;
    uint256 internal _nonce;

    function attest(address attester, address recipient, bytes32 schema, uint64 expiration, bytes memory data)
        external
        returns (bytes32 uid)
    {
        uid = keccak256(abi.encode(++_nonce, recipient, schema));
        Attestation storage a = _attestations[uid];
        a.uid = uid;
        a.schema = schema;
        a.time = uint64(block.timestamp);
        a.expirationTime = expiration;
        a.recipient = recipient;
        a.attester = attester;
        a.revocable = true;
        a.data = data;
    }

    function revoke(bytes32 uid) external {
        _attestations[uid].revocationTime = uint64(block.timestamp);
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        return _attestations[uid];
    }
}

contract MockIndexer is ICoinbaseIndexer {
    mapping(address => mapping(bytes32 => bytes32)) internal _uids;

    function index(address recipient, bytes32 schema, bytes32 uid) external {
        _uids[recipient][schema] = uid;
    }

    function getAttestationUid(address recipient, bytes32 schemaUid) external view returns (bytes32) {
        return _uids[recipient][schemaUid];
    }
}
