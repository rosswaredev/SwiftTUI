public extension View {
  /// Invoked for every key event received by the application.
  /// Return `true` to indicate the event has been handled and should not be forwarded to other handlers.
  func onKeyEvent(_ action: @escaping (KeyEvent) -> Bool) -> some View {
    OnKeyEvent(content: self, action: action)
  }
}

struct OnKeyEvent<Content: View>: View, PrimitiveView, ModifierView {
  let content: Content
  let action: (KeyEvent) -> Bool

  static var size: Int? { Content.size }

  func buildNode(_ node: Node) {
    node.addNode(at: 0, Node(view: content.view))
  }

  func updateNode(_ node: Node) {
    node.view = self
    node.children[0].update(using: content.view)
  }

  func passControl(_ control: Control, node: Node) -> Control {
    let onKeyEventControl = OnKeyEventControl(action: action)
    onKeyEventControl.addSubview(control, at: 0)
    return onKeyEventControl
  }
}

final class OnKeyEventControl: Control {
  let action: (KeyEvent) -> Bool

  init(action: @escaping (KeyEvent) -> Bool) {
    self.action = action
  }

  override func size(proposedSize: Size) -> Size {
    children[0].size(proposedSize: proposedSize)
  }

  override func layout(size: Size) {
    super.layout(size: size)
    children[0].layout(size: size)
  }
}

