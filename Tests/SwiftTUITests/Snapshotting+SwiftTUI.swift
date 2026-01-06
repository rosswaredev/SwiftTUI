import SnapshotTesting
@testable import SwiftTUI

extension Snapshotting where Value: View, Format == String {
    /// Snapshots a `SwiftTUI.View` by rendering it into a fixed-size terminal viewport and
    /// returning the visible characters as plain text.
    static func swiftTUI(
        width: Int = 80,
        height: Int = 24,
        trimTrailingWhitespace: Bool = true,
        trimTrailingEmptyLines: Bool = true
    ) -> Snapshotting<Value, String> {
        Snapshotting<String, String>.lines.pullback { view in
            SwiftTUIViewSnapshotRenderer.render(
                view,
                viewport: Size(width: Extended(width), height: Extended(height)),
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
            trimTrailingWhitespace: trimTrailingWhitespace,
            trimTrailingEmptyLines: trimTrailingEmptyLines
        )
    }

    private static func render(
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
}

private extension String {
    func trimmingTrailingSpaces() -> String {
        guard let lastNonSpace = lastIndex(where: { $0 != " " }) else {
            return ""
        }
        return String(self[...lastNonSpace])
    }
}
