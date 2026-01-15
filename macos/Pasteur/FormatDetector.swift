import Foundation

final class FormatDetector {
    func detectFormat(for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
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

        if isLikelySMILES(trimmed) {
            return "smiles"
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
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count >= 3 else { return false }

        let firstTokens = lines[0].split(whereSeparator: \.isWhitespace)
        if let firstToken = firstTokens.first, let atomCount = Int(firstToken), atomCount > 0 {
            let startsWithAtom = lines.count > 1 && looksLikeAtomRecord(lines[1])
            let atomLines = startsWithAtom ? lines.dropFirst(1) : lines.dropFirst(2)
            guard atomLines.count >= atomCount else { return false }
            return atomLines.prefix(atomCount).allSatisfy { looksLikeAtomRecord($0) }
        }

        if looksLikeAtomRecord(lines[0]) {
            return lines.allSatisfy { looksLikeAtomRecord($0) }
        }

        return false
    }

    private func looksLikeAtomRecord(_ line: String) -> Bool {
        let tokens = line.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 4 else { return false }
        return tokens[1...3].allSatisfy { Double($0) != nil }
    }

    private func isLikelySMILES(_ text: String) -> Bool {
        // Single line only (not multi-line like PDB/XYZ)
        let lines = text.split(whereSeparator: \.isNewline)
        guard lines.count <= 2 else { return false }

        let smiles = String(lines[0]).trimmingCharacters(in: .whitespaces)

        // Length check: SMILES 1-500 chars (allow C, O, N, etc.)
        guard smiles.count >= 1 && smiles.count <= 500 else { return false }

        // Allowed SMILES character set
        let smilesCharSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789@+\\-[]()=#$/\\%.")
        guard smiles.unicodeScalars.allSatisfy({ smilesCharSet.contains($0) }) else { return false }

        // Must contain at least one organic atom symbol
        let organicAtoms = ["C", "N", "O", "S", "P", "F", "Cl", "Br", "I", "c", "n", "o", "s", "p"]
        guard organicAtoms.contains(where: { smiles.contains($0) }) else { return false }

        // Negative filters: exclude XYZ coordinate patterns
        let tokens = smiles.split(whereSeparator: \.isWhitespace)
        if tokens.count >= 4 {
            // Check if looks like "ELEMENT X Y Z" (XYZ format)
            if tokens[1...3].allSatisfy({ Double($0) != nil }) {
                return false
            }
        }

        // Exclude file paths
        if smiles.contains("/") || smiles.contains("\\") {
            return false
        }

        // Check balanced parentheses and brackets
        var parenCount = 0
        var bracketCount = 0
        for char in smiles {
            if char == "(" { parenCount += 1 }
            if char == ")" { parenCount -= 1 }
            if char == "[" { bracketCount += 1 }
            if char == "]" { bracketCount -= 1 }
            if parenCount < 0 || bracketCount < 0 { return false }
        }
        guard parenCount == 0 && bracketCount == 0 else { return false }

        Logger.log("[FormatDetector] SMILES detected: '\(smiles)'")
        return true
    }
}

