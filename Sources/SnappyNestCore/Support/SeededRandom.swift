import Foundation

/// Deterministic pseudo-random source. Uses a 64-bit xoshiro256** mixer —
/// small, fast, and identical across platforms so the same seed produces the
/// same action sequence in tests as it does at runtime. GameplayKit's
/// GKMersenneTwisterRandomSource would also work but pulls in a heavier
/// framework; this stays in Foundation so tests run without extra deps.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    public var state: (UInt64, UInt64, UInt64, UInt64)

    public init(seed: UInt64) {
        // SplitMix64 to spread the seed across four state words.
        var s = seed &+ 0x9E37_79B9_7F4A_7C15
        func mix() -> UInt64 {
            s = s &+ 0x9E37_79B9_7F4A_7C15
            var z = s
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        self.state = (mix(), mix(), mix(), mix())
        if state.0 == 0 && state.1 == 0 && state.2 == 0 && state.3 == 0 {
            state.0 = 1
        }
    }

    public mutating func next() -> UInt64 {
        let result = rotl(state.1 &* 5, 7) &* 9
        let t = state.1 &<< 17
        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        state.2 ^= t
        state.3 = rotl(state.3, 45)
        return result
    }

    public mutating func nextDouble() -> Double {
        // 53-bit fraction in [0, 1).
        Double(next() >> 11) * (1.0 / Double(UInt64(1) << 53))
    }

    public mutating func nextInt(in range: Range<Int>) -> Int {
        precondition(range.lowerBound < range.upperBound)
        let span = UInt64(range.upperBound - range.lowerBound)
        return range.lowerBound + Int(next() % span)
    }

    private func rotl(_ x: UInt64, _ k: UInt64) -> UInt64 {
        (x &<< k) | (x &>> (64 &- k))
    }
}
