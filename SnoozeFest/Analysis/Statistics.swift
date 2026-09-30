import Foundation

/// Small, dependency-free statistics toolkit.
enum Stats {
    static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? .nan : xs.reduce(0, +) / Double(xs.count)
    }

    /// Sample variance (n - 1 denominator).
    static func variance(_ xs: [Double]) -> Double {
        guard xs.count > 1 else { return .nan }
        let m = mean(xs)
        return xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
    }

    static func standardDeviation(_ xs: [Double]) -> Double { variance(xs).squareRoot() }

    // MARK: - Welch's t-test

    struct WelchResult: Equatable {
        /// mean(after) - mean(before)
        var difference: Double
        var t: Double
        var degreesOfFreedom: Double
        /// Two-sided p-value.
        var p: Double
        /// 95% confidence interval for the difference.
        var ciLow: Double
        var ciHigh: Double
        /// Cohen's d using the pooled standard deviation (NaN when both groups are constant).
        var cohensD: Double
    }

    /// Two-sided Welch's unequal-variance t-test comparing `after` against `before`.
    /// Returns nil when either group has fewer than 2 values.
    static func welch(before: [Double], after: [Double]) -> WelchResult? {
        guard before.count >= 2, after.count >= 2 else { return nil }
        return welch(meanBefore: mean(before), varianceBefore: variance(before), countBefore: Double(before.count),
                     meanAfter: mean(after), varianceAfter: variance(after), countAfter: Double(after.count))
    }

    /// Welch's t-test from summary statistics (counts must be at least 2).
    /// Skipping the confidence interval (NaN) avoids the quantile search when only `p` is needed.
    static func welch(meanBefore m1: Double, varianceBefore v1: Double, countBefore n1: Double,
                      meanAfter m2: Double, varianceAfter v2: Double, countAfter n2: Double,
                      confidenceInterval: Bool = true) -> WelchResult {
        let diff = m2 - m1
        let a = v1 / n1, b = v2 / n2
        let se = (a + b).squareRoot()
        let pooledSD = (((n1 - 1) * v1 + (n2 - 1) * v2) / (n1 + n2 - 2)).squareRoot()
        let d = pooledSD > 0 ? diff / pooledSD : .nan

        guard se > 0 else {
            // Both groups constant: no sampling noise to test against.
            return WelchResult(difference: diff, t: diff == 0 ? 0 : .infinity * (diff > 0 ? 1 : -1),
                               degreesOfFreedom: n1 + n2 - 2, p: diff == 0 ? 1 : 0,
                               ciLow: diff, ciHigh: diff, cohensD: d)
        }
        let df = (a + b) * (a + b) / (a * a / (n1 - 1) + b * b / (n2 - 1))
        let t = diff / se
        let p = studentTTwoSidedP(t: t, df: df)
        let tCrit = confidenceInterval ? studentTQuantile(p: 0.975, df: df) : .nan
        return WelchResult(difference: diff, t: t, degreesOfFreedom: df, p: p,
                           ciLow: diff - tCrit * se, ciHigh: diff + tCrit * se, cohensD: d)
    }

    // MARK: - Fisher's exact test

    /// Two-sided Fisher's exact test for the 2x2 table [[a, b], [c, d]].
    /// Sums the probabilities of all tables at least as extreme as the observed one
    /// (same method as scipy.stats.fisher_exact).
    static func fisherExact(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Double {
        let row1 = a + b, row2 = c + d, col1 = a + c
        let n = row1 + row2
        guard n > 0 else { return 1 }
        let lo = max(0, col1 - row2), hi = min(row1, col1)
        func logP(_ x: Int) -> Double {
            logChoose(row1, x) + logChoose(row2, col1 - x) - logChoose(n, col1)
        }
        let observed = logP(a)
        var total = 0.0
        for x in lo...hi {
            let lp = logP(x)
            if lp <= observed + 1e-7 { total += exp(lp) }
        }
        return min(1, total)
    }

    static func logChoose(_ n: Int, _ k: Int) -> Double {
        lgamma(Double(n + 1)) - lgamma(Double(k + 1)) - lgamma(Double(n - k + 1))
    }

    // MARK: - Student's t distribution

    static func studentTTwoSidedP(t: Double, df: Double) -> Double {
        guard t.isFinite else { return 0 }
        return regularizedIncompleteBeta(x: df / (df + t * t), a: df / 2, b: 0.5)
    }

    static func studentTCDF(t: Double, df: Double) -> Double {
        let tail = 0.5 * studentTTwoSidedP(t: t, df: df)
        return t >= 0 ? 1 - tail : tail
    }

    /// Inverse CDF via bisection (plenty fast for one CI per intervention).
    static func studentTQuantile(p: Double, df: Double) -> Double {
        var lo = -1000.0, hi = 1000.0
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if studentTCDF(t: mid, df: df) < p { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Regularized incomplete beta I_x(a, b) using Lentz's continued fraction.
    static func regularizedIncompleteBeta(x: Double, a: Double, b: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        let lnFront = lgamma(a + b) - lgamma(a) - lgamma(b) + a * log(x) + b * log(1 - x)
        if x < (a + 1) / (a + b + 2) {
            return exp(lnFront) * betaContinuedFraction(x: x, a: a, b: b) / a
        } else {
            return 1 - exp(lnFront) * betaContinuedFraction(x: 1 - x, a: b, b: a) / b
        }
    }

    private static func betaContinuedFraction(x: Double, a: Double, b: Double) -> Double {
        let tiny = 1e-300, eps = 1e-15
        let qab = a + b, qap = a + 1, qam = a - 1
        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d
        for m in 1...300 {
            let m = Double(m), m2 = 2 * m
            var aa = m * (b - m) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c
            aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d; if abs(d) < tiny { d = tiny }
            c = 1 + aa / c; if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < eps { break }
        }
        return h
    }

    // MARK: - Moving average

    /// Trailing moving average of uninterrupted hours (first stretch) over the last
    /// `window` calendar days (inclusive), averaging whatever nights were recorded in that span.
    static func movingAverage(_ nights: [Night], window: Int) -> [(date: Date, value: Double)] {
        let sorted = nights.filter { !$0.excluded }.sorted { $0.date < $1.date }
        var result: [(Date, Double)] = []
        var start = 0
        var sum = 0.0
        for (i, night) in sorted.enumerated() {
            sum += night.uninterruptedHours
            while Day.between(sorted[start].date, night.date) >= window {
                sum -= sorted[start].uninterruptedHours
                start += 1
            }
            result.append((night.date, sum / Double(i - start + 1)))
        }
        return result
    }
}
