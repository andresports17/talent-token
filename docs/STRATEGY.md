# Talent Token — strategy and current behaviour

## Nodes (NodeLicense)
- Hard cap: 5,000 (constant).
- Placeholder USDC tiers (owner to confirm before the sale opens):
  - 1–500 Founding Scouts: 100 USDC
  - 501–2,000 Regional: 250 USDC
  - 2,001–4,000 National: 500 USDC
  - 4,001–5,000 International: 1,000 USDC
  - A full sell-out raises 2,425,000 USDC to the treasury.
- Wallet cap: 10 nodes (admin-adjustable). The sale is paused at deploy. Prices can only change while paused.
- Transfers are locked until the admin unlocks them (one-way), and then only to KYC'd wallets.
- Nodes give voting rights only: no yield, staking rewards or revenue share.

## Voting (NodeVoting)
- One vote per node, recorded per node id, so no double voting even after a transfer.
- Only nodes that existed when the ballot opened can vote.
- Default: 3-day voting period, 20% quorum, and yes must beat no.

## Talents (TalentRegistry)
Nominate (by a node holder) → node vote → verifier confirms ID and 18+ → talent consents from own wallet → admin launches the token and vault pool.
A rejected nomination frees the wallet for a later re-nomination. No personal data goes on-chain, only a reference hash of the ID check.

## Supporter tokens and escrow (TalentToken, SupportVault)
- Fixed supply minted once to the vault. Transfers need both wallets to pass KYC.
- Fans pay USDC at a fixed price per token. USDC stays in escrow per talent.
- The talent (or admin) proposes a milestone with a proof link. Node vote releases it to the talent's wallet.
- The guardian (admin) can freeze a pool. New support and releases stop, pending milestones are cancelled, and each contributor can claim `contribution × unreleased ÷ raised`.
- Accounting invariant: raised = released + pending + available + refundable.
- Refunds go to the wallet that contributed, not whoever holds the tokens now.

## Open decisions for the owner
- Final node prices and wallet cap.
- Voting period and quorum.
- Who holds the verifier role (ID + age checks) and the KYC role.
- What happens to unsold supporter tokens left in the vault.

## Backlog
Merkle allow-list for Founding Scouts; soulbound supporter badges; indexer/subgraph; web app (Next.js + wagmi + OnchainKit); IPFS milestone proofs with a dispute window; more invariant tests (raised = released + pending + available).
