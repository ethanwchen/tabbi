#!/usr/bin/env bash
# Fails when a tracked text file contains an em dash or an emoji.
# The maintainer's writing rule (see AGENTS.md, "Writing style") covers UI
# strings, docs, comments and kit descriptions alike. Tests that need such
# characters as input write them as escapes, e.g. "\u{1F3A7}".
#
# Usage: scripts/check-style.sh [file ...]   (default: every tracked file)
set -euo pipefail

cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
    files=("$@")
else
    files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(git ls-files -z)
fi

# Perl ships with macOS; BSD grep has no Unicode-aware -P.
# Emoji: the pictograph planes, misc symbols and dingbats, the emoji-styled
# arrows and stars, the watch/hourglass/media keys, and the emoji variation
# selector. Symbols used as plain text (arrows, the Command key) stay legal.
perl -CSD -Mutf8 -e '
    my $bad = qr/[\x{2014}\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{231A}\x{231B}\x{23E9}-\x{23F3}\x{23F8}-\x{23FA}\x{FE0F}]/;
    my $found = 0;
    for my $path (@ARGV) {
        next unless -f $path && -T $path;
        open(my $fh, "<:encoding(UTF-8)", $path) or next;
        while (my $line = <$fh>) {
            while ($line =~ /($bad)/g) {
                my $what = $1 eq "\x{2014}" ? "em dash" : sprintf("emoji U+%04X", ord($1));
                printf "%s:%d: %s\n", $path, $., $what;
                $found = 1;
            }
        }
        close($fh);
    }
    if ($found) {
        print STDERR "check-style: replace em dashes with \"-\", a comma, a colon or parentheses, and remove emojis.\n";
        exit 1;
    }
' "${files[@]}"
