import SwiftUI

struct MarkdownView: View {
    let text: String
    @State private var showingCitations = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(processedLines.enumerated()), id: \.offset) { _, line in
                renderLine(line)
            }
        }
        .textSelection(.enabled)
        .lineSpacing(4)
    }
    
    private var processedLines: [ProcessedLine] {
        lines.map { line in
            ProcessedLine(
                content: line,
                type: determineLineType(line),
                citations: extractCitations(line)
            )
        }
    }
    
    @ViewBuilder
    private func renderLine(_ line: ProcessedLine) -> some View {
        switch line.type {
        case .empty:
            Spacer().frame(height: 8)
            
        case .heading(let level):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(attributed(headingText(from: line.content)))
                    .font(fontForHeading(level))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if !line.citations.isEmpty {
                    citationBadges(line.citations)
                }
            }
            .padding(.vertical, 4)
            
        case .bullet:
            if let bullet = bulletBody(line.content) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("•")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(AppTheme.accentColor)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(attributed(bullet))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if !line.citations.isEmpty {
                            citationBadges(line.citations)
                        }
                    }
                }
                .padding(.leading, 4)
            }
            
        case .code:
            Text(codeBlockText(line.content))
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
            
        case .divider:
            Divider()
                .padding(.vertical, 4)
            
        case .regular:
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(attributed(line.content))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !line.citations.isEmpty {
                    citationBadges(line.citations)
                }
            }
        }
    }
    
    @ViewBuilder
    private func citationBadges(_ citations: [Int]) -> some View {
        HStack(spacing: 4) {
            ForEach(citations, id: \.self) { num in
                Text("[\(num)]")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [AppTheme.accentColor, AppTheme.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    )
                    .shadow(color: AppTheme.accentColor.opacity(0.3), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    enum LineType {
        case empty
        case heading(level: Int)
        case bullet
        case code
        case divider
        case regular
    }
    
    struct ProcessedLine {
        let content: String
        let type: LineType
        let citations: [Int]
    }
    
    private func determineLineType(_ line: String) -> LineType {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.isEmpty { return .empty }
        if let level = headingLevel(line) { return .heading(level: level) }
        if bulletBody(line) != nil { return .bullet }
        if isCodeBlock(line) { return .code }
        if trimmed == "---" || trimmed == "===" { return .divider }
        
        return .regular
    }
    
    private func extractCitations(_ line: String) -> [Int] {
        var citations: [Int] = []
        let pattern = "\\[(\\d+)\\]"
        
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, range: range)
            
            for match in matches {
                if match.numberOfRanges >= 2,
                   let numRange = Range(match.range(at: 1), in: line),
                   let num = Int(line[numRange]) {
                    citations.append(num)
                }
            }
        }
        
        return Array(Set(citations)).sorted()
    }

    private var lines: [String] {
        // Normalize line endings and keep empty lines for spacing
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private func headingLevel(_ line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let count = trimmed.prefix { $0 == "#" }.count
        // Markdown requires a space after the hashes
        if count > 0, trimmed.dropFirst(count).first == " " { return min(count, 3) }
        return nil
    }

    private func headingText(from line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let count = trimmed.prefix { $0 == "#" }.count
        return String(trimmed.dropFirst(count)).trimmingCharacters(in: .whitespaces)
    }

    private func fontForHeading(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        default: return .title3
        }
    }

    private func bulletBody(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("- ") { return String(trimmed.dropFirst(2)) }
        if trimmed.hasPrefix("• ") { return String(trimmed.dropFirst(2)) }
        // Support numbered lists too
        if let match = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
            return String(trimmed[match.upperBound...])
        }
        return nil
    }
    
    private func isCodeBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("    ")
    }
    
    private func codeBlockText(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") {
            return String(trimmed.dropFirst(3))
        }
        return line
    }

    private func attributed(_ text: String) -> AttributedString {
        // Try to parse the text as markdown, with better error handling
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        
        do {
            // First try with inline-only parsing for better inline formatting
            let result = try AttributedString(markdown: text, options: options)
            return result
        } catch {
            // Fallback: try standard markdown parsing
            if let a = try? AttributedString(markdown: text) { 
                return a 
            }
            // If all else fails, return plain text
            return AttributedString(text)
        }
    }
}
