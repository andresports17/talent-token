# Talent Token launch checklist

## Stage 1 — Journey Pass pilot on testnet (now)
- [ ] Pull request with JourneyPass, tests and website passes CI, then merged by the owner
- [ ] Throwaway deployer + separate verifier wallets created and funded with test ETH
- [ ] `DEMO_DEPLOYER_KEY` secret and `JOURNEY_VERIFIER` variable set
- [ ] `deploy-journey-demo` run; address in `deployments/base-sepolia.json`
- [ ] GitHub Pages turned on; site live and switched from preview to live
- [ ] Five outside testers claim a pass; verifier verifies one milestone and rejects one

## Stage 2 — full system on testnet
- [ ] `script/Deploy.s.sol` run on Base Sepolia (treasury + verifier addresses decided)
- [ ] Coinbase Verifications attester and schema values confirmed for Base Sepolia
- [ ] Test node sale with test USDC, a nomination, a vote, a milestone payout and a refund
- [ ] Decide: is "Soft Entry Node" just nodes #1–100 at $500, or a separate tier? (A separate tier needs new code and still counts toward 5,000.)

## Stage 3 — before any real money (owner AND securities counsel)
- [ ] Legal entity that issues nodes; who holds admin and treasury wallets
- [ ] Counsel review of node voting rights over fund releases, transfer unlock, wallet cap, and all marketing wording ("ecosystem participation", any IRA or valuation talk)
- [ ] Outside security audit report in `audits/`
- [ ] Safe multisig as admin on mainnet
- [ ] Only then: owner says "mainnet" in writing
