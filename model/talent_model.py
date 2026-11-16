"""Talent Token economic model.

Mirrors the contract math in NodeLicense (tier pricing) and SupportVault
(escrow, milestones, pro-rata refunds). Keep in sync with src/.
Run: python3 model/talent_model.py
"""

USDC = 10**6
MAX_SUPPLY = 5_000

# Step curve — same as script/Deploy.s.sol and NodeLicense.priceOf
START_PRICE = 500 * USDC  # nodes 1-100
PRICE_STEP = 100 * USDC  # +$100 ...
STEP_SIZE = 100  # ... every 100 nodes


def price_of(token_id: int) -> int:
    if not 1 <= token_id <= MAX_SUPPLY:
        raise ValueError("sold out")
    return START_PRICE + PRICE_STEP * ((token_id - 1) // STEP_SIZE)


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
    assert full == 14_750_000 * USDC, full
    assert quote(99, 3) == 1_700 * USDC
    assert price_of(5_000) == 5_400 * USDC
    print(f"Full node sell-out raises {full / USDC:,.0f} USDC to treasury")
    raised = 0
    for batch in range(0, MAX_SUPPLY, STEP_SIZE):
        raised += STEP_SIZE * price_of(batch + 1)
        sold = batch + STEP_SIZE
        if sold in (100, 500, 1_000, 2_000, 3_000, 4_000, 5_000):
            print(f"  after {sold:>5,} nodes: price ${price_of(sold) / USDC:>5,.0f}, raised {raised / USDC:>12,.0f} USDC")

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
