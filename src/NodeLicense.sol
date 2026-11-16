// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ComplianceRegistry} from "./ComplianceRegistry.sol";

/// @title NodeLicense — Talent Scout node licenses
/// @notice ERC-721 with a hard cap of 5,000. Sold for USDC in price tiers.
///         Paused at deploy. Non-transferable until the admin unlocks transfers (one-way).
///         A node gives one vote in talent nominations and milestone releases.
///         Nodes earn NO yield, staking rewards or revenue share.
contract NodeLicense is ERC721, AccessControl, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Hard cap. Never raise this or make it variable (owner + securities-lawyer sign-off required).
    uint256 public constant MAX_SUPPLY = 5_000;

    IERC20 public immutable usdc;
    ComplianceRegistry public immutable compliance;

    address public treasury;
    uint256 public totalMinted;
    uint256 public maxPerWallet;
    bool public transfersUnlocked;

    /// @notice tierCaps[i] is the last token id sold at tierPrices[i] (USDC, 6 decimals).
    uint256[] public tierCaps;
    uint256[] public tierPrices;

    mapping(address => uint256) public mintedBy;
    string private _baseTokenURI;

    event NodesPurchased(address indexed buyer, uint256 firstId, uint256 quantity, uint256 cost);
    event TiersSet(uint256[] caps, uint256[] prices);
    event TransfersUnlocked();
    event TreasurySet(address treasury);
    event MaxPerWalletSet(uint256 maxPerWallet);

    error ZeroAddress();
    error ZeroQuantity();
    error SoldOut();
    error WalletCapExceeded();
    error NotCompliant(address account);
    error TransfersLocked();
    error BadTiers();

    constructor(
        address admin,
        IERC20 usdc_,
        ComplianceRegistry compliance_,
        address treasury_,
        uint256[] memory caps,
        uint256[] memory prices,
        uint256 maxPerWallet_
    ) ERC721("Talent Scout Node", "SCOUT") {
        if (admin == address(0) || address(usdc_) == address(0) || address(compliance_) == address(0)) {
            revert ZeroAddress();
        }
        if (treasury_ == address(0)) revert ZeroAddress();
        usdc = usdc_;
        compliance = compliance_;
        treasury = treasury_;
        maxPerWallet = maxPerWallet_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _setTiers(caps, prices);
        _pause();
    }

    // ---------------------------------------------------------------- buying

    function priceOf(uint256 tokenId) public view returns (uint256) {
        uint256 n = tierCaps.length;
        for (uint256 i; i < n; ++i) {
            if (tokenId <= tierCaps[i]) return tierPrices[i];
        }
        revert SoldOut();
    }

    /// @notice USDC cost of buying `quantity` nodes right now (can span tiers).
    function quote(uint256 quantity) public view returns (uint256 cost) {
        if (totalMinted + quantity > MAX_SUPPLY) revert SoldOut();
        for (uint256 k = 1; k <= quantity; ++k) {
            cost += priceOf(totalMinted + k);
        }
    }

    function buy(uint256 quantity) external whenNotPaused nonReentrant returns (uint256 firstId) {
        if (quantity == 0) revert ZeroQuantity();
        if (!compliance.isAllowed(msg.sender)) revert NotCompliant(msg.sender);
        if (totalMinted + quantity > MAX_SUPPLY) revert SoldOut();
        if (mintedBy[msg.sender] + quantity > maxPerWallet) revert WalletCapExceeded();

        uint256 cost = quote(quantity);
        firstId = totalMinted + 1;
        mintedBy[msg.sender] += quantity;
        totalMinted += quantity;

        usdc.safeTransferFrom(msg.sender, treasury, cost);
        for (uint256 i; i < quantity; ++i) {
            _mint(msg.sender, firstId + i);
        }
        emit NodesPurchased(msg.sender, firstId, quantity, cost);
    }

    // ---------------------------------------------------------------- admin

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice One-way switch that lets node holders transfer nodes (to KYC'd wallets only).
    function unlockTransfers() external onlyRole(DEFAULT_ADMIN_ROLE) {
        transfersUnlocked = true;
        emit TransfersUnlocked();
    }

    /// @notice Tier prices can only change while sales are paused.
    function setTiers(uint256[] calldata caps, uint256[] calldata prices)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenPaused
    {
        _setTiers(caps, prices);
    }

    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    function setMaxPerWallet(uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxPerWallet = cap;
        emit MaxPerWalletSet(cap);
    }

    function setBaseURI(string calldata uri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = uri;
    }

    function tierCount() external view returns (uint256) {
        return tierCaps.length;
    }

    // ---------------------------------------------------------------- internals

    function _setTiers(uint256[] memory caps, uint256[] memory prices) internal {
        uint256 n = caps.length;
        if (n == 0 || n != prices.length || caps[n - 1] != MAX_SUPPLY) revert BadTiers();
        uint256 prev;
        for (uint256 i; i < n; ++i) {
            if (caps[i] <= prev || prices[i] == 0) revert BadTiers();
            prev = caps[i];
        }
        tierCaps = caps;
        tierPrices = prices;
        emit TiersSet(caps, prices);
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /// @dev Blocks holder-to-holder transfers until unlocked; receivers must be KYC'd.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            if (!transfersUnlocked) revert TransfersLocked();
            if (!compliance.isAllowed(to)) revert NotCompliant(to);
        }
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
