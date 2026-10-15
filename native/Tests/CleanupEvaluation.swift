import Foundation

private struct CleanupCase: Decodable {
    let id: String
    let input: String
    let balanced: String
    let model: Bool?
    let preserved: [String]?
}

private struct InvalidEdit: Decodable {
    let original: String
    let candidate: String
}

@main enum CleanupEvaluation {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else { fatalError("Pass the cleanup fixture JSON path") }
        let cases = try JSONDecoder().decode([CleanupCase].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        var failures = [String]()
        struct Unavailable: Error {}
        let unavailable = TranscriptPolisher(availability: .init(available: false, message: "Unavailable for test")) { _ in
            fatalError("Unavailable model must not run")
        }
        let failing = TranscriptPolisher(availability: .init(available: true, message: "Available for test")) { _ in
            throw Unavailable()
        }
        for item in cases {
            let fast = try await unavailable.polish(item.input, mode: .fast)
            if fast.text != item.input { failures.append("fast-\(item.id)") }
            for (name, polisher) in [("unavailable", unavailable), ("error", failing)] {
                let fallback = try await polisher.polish(item.input, mode: .accurate)
                if fallback.text != item.balanced { failures.append("\(name)-\(item.id)") }
            }
            let actual = TranscriptPolisher.clean(item.input)
            if TranscriptPolisher.clean(actual) != actual { failures.append("repeat-cleanup-\(item.id)") }
            if actual != item.balanced {
                failures.append(item.id)
                print("FAIL \(item.id): \(actual.debugDescription), expected \(item.balanced.debugDescription)")
            }
        }
        let invalidURL = URL(fileURLWithPath: arguments[1]).deletingLastPathComponent().appendingPathComponent("cleanup-invalid-edits.json")
        let invalidEdits = try JSONDecoder().decode([InvalidEdit].self, from: Data(contentsOf: invalidURL))
        for edit in invalidEdits where TranscriptPolisher.accepts(edit.candidate, original: edit.original) {
            failures.append("unsafe-edit")
            print("FAIL accepted unsafe edit: \(edit.original.debugDescription) -> \(edit.candidate.debugDescription)")
        }
        if arguments.contains("--model") {
            let polisher = TranscriptPolisher.system
            guard polisher.availability.available else { fatalError(polisher.availability.message) }
            for item in cases where item.model == true {
                let result = try await polisher.polish(item.input, mode: .accurate)
                let literalsPreserved = (item.preserved ?? []).allSatisfy { result.text.contains($0) }
                func words(_ text: String) -> [String] {
                    text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.map { $0.lowercased() }
                }
                let valid = literalsPreserved && words(result.text) == words(item.balanced)
                if !valid { failures.append("model-\(item.id)") }
                print("\(valid ? "PASS" : "FAIL") model \(item.id): \(result.text.debugDescription) notice=\(result.notice.debugDescription)")
            }
        }
        guard failures.isEmpty else {
            print("Failed cases: \(failures.joined(separator: ", "))")
            exit(1)
        }
        print("PASS \(cases.count) cleanup fixtures, fallback behavior, repeat cleanup, and \(invalidEdits.count) unsafe edit rejections")
    }

}
