import Foundation

/// Builds a line for the user to paste into Terminal that runs a tool by
/// its full path.
///
/// A tool Tabbi found on disk is often not on the PATH of a fresh Terminal
/// window: Claude's native installer puts `claude` in `~/.local/bin` and
/// only prints a hint about PATH, so a pasted `claude auth login` fails
/// with "command not found". Naming the file Tabbi found avoids that.
public enum ShellCommandLine {
    /// `executable` followed by `arguments`, each quoted for zsh and bash
    /// only when it needs to be, so a plain path stays readable.
    public static func running(_ executable: URL, arguments: [String] = []) -> String {
        ([executable.path] + arguments).map(quoted).joined(separator: " ")
    }

    /// One word as the shell reads it back unchanged: as is when it holds
    /// only characters the shell gives no meaning to, otherwise in single
    /// quotes, with each single quote inside written as `'\''`.
    public static func quoted(_ word: String) -> String {
        guard !word.isEmpty else { return "''" }
        let plain = word.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "/._-+:@%,".unicodeScalars.contains(scalar))
        }
        if plain { return word }
        return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
