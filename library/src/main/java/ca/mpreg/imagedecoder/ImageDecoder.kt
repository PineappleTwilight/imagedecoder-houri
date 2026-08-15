package ca.mpreg.imagedecoder

import java.io.InputStream
import java.nio.ByteBuffer

class ImageDecoder private constructor(
    private val ptr: Long,
    val pages: Int,
    var page: Int,
    val isHdr: Boolean,
    private val loader: String,
) {
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
            loader.startsWith("gif") -> "gif"   // built into libvips, no external dep
            loader.startsWith("tiff") -> "tiff"
            loader.startsWith("heif") -> "heif"  // covers HEIC and AVIF (via libheif)
            loader.startsWith("jxl") -> "jxl"
            loader.startsWith("jp2k") -> "jp2k"  // JPEG 2000 via libopenjp2
            else -> loader.removeSuffix("load_buffer").removeSuffix("load")
        }

    class DecodeException private constructor(message: String) : Exception(message)

    class DecodeResult private constructor(
        private val ptr: Long,
        val image: ByteBuffer,
        val width: Int,
        val height: Int,
        val duration: Int,
        val trim_left: Int,
        val trim_top: Int,
        val trim_width: Int,
        val trim_height: Int,
    ) {
        protected fun finalize() {
            free()
        }

        private external fun free()
    }

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
    ) {
        protected fun finalize() {
            free()
        }

        private external fun free()
    }

    @Synchronized
    @Throws(DecodeException::class)
    external fun encode(suffix: String, page: Int = -1): EncodeResult

    protected fun finalize() {
        free()
    }

    private external fun free()

    companion object {
        init {
            System.loadLibrary("imagedecoder2")
        }

        @JvmStatic
        @Throws(DecodeException::class)
        external fun new(inputStream: InputStream): ImageDecoder
    }
}
