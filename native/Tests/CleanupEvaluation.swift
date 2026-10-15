import Foundation

private struct CleanupCase: Decodable {
    let id: String
    let input: String
    let balanced: String
    let model: Bool?
}

@main enum CleanupEvaluation {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else { fatalError("Pass the cleanup fixture JSON path") }
        let cases = try JSONDecoder().decode([CleanupCase].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        var failures = [String]()
        for item in cases {
            let actual = TranscriptPolisher.clean(item.input)
            if actual != item.balanced {
                failures.append(item.id)
                print("FAIL \(item.id): \(actual.debugDescription), expected \(item.balanced.debugDescription)")
            }
        }
        if arguments.contains("--model") {
            let polisher = TranscriptPolisher.system
            guard polisher.availability.available else { fatalError(polisher.availability.message) }
            for item in cases where item.model == true {
                let result = try await polisher.polish(item.input, mode: .accurate)
                let valid = result.text == item.balanced || TranscriptPolisher.accepts(result.text, original: item.balanced)
                if !valid { failures.append("model-\(item.id)") }
                print("\(valid ? "PASS" : "FAIL") model \(item.id): \(result.text.debugDescription) notice=\(result.notice.debugDescription)")
            }
        }
        guard failures.isEmpty else {
            print("Failed cases: \(failures.joined(separator: ", "))")
            exit(1)
        }
        print("PASS cleanup fixture outputs")
    }

}
