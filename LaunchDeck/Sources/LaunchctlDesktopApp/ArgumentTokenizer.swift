import Foundation

func splitShellArguments(_ raw: String) -> [String] {
    enum Mode {
        case normal
        case singleQuoted
        case doubleQuoted
        case escaped
    }

    var mode: Mode = .normal
    var token = ""
    var output: [String] = []

    func flushToken() {
        guard !token.isEmpty else { return }
        output.append(token)
        token.removeAll(keepingCapacity: true)
    }

    for character in raw {
        switch mode {
        case .normal:
            if character.isWhitespace {
                flushToken()
            } else if character == "\\" {
                mode = .escaped
            } else if character == "'" {
                mode = .singleQuoted
            } else if character == "\"" {
                mode = .doubleQuoted
            } else {
                token.append(character)
            }
        case .singleQuoted:
            if character == "'" {
                mode = .normal
            } else {
                token.append(character)
            }
        case .doubleQuoted:
            if character == "\"" {
                mode = .normal
            } else if character == "\\" {
                mode = .escaped
            } else {
                token.append(character)
            }
        case .escaped:
            token.append(character)
            mode = .normal
        }
    }

    flushToken()
    return output
}
