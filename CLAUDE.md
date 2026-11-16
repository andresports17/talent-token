# Talent Token — agent notes

Owner: Prophet Kerceus André. Read `docs/STRATEGY.md` before changing behaviour.

- Solidity 0.8.24, Foundry, OpenZeppelin v5.1, Base + USDC.
- `forge build --sizes`, `forge test -vv` and `python3 model/talent_model.py` must pass. Keep the model in sync with contract math.
- Explain changes to the owner in plain, non-technical language.

## Hard guardrails (need written sign-off from the owner AND a securities lawyer)
- Never raise or make variable the 5,000 node cap.
- No payouts to token or node holders from a talent's wages, transfer fees, prize money or royalties (FIFA RSTP Art. 18ter; securities risk).
- No yield, staking rewards or revenue share for nodes unless it's a separate, counsel-approved module.
- Never tokenize minors. Launch needs the 18+ identity check and the talent's own on-chain consent.
- Base Sepolia only. Mainnet needs the owner's explicit go-ahead AND an outside audit in `audits/`; mainnet admin must be a Safe multisig. Never handle or commit private keys.
