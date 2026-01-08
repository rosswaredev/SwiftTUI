public enum KeyEvent: Sendable, Equatable {
  case character(Character)
  case special(Special)

  public enum Special: Sendable, Equatable {
    case up
    case down
    case left
    case right

    case shiftUp
    case shiftDown
    case shiftLeft
    case shiftRight

    case shiftTab
    case delete
    case escape
  }
}

