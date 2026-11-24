# Talent Token — strategy and current behaviour

## Nodes (NodeLicense)
- Hard cap: 5,000 (constant).
- Pricing (set by the owner, Nov 2026): $500 for nodes 1–100, then the price rises $100 after every 100 nodes sold. The last 100 nodes cost $5,400.
  - Running totals: 1,000 nodes sold → $950,000; 2,000 → $2.9M; 4,000 → $9.8M; all 5,000 → $14,750,000 USDC to the treasury.
- Wallet cap: 10 nodes (admin-adjustable). The sale is paused at deploy. Pricing can only change while the sale is paused.
- Transfers are locked until the admin unlocks them (one-way), and then only to KYC'd wallets.
- Nodes give voting rights only: no yield, staking rewards or revenue share.

## Voting (NodeVoting)
- One vote per node, recorded per node id, so no double voting even after a transfer.
- Only nodes that existed when the ballot opened can vote.
- Default: 3-day voting period, 20% quorum, and yes must beat no.

## Automated identity (ComplianceRegistry + CoinbaseVerifier)
- Uses Coinbase Verifications, which are free on-chain credentials on Base:
  - "Verified Account" means the wallet owner passed Coinbase's ID check. Coinbase only serves adults, so this is the 18+ signal.
  - "Verified Country" is the owner's country of residence, used for country blocks.
- KYC: any wallet with both credentials calls `selfVerify()` and is approved for 30 days. Blocked countries are refused. Anyone can call `recheck()` to remove a wallet whose credential was revoked.
- Talent ID + 18+: once node holders approve a nomination, anyone can call `verifyIdentityAuto()`. It passes only if the talent's wallet holds a valid Verified Account credential.
- Only credentials signed by the official Coinbase attester count. Revoked or expired ones are rejected.
- Backup: the admin can still approve KYC by hand, and a human VERIFIER can still verify talents, for people who can't use Coinbase.

## Talents (TalentRegistry)
Nominate (by a node holder) → node vote → automated ID + 18+ check (or human verifier) → talent consents from own wallet → admin launches the token and vault pool.
A rejected nomination frees the wallet for a later re-nomination. No personal data goes on-chain, only the credential reference.

## Supporter tokens and escrow (TalentToken, SupportVault)
- Fixed supply minted once to the vault. Transfers need both wallets to pass KYC.
- Fans pay USDC at a fixed price per token. USDC stays in escrow per talent.
- The talent (or admin) proposes a milestone with a proof link. Node vote releases it to the talent's wallet.
- The guardian (admin) can freeze a pool. New support and releases stop, pending milestones are cancelled, and each contributor can claim `contribution × unreleased ÷ raised`.
- Accounting invariant: raised = released + pending + available + refundable.
- Refunds go to the wallet that contributed, not whoever holds the tokens now.

## Free Journey Pass (JourneyPass) — testnet pilot
- One free, soulbound pass per wallet per athlete. No price, no payable function, no financial rights.
- Admin proposes milestones with proof; a separate verifier marks them Verified or Rejected.
- Demo profiles are fictional. Real profiles only after the registry has Launched the talent (vote, 18+ ID check, consent).
- Website in web/ (GitHub Pages). See docs/JOURNEY_PASS.md and docs/LAUNCH_CHECKLIST.md.

## Open decisions for the owner
- Wallet cap (currently 10 nodes per wallet).
- Whether Coinbase "Verified Account" is acceptable proof of 18+ (confirm with counsel).
- Voting period and quorum.
- Who holds the backup human verifier and KYC roles.
- What happens to unsold supporter tokens left in the vault.

## Backlog
Merkle allow-list for Founding Scouts; indexer/subgraph; web app (Next.js + wagmi + OnchainKit); IPFS milestone proofs with a dispute window; more invariant tests (raised = released + pending + available).
