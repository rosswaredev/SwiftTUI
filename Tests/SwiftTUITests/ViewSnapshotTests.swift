import InlineSnapshotTesting
import XCTest
@testable import SwiftTUI

final class ViewSnapshotTests: XCTestCase {
    func test_vStack() {
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("One")
                    Text("Two")
                }
            }
        }

        assertInlineSnapshot(of: MyView(), as: .swiftTUI(width: 20, height: 10)) {
            """
            One
            Two
            """
        }
    }

    func test_hStack_defaultSpacingIsOne() {
        struct MyView: View {
            var body: some View {
                HStack {
                    Text("A")
                    Text("B")
                }
            }
        }

        assertInlineSnapshot(of: MyView(), as: .swiftTUI(width: 20, height: 10)) {
            """
            A B
            """
        }
    }

    func test_border() {
        assertInlineSnapshot(of: Text("Hi").border(), as: .swiftTUI(width: 20, height: 10)) {
            """
            ┌──┐
            │Hi│
            └──┘
            """
        }
    }

    func test_styledSnapshot_includesForegroundAndBackgroundColors() {
        let view = VStack {
            Text("Hi").foregroundColor(.red)
            Text("Hi").frame(width: 4).background(.blue)
        }

        assertInlineSnapshot(of: view, as: .swiftTUI(width: 20, height: 10, format: .styled)) {
            """
            ⟦fg=red⟧Hi⟦/⟧
            ⟦bg=blue⟧Hi··⟦/⟧
            """
        }
    }

  func test_spacer() {
      let view = VStack {
          Text("Hello")
          Spacer()
      }
      .border()
      assertInlineSnapshot(of: view, as: .swiftTUI(width: 20, height: 10)) {
          """
          ┌─────┐
          │Hello│
          │     │
          │     │
          │     │
          │     │
          │     │
          │     │
          │     │
          └─────┘
          """
      }
  }
}
