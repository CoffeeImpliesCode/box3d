/* The header this package translates, plus the one it authors itself.
 *
 * `#include <box3d/box3d.h>` is upstream's whole public surface, reached
 * through upstream's own include graph, and `translate-c` turns it into the
 * `c` module `zig/root.zig` and every dependent import. The second include is
 * this package's own pointer-taking entry points for the ten public
 * signatures whose by-value form Zig's x86_64 backend lowers differently from
 * the clang that compiled the core; `build_support/box3d_abi_bridge.h` says
 * which ten, what was measured, and why the list is complete.
 *
 * They belong in this translation rather than in a second one for two
 * reasons. The facade reaches `c.b3Vec3` and `c.box3dAbi_CastRayClosest`
 * through one nominal namespace, so the pointer arguments are spelled with the
 * same types as everything else rather than with a second copy of them. And
 * `-Druntime=true` builds its dispatch from whatever this translation produced
 * (`runtime/generate.zig`, which the API role owns), so a declaration made
 * anywhere else would be the one kind of entry point the runtime route could
 * not resolve.
 *
 * `../build_support/box3d_abi_bridge.h` is a quoted path relative to this
 * file, so this header is reached by its own name rather than through a
 * search path. `build_support/` does appear on a compile line, but as the
 * late `-idirafter` entry that supplies `Windows.h` to the two upstream units
 * that spell their include that way (`src/timer.c:26`, `shared/utils.c:7`),
 * and that name is the only thing it is there for; a build where the file
 * system already matches the spelling never opens it.
 *
 * Why one include is the whole public surface
 * ------------------------------------------
 * Box3D ships eight headers (`src/CMakeLists.txt:92-101`) and they are not
 * peers: `box3d/box3d.h:6-10` already includes `base.h`, `collision.h`,
 * `id.h`, `math_functions.h` and `types.h`; `types.h:6-9` adds `constants.h`;
 * and `base.h:14` adds `config.h`. So `<box3d/box3d.h>` reaches all eight, and
 * a second `#include` here would be the same header's own include guard
 * (`#pragma once`) resolving to nothing. Listing them all would not be more
 * complete, only longer and one more place to forget an entry.
 *
 * Nothing about upstream is copied here. Every declaration, typedef, enum,
 * callback and constant the translation exposes is upstream's own bytes,
 * reached through upstream's own include graph, so the translation cannot
 * drift from the header by omission. A generated header that restated any of
 * it would be a second dialect of the same interface.
 *
 * The include path, not a macro
 * -----------------------------
 * `#include <box3d/box3d.h>` is an ordinary angle-bracket search. There is no
 * `box3d/` directory beside this file, so the search is settled by the `-I`
 * directories `build.zig` gives the translation -- the package's own
 * `include/` -- and a Box3D installed somewhere on the build machine cannot
 * shadow the pinned header this build compiles. That is the same rule
 * `WISDOM.md` W14 states, and it is why no fork-only macro appears below.
 *
 * What the export macros are, and where they come from
 * ---------------------------------------------------
 * `include/box3d/base.h:21-35` reads `box3d_EXPORTS` and `BOX3D_DLL` to decide
 * whether a declaration is `__declspec(dllexport)`, `__declspec(dllimport)`,
 * `__attribute__((visibility("default")))`, or undecorated. They describe how
 * *this particular library* was linked, not what the interface is, so upstream
 * puts them on the compiler command line and this header stays silent about
 * them:
 *
 *   * `zig build -Dlinkage=static` (the default) defines neither, which is how
 *     a static archive is consumed on every platform.
 *   * `zig build -Dlinkage=dynamic` defines `box3d_EXPORTS` on the library's
 *     own compile line and `BOX3D_DLL` on this translation, the split
 *     upstream makes between the definition and the declaration side.
 *   * The installed `box3d.pc` carries `-DBOX3D_DLL` in `Cflags` for a shared
 *     install, so a C consumer gets the same answer without repeating the
 *     flag.
 *
 * The two other compile-time options that change what a consumer sees are on
 * the command line for the same reason. `BOX3D_DOUBLE_PRECISION` is upstream's
 * only `PUBLIC` compile definition (`src/CMakeLists.txt:164-168`) because it
 * changes the width of the world-position fields, so a consumer that did not
 * see it would describe a different ABI; this build passes `-Ddouble-precision`
 * to the translation exactly when it passes it to the core.
 * `BOX3D_DISABLE_SIMD` and `BOX3D_VALIDATE` are `PRIVATE`
 * (`src/CMakeLists.txt:154-162`): they select code paths inside the library
 * and change no declaration, so the translation must not see them, or `pub
 * const c` would expose constants that the compiled archive was never built
 * with. `BOX3D_VALIDATE` does reach a recorded byte -- `src/recording.h:62`
 * stores it in the recording header -- and that byte is written by the library
 * at run time and read by `b3ValidateReplay`, so it is a fact about a
 * recording rather than about this compilation.
 *
 * On anything that is not Windows (`include/box3d/base.h:22`, `:25`) the
 * export macros are unread and `BOX3D_EXPORT` is the visibility attribute
 * instead, so the declarations below are identical in every configuration.
 *
 * The compiler's own 128-bit integer typedefs
 * -------------------------------------------
 * `__int128_t` and `__uint128_t` belong to the compiler, not to a header:
 * Clang declares them next to the `__int128` primitive it provides, and no
 * header declares them. NetBSD's `generic-netbsd/arm/cdefs.h:62-63` spells
 * `__ALIGNBYTES` as `sizeof(__int128_t) - 1` on the `__ARM_PCS_AAPCS64` branch,
 * and that is the branch `aarch64-netbsd` takes, because `__ARM_PCS_AAPCS64`
 * is one of the compiler's own predefines for AArch64. This package's
 * preprocessed route keeps every `#define` in the file Aro parses (`-dD`), so
 * the spelling survives into the expansion and the translated Zig comes out
 * naming an identifier nothing in it declares: `use of undeclared identifier
 * '__int128_t'` on `aarch64-netbsd` and `aarch64_be-netbsd`, beside a green
 * `translate-c` and a green `compile lib box3d` (`box3d-translate.zig:5208:43`).
 *
 * The two typedefs below restate that compiler builtin in the one file
 * `zig translate-c` reads. The guard is the compiler's own statement that this
 * target has the extension -- Clang defines `__SIZEOF_INT128__` exactly when
 * `TI.hasInt128Type()` holds -- so a target without it declares neither name,
 * and C permits a typedef to be restated for the type it already denotes, so a
 * target whose own headers declare them is unaffected. **No upstream `.c` or
 * `.h` byte is touched, and no Box3D declaration, constant or prototype is
 * added or removed.** This is the same bridge ERFA, LMDB and PCRE2 carry in
 * their own `zig/translate.h`.
 */

#ifndef BOX3D_TRANSLATE_H
#define BOX3D_TRANSLATE_H

/* The compiler's own 128-bit integer types. See the comment above. */
#if defined(__SIZEOF_INT128__)
typedef __int128 __int128_t;
typedef unsigned __int128 __uint128_t;
#endif

#include <box3d/box3d.h>

#include "../build_support/box3d_abi_bridge.h"

#endif /* BOX3D_TRANSLATE_H */