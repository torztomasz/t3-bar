extension Comparable {
    /// For fractions and progress that must stay within their bounds whatever the clock or the provider reports.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
