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
                // Force MSYS2 Bash on Windows before Git Bash / WSL bash (MSYS has autoreconf etc.)
                // Use forward slashes; CMake will handle the space in "Program Files".
                if (System.getProperty("os.name").contains("Windows", ignoreCase = true)) {
                    val msysBash = File("C:/msys64/usr/bin/bash.exe")
                    val msysBash2 = File("C:/tools/msys64/usr/bin/bash.exe")
                    val msysBash3 = File("C:/msys64/bin/bash.exe")
                    val gitBash = File("C:/Program Files/Git/usr/bin/bash.exe")
                    val gitBashAlt = File("C:/Program Files/Git/bin/bash.exe")
                    val bashPath = when {
                        msysBash.exists() -> msysBash.absolutePath
                        msysBash2.exists() -> msysBash2.absolutePath
                        msysBash3.exists() -> msysBash3.absolutePath
                        gitBash.exists() -> gitBash.absolutePath
                        gitBashAlt.exists() -> gitBashAlt.absolutePath
                        else -> null
                    }
                    if (bashPath != null) {
                        arguments += "-DBASH_EXECUTABLE=${bashPath.replace('\\', '/')}"
                    }
                    val mesonBash = File("C:/Program Files/Meson/meson.exe")
                    if (mesonBash.exists()) {
                        arguments += "-DMeson_EXECUTABLE=${mesonBash.absolutePath.replace('\\', '/')}"
                    }
                    val ninjaFromMeson = File("C:/Program Files/Meson/ninja.exe")
                    val ninjaFromSdk = File(System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT") ?: "", "cmake/3.22.1/bin/ninja.exe")
                    val ninjaPath = when {
                        ninjaFromSdk.exists() -> ninjaFromSdk.absolutePath
                        ninjaFromMeson.exists() -> ninjaFromMeson.absolutePath
                        else -> null
                    }
                    if (ninjaPath != null) {
                        arguments += "-DNinja_EXECUTABLE=${ninjaPath.replace('\\', '/')}"
                    }
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
