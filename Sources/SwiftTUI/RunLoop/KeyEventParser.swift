import Foundation

struct KeyEventParser {
  enum State: Sendable, Equatable {
    case idle
    case escape
    case escapeBracket

    case escapeBracket1
    case escapeBracket1Semicolon
    case escapeBracket1Semicolon2

    case escapeBracket3
  }

  private(set) var state: State = .idle

  var hasPendingEscape: Bool {
    state == .escape
  }

  mutating func feed(_ character: Character) -> [KeyEvent] {
    switch state {
    case .idle:
      if character == "\u{1B}" {
        state = .escape
        return []
      }
      return [.character(character)]

    case .escape:
      if character == "[" {
        state = .escapeBracket
        return []
      }

      state = .idle
      return [.special(.escape), .character(character)]

    case .escapeBracket:
      switch character {
      case "A":
        state = .idle
        return [.special(.up)]
      case "B":
        state = .idle
        return [.special(.down)]
      case "C":
        state = .idle
        return [.special(.right)]
      case "D":
        state = .idle
        return [.special(.left)]
      case "Z":
        state = .idle
        return [.special(.shiftTab)]
      case "1":
        state = .escapeBracket1
        return []
      case "3":
        state = .escapeBracket3
        return []
      default:
        state = .idle
        return [.special(.escape), .character(character)]
      }

    case .escapeBracket1:
      if character == ";" {
        state = .escapeBracket1Semicolon
        return []
      }

      state = .idle
      return [.special(.escape), .character(character)]

    case .escapeBracket1Semicolon:
      if character == "2" {
        state = .escapeBracket1Semicolon2
        return []
      }

      state = .idle
      return [.special(.escape), .character(character)]

    case .escapeBracket1Semicolon2:
      switch character {
      case "A":
        state = .idle
        return [.special(.shiftUp)]
      case "B":
        state = .idle
        return [.special(.shiftDown)]
      case "C":
        state = .idle
        return [.special(.shiftRight)]
      case "D":
        state = .idle
        return [.special(.shiftLeft)]
      default:
        state = .idle
        return [.special(.escape), .character(character)]
      }

    case .escapeBracket3:
      if character == "~" {
        state = .idle
        return [.special(.delete)]
      }

      state = .idle
      return [.special(.escape), .character(character)]
    }
  }

  mutating func flushPendingEscape() -> [KeyEvent] {
    guard state == .escape else { return [] }
    state = .idle
    return [.special(.escape)]
  }
}

