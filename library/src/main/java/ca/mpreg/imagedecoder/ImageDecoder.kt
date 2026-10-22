package ca.mpreg.imagedecoder

import android.os.Build
import java.io.Closeable
import java.io.InputStream
import java.lang.reflect.Method
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicLong

class ImageDecoder private constructor(
    private val ptr: Long,
    val pages: Int,
    var page: Int,
    val isHdr: Boolean,
    private val loader: String,
) : Closeable {
    /**
     * Normalized image format derived from the libvips loader name.
     *
     * Enabled formats: jpeg, png, webp, gif, tiff, heif (includes avif/heic), jxl, jp2k.
     */
    val format: String
        get() = when {
            loader.startsWith("jpeg") -> "jpeg"
            loader.startsWith("png") -> "png"
            loader.startsWith("webp") -> "webp"
            loader.startsWith("gif") -> "gif"
            loader.startsWith("tiff") -> "tiff"
            loader.startsWith("heif") -> "heif"
            loader.startsWith("jxl") -> "jxl"
            loader.startsWith("jp2k") -> "jp2"
            else -> loader.removeSuffix("load_buffer").removeSuffix("load")
        }

    open class DecodeException internal constructor(message: String, cause: Throwable? = null) : Exception(message, cause)

    class UnknownFormatException internal constructor(message: String) : DecodeException(message)

    class DecodeResult private constructor(
        val image: ByteBuffer,
        val width: Int,
        val height: Int,
        val duration: Int,
        val trim_left: Int,
        val trim_top: Int,
        val trim_width: Int,
        val trim_height: Int,
    )

    @Synchronized
    @Throws(DecodeException::class)
    fun decodeNext(crop: Boolean = false, getTrim: Boolean = false): DecodeResult {
        val res = decode(page, crop, getTrim)
        page = (page + 1) % pages
        return res
    }

    @Synchronized
    @Throws(DecodeException::class)
    external fun decode(
        page: Int = 0, crop: Boolean = false, getTrim: Boolean = false
    ): DecodeResult

    class EncodeResult private constructor(
        private val ptr: Long,
        val bytes: ByteBuffer,
    ) : Closeable {
        @Volatile private var freed = false

        @Synchronized
        fun closeAndFree() {
            if (!freed) {
                freed = true
                try { free() } catch (_: Exception) {}
            }
        }

        override fun close() = closeAndFree()

        protected fun finalize() {
            closeAndFree()
        }

        private external fun free()
    }

    @Synchronized
    @Throws(DecodeException::class)
    external fun encode(suffix: String, page: Int = -1): EncodeResult

    private val closePtr = AtomicLong(ptr)
    private val cleanable: Any?

    init {
        val p = ptr
        // KMK --> Cleaner registration reuses the companion's cached `register` Method; the old
        // per-instance `getMethod` call ran reflection resolution on every decoder construction -
        // once per page on the decode path.
        cleanable = try {
            val c = cleaner
            val register = cleanerRegisterMethod
            if (c != null && register != null) {
                register.invoke(
                    c,
                    this,
                    Runnable {
                        val v = closePtr.getAndSet(0L)
                        if (v != 0L) {
                            try { nativeFree(v) } catch (_: Exception) {}
                        }
                    },
                )
            } else null
        } catch (_: Throwable) {
            null
        }
        // KMK <--
    }

    @Synchronized
    override fun close() {
        val v = closePtr.getAndSet(0L)
        if (v != 0L) {
            try { free() } catch (_: Exception) {}
            // KMK --> `clean` comes from the companion's cached Method; resolving it per close was
            // a second reflection lookup on a KMR-hot path.
            try {
                cleanable?.let { cl ->
                    try { cleanableCleanMethod?.invoke(cl) } catch (_: Throwable) {}
                }
            } catch (_: Exception) {}
            // KMK <--
        }
    }

    protected fun finalize() {
        try { close() } catch (_: Throwable) {}
    }

    private external fun free()

    data class ImageInfo(
        val width: Int,
        val height: Int,
        val pages: Int,
        val format: String,
        val isHdr: Boolean,
        val durationMs: Int,
    )

    companion object {
        // KMK --> Cached reflection against the cleaner, guarded by the same SDK check. `register`
        // is re-resolved per instance and `clean` per close without this; both sit on the per-page
        // decode path. One `Cleaner.create()` still happens in [cleaner]; these two only stop the
        // per-instance method lookups.
        private val cleanerCreateMethod: Method? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                Class.forName("java.lang.ref.Cleaner").getMethod("create")
            } else null
        } catch (_: Throwable) {
            null
        }

        private val cleaner: Any? = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                cleanerCreateMethod?.invoke(null)
            } else null
        } catch (_: Throwable) {
            null
        }

        private val cleanerRegisterMethod: Method? = try {
            cleaner?.javaClass?.getMethod("register", Any::class.java, Runnable::class.java)
        } catch (_: Throwable) {
            null
        }

        /** `Cleanable.clean`, resolved against the documented nested interface once. */
        private val cleanableCleanMethod: Method? = try {
            Class.forName("java.lang.ref.Cleaner\$Cleanable").getMethod("clean")
        } catch (_: Throwable) {
            null
        }
        // KMK <--

        @JvmStatic
        private external fun nativeFree(ptr: Long)

        @Volatile private var loadError: Throwable? = null
        @Volatile private var isLoaded = false

        init {
            try {
                System.loadLibrary("imagedecoder2")
                isLoaded = true
            } catch (e: Throwable) {
                loadError = e
                isLoaded = false
            }
        }

        private fun ensureLoaded() {
            if (!isLoaded) throw DecodeException("imagedecoder native library not loaded: ${loadError?.message}", loadError)
        }

        @JvmStatic
        @Throws(DecodeException::class)
        external fun new(inputStream: InputStream): ImageDecoder

        /**
         * Constructs from bytes that are already fully in memory.
         *
         * Identical to [new] over those bytes' stream, minus the chunked read: the stream path
         * handed JNI `read` calls in 8 KiB pieces and copied every byte twice (element buffer and
         * bytearray append), so one 25 MB page crossed the JVM boundary thousands of times before
         * the decoder saw a buffer. Here the array is consumed in a single native copy.
         */
        @JvmStatic
        @Throws(DecodeException::class)
        external fun newBytes(bytes: ByteArray): ImageDecoder

        @JvmStatic
        @Throws(DecodeException::class)
        external fun getInfo(inputStream: InputStream): ImageInfo

        @JvmStatic
        @Throws(DecodeException::class)
        fun fromBytes(bytes: ByteArray): ImageDecoder = newBytes(bytes)

        @JvmStatic
        fun isSupportedFormat(loader: String): Boolean = when {
            loader.startsWith("jpeg") -> true
            loader.startsWith("png") -> true
            loader.startsWith("webp") -> true
            loader.startsWith("gif") -> true
            loader.startsWith("tiff") -> true
            loader.startsWith("heif") -> true
            loader.startsWith("jxl") -> true
            loader.startsWith("jp2k") -> true
            else -> false
        }
    }
}
