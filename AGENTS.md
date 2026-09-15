# PROJECT KNOWLEDGE BASE

**Generated:** 2026-09-14
**Commit:** 20a5e30
**Branch:** master

## OVERVIEW

Android library (`ca.mpreg.imagedecoder`) wrapping libvips via JNI — decodes jpeg/png/webp/gif/tiff/heif(jxl)/jp2k with pages, HDR, trim/crop, re-encode. Kotlin + C++ (CMake ExternalProject). Submodule of komikku-pineapple at `external/imagedecoder-houri`.

## STRUCTURE

```
./
├── library/src/main/
│   ├── java/ca/mpreg/imagedecoder/ImageDecoder.kt  # entire public API (1 file)
│   └── cpp/
│       ├── CMakeLists.txt    # 1255-line native orchestrator (see cpp/AGENTS.md)
│       ├── cmake/            # 18 per-dependency ExternalProject recipes
│       ├── imagedecoder/     # imagedecoder.cpp (356-line JNI) + CMakeLists.txt
│       └── patches/          # libvips-remove-subdirs.patch
├── sample/                   # Compose demo app (namespace ...imagedecoder.test)
├── tests/wsl/                # bash + cmake -P build-helper tests (see tests/wsl/AGENTS.md)
├── gradle/libs.versions.toml # AGP 9.3.2, Kotlin 2.4.10, Compose BOM 2026.08.00
├── BUILD.md                  # authoritative native-build doc
└── .github/workflows/build.yml  # CI: native-Linux build + publishToMavenCentral
```

Excluded from map: `library/.cxx/`, `library/build/`, `.gradle/`, `.kotlin/` (generated).

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Public API (decode/encode/info) | `library/src/main/java/ca/mpreg/imagedecoder/ImageDecoder.kt` | single file; `new()`, `getInfo()`, `decode()`, `encode()` |
| JNI decode/encode impl | `library/src/main/cpp/imagedecoder/imagedecoder.cpp` | `vips::VImage::new_from_buffer` funnel; RGBA direct ByteBuffer out |
| Native dep wiring | `library/src/main/cpp/CMakeLists.txt` + `cmake/*.cmake` | see `library/src/main/cpp/AGENTS.md` |
| Build-helper tests | `tests/wsl/` | see `tests/wsl/AGENTS.md`; no `src/test` anywhere |
| Module config (publishing, WSL gate) | `library/build.gradle.kts` | vanniktech publish 0.36.0, cmake 3.22.1, target `ep_imagedecoder` |
| Version bumps (JVM side) | `gradle/libs.versions.toml` | publish plugin version hardcoded inline in `library/build.gradle.kts:5` |
| Sample usage pattern | `sample/src/main/java/ca/mpreg/imagedecoder/MainActivity.kt` | `ImageDecoder.new(stream).decode()` |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `ImageDecoder.new/getInfo` | Kotlin companion externals | `ImageDecoder.kt:170,174` | entry: construct from stream, probe info |
| `ImageDecoder.decode/encode` | Kotlin externals | `ImageDecoder.kt:59,88` | per-page RGBA decode; re-encode via suffix |
| `ImageDecoder.format/isSupportedFormat` | Kotlin mappings | `ImageDecoder.kt:21,181` | vips-loader → jpeg/png/webp/gif/tiff/heif/jxl/jp2 |
| `JNI_OnLoad` | C++ JNI | `imagedecoder.cpp:42` | `VIPS_INIT`, concurrency=1, cache off |
| `Java_..._ImageDecoder_new/getInfo/decode/encode` | C++ JNI exports | `imagedecoder.cpp:146,232,268,322` | buffer ingest (80 MB cap, 16384px cap) → vips → ByteBuffer |
| `Decoder` / `decoder_new/free` | C++ struct | `imagedecoder.cpp:78,86,91` | owns `buffer`, `pages`, `durations` |
| `to_msys_path` | CMake function | `cpp/CMakeLists.txt:139` | `C:/` → `/mnt/c/`; core of WSL strategy |
| `EP_MESON_ARGS` / `EP_AUTOTOOLS_ARGS` | CMake vars | `cpp/CMakeLists.txt:568,764` | cross-file + prefix + static-only flags |
| `ep_imagedecoder` | CMake/AGP target | `cpp/CMakeLists.txt:1246` | final `imagedecoder2` shared lib |
| `run_all.sh` / `_assert.sh` | bash harness | `tests/wsl/` | auto-discovers `test_*.sh`; assert primitives |

## CONVENTIONS

- C++: `.clang-format` = Mozilla base, 100-col, BinPack args/params. Kotlin: `kotlin.code.style=official`, Java 17.
- Native libs static-only (`--default-library=static`, `--disable-shared`, `BUILD_SHARED_LIBS=OFF`, `--buildtype=release`).
- Vendored-dep warnings suppressed (`-Wno-*` block in root `EP_CMAKE_ARGS`); don't "fix" upstream warnings.
- `src/main/keepRules/rules.keep` (not `proguard-rules.pro`) — AGP 8.1+ convention, fine.
- Version = git short SHA + `-SNAPSHOT` unless tag build (`library/build.gradle.kts:11`).
- No JVM tests exist; build-helper regressions go in `tests/wsl/` (bash + `cmake -P`), not `src/test`.

## ANTI-PATTERNS (THIS PROJECT)

- MSYS2 / Git Bash / Windows `meson.exe` for native builds — WSL is the single Windows path; `CMakeLists.txt` FATAL_ERRORs without `wsl.exe`.
- Passing `BASH_EXECUTABLE` / `Make_EXECUTABLE` / `Meson_EXECUTABLE` from Gradle on Windows (`library/build.gradle.kts:57`) — overrides WSL forcing, reintroduces `C:/` bugs.
- `C:/` or `/c/` paths in meson `--prefix` / `--cross-file` / autotools `CC=` — must be `/mnt/c/` (use `to_msys_path`); `CC=C:/...` parses as variable `C`.
- Ninja with a space in path (`C:/Program Files/Meson/...`) — breaks `cmake -E env`; use Android SDK ninja.
- Editing generated `android-cross-file.txt` or anything under `library/.cxx/` — regenerate via Gradle instead.
- `forwarding MAKE` via `WSLENV` — shadows `make`, breaks autotools (`all-recursive: command not found` precedent).

## UNIQUE STYLES

- `fk/` fakeroot + `ep/` ExternalProject base — short names dodge Windows MAX_PATH on stamp files.
- `WSL_ENV_FORWARD` (`CC:CCAS:CFLAGS:...`) — `cmake -E env` does not reach WSL Linux otherwise (host-`gcc` miscompile precedent).
- Linux NDK (`/usr/lib/.../linux-x86_64/bin/clang`) preferred inside WSL over Windows `.exe` (avoids `Exec format error`, correct `aarch64` target).
- `imagedecoder2` `.so` name vs `imagedecoder` module/class — historical, keep.
- `:imagedecoder` module lives in `library/` (`settings.gradle.kts:28` remap) — use Gradle name, not dir name.

## COMMANDS

```bash
./gradlew :library:assembleDebug --rerun-tasks        # native Linux / CI
.\gradlew.bat :library:assembleDebug --rerun-tasks    # Windows (Debian WSL required)
bash tests/wsl/run_all.sh                             # build-helper tests, no Gradle needed
rm -rf library/.cxx .gradle/configuration-cache && ./gradlew --stop  # stale-cache recovery
```

## NOTES

- Stale `library/.cxx` with empty `--cross-file=` in `build.ninja` is the classic failure — always nuke `.cxx` after editing `CMakeLists.txt` or switching NDK.
- 32-bit Gradle daemon can't see `System32\wsl.exe` — `gradlew --stop` + `Sysnative` check if WSL probe FATALs spuriously.
- WSL `make`/`meson` probe `MISSING` warnings can be flaky; tools are installed — verify manually before acting.
- `MainActivity.kt` opens `assets/anim-icos.gif`, but `sample` assets live at module root (`sample/assets/`) and the referenced file may be absent.
- CI publishes to Maven Central on every `master` push and runs zero tests — don't assume green CI means tests passed.
- `BUILD.md` references `scripts/wsl-tests/run.ps1` — stale; real path is `tests/wsl/run.ps1` (parent repo has the wrapper).
