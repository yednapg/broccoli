import BroccoliCore
import Foundation

let entries = (0..<10_000).map { index in
    SearchEntry(
        id: "benchmark:\(index)",
        kind: index.isMultiple(of: 3) ? .application : (index.isMultiple(of: 2) ? .systemSetting : .action),
        title: "Benchmark Application \(index)",
        subtitle: "Synthetic entry",
        keywords: ["utility", "sample", "item \(index)"],
        target: .action(id: "benchmark.\(index)")
    )
}
let snapshot = SearchSnapshot(entries: entries)
let engine = SearchEngine()
let queries = ["b", "bench", "application 99", "ba9", "utility", "sample", "9999"]
var durations: [Double] = []
var durationsByQuery: [String: [Double]] = [:]

for iteration in 0..<300 {
    let query = queries[iteration % queries.count]
    let start = ContinuousClock.now
    _ = engine.search(query: query, snapshot: snapshot, usage: [:])
    let duration = start.duration(to: .now).components
    let milliseconds = Double(duration.seconds) * 1_000
        + Double(duration.attoseconds) / 1_000_000_000_000_000
    if iteration >= 20 {
        durations.append(milliseconds)
        durationsByQuery[query, default: []].append(milliseconds)
    }
}

durations.sort()
let p95Index = min(durations.count - 1, Int(Double(durations.count) * 0.95))
let p95 = durations[p95Index]
let median = durations[durations.count / 2]
print(String(format: "10,000 entries: median %.3f ms, p95 %.3f ms", median, p95))
for query in queries {
    let values = durationsByQuery[query, default: []].sorted()
    guard !values.isEmpty else { continue }
    let queryP95 = values[min(values.count - 1, Int(Double(values.count) * 0.95))]
    print(String(format: "  %-16@ p95 %.3f ms", query as NSString, queryP95))
}
if p95 > 10 {
    fputs("Performance gate failed: p95 exceeds 10 ms\n", stderr)
    exit(1)
}

let calculator = CalculatorEngine()
let expressions = ["2 + 2", "sqrt(144)", "10 km in mi", "32 f in c", "sin(pi / 2)"]
var calculatorDurations: [Double] = []
for iteration in 0..<1_000 {
    let start = ContinuousClock.now
    _ = calculator.evaluate(expressions[iteration % expressions.count])
    let duration = start.duration(to: .now).components
    if iteration >= 50 {
        calculatorDurations.append(
            Double(duration.seconds) * 1_000
                + Double(duration.attoseconds) / 1_000_000_000_000_000
        )
    }
}
calculatorDurations.sort()
let calculatorP95 = calculatorDurations[
    min(calculatorDurations.count - 1, Int(Double(calculatorDurations.count) * 0.95))
]
print(String(format: "Calculator: p95 %.3f ms", calculatorP95))
if calculatorP95 > 2 {
    fputs("Performance gate failed: calculator p95 exceeds 2 ms\n", stderr)
    exit(1)
}

let clipboardPreviews = (0..<1_000).map { "Clipboard item \($0) with reusable local text" }
    .map(SearchNormalizer.normalize)
var clipboardDurations: [Double] = []
for iteration in 0..<500 {
    let query = iteration.isMultiple(of: 2) ? "item 99" : "reusable"
    let normalized = SearchNormalizer.normalize(query)
    let start = ContinuousClock.now
    _ = clipboardPreviews.filter { $0.contains(normalized) }
    let duration = start.duration(to: .now).components
    if iteration >= 25 {
        clipboardDurations.append(
            Double(duration.seconds) * 1_000
                + Double(duration.attoseconds) / 1_000_000_000_000_000
        )
    }
}
clipboardDurations.sort()
let clipboardP95 = clipboardDurations[
    min(clipboardDurations.count - 1, Int(Double(clipboardDurations.count) * 0.95))
]
print(String(format: "Clipboard filter (1,000 items): p95 %.3f ms", clipboardP95))
if clipboardP95 > 5 {
    fputs("Performance gate failed: clipboard filter p95 exceeds 5 ms\n", stderr)
    exit(1)
}
