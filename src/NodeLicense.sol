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
/// @notice ERC-721 with a hard cap of 5,000. Sold for USDC on a step curve:
///         price = startPrice + priceStep x floor((tokenId - 1) / stepSize).
///         Default: $500 for nodes 1-100, then +$100 every 100 nodes (last 100 nodes $5,400).
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

    /// @notice Pricing curve, USDC base units (6 decimals).
    uint256 public startPrice;
    uint256 public priceStep;
    uint256 public stepSize;

    mapping(address => uint256) public mintedBy;
    string private _baseTokenURI;

    event NodesPurchased(address indexed buyer, uint256 firstId, uint256 quantity, uint256 cost);
    event PricingSet(uint256 startPrice, uint256 priceStep, uint256 stepSize);
    event TransfersUnlocked();
    event TreasurySet(address treasury);
    event MaxPerWalletSet(uint256 maxPerWallet);

    error ZeroAddress();
    error ZeroQuantity();
    error SoldOut();
    error WalletCapExceeded();
    error NotCompliant(address account);
    error TransfersLocked();
    error BadPricing();

    constructor(
        address admin,
        IERC20 usdc_,
        ComplianceRegistry compliance_,
        address treasury_,
        uint256 startPrice_,
        uint256 priceStep_,
        uint256 stepSize_,
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
        _setPricing(startPrice_, priceStep_, stepSize_);
        _pause();
    }

    // ---------------------------------------------------------------- buying

    function priceOf(uint256 tokenId) public view returns (uint256) {
        if (tokenId == 0 || tokenId > MAX_SUPPLY) revert SoldOut();
        return startPrice + priceStep * ((tokenId - 1) / stepSize);
    }

    /// @notice USDC cost of buying `quantity` nodes right now (can span price steps).
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

    /// @notice Pricing can only change while sales are paused.
    function setPricing(uint256 startPrice_, uint256 priceStep_, uint256 stepSize_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenPaused
    {
        _setPricing(startPrice_, priceStep_, stepSize_);
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

    // ---------------------------------------------------------------- internals

    function _setPricing(uint256 startPrice_, uint256 priceStep_, uint256 stepSize_) internal {
        if (startPrice_ == 0 || stepSize_ == 0 || stepSize_ > MAX_SUPPLY) revert BadPricing();
        startPrice = startPrice_;
        priceStep = priceStep_;
        stepSize = stepSize_;
        emit PricingSet(startPrice_, priceStep_, stepSize_);
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
