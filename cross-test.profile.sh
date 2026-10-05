#!/usr/bin/env bash
# cross-test.profile.sh — settings only, for the `cross-test` harness.
#
# `cross-test` is run from this package root. It compiles and runs this
# package's real `test` step, `zig build test -Dtarget=TARGET`, once per target
# of the published Zig 0.16.0 Tier 1/2 matrix (53 platforms), and it owns the
# matrix, the runner policy and the QEMU/Wine/Wasmtime detection. This file
# configures none of that and must not: it holds ordinary Bash variable
# definitions only, no `cross_build_command`/`cross_artifact` hooks (so the
# standard Zig-build mode is used), no `CROSS_MATRIX` and no `TARGETS` (so the
# full published matrix is selected, never a subset), and no host-specific
# path. Every value here is a default that the command line overrides, so
# `cross-test --jobs N --build-jobs N --build-timeout N --timeout N` still
# wins; see `cross-test --help`.
#
# There is deliberately no matrix or target list named here for a second
# reason specific to this package. The fast six-target compile matrix in
# `build.zig` is a *different* thing from this one: `zig build check` compiles
# the forty-nine C units of the core, the translation, the facade, `tests.zig`,
# `smoke.zig` and upstream's own twenty-one-file C unit-test program for six
# targets without running anything. A matrix declared in this file would
# replace the 53-platform run rather than add to it, and the two must not be
# confused: `check` is compile evidence, and this profile runs the behavioural
# tests.
#
# `CROSS_LIBC_RUNTIMES` is deliberately absent: it names a directory of foreign
# libc loaders on the machine running the harness, which is that machine's
# business and not this package's. Supply it in the environment when a
# GNU-libc cell needs one.
#
# Nothing here selects a linkage. The default `-Dlinkage=static` graph is the
# one this file describes, because that is the artifact the package has always
# delivered; a shared-artifact matrix is a separate gate -- the same
# `cross-test` run with `CROSS_BUILD_ARGS=(-Dlinkage=dynamic)` supplied by
# whoever runs it -- so this file does not hard-code one linkage and silently
# narrow the other out. That shared run covers the platforms that have a
# dynamic linker. A platform with none, `wasm32-wasi` among them, is refused by
# `-Dlinkage=dynamic` with a message naming the platform fact, and
# `-Dlinkage=static` -- the default -- remains a full configuration there.
#
# Licence: **none asserted.** This is a fork-authored file, like `build.zig`,
# `zig/translate.h`, `zig/root.zig`, `tests.zig`, `smoke.zig` and `consumer/`.
# Box3D is MIT, and this grant is upstream's; the grant covering this fork's own
# additions is recorded in `FORK-LICENSE.md`.
#
# The step that runs the public Zig API tests. This is the harness default too;
# it is named here so the package's contract is in the package. `build.zig`
# hands that step a real `addRunArtifact` for whatever `-Dtarget` resolves to,
# which is what leaves the runner policy open: a host target executes, a
# foreign target executes under whatever executor the harness detects (QEMU
# user mode, Wine, wasmtime), and a foreign target with no executor is reported
# as build-only coverage -- compiled, never executed, never counted as a pass.
#
# Upstream's own C unit tests are a separate step, `upstream-test`, and are not
# named here: the harness drives one step, and a step that runs both would make
# a failure in either indistinguishable from a failure of the Zig facade. Run
# `zig build upstream-test -Dtarget=TARGET` directly for those.
CROSS_BUILD_STEP=test

# One target at a time inside one `zig build`. A target graph compiles all
# forty-nine units of the core for that target, translates `<box3d/box3d.h>`
# through `zig/translate.h` for it, and links the test binary against the
# result -- so one cell is a whole library build, not a single object. Keeping
# four build jobs available lets a cell use the machine without making the host
# oversubscribed by 53 targets' worth of memory pressure.
CROSS_BUILD_JOBS=4

# Deadline for one `zig build test -Dtarget=...`, covering both the compile and
# the run of that target's test binary.
CROSS_BUILD_TIMEOUT=3600

# Per-test-binary deadline, passed on as `zig build --test-timeout`. Box3D's
# tests step real worlds -- `test_world.c` runs the sample suites through the
# benchmark harness and `test_large_world.c` builds a large one -- so a cell
# whose runner is an emulator rather than the host that is a long run, and the
# harness default is not a ceiling this package can meet. Every value on this
# file is a default chosen in advance, not a receipt; what a run produced belongs
# to the driver's own cross-test summary, not here.
CROSS_TIMEOUT=3600