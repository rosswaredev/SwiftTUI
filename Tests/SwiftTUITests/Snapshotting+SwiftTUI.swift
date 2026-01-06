import SnapshotTesting
@testable import SwiftTUI

enum SwiftTUISnapshotFormat: Sendable {
    /// Render only visible characters.
    case plain

    /// Render characters and annotate non-default foreground/background colors (and optionally
    /// attributes) in a compact, inline-friendly format.
    case styled
}

extension Snapshotting where Value: View, Format == String {
    /// Snapshots a `SwiftTUI.View` by rendering it into a fixed-size terminal viewport and
    /// returning its rendered contents as text.
    static func swiftTUI(
        width: Int = 80,
        height: Int = 24,
        format: SwiftTUISnapshotFormat = .plain,
        visibleWhitespace: Bool? = nil,
        includeAttributes: Bool = true,
        trimTrailingWhitespace: Bool = true,
        trimTrailingEmptyLines: Bool = true
    ) -> Snapshotting<Value, String> {
        Snapshotting<String, String>.lines.pullback { view in
            SwiftTUIViewSnapshotRenderer.render(
                view,
                viewport: Size(width: Extended(width), height: Extended(height)),
                format: format,
                visibleWhitespace: visibleWhitespace,
                includeAttributes: includeAttributes,
                trimTrailingWhitespace: trimTrailingWhitespace,
                trimTrailingEmptyLines: trimTrailingEmptyLines
            )
        }
    }
}

private enum SwiftTUIViewSnapshotRenderer {
    static func render<V: View>(
        _ view: V,
        viewport: Size,
        format: SwiftTUISnapshotFormat,
        visibleWhitespace: Bool?,
        includeAttributes: Bool,
        trimTrailingWhitespace: Bool,
        trimTrailingEmptyLines: Bool
    ) -> String {
        let node = Node(view: VStack(content: view).view)
        let window = Window()

        node.build()
        guard let control = node.control else {
            return "[SwiftTUISnapshotting] Failed to build root control."
        }

        window.addControl(control)
        window.layer.frame.size = viewport
        control.layout(size: viewport)

        window.firstResponder = control.firstSelectableElement
        window.firstResponder?.becomeFirstResponder()

        return render(
            layer: window.layer,
            viewport: viewport,
            format: format,
            visibleWhitespace: visibleWhitespace,
            includeAttributes: includeAttributes,
            trimTrailingWhitespace: trimTrailingWhitespace,
            trimTrailingEmptyLines: trimTrailingEmptyLines
        )
    }

    private static func render(
        layer: Layer,
        viewport: Size,
        format: SwiftTUISnapshotFormat,
        visibleWhitespace: Bool?,
        includeAttributes: Bool,
        trimTrailingWhitespace: Bool,
        trimTrailingEmptyLines: Bool
    ) -> String {
        switch format {
        case .plain:
            return renderPlain(
                layer: layer,
                viewport: viewport,
                trimTrailingWhitespace: trimTrailingWhitespace,
                trimTrailingEmptyLines: trimTrailingEmptyLines
            )
        case .styled:
            return renderStyled(
                layer: layer,
                viewport: viewport,
                visibleWhitespace: visibleWhitespace ?? true,
                includeAttributes: includeAttributes,
                trimTrailingWhitespace: trimTrailingWhitespace,
                trimTrailingEmptyLines: trimTrailingEmptyLines
            )
        }
    }

    private static func renderPlain(
        layer: Layer,
        viewport: Size,
        trimTrailingWhitespace: Bool,
        trimTrailingEmptyLines: Bool
    ) -> String {
        let width = viewport.width.intValue
        let height = viewport.height.intValue

        var lines: [String] = []
        lines.reserveCapacity(height)

        for line in 0 ..< height {
            var characters: [Character] = []
            characters.reserveCapacity(width)
            for column in 0 ..< width {
                let position = Position(column: Extended(column), line: Extended(line))
                characters.append(layer.cell(at: position)?.char ?? " ")
            }

            var renderedLine = String(characters)
            if trimTrailingWhitespace {
                renderedLine = renderedLine.trimmingTrailingSpaces()
            }
            lines.append(renderedLine)
        }

        if trimTrailingEmptyLines {
            while lines.last?.isEmpty == true {
                lines.removeLast()
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func renderStyled(
        layer: Layer,
        viewport: Size,
        visibleWhitespace: Bool,
        includeAttributes: Bool,
        trimTrailingWhitespace: Bool,
        trimTrailingEmptyLines: Bool
    ) -> String {
        let width = viewport.width.intValue
        let height = viewport.height.intValue

        let defaultAttributes = CellAttributes()
        let defaultStyle = SwiftTUISnapshotStyle(
            foreground: .default,
            background: .default,
            attributes: defaultAttributes
        )

        var cells: [[Cell]] = .init(repeating: .init(repeating: Cell(char: " "), count: width), count: height)
        for line in 0 ..< height {
            for column in 0 ..< width {
                let position = Position(column: Extended(column), line: Extended(line))
                cells[line][column] = layer.cell(at: position) ?? Cell(char: " ")
            }
        }

        func style(for cell: Cell) -> SwiftTUISnapshotStyle {
            SwiftTUISnapshotStyle(
                foreground: cell.foregroundColor,
                background: cell.backgroundColor ?? .default,
                attributes: cell.attributes
            )
        }

        func cellIsMeaningful(_ cell: Cell) -> Bool {
            if cell.char != " " { return true }
            let cellStyle = style(for: cell)
            if cellStyle.foreground != .default { return true }
            if cellStyle.background != .default { return true }
            if includeAttributes, cellStyle.attributes != defaultAttributes { return true }
            return false
        }

        var lastContentRow = height - 1
        if trimTrailingEmptyLines {
            lastContentRow = -1
            for row in (0 ..< height).reversed() {
                if cells[row].contains(where: cellIsMeaningful) {
                    lastContentRow = row
                    break
                }
            }
            if lastContentRow == -1 {
                return ""
            }
        }

        var lines: [String] = []
        lines.reserveCapacity(lastContentRow + 1)

        for row in 0 ... lastContentRow {
            var lastColumn = width - 1
            if trimTrailingWhitespace {
                lastColumn = -1
                for col in (0 ..< width).reversed() {
                    if cellIsMeaningful(cells[row][col]) {
                        lastColumn = col
                        break
                    }
                }
                if lastColumn == -1 {
                    lines.append("")
                    continue
                }
            }

            var line = ""
            line.reserveCapacity(lastColumn + 1)

            var currentStyle = defaultStyle
            var isStyled = false

            for col in 0 ... lastColumn {
                let cell = cells[row][col]
                let cellStyle = style(for: cell)
                let normalizedStyle: SwiftTUISnapshotStyle
                if includeAttributes {
                    normalizedStyle = cellStyle
                } else {
                    normalizedStyle = SwiftTUISnapshotStyle(
                        foreground: cellStyle.foreground,
                        background: cellStyle.background,
                        attributes: defaultAttributes
                    )
                }

                if normalizedStyle != currentStyle {
                    if isStyled {
                        line += "⟦/⟧"
                        isStyled = false
                    }
                    if normalizedStyle != defaultStyle {
                        line += "⟦\(normalizedStyle.snapshotLabel)⟧"
                        isStyled = true
                    }
                    currentStyle = normalizedStyle
                }

                if cell.char == " ", visibleWhitespace, normalizedStyle != defaultStyle {
                    line.append("·")
                } else {
                    line.append(cell.char)
                }
            }

            if isStyled {
                line += "⟦/⟧"
            }
            lines.append(line)
        }

        return lines.joined(separator: "\n")
    }
}

private struct SwiftTUISnapshotStyle: Equatable {
    let foreground: Color
    let background: Color
    let attributes: CellAttributes

    var snapshotLabel: String {
        var parts: [String] = []
        if foreground != .default {
            parts.append("fg=\(TerminalColor(foregroundEscapeSequence: foreground.foregroundEscapeSequence).label)")
        }
        if background != .default {
            parts.append("bg=\(TerminalColor(backgroundEscapeSequence: background.backgroundEscapeSequence).label)")
        }
        if attributes.bold { parts.append("bold") }
        if attributes.italic { parts.append("italic") }
        if attributes.underline { parts.append("underline") }
        if attributes.strikethrough { parts.append("strikethrough") }
        if attributes.inverted { parts.append("inverted") }
        return parts.joined(separator: " ")
    }
}

private enum TerminalColor: Equatable {
    case `default`
    case ansi(String)
    case xterm(Int)
    case rgb(Int, Int, Int)
    case unknown(String)

    init(foregroundEscapeSequence escapeSequence: String) {
        self = TerminalColor.parse(escapeSequence) ?? .unknown(escapeSequence)
    }

    init(backgroundEscapeSequence escapeSequence: String) {
        self = TerminalColor.parse(escapeSequence) ?? .unknown(escapeSequence)
    }

    var label: String {
        switch self {
        case .default:
            return "default"
        case .ansi(let name):
            return name
        case .xterm(let value):
            return "xterm(\(value))"
        case .rgb(let r, let g, let b):
            return "rgb(\(r),\(g),\(b))"
        case .unknown(let value):
            return value.debugDescription
        }
    }

    private static func parse(_ escapeSequence: String) -> TerminalColor? {
        let prefix = "\u{001B}["
        guard escapeSequence.hasPrefix(prefix), escapeSequence.hasSuffix("m") else {
            return nil
        }

        let body = escapeSequence.dropFirst(prefix.count).dropLast()
        let parts = body.split(separator: ";").compactMap { Int($0) }
        guard let first = parts.first else { return nil }

        if first == 38 || first == 48 {
            guard parts.count >= 3 else { return nil }
            switch parts[1] {
            case 5:
                return .xterm(parts[2])
            case 2:
                guard parts.count >= 5 else { return nil }
                return .rgb(parts[2], parts[3], parts[4])
            default:
                return nil
            }
        }

        if let ansiName = ansiName(for: first) {
            return ansiName == "default" ? .default : .ansi(ansiName)
        }

        return nil
    }

    private static func ansiName(for code: Int) -> String? {
        switch code {
        case 39, 49: return "default"
        case 30, 40: return "black"
        case 31, 41: return "red"
        case 32, 42: return "green"
        case 33, 43: return "yellow"
        case 34, 44: return "blue"
        case 35, 45: return "magenta"
        case 36, 46: return "cyan"
        case 37, 47: return "white"
        case 90, 100: return "brightBlack"
        case 91, 101: return "brightRed"
        case 92, 102: return "brightGreen"
        case 93, 103: return "brightYellow"
        case 94, 104: return "brightBlue"
        case 95, 105: return "brightMagenta"
        case 96, 106: return "brightCyan"
        case 97, 107: return "brightWhite"
        default: return nil
        }
    }
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        guard let lastNonSpace = lastIndex(where: { $0 != " " }) else {
            return ""
        }
        return String(self[...lastNonSpace])
    }
}
