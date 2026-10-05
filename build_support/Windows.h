/* SPDX-License-Identifier: MIT
 *
 * The header `src/timer.c` asks for, under the name it asks for it.
 *
 * Why it exists
 * -------------
 * `src/timer.c:26` is an unconditional Windows translation unit in
 * `BOX3D_SOURCE_FILES` (`src/CMakeLists.txt:3-90`), and its platform half opens
 * with
 *
 *     #include <Windows.h>
 *
 * Upstream never had to think about that spelling. CMake builds this file with
 * MSVC, and Windows, macOS and the BSDs all resolve `Windows.h` to the
 * `windows.h` beside it, because none of those filesystems distinguishes case.
 * The cross targets in this build's matrix are compiled from a case-sensitive
 * host, where the only `windows.h` on the search path is MinGW-w64's - Zig
 * ships it at `lib/libc/include/any-windows-any/windows.h` and puts that
 * directory on the include line for a `windows-gnu` target - and `Windows.h`
 * matches nothing there. The compiler stops with
 *
 *     src/timer.c:26:10: error: 'Windows.h' file not found
 *
 * which is not a warning to live with: dropping the unit would leave
 * `b3GetTicks`, `b3GetMilliseconds` and `b3GetNanoseconds` undefined on a
 * Windows build, and nothing in `src/` is edited to get around it.
 *
 * What it does
 * ------------
 * One include, asking for the same header by the spelling the toolchain
 * actually ships. `QueryPerformanceCounter`, `QueryPerformanceFrequency` and
 * `Sleep`, which is all the unit uses, come from MinGW's own header, unchanged
 * upstream code compiled against upstream's own API.
 *
 * `-idirafter`, not `-I`
 * ----------------------
 * `build.zig` adds this directory as a late include path rather than a normal
 * one, and that is the load-bearing detail rather than a style choice. Clang
 * searches every `-idirafter` directory after all `-I` and system directories.
 * If this directory were an ordinary `-I` that came first, then on a
 * case-insensitive host `#include <Windows.h>` would land in this file, the
 * `#include <windows.h>` below would land in this file again, and MinGW's
 * header would never be read at all - the same missing-header failure, quieter
 * and much harder to see. As a late path, a host whose filesystem already
 * matches the spelling finds the real header first and never opens this file,
 * and only a case-sensitive host falls through to it.
 */

#ifndef BOX3D_BUILD_SUPPORT_WINDOWS_H
#define BOX3D_BUILD_SUPPORT_WINDOWS_H

#include <windows.h>

#endif /* BOX3D_BUILD_SUPPORT_WINDOWS_H */
