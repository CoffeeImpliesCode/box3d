#!/usr/bin/env bash
# Provenance and licence integrity check for the box3d SDK.
#
# Answers three questions, none of which needs a compiler:
#
#   1. Does every upstream file still hash to the digest UPSTREAM.sha256
#      records?
#   2. Is the licence text of each licence-bearing vendored file still present
#      in that file?
#   3. Is upstream's README still preserved, byte for byte, as
#      README.upstream.md?
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs. It is the check that a future edit to an imported file cannot pass as a
# routine change. CI calls this script rather than carrying a second copy of the
# same checks, which would be a drift risk with nothing to detect the drift.
#
# Usage: tools/check-provenance.sh   (from the repository root)
#
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f UPSTREAM.sha256 ]; then
    echo "UPSTREAM.sha256 is missing; this repository cannot verify its own provenance" >&2
    exit 1
fi

# Record the count as well as the outcome: a manifest that silently shrank to
# one line would otherwise still "pass".
records=$(grep -cv '^#' UPSTREAM.sha256)
if [ "$records" -lt 2 ]; then
    echo "UPSTREAM.sha256 holds $records record(s); that is not this project's manifest" >&2
    exit 1
fi

# Comment lines are stripped rather than relying on sha256sum to skip them.
if ! grep -v '^#' UPSTREAM.sha256 | sha256sum --quiet -c -; then
    echo "one or more imported files no longer match UPSTREAM.sha256" >&2
    echo "An intentional native change needs its own record: a per-file" >&2
    echo "deviation entry in NOTICE.md, a new CHANGELOG.md entry, and an" >&2
    echo "updated digest here, in the same change." >&2
    exit 1
fi
echo "all $records imported files match UPSTREAM.sha256"

# Upstream's own licence, and the three vendored files whose terms differ from
# it. Each check is for that file's own notice, because the point of the
# inventory in NOTICE.md is that these terms are per file and not one label.
check_notice() {
    file=$1
    text=$2
    if [ ! -f "$file" ]; then
        echo "$file is missing" >&2
        exit 1
    fi
    if ! grep -qF "$text" "$file"; then
        echo "$file no longer carries its own licence notice" >&2
        exit 1
    fi
    echo "$file carries its own licence notice"
}

check_notice LICENSE "Copyright (c) 2026 Erin Catto"
check_notice samples/jsmn.h "Copyright (c) 2010 Serge Zaitsev"
check_notice samples/tiny_obj_loader.h "Copyright (c) 2012-Present, Syoyo Fujita"
check_notice extern/sokol/LICENSE "Copyright (c) 2018 Andre Weissflog"

# samples/earcut.h carries no notice at all upstream. That is recorded in
# NOTICE.md as a fact about the import, not repaired here: inventing a grant for
# a file that has none would be worse than reporting the gap.

# Upstream's README is preserved under the fork's name. The relocation digest is
# stated in UPSTREAM.sha256's header; compare the file against that header line
# rather than against a digest repeated here, so there is one source for it.
relocated=$(sed -n 's/.*: \([0-9a-f]\{64\}\)\.$/\1/p' UPSTREAM.sha256 | head -1)
if [ -z "$relocated" ]; then
    echo "UPSTREAM.sha256 states no README relocation digest" >&2
    exit 1
fi
actual=$(sha256sum README.upstream.md | cut -d' ' -f1)
if [ "$relocated" != "$actual" ]; then
    echo "README.upstream.md is not the preserved upstream README" >&2
    echo "  expected $relocated" >&2
    echo "  actual   $actual" >&2
    exit 1
fi
echo "README.upstream.md matches the recorded upstream README digest: $actual"

# The authorisation record and the inventory must both exist; a checkout that
# lost either would otherwise pass the checks above silently.
for file in FORK-LICENSE.md NOTICE.md UPSTREAM.md; do
    if [ ! -s "$file" ]; then
        echo "$file is missing or empty" >&2
        exit 1
    fi
done

echo "provenance checks passed"