"""SeededRng (xorshift32 + 31-bit seed hash) exactly as specified in docs/dev/unity-port.md
section 4. Python ints are unbounded and ">>" is arithmetic, like C# long."""
M32 = 0xFFFFFFFF

def mix(a: int, b: int) -> int:
    # a, b are signed 64-bit; Python ints are unbounded and >> is arithmetic like C# long.
    h = (a & 0x7FFFFFFF) ^ ((a >> 31) & 0x7FFFFFFF)
    h = (h * 0x9E3779B1) & M32
    h ^= (b & 0x7FFFFFFF)
    h = ((h & 0x7FFFFFFF) * 0x85EBCA77) & M32
    h ^= h >> 15
    h = ((h & 0x7FFFFFFF) * 0xC2B2AE3D) & M32
    h ^= h >> 13
    return h & 0x7FFFFFFF

class Rng:
    def __init__(self, seed=1):
        self.s = mix(seed, 0x2545F491)
        if self.s == 0:
            self.s = 0x6D2B79F5
        for _ in range(3):
            self.next_u32()
    def next_u32(self):
        x = self.s
        x = (x ^ (x << 13)) & M32
        x = x ^ (x >> 17)
        x = (x ^ (x << 5)) & M32
        self.s = x
        return x
    def range_int(self, lo, hi):
        if hi <= lo:
            return lo
        return lo + self.next_u32() % (hi - lo + 1)
    def chance_bp(self, bp):
        if bp <= 0: return False
        if bp >= 10000: return True
        return self.next_u32() % 10000 < bp
    def pick(self, arr):
        return arr[self.next_u32() % len(arr)]
