import Foundation

final class FormatDetector {
    func detectFormat(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 4 {
            return nil
        }

        if looksLikeJSON(trimmed) || looksLikeSourceCode(trimmed) {
            return nil
        }

        if trimmed.contains("@<TRIPOS>") {
            return "mol2"
        }

        if trimmed.contains("$$$$") && trimmed.contains("M  END") {
            return "sdf"
        }

        if trimmed.contains("M  END") && (trimmed.contains("V2000") || trimmed.contains("V3000")) {
            return "mol"
        }

        if isLikelyPDB(trimmed) {
            return "pdb"
        }

        if isLikelyCIF(trimmed) {
            return "mmcif"
        }

        if isLikelyXYZ(trimmed) {
            return "xyz"
        }

        return nil
    }

    private func looksLikeJSON(_ text: String) -> Bool {
        let first = text.first
        return first == "{" || first == "["
    }

    private func looksLikeSourceCode(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("class ") || lowered.contains("import ") || lowered.contains("def ")
    }

    private func isLikelyPDB(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }

        let prefixes = ["ATOM", "HETATM", "HEADER", "MODEL", "COMPND", "TITLE"]
        var matchCount = 0
        for line in lines.prefix(50) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if prefixes.contains(where: { trimmed.hasPrefix($0) }) {
                matchCount += 1
            }
        }
        return matchCount >= 2
    }

    private func isLikelyCIF(_ text: String) -> Bool {
        if text.lowercased().hasPrefix("data_") {
            return true
        }
        return text.contains("_atom_site.")
    }

    private func isLikelyXYZ(_ text: String) -> Bool {
        let lines = text.split(whereSeparator: \.isNewline).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 3 else { return false }
        guard let atomCount = Int(lines[0]), atomCount > 0 else { return false }
        let atomLines = lines.dropFirst(2)
        return atomLines.prefix(atomCount).allSatisfy { !$0.isEmpty }
    }
}
