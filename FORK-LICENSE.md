# Fork licence — box3d

What licence applies to the material **this fork wrote**, on what authority.
`NOTICE.md` carries the per-file inventory and `UPSTREAM.md` carries the source
provenance.

## 1. The native material is not covered by anything below

Erin Catto's Box3D is MIT (`LICENSE`, `Copyright (c) 2026 Erin Catto`), and the
import also carries two MIT notices from other holders — Alexey Tourbin in
`src/qsort.h` and Jackson L. Allan in `src/verstable.h` — plus the zlib/libpng
terms of the vendored sokol headers. This fork has no authority to change any
of those, and nothing below does. The full per-file inventory is `NOTICE.md`.

## 2. The fork-authored material

Every file this fork wrote — the build graph, the Zig translation header, the
typed module, the runtime graph, the tests, the smoke example, the consumer
package, the CI workflow, the provenance script, the Nix packaging and this
documentation — is covered by this grant.

### Grant

**Those fork-authored files are released under the MIT License.**

Upstream's own term for Box3D is MIT, so the packaging carries the same terms as
the library it packages. Matching keeps one licence to read across the whole
repository.

### Authority for that grant

The repository owner directly authorized a per-project licence for
fork-authored additions as part of the SDK contract migration, with terms chosen
to match each project's primary upstream terms where appropriate. That
authorization is the basis recorded here.

Upstream's MIT grant does not make this record necessary for its own sake and
does not limit it: Erin Catto granted nothing about these files and is not asked
to. No personal copyright identity is asserted anywhere in this file, and none
is invented for the record.

### SPDX identifier

`MIT`

Fork-authored source, build and packaging files carry
`SPDX-License-Identifier: MIT`. This is a standardised SPDX identifier, not a
custom reference, and it is the same identifier the imported files use for
different authors.

## 3. What this grant does not do

* It does not re-license, sublicense or add a condition to any imported file,
  including the two vendored MIT headers inside the compiled library and the
  zlib/libpng sokol headers.
* It does not assert that Erin Catto, Alexey Tourbin, Jackson L. Allan,
  Serge Zaitsev, Syoyo Fujita or Andre Weissflog authored, reviewed or approved
  any fork-authored file.
* It does not extend to a consumer's own code, to the compiled output's link
  metadata, or to anything outside this repository.
* It does not grant anything for `samples/earcut.h`, which carries no notice.

## 4. Supersession

Before the owner's authorization, the fork-authored files carried no licence
statement and were described in `NOTICE.md` as having no licence asserted. That
described the state before the authorization. The authorization and the grant
above replace it, and only this file replaces it.