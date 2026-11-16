// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";

/// @title TalentToken — supporter token for one verified talent
/// @notice Fixed supply, minted once to the SupportVault. No mint function after that.
///         Gives perks and fan votes only. It is NEVER a share of the talent's wages,
///         transfer fees, prize money or royalties (FIFA RSTP Art. 18ter; securities risk).
///         Transfers between wallets require both sides to pass compliance.
contract TalentToken is ERC20 {
    ComplianceRegistry public immutable compliance;
    uint256 public immutable talentId;

    error NotCompliant(address account);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply,
        address initialHolder,
        ComplianceRegistry compliance_,
        uint256 talentId_
    ) ERC20(name_, symbol_) {
        compliance = compliance_;
        talentId = talentId_;
        _mint(initialHolder, supply);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            if (!compliance.isAllowed(from)) revert NotCompliant(from);
            if (!compliance.isAllowed(to)) revert NotCompliant(to);
        }
        super._update(from, to, value);
    }
}
