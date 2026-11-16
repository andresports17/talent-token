# talent-token

The most innovative talent support project.

Talent Token is a network of up to **5,000 Talent Scout node licenses** plus one **supporter token** per verified talent. It starts with soccer and King David André, then grows into music, academics, entrepreneurship and ministry, at local, regional, national and international levels. Built for **Base** with **USDC**.

## How it works

1. **Scouts buy a node** (`NodeLicense`). There are 5,000 max, sold in USDC price tiers. Nodes can't be transferred until transfers are unlocked.
2. **A scout nominates a talent** (`TalentRegistry`). Node holders vote, one vote per node.
3. **A verifier checks ID and confirms the talent is 18+.** Minors are never tokenized.
4. **The talent consents** from their own wallet, then the admin launches their **supporter token** (`TalentToken`).
5. **Fans support the talent** (`SupportVault`). They pay USDC and get supporter tokens. The USDC sits in escrow and goes to the talent only in milestones that node holders approve by vote. If a pool is frozen, fans get pro-rata refunds of whatever hasn't been released.

Supporter tokens give perks and fan votes, never a share of a talent's wages, transfer fees, prize money or royalties.

## Contracts

| Contract | Purpose |
|---|---|
| `ComplianceRegistry` | KYC allow-list with expiry and country blocks |
| `NodeLicense` | ERC-721 Talent Scout nodes, hard cap 5,000 |
| `NodeVoting` | Shared one-node-one-vote ballots |
| `TalentRegistry` | Nominate → vote → verify 18+ → consent → launch |
| `TalentToken` | Fixed-supply ERC-20 supporter token, KYC-gated transfers |
| `SupportVault` | USDC escrow, milestone releases, refunds |

## Develop

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git
forge build --sizes
forge test -vv
python3 model/talent_model.py
```

GitHub Actions runs all of this on every push (`.github/workflows/test.yml`).

## Deploy (Base Sepolia only)

```bash
cp .env.example .env   # fill in TREASURY and VERIFIER
cast wallet import deployer --interactive
source .env && forge script script/Deploy.s.sol --rpc-url base_sepolia --account deployer --broadcast
```

The node sale stays paused after deploy until pricing is approved. Mainnet requires an outside audit in `audits/` and a Safe multisig as admin.
