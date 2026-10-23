import SwiftUI

enum Block: Equatable {
    case heading(Int, String)
    case paragraph(String)
    case bullet(Int, String)
    case ordered(Int, String, String)
    case task(Int, Bool, String)
    case quote(String)
    case code(String)
    case rule
}

// shortcut: line-based subset of Markdown (no tables, no images, no nested quotes); upgrade to swift-markdown if needed.
enum Markdown {
    static func parse(_ source: String) -> [Block] {
        var lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // Obsidian properties (YAML frontmatter)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
            lines.removeSubrange(0...end)
        }

        var blocks: [Block] = []
        var para: [String] = []
        var code: [String]?
        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if let c = code { blocks.append(.code(c.joined(separator: "\n"))); code = nil } else { flush(); code = [] }
                continue
            }
            if code != nil { code!.append(line); continue }
            if trimmed.isEmpty { flush(); continue }

            let spaces = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let indent = (spaces + 2) / 4

            if let m = trimmed.wholeMatch(of: /(#{1,6})\s+(.*)/) {
                flush(); blocks.append(.heading(m.1.count, String(m.2)))
            } else if trimmed.wholeMatch(of: /(\*\s*){3,}|(-\s*){3,}|(_\s*){3,}/) != nil {
                flush(); blocks.append(.rule)
            } else if let m = trimmed.wholeMatch(of: /[-*+]\s+\[([ xX])\]\s*(.*)/) {
                flush(); blocks.append(.task(indent, m.1 != " ", String(m.2)))
            } else if let m = trimmed.wholeMatch(of: /[-*+]\s+(.*)/) {
                flush(); blocks.append(.bullet(indent, String(m.1)))
            } else if let m = trimmed.wholeMatch(of: /(\d+)[.)]\s+(.*)/) {
                flush(); blocks.append(.ordered(indent, String(m.1), String(m.2)))
            } else if let m = trimmed.wholeMatch(of: />\s?(.*)/) {
                flush()
                let s = String(m.1).replacing(/^\[!\w+\][+-]?\s*/, with: "") // callout marker
                if case .quote(let prev) = blocks.last {
                    blocks[blocks.count - 1] = .quote(prev.isEmpty ? s : prev + "\n" + s)
                } else {
                    blocks.append(.quote(s))
                }
            } else {
                para.append(trimmed)
            }
        }
        if let c = code { blocks.append(.code(c.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    static func inline(_ s: String) -> AttributedString {
        var t = s.replacing(/!\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/) { "🖼 \($0.1)" }
        t = t.replacing(/\[\[([^\]|#]*)(#[^\]|]*)?(?:\|([^\]]+))?\]\]/) { m in
            let label = m.3.map(String.init) ?? String(m.1) + String(m.2 ?? "")
            return "[\(label)](\(obsidianURL("file", String(m.1)).absoluteString))"
        }
        t = t.replacing(/==([^=]+)==/) { "[\($0.1)](mdw-hl:x)" }

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible)
        var a = (try? AttributedString(markdown: t, options: options)) ?? AttributedString(s)
        for range in a.runs.filter({ $0.link?.scheme == "mdw-hl" }).map(\.range) {
            a[range].link = nil
            a[range].swiftUI.backgroundColor = Color.yellow.opacity(0.35)
        }
        for range in a.runs.filter({ $0.inlinePresentationIntent?.contains(.code) == true }).map(\.range) {
            a[range].swiftUI.font = .system(size: 12, design: .monospaced)
            a[range].swiftUI.backgroundColor = Color.primary.opacity(0.12)
        }
        return a
    }

    static func obsidianURL(_ key: String, _ value: String) -> URL {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?()")
        return URL(string: "obsidian://open?\(key)=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""))!
    }

    static func selfTest() {
        let b = parse("---\ntitle: x\n---\n# Hi\n- [x] done\n- item\n\t- sub\n2. two\n> [!note] Callout\n> more\n```\ncode\n```\n---\ntext\nline2")
        let expected: [Block] = [.heading(1, "Hi"), .task(0, true, "done"), .bullet(0, "item"), .bullet(1, "sub"),
                                 .ordered(0, "2", "two"), .quote("Callout\nmore"), .code("code"), .rule, .paragraph("text\nline2")]
        precondition(b == expected, "parse: \(b)")
        let a = inline("see [[Note|Alias]], [[Other]] and ==hl== **b**")
        precondition(String(a.characters) == "see Alias, Other and hl b", "inline: \(String(a.characters))")
        precondition(a.runs.contains { $0.swiftUI.backgroundColor != nil }, "highlight missing")
        precondition(a.runs.contains { $0.link?.absoluteString == "obsidian://open?file=Note" }, "wikilink missing")
        print("selftest ok")
    }
}

struct MarkdownView: View {
    let blocks: [Block]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in row(block) }
        }
    }

    @ViewBuilder private func row(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let s):
            Text(Markdown.inline(s))
                .font(level == 1 ? .title2.bold() : level == 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .paragraph(let s):
            Text(Markdown.inline(s))
        case .bullet(let i, let s):
            item(i, Text("•").foregroundStyle(.secondary), s)
        case .ordered(let i, let n, let s):
            item(i, Text("\(n).").foregroundStyle(.secondary).monospacedDigit(), s)
        case .task(let i, let done, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.accentColor : .secondary)
                Text(Markdown.inline(s)).strikethrough(done).foregroundStyle(done ? .secondary : .primary)
            }
            .padding(.leading, CGFloat(i) * 16)
        case .quote(let s):
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(.tertiary).frame(width: 3)
                Text(Markdown.inline(s)).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let s):
            Text(s)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        case .rule:
            Divider()
        }
    }

    private func item(_ indent: Int, _ marker: Text, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            marker
            Text(Markdown.inline(s))
        }
        .padding(.leading, CGFloat(indent) * 16)
    }
}
