# imagedecoder-houri

Android image decoding library (`ca.mpreg.imagedecoder`) backed by **libvips via JNI**. Decodes `jpeg / png / webp / gif / tiff / heif (avif, heic) / jxl / jp2` to RGBA `ByteBuffer`s, with multi-page (animated) support, HDR detection, trim/crop, and re-encode. Submodule of `komikku-pineapple` at `external/imagedecoder-houri`.

Native output is named **`imagedecoder2`** (`.so`) for historical reasons; the Gradle module and Kotlin class are `imagedecoder` / `ImageDecoder`. The `:imagedecoder` module lives in `library/` (see `settings.gradle.kts`).

## Features

- Single-JNI funnel: `VImage::new_from_buffer` → sRGB → RGBA direct `ByteBuffer` out.
- Multi-page: `pages`, per-page `decode(page)`, `decodeNext()` round-robins, per-page GIF/WebP `duration`.
- `getInfo()` probe without a full decode (width, height, pages, format, HDR, duration).
- Trim/crop: `decode(crop = true)` auto-crops borders via `find_trim`; `getTrim = true` returns `trim_*` box without cropping.
- Re-encode: `encode(suffix, page)` (e.g. `.jpg`, `.png`, `.webp`) via libvips saver.
- HDR flag via `VIPS_INTERPRETATION_scRGB`.
- Hard caps in JNI (`imagedecoder.cpp`): 80 MB input buffer, 16384 px per side, max 1024 pages.

## Requirements

- JDK 17, AGP 9.3.2, Kotlin 2.4.10, `compileSdk 37`, `minSdk 24` (see `gradle/libs.versions.toml`, `library/build.gradle.kts`).
- CMake 3.22.1 + NDK `28.2.13676358` (both prebuilts: `windows-x86_64` + `linux-x86_64`).
- **Windows: Debian WSL2 is the single supported path.** No MSYS2 / Git Bash. `CMakeLists.txt` `FATAL_ERROR`s without `wsl.exe`. See `BUILD.md`.
- **Linux (CI):** native build, no WSL.

## Usage

```kotlin
import ca.mpreg.imagedecoder.ImageDecoder

// From stream
val stream = assets.open("anim-icos.gif")
val decoder = ImageDecoder.new(stream)
try {
    val info = ImageDecoder.getInfo(inputStream2) // ImageInfo(width, height, pages, format, isHdr, durationMs)
    println("${info.format} ${info.width}x${info.height} pages=${info.pages}")

    val page0 = decoder.decode(page = 0)          // DecodeResult(image, width, height, duration, trim_*)
    val next = decoder.decodeNext(crop = true)    // auto-advance + crop borders
    val box = decoder.decode(page = 0, getTrim = true) // trim_left/top/width/height only

    decoder.encode(".jpg").use { out -> /* out.bytes: ByteBuffer */ }
} finally {
    decoder.close()
}

// From bytes
val decoder2 = ImageDecoder.fromBytes(bytes)

// Format helpers
decoder.format // "jpeg" | "png" | "webp" | "gif" | "tiff" | "heif" | "jxl" | "jp2"
ImageDecoder.isSupportedFormat(loaderString)
```

`DecodeResult.image` is a direct RGBA `ByteBuffer` (`width × height × 4`). `EncodeResult.bytes` must be closed/freed (`use { }` or `closeAndFree()`). Errors throw `DecodeException` (`UnknownFormatException` for unrecognized input). See `library/src/main/java/ca/mpreg/imagedecoder/ImageDecoder.kt` (entire public API, one file) and `sample/.../MainActivity.kt`.

## Build

```bash
# Linux / CI
./gradlew :library:assembleDebug --rerun-tasks

# Windows (Debian WSL required)
.\gradlew.bat :library:assembleDebug --rerun-tasks
```

Full native-build doc (deps, architecture, troubleshooting): [`BUILD.md`](BUILD.md).

Stale-cache recovery:

```bash
rm -rf library/.cxx .gradle/configuration-cache && ./gradlew --stop
```

## Project structure

```
./
├── library/src/main/
│   ├── java/ca/mpreg/imagedecoder/ImageDecoder.kt  # entire public API
│   └── cpp/
│       ├── CMakeLists.txt    # native orchestrator (18 static deps, then imagedecoder2)
│       ├── cmake/            # per-dependency ExternalProject recipes
│       ├── imagedecoder/     # imagedecoder.cpp (JNI) + CMakeLists.txt
│       └── patches/          # libvips-remove-subdirs.patch
├── sample/                   # Compose demo app
├── tests/wsl/                # bash + cmake -P regression guards (see tests/README.md)
├── gradle/libs.versions.toml
├── BUILD.md                  # authoritative native-build doc
└── .github/workflows/build.yml  # CI: native-Linux build + publishToMavenCentral
```

Native details: `library/src/main/cpp/AGENTS.md`. Test harness: `tests/wsl/AGENTS.md`, [`tests/README.md`](tests/README.md).

## Tests

No JVM tests. Build-helper regressions are pure `bash` + `cmake -P`:

```bash
bash tests/wsl/run_all.sh
```

```powershell
powershell -ExecutionPolicy Bypass -File tests\wsl\run.ps1
```

See [`tests/README.md`](tests/README.md).

## Publishing

`library/build.gradle.kts` uses `com.vanniktech.maven.publish` 0.36.0 → `ca.mpreg:imagedecoder:<git-short-SHA>-SNAPSHOT` (or tag name on tag builds). CI publishes to Maven Central on every `master` push. CI runs zero tests — green CI does not mean tests passed.

## License

MIT — see [`LICENSE`](LICENSE).
