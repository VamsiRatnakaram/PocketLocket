import Foundation

enum AnalysisDateWindow {
    static func domain(
        for dates: [Date],
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        let earliest = dates.min() ?? reference
        let latest = max(dates.max() ?? reference, reference)
        let start = calendar.dateInterval(of: .month, for: earliest)?.start
            ?? calendar.startOfDay(for: earliest)
        let end = calendar.dateInterval(of: .month, for: latest)?.end
            ?? latest.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    static func defaultSelection(
        in domain: DateInterval,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval {
        let cutoff = calendar.date(byAdding: .month, value: -12, to: domain.end) ?? domain.start
        return snappedToMonths(
            DateInterval(start: max(domain.start, cutoff), end: domain.end),
            in: domain,
            calendar: calendar
        )
    }

    static func clamped(_ selection: DateInterval, to domain: DateInterval) -> DateInterval {
        let start = min(max(selection.start, domain.start), domain.end)
        let end = max(min(selection.end, domain.end), start.addingTimeInterval(1))
        return DateInterval(start: start, end: min(end, domain.end))
    }

    static func fractions(for selection: DateInterval, in domain: DateInterval) -> ClosedRange<Double> {
        guard domain.duration > 0 else { return 0...1 }
        let clamped = clamped(selection, to: domain)
        let lower = clamped.start.timeIntervalSince(domain.start) / domain.duration
        let upper = clamped.end.timeIntervalSince(domain.start) / domain.duration
        return min(max(lower, 0), 1)...min(max(upper, 0), 1)
    }

    static func interval(for fractions: ClosedRange<Double>, in domain: DateInterval) -> DateInterval {
        let lower = min(max(fractions.lowerBound, 0), 1)
        let upper = min(max(fractions.upperBound, lower), 1)
        return DateInterval(
            start: domain.start.addingTimeInterval(domain.duration * lower),
            end: domain.start.addingTimeInterval(domain.duration * upper)
        )
    }

    static func date(for fraction: Double, in domain: DateInterval) -> Date {
        domain.start.addingTimeInterval(domain.duration * min(max(fraction, 0), 1))
    }

    static func monthBoundaries(
        in domain: DateInterval,
        calendar: Calendar = .current
    ) -> [Date] {
        var boundaries: [Date] = [domain.start]
        var date = domain.start
        while let next = calendar.date(byAdding: .month, value: 1, to: date), next < domain.end {
            boundaries.append(next)
            date = next
        }
        if boundaries.last != domain.end { boundaries.append(domain.end) }
        return boundaries
    }

    static func snappedToMonths(
        _ selection: DateInterval,
        in domain: DateInterval,
        calendar: Calendar = .current
    ) -> DateInterval {
        let boundaries = monthBoundaries(in: domain, calendar: calendar)
        guard boundaries.count >= 2 else { return domain }

        func nearestIndex(to date: Date) -> Int {
            boundaries.indices.min {
                abs(boundaries[$0].timeIntervalSince(date))
                    < abs(boundaries[$1].timeIntervalSince(date))
            } ?? 0
        }

        let lower = min(nearestIndex(to: selection.start), boundaries.count - 2)
        let upper = max(nearestIndex(to: selection.end), lower + 1)
        return DateInterval(start: boundaries[lower], end: boundaries[min(upper, boundaries.count - 1)])
    }

    static func fraction(for date: Date, in domain: DateInterval) -> Double {
        guard domain.duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(domain.start) / domain.duration, 0), 1)
    }

    /// Finds the selected slice in a newest-first collection without scanning
    /// transactions outside the window.
    static func indices(
        count: Int,
        dateAt: (Int) -> Date,
        in selection: DateInterval
    ) -> Range<Int> {
        func firstIndex(before boundary: Date) -> Int {
            var lower = 0
            var upper = count
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if dateAt(middle) >= boundary {
                    lower = middle + 1
                } else {
                    upper = middle
                }
            }
            return lower
        }

        let start = firstIndex(before: selection.end)
        let end = firstIndex(before: selection.start)
        return min(start, end)..<max(start, end)
    }
}
