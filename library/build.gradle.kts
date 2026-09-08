import java.util.concurrent.TimeUnit

plugins {
    alias(libs.plugins.android.library)
    id("com.vanniktech.maven.publish") version "0.36.0"
}

group = "ca.mpreg"
version = "0.0.0"

val tag = if (System.getenv("GITHUB_REF_TYPE") == "tag") {
    System.getenv("GITHUB_REF_NAME")
} else {
    val baseVersion = providers.exec {
        commandLine("git", "rev-parse", "--short", "HEAD")
    }.standardOutput.asText.map { it.trim() }.getOrElse("unknown")
    "$baseVersion-SNAPSHOT"
}

android {
    namespace = "ca.mpreg.imagedecoder"
    compileSdk = 37

    defaultConfig {
        minSdk = 24

        externalNativeBuild {
            cmake {
                cppFlags("-O3 -flto")
                targets("ep_imagedecoder")
                // WSL is the SINGLE path for Windows native builds. No MSYS2/Git Bash fallback.
                // CMakeLists.txt (WIN32) will FATAL_ERROR if WSL is missing, so we only verify
                // here with a clear Gradle error before CMake configuration starts.
                if (System.getProperty("os.name").contains("Windows", ignoreCase = true)) {
                    val wslCandidates = listOf(
                        File("C:/Windows/System32/wsl.exe"),
                        File("C:/Windows/Sysnative/wsl.exe"),
                    )
                    val wslFoundViaFile = wslCandidates.any { it.exists() }
                    val wslFoundViaExec = try {
                        val proc = ProcessBuilder("wsl", "--status")
                            .redirectErrorStream(true).start()
                        proc.waitFor(8, TimeUnit.SECONDS)
                        wslFoundViaFile || proc.exitValue() == 0
                    } catch (_: Exception) {
                        wslFoundViaFile
                    }
                    if (!wslFoundViaExec) {
                        throw org.gradle.api.GradleException(
                            "WSL is required on Windows for imagedecoder native builds. " +
                                "WSL not found (checked 'wsl --status' and ${wslCandidates.joinToString()} ). " +
                                "Install WSL from https://aka.ms/wsl (run 'wsl --install' in elevated PowerShell), " +
                                "ensure 'wsl --status' works, then: pacman -S base-devel autoconf automake libtool pkg-config meson ninja cmake  inside WSL, " +
                                "and re-sync Gradle. MSYS2/Git Bash is NOT supported — WSL is the single only path.",
                        )
                    }
                    // Do NOT pass BASH_EXECUTABLE/Make_EXECUTABLE/Meson_EXECUTABLE for Windows:
                    // CMakeLists.txt detects WIN32+WSL and forces 'wsl bash' / 'wsl meson' / 'wsl make' etc.
                    // Passing MSYS Windows paths would override that and reintroduce C:/ vs /c/ bugs.
                    logger.lifecycle("Windows detected: delegating all native builds to WSL (single path).")
                }
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {}

afterEvaluate {
    mavenPublishing {
        coordinates("ca.mpreg", "imagedecoder", tag)

        pom {
            name.set("imagedecoder")
            description.set("imagedecoder")
            inceptionYear.set("2026")
            url.set("https://github.com/mpreg-ca/imagedecoder")
            licenses {
                license {
                    name.set("MIT License")
                    url.set("https://opensource.org")
                    distribution.set("repo")
                }
            }
            developers {
                developer {
                    id.set("wwww-wwww")
                    name.set("w")
                    url.set("https://github.com/wwww-wwww/")
                }
            }
            scm {
                url.set("https://github.com/mpreg-ca/imagedecoder/")
                connection.set("scm:git:git://github.com/mpreg-ca/imagedecoder.git")
                developerConnection.set("scm:git:ssh://git@github.com/mpreg-ca/imagedecoder.git")
            }
        }

        publishToMavenCentral(automaticRelease = true)
        signAllPublications()
    }
}
