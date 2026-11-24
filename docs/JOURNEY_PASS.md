# Talent Journey Pass (testnet pilot)

A free, non-transferable pass. A supporter claims it, then follows a fictional athlete's milestones
as an admin proposes them and an independent verifier marks them Verified or Rejected.
Contract: `src/JourneyPass.sol`. Website: `web/index.html`. Tests: `test/JourneyPass.t.sol`.

## Roles
| Role | Can do | Cannot do |
|---|---|---|
| Admin (testnet wallet; Safe multisig for any mainnet) | Create athlete profiles, update a profile link, open/close claims, propose milestones, assign the verifier | Move supporter passes, take payments, verify its own proposals without first granting itself the role on-chain (visible to everyone) |
| Verifier | Mark a proposed milestone Verified or Rejected, with a note | Create passes, create or change profiles, propose milestones |
| Supporter | Claim one free pass per athlete, view milestones | Transfer, sell or pay |

## Pilot acceptance criteria and where each is proven
| # | Criterion | Proof |
|---|---|---|
| 1 | A new wallet claims one pass for free; a second claim fails | `test_AC1_FreeClaimThenSecondClaimFails` |
| 2 | A pass cannot be transferred | `test_AC2_PassCannotBeTransferred` (ERC-5192 locked) |
| 3 | Only the admin proposes; only the verifier verifies or rejects | `test_AC3_*`, `test_VerifierCannotCreateProfilesOrEditThem` |
| 4 | The web page shows pass and milestone statuses matching on-chain data | `test_AC4_TimelineDataMatchesStatuses`; the page reads `athlete()`, `milestones()`, `passOf()` live |
| 5 | No function accepts real money or USDC | `test_AC5_NoFunctionAcceptsMoney` (no payable function, no receive) |
| 6 | All tests pass in GitHub Actions, old tests still pass | `test` workflow |
| 7 | Deployed on Base Sepolia, addresses in the README | `deploy-journey-demo` workflow writes `deployments/base-sepolia.json` |

## Guardrails
- Demo profiles are flagged `demo = true` and use fictional people only.
- A real athlete's profile can only be created with `createAthleteFromRegistry`, which requires the
  TalentRegistry to have **Launched** them: node vote, ID and 18+ check, and their own on-chain consent.
  Using David André's real profile is a separate step that also needs written approval of the exact fields.
- No personal data on-chain: profile and proof are links (IPFS) and hashes. Names are limited to 80
  characters with no quotes, so the on-chain metadata stays valid.
- No changes to NodeLicense, SupportVault or TalentRegistry.

## Run the pilot story yourself
```
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts@v5.1.0 --no-git
forge test --mc JourneyPassTest -vv
```

## Launch on Base Sepolia (owner steps)
1. Make two **new** wallets: a throwaway deployer (becomes admin) and a verifier. Never use a wallet with real funds.
2. Get free Base Sepolia test ETH for both from a faucet.
3. In GitHub: Settings → Secrets and variables → Actions:
   - secret `DEMO_DEPLOYER_KEY` = the throwaway deployer's private key (only you type this; it never goes in chat or code)
   - variable `JOURNEY_VERIFIER` = the verifier's address
4. Actions → **deploy-journey-demo** → Run workflow. It runs the tests, deploys, creates the fictional athlete
   with three proposed milestones, and commits the address to `deployments/base-sepolia.json` and `web/deployment.json`.
5. Settings → Pages → Source: **GitHub Actions**. The **website** workflow publishes `web/`.
   The page switches from preview to live automatically once `deployment.json` exists.
6. Open the site with the verifier wallet to verify or reject milestones; with any other wallet to claim a pass.

Or from your own computer: `VERIFIER=0x... forge script script/DeployJourneyDemo.s.sol --rpc-url base_sepolia --account <keystore> --broadcast`.

## Not included
Mainnet, a security audit, real athlete data, the Soft Entry Node.
