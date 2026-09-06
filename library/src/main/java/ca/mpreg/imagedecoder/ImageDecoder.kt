package ca.mpreg.imagedecoder

import java.io.Closeable
import java.io.InputStream
import java.lang.ref.Cleaner
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
    private val cleanable: Cleaner.Cleanable?

    init {
        val p = ptr
        cleanable = cleaner.register(this) {
            val v = closePtr.getAndSet(0L)
            if (v != 0L) {
                try { nativeFree(v) } catch (_: Exception) {}
            }
        }
    }

    @Synchronized
    override fun close() {
        val v = closePtr.getAndSet(0L)
        if (v != 0L) {
            try { free() } catch (_: Exception) {}
            try { cleanable?.clean() } catch (_: Exception) {}
        }
    }

    protected fun finalize() {
        close()
    }

    private external fun free()

    companion object {
        private val cleaner: Cleaner = Cleaner.create()

        @JvmStatic
        private external fun nativeFree(ptr: Long)

        init {
            System.loadLibrary("imagedecoder2")
        }

        @JvmStatic
        @Throws(DecodeException::class)
        external fun new(inputStream: InputStream): ImageDecoder

        @JvmStatic
        @Throws(DecodeException::class)
        fun fromBytes(bytes: ByteArray): ImageDecoder = new(bytes.inputStream())

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
