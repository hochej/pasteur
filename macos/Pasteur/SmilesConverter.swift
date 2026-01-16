import Foundation

enum SmilesConversionError: LocalizedError {
    case openBabelNotConfigured
    case openBabelNotFound(String)
    case invalidSMILES(String)
    case conversionTimeout
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .openBabelNotConfigured:
            return "OpenBabel path not configured. Set it in Preferences."
        case .openBabelNotFound(let path):
            return "OpenBabel not found at: \(path)"
        case .invalidSMILES(let message):
            return "Invalid SMILES: \(message)"
        case .conversionTimeout:
            return "SMILES conversion timed out (complex structure)"
        case .invalidOutput:
            return "SMILES conversion produced invalid output"
        }
    }
}

final class SmilesConverter {
    private var conversionCache: [String: String] = [:]  // LRU cache
    private let cacheLimit = 10
    private var openBabelPath: String

    init(openBabelPath: String) {
        self.openBabelPath = openBabelPath
    }

    func updateOpenBabelPath(_ path: String) {
        self.openBabelPath = path
    }

    // Convert SMILES to XYZ format
    func convertToXYZ(_ smiles: String) async throws -> String {
        // Check cache
        if let cached = conversionCache[smiles] {
            Logger.log("[Pasteur] SMILES cache hit")
            return cached
        }

        guard !openBabelPath.isEmpty else {
            throw SmilesConversionError.openBabelNotConfigured
        }

        // Verify OpenBabel exists
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: openBabelPath) else {
            throw SmilesConversionError.openBabelNotFound(openBabelPath)
        }

        let xyz = try await convertWithOpenBabel(smiles)
        cacheResult(smiles: smiles, xyz: xyz)
        return xyz
    }

    private func convertWithOpenBabel(_ smiles: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: openBabelPath)
        process.arguments = ["-:\(smiles)", "-oxyz", "--gen3d"]

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()

                // Timeout after 5 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if process.isRunning {
                        process.terminate()
                        continuation.resume(throwing: SmilesConversionError.conversionTimeout)
                    }
                }

                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: SmilesConversionError.invalidSMILES(errorMsg))
                    return
                }

                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                guard let xyz = String(data: data, encoding: .utf8), !xyz.isEmpty else {
                    continuation.resume(throwing: SmilesConversionError.invalidOutput)
                    return
                }

                continuation.resume(returning: xyz)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func cacheResult(smiles: String, xyz: String) {
        conversionCache[smiles] = xyz
        if conversionCache.count > cacheLimit {
            // Remove oldest entry (simple approach - remove first)
            if let firstKey = conversionCache.keys.first {
                conversionCache.removeValue(forKey: firstKey)
            }
        }
    }
}
