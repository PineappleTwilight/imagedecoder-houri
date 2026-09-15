# AGENTS.md — library/src/main/cpp (native build)

**Generated:** 2026-09-15

## OVERVIEW

WSL-only native orchestrator: `CMakeLists.txt` (1255 lines) builds 18 static third-party deps via ExternalProject, then compiles the `imagedecoder2` JNI shared lib. No native build runs without `wsl.exe` (FATAL_ERROR otherwise). Read this file before touching the build; read `CMakeLists.txt` only for details.

## STRUCTURE

```
cpp/
├── CMakeLists.txt          # 1255-line orchestrator: probes, helpers, 18 includes, ep_imagedecoder
├── cmake/                  # 18 ExternalProject recipes, one per dep
│   ├── meson flavor:       # dav1d, glib, libvips, libde265, highway
│   ├── autotools flavor:   # libffi, lcms2, libiconv (BUILD_IN_SOURCE)
│   └── cmake flavor:       # libwebp, zlib, libpng, libjpeg-turbo, libtiff, ...
├── imagedecoder/
│   ├── CMakeLists.txt      # 30 lines: SHARED imagedecoder2, pkg-config vips-cpp, links dav1d + -static-libgcc/stdc++
│   └── imagedecoder.cpp    # 356-line JNI: new/getInfo/decode/encode
└── patches/                # libvips-remove-subdirs.patch
```

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Add a dependency | `cmake/<name>.cmake` (copy nearest flavor) + `include("cmake/<name>.cmake")` in the include block at `CMakeLists.txt:1221`; wire `DEPENDS` in `cmake/libvips.cmake:15` if vips needs it |
| Remove a dependency | delete recipe + its `include(...)` line; drop from `ep_libvips` DEPENDS |
| Windows→WSL path conversion | `to_msys_path` at `CMakeLists.txt:139` (`C:/` → `/mnt/c/`) |
| Meson cross-file | generated `$build/android-cross-file.txt` (`CMakeLists.txt:1011`); consumed via `EP_MESON_ARGS` (`:568`, re-set `:1031`) |
| Tool wrappers | `$build/wrappers/` (NDK `.exe` → WSL, fixes `Exec format error`); `meson_helper.sh` (`:1164`), `autotools_helper*.sh` (`:1056`) |
| JNI decode path | `imagedecoder.cpp:268` (`Java_..._decode`); `new` `:146`, `getInfo` `:232`, `encode` `:322` |
| Final JNI target | `ep_imagedecoder` at `CMakeLists.txt:1246` → inner `imagedecoder/CMakeLists.txt` |

## CONVENTIONS

- Static-only everywhere: `--default-library=static`, `--disable-shared`, `BUILD_SHARED_LIBS=OFF`, `--buildtype=release`.
- Shared vars: `EP_CMAKE_ARGS` (`:592`), `EP_MESON_ARGS` (`:568`), `EP_AUTOTOOLS_ARGS` (`:764`); recipes consume these, don't redefine.
- `BUILD_ALWAYS 1` only on `ep_imagedecoder` (`:1250`) and `ep_libvips` (`cmake/libvips.cmake:31`).
- Prefix `fk/` (fakeroot) + `EP_BASE ep/` (`:486`) — short names dodge Windows MAX_PATH on stamp files.
- Linux NDK clang (`.../linux-x86_64/bin/clang`) inside WSL, not Windows `.exe`.
- ccache/sccache auto-detected (`:17`); host launcher skipped if WSL-only path.
- Vendored-dep warnings suppressed in root `EP_CMAKE_ARGS`; don't "fix" upstream warnings.

## ANTI-PATTERNS

- Editing generated `android-cross-file.txt`, `meson_helper.sh`, or anything under `library/.cxx/` — regenerate via Gradle.
- `C:/` or `/c/` in meson `--prefix`/`--cross-file` or autotools `CC=` — must be `/mnt/c/` (`to_msys_path`); `CC=C:/...` parses as variable `C`.
- `MAKE` in `WSLENV` — shadows `make`, breaks autotools (`all-recursive: command not found` precedent).
- Ninja with a space in path (`C:/Program Files/Meson/...`) — breaks `cmake -E env`; use Android SDK ninja.
- Stale `library/.cxx` with empty `--cross-file=` in `build.ninja` — nuke `.cxx` after editing `CMakeLists.txt` or switching NDK.