"""Talent Token economic model.

Mirrors the contract math in NodeLicense (tier pricing) and SupportVault
(escrow, milestones, pro-rata refunds). Keep in sync with src/.
Run: python3 model/talent_model.py
"""

USDC = 10**6
MAX_SUPPLY = 5_000

# (last token id in tier, price in USDC base units) — same as script/Deploy.s.sol
TIERS = [
    (500, 100 * USDC),  # Founding Scouts
    (2_000, 250 * USDC),  # Regional
    (4_000, 500 * USDC),  # National
    (5_000, 1_000 * USDC),  # International
]


def price_of(token_id: int) -> int:
    for cap, price in TIERS:
        if token_id <= cap:
            return price
    raise ValueError("sold out")


def quote(total_minted: int, qty: int) -> int:
    if total_minted + qty > MAX_SUPPLY:
        raise ValueError("sold out")
    return sum(price_of(total_minted + k) for k in range(1, qty + 1))


class Pool:
    def __init__(self, price_usdc: int):
        self.price = price_usdc
        self.raised = self.released = self.pending = 0
        self.refund_base = self.refundable = self.refunded = 0
        self.frozen = False
        self.contributed: dict[str, int] = {}

    def available(self) -> int:
        return 0 if self.frozen else self.raised - self.released - self.pending

    def support(self, who: str, amount: int) -> int:
        assert not self.frozen
        tokens = amount * 10**18 // self.price
        assert tokens > 0
        self.raised += amount
        self.contributed[who] = self.contributed.get(who, 0) + amount
        return tokens

    def propose(self, amount: int) -> int:
        assert 0 < amount <= self.available()
        self.pending += amount
        return amount

    def finalize(self, amount: int, passed: bool) -> None:
        if self.frozen:
            return
        self.pending -= amount
        if passed:
            self.released += amount

    def freeze(self) -> None:
        self.frozen = True
        self.refund_base = self.raised
        self.refundable = self.raised - self.released
        self.pending = 0

    def refund(self, who: str) -> int:
        c = self.contributed.pop(who, 0)
        amt = c * self.refundable // self.refund_base
        self.refunded += amt
        return amt

    def check(self) -> None:
        assert self.raised == self.released + self.pending + self.available() + self.refundable


def main() -> None:
    full = quote(0, MAX_SUPPLY)
    assert full == 2_425_000 * USDC, full
    assert quote(499, 3) == 600 * USDC
    print(f"Full node sell-out raises {full / USDC:,.0f} USDC to treasury")
    for i, (cap, price) in enumerate(TIERS):
        start = TIERS[i - 1][0] + 1 if i else 1
        n = cap - start + 1
        print(f"  ids {start:>5}-{cap:<5} {n:>5} nodes x {price / USDC:>6,.0f} = {n * price / USDC:>12,.0f} USDC")

    # Mirrors test_FreezeGivesProRataRefundsOfUnreleased
    p = Pool(2 * USDC)
    assert p.support("fan1", 600 * USDC) == 300 * 10**18
    p.support("fan2", 400 * USDC)
    p.check()
    p.finalize(p.propose(500 * USDC), passed=True)
    p.check()
    p.propose(200 * USDC)
    p.check()
    p.freeze()
    p.check()
    assert p.refund("fan1") == 300 * USDC
    assert p.refund("fan2") == 200 * USDC
    print("Vault scenario: raised 1,000 / released 500 / refunds 300 + 200 — OK")


if __name__ == "__main__":
    main()
