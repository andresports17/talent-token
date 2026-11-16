// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IIdentityVerifier} from "./IIdentityVerifier.sol";

/// @dev Subset of the EAS attestation struct (field order must match EAS exactly).
struct Attestation {
    bytes32 uid;
    bytes32 schema;
    uint64 time;
    uint64 expirationTime;
    uint64 revocationTime;
    bytes32 refUID;
    address recipient;
    address attester;
    bool revocable;
    bytes data;
}

interface IEAS {
    function getAttestation(bytes32 uid) external view returns (Attestation memory);
}

interface ICoinbaseIndexer {
    function getAttestationUid(address recipient, bytes32 schemaUid) external view returns (bytes32);
}

/// @title CoinbaseVerifier
/// @notice Reads Coinbase Verifications (EAS attestations on Base).
///   - "Verified Account": the wallet owner completed Coinbase ID verification.
///     Coinbase only opens accounts to adults, so this is used as the 18+ signal.
///   - "Verified Country": the wallet owner's country of residence.
///   Attestations must come from the configured Coinbase attester, be unrevoked and unexpired.
///   Base mainnet: EAS 0x4200…0021, Indexer 0x2c7eE1E5f416dfF40054c27A62f7B357C4E8619C,
///   Attester 0x357458739F90461b99789350868CD7CF330Dd7EE (see github.com/coinbase/verifications).
contract CoinbaseVerifier is IIdentityVerifier {
    IEAS public immutable eas;
    ICoinbaseIndexer public immutable indexer;
    address public immutable attester;
    bytes32 public immutable accountSchema;
    bytes32 public immutable countrySchema;

    error ZeroAddress();

    constructor(IEAS eas_, ICoinbaseIndexer indexer_, address attester_, bytes32 accountSchema_, bytes32 countrySchema_) {
        if (address(eas_) == address(0) || address(indexer_) == address(0) || attester_ == address(0)) {
            revert ZeroAddress();
        }
        eas = eas_;
        indexer = indexer_;
        attester = attester_;
        accountSchema = accountSchema_;
        countrySchema = countrySchema_;
    }

    function verifiedAdult(address wallet) external view returns (bool ok, bytes32 ref) {
        Attestation memory a;
        (ok, a) = _valid(wallet, accountSchema);
        if (ok) ref = a.uid;
    }

    function verifiedCountry(address wallet) external view returns (bool ok, bytes2 country) {
        Attestation memory a;
        (ok, a) = _valid(wallet, countrySchema);
        if (!ok) return (false, bytes2(0));
        bytes memory code = bytes(abi.decode(a.data, (string)));
        if (code.length != 2) return (false, bytes2(0));
        country = bytes2(uint16(uint8(code[0])) << 8 | uint16(uint8(code[1])));
    }

    function _valid(address wallet, bytes32 schema) internal view returns (bool ok, Attestation memory a) {
        bytes32 uid = indexer.getAttestationUid(wallet, schema);
        if (uid == bytes32(0)) return (false, a);
        a = eas.getAttestation(uid);
        ok = a.uid == uid && a.schema == schema && a.recipient == wallet && a.attester == attester
            && a.revocationTime == 0 && (a.expirationTime == 0 || a.expirationTime > block.timestamp);
    }
}
