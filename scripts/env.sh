# Common environment for Decanter's build scripts. Source, don't execute.

set -euo pipefail

DECANTER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DECANTER_HOME="${DECANTER_HOME:-$HOME/.local/share/decanter}"
DECANTER_WORK="${DECANTER_WORK:-$HOME/.cache/decanter}"

# The arm64 Homebrew, never the Intel one under /usr/local: the whole point is to stay
# off Rosetta, and the PE cross toolchain has to be arm64.
export PATH="/opt/homebrew/bin:$PATH"

BREW="${BREW:-/opt/homebrew}"
# Where Hadron's checkout lives: the sources the runtime is built from, and the licences that
# have to travel with it.
CHECKOUT="${CHECKOUT:-$DECANTER_WORK/hadron}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -m)" == arm64 ]] || die "Decanter targets Apple Silicon (arm64) hosts only"
[[ "$(brew --prefix)" == "/opt/homebrew" ]] || die "expected arm64 Homebrew at /opt/homebrew"
