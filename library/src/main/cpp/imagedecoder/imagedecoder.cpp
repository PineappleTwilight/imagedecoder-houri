#include <stdint.h>

#include <glib.h>
#include <jni.h>
#include <vips/vips8>

using namespace vips;

static void
throw_vips_error(JNIEnv* env, const vips::VError& e)
{
  std::string msg = e.what();
  vips_error_clear();
  if (env->ExceptionCheck())
    env->ExceptionClear();
  const char* cls = msg.find("not in a known format") != std::string::npos
                      ? "ca/mpreg/imagedecoder/ImageDecoder$UnknownFormatException"
                      : "ca/mpreg/imagedecoder/ImageDecoder$DecodeException";
  env->ThrowNew(env->FindClass(cls), msg.c_str());
}

jint
JNI_OnLoad(JavaVM* vm, void*)
{
  if (VIPS_INIT("VipsDecoder"))
    return JNI_ERR;
  vips_concurrency_set(1);
  vips_cache_set_max(0);

  JNIEnv* env;
  if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK)
    return JNI_ERR;

  return JNI_VERSION_1_6;
}

jlong
get_ptr(JNIEnv* env, jobject obj)
{
  jclass cls = env->GetObjectClass(obj);
  jfieldID ptr_field = env->GetFieldID(cls, "ptr", "J");
  return env->GetLongField(obj, ptr_field);
}

jlong
take_ptr(JNIEnv* env, jobject obj)
{
  jclass cls = env->GetObjectClass(obj);
  jfieldID ptr_field = env->GetFieldID(cls, "ptr", "J");
  jlong ptr = env->GetLongField(obj, ptr_field);
  env->SetLongField(obj, ptr_field, 0L);
  return ptr;
}

struct Decoder
{
  uint8_t* buffer;
  size_t buffer_size;
  int pages;
  int* durations;
  int durations_count;
};

static Decoder*
decoder_new()
{
  Decoder* d = g_new0(Decoder, 1);
  return d;
}

static void
decoder_free(Decoder* d)
{
  if (!d) {
    return;
  }
  g_free(d->buffer);
  g_free(d->durations);
  g_free(d);
}

static constexpr size_t kMaxImageBytes = 80 * 1024 * 1024;

static uint8_t*
read_all(JNIEnv* env, jobject jstream, size_t* out_size)
{
  jclass cls = env->GetObjectClass(jstream);
  if (cls == nullptr) {
    *out_size = 0;
    return nullptr;
  }
  jmethodID readMethod = env->GetMethodID(cls, "read", "([B)I");
  if (readMethod == nullptr) {
    *out_size = 0;
    return nullptr;
  }

  jbyteArray buf = env->NewByteArray(8192);
  if (buf == nullptr) {
    *out_size = 0;
    return nullptr;
  }
  GByteArray* result = g_byte_array_new();
  if (result == nullptr) {
    *out_size = 0;
    return nullptr;
  }

  while (true) {
    jint n = env->CallIntMethod(jstream, readMethod, buf);

    if (env->ExceptionCheck()) {
      env->ExceptionClear();
      break;
    }

    if (n <= 0) {
      break;
    }
    if (result->len + static_cast<size_t>(n) > kMaxImageBytes) {
      g_byte_array_free(result, TRUE);
      *out_size = 0;
      jclass ex = env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException");
      if (ex != nullptr) env->ThrowNew(ex, "Image too large (>80MB)");
      return nullptr;
    }
    jbyte* bytes = env->GetByteArrayElements(buf, nullptr);
    if (bytes == nullptr)
      break;
    g_byte_array_append(result, (const guint8*)bytes, n);
    env->ReleaseByteArrayElements(buf, bytes, JNI_ABORT);
  }

  *out_size = result->len;
  uint8_t* data = g_byte_array_free(result, FALSE);
  return data;
}

extern "C" JNIEXPORT jobject JNICALL
Java_ca_mpreg_imagedecoder_ImageDecoder_new(JNIEnv* env, jclass, jobject jstream)
{
  Decoder* decoder = decoder_new();
  decoder->buffer = read_all(env, jstream, &decoder->buffer_size);

  if (decoder->buffer_size == 0 || decoder->buffer == nullptr) {
    decoder_free(decoder);
    if (env->ExceptionCheck())
      env->ExceptionClear();
    env->ThrowNew(env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException"),
                  "Empty or unreadable image stream");
    return nullptr;
  }

  {
    const size_t n = MIN(decoder->buffer_size, (size_t)16);
    char hex[64] = {};
    for (size_t i = 0; i < n; i++) {
      sprintf(hex + i * 3, "%02x ", decoder->buffer[i]);
    }
  }

  try {
    vips::VImage image = vips::VImage::new_from_buffer(decoder->buffer, decoder->buffer_size, "");

    decoder->pages =
      image.get_typeof(VIPS_META_N_PAGES) != 0 ? image.get_int(VIPS_META_N_PAGES) : 1;

    if (decoder->pages > 0 && image.get_typeof("delay") != 0) {
      int* delays;
      int n;

      image.get_array_int("delay", &delays, &n);
      decoder->durations = g_new(int, n);
      decoder->durations_count = n;
      memcpy(decoder->durations, delays, n * sizeof(int));
    }

    bool is_hdr = image.interpretation() == VIPS_INTERPRETATION_scRGB;

    const char* loader_cstr =
      image.get_typeof("vips-loader") != 0 ? image.get_string("vips-loader") : "";
    std::string loader_str = loader_cstr ? loader_cstr : "";

    image = vips::VImage();
    jstring jloader = env->NewStringUTF(loader_str.c_str());
    jclass cls = env->FindClass("ca/mpreg/imagedecoder/ImageDecoder");
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(JIIZLjava/lang/String;)V");
    return env->NewObject(cls, ctor, reinterpret_cast<jlong>(decoder), decoder->pages, 0, is_hdr,
                          jloader);
  } catch (const vips::VError& e) {
    decoder_free(decoder);
    throw_vips_error(env, e);
    return nullptr;
  }
}

extern "C" JNIEXPORT void JNICALL
Java_ca_mpreg_imagedecoder_ImageDecoder_free(JNIEnv* env, jobject obj)
{
  jlong ptr = take_ptr(env, obj);
  if (ptr == 0) return;
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);
  decoder_free(decoder);
}

extern "C" JNIEXPORT void JNICALL
Java_ca_mpreg_imagedecoder_ImageDecoder_nativeFree(JNIEnv* env, jclass, jlong ptr)
{
  if (ptr == 0) return;
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);
  decoder_free(decoder);
}

extern "C" JNIEXPORT jobject JNICALL
Java_ca_mpreg_imagedecoder_ImageDecoder_decode(JNIEnv* env, jobject obj, jint page, jboolean crop,
                                               jboolean getTrim)
{
  jlong ptr = get_ptr(env, obj);
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);
  if (decoder == nullptr || decoder->buffer == nullptr) {
    jclass ex = env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException");
    if (ex != nullptr) env->ThrowNew(ex, "Decoder already closed");
    return nullptr;
  }
  if (page < 0 || page >= decoder->pages) {
    jclass ex = env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException");
    if (ex != nullptr) env->ThrowNew(ex, "Page index out of range");
    return nullptr;
  }

  try {
    vips::VImage frame = vips::VImage::new_from_buffer(
      decoder->buffer, decoder->buffer_size, "",
      vips::VImage::option()
        ->set("access", (crop || getTrim) ? VIPS_ACCESS_RANDOM : VIPS_ACCESS_SEQUENTIAL)
        ->set("page", page));

    if (frame.interpretation() != VIPS_INTERPRETATION_sRGB &&
        frame.interpretation() != VIPS_INTERPRETATION_scRGB)
      frame = frame.colourspace(VIPS_INTERPRETATION_sRGB);

    if (frame.bands() < 4)
      frame = frame.bandjoin(255);
    if (frame.bands() > 4)
      frame = frame.extract_band(0, vips::VImage::option()->set("n", 4));

    int width = frame.width();
    int height = frame.height();
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) {
      jclass ex = env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException");
      if (ex != nullptr) env->ThrowNew(ex, "Decoded dimensions out of range");
      return nullptr;
    }

    int duration = 0;
    if (decoder->pages > 0 && page < decoder->durations_count)
      duration = decoder->durations[page];

    int trim_left = 0;
    int trim_top = 0;
    int trim_width = 0;
    int trim_height = 0;

    if (crop || getTrim) {
      int trim_left_w, trim_top_w, trim_width_w, trim_height_w;
      trim_left_w = frame.find_trim(&trim_top_w, &trim_width_w, &trim_height_w,
                                    vips::VImage::option()->set("line_art", true));

      int trim_left_b, trim_top_b, trim_width_b, trim_height_b;
      trim_left_b =
        frame.find_trim(&trim_top_b, &trim_width_b, &trim_height_b,
                        vips::VImage::option()->set("line_art", true)->set("background", 0.0));

      // find_trim can return width/height <=0 on solid-color images; guard against zero crop
      if (trim_width_w <= 0 || trim_height_w <= 0 || trim_width_b <= 0 || trim_height_b <= 0) {
        trim_left = 0;
        trim_top = 0;
        trim_width = width;
        trim_height = height;
      } else {
        trim_left = std::max(trim_left_w, trim_left_b);
        trim_top = std::max(trim_top_w, trim_top_b);
        trim_width = std::min(trim_width_w, trim_width_b);
        trim_height = std::min(trim_height_w, trim_height_b);
        trim_width = std::max(1, std::min(trim_width, width - trim_left));
        trim_height = std::max(1, std::min(trim_height, height - trim_top));
      }
    }

    if (crop) {
      if (trim_width <= 0 || trim_height <= 0 || trim_left < 0 || trim_top < 0 ||
          trim_left + trim_width > width || trim_top + trim_height > height) {
        // Invalid trim would produce zero crop — return full frame instead
      } else {
        frame = frame.crop(trim_left, trim_top, trim_width, trim_height);
        width = trim_width;
        height = trim_height;
      }
      trim_left = 0;
      trim_top = 0;
      trim_width = 0;
      trim_height = 0;
    }

    size_t size = VIPS_IMAGE_SIZEOF_IMAGE(frame.get_image());

    jclass bufferCls = env->FindClass("java/nio/ByteBuffer");
    jmethodID allocateDirect =
      env->GetStaticMethodID(bufferCls, "allocateDirect", "(I)Ljava/nio/ByteBuffer;");

    jobject byteBuffer = size <= (size_t)G_MAXINT
                           ? env->CallStaticObjectMethod(bufferCls, allocateDirect, (jint)size)
                           : nullptr;
    if (!byteBuffer || env->ExceptionCheck()) {
      if (env->ExceptionCheck())
        env->ExceptionClear();
      env->ThrowNew(env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException"),
                    "Out of memory");
      return nullptr;
    }

    void* data = env->GetDirectBufferAddress(byteBuffer);
    if (!data) {
      if (env->ExceptionCheck())
        env->ExceptionClear();
      env->ThrowNew(env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException"),
                    "Failed to allocate direct byte buffer");
      return nullptr;
    }

    frame.write(vips::VImage::new_from_memory(data, size, frame.width(), frame.height(),
                                              frame.bands(), frame.format()));

    jclass cls = env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeResult");
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(Ljava/nio/ByteBuffer;IIIIIII)V");
    return env->NewObject(cls, ctor, byteBuffer, width, height, duration, trim_left, trim_top,
                          trim_width, trim_height);
  } catch (const vips::VError& e) {
    throw_vips_error(env, e);
    return nullptr;
  }
}

extern "C" JNIEXPORT jobject JNICALL
Java_ca_mpreg_imagedecoder_ImageDecoder_encode(JNIEnv* env, jobject obj, jstring jsuffix, jint page)
{
  jlong ptr = get_ptr(env, obj);
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);

  const char* suffix = env->GetStringUTFChars(jsuffix, nullptr);

  try {
    vips::VImage frame = vips::VImage::new_from_buffer(decoder->buffer, decoder->buffer_size, "",
                                                       vips::VImage::option()->set("page", page));

    size_t size;
    void* data;
    frame.write_to_buffer(suffix, &data, &size);

    env->ReleaseStringUTFChars(jsuffix, suffix);

    jobject byteBuffer = env->NewDirectByteBuffer(data, size);
    if (!byteBuffer) {
      g_free(data);
      if (env->ExceptionCheck())
        env->ExceptionClear();
      env->ThrowNew(env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$DecodeException"),
                    "Failed to allocate direct byte buffer");
      return nullptr;
    }

    jclass cls = env->FindClass("ca/mpreg/imagedecoder/ImageDecoder$EncodeResult");
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(JLjava/nio/ByteBuffer;)V");
    return env->NewObject(cls, ctor, (jlong)(intptr_t)data, byteBuffer);
  } catch (const vips::VError& e) {
    env->ReleaseStringUTFChars(jsuffix, suffix);
    throw_vips_error(env, e);
    return nullptr;
  }
}

extern "C" JNIEXPORT void JNICALL
Java_ca_mpreg_imagedecoder_ImageDecoder_00024EncodeResult_free(JNIEnv* env, jobject obj)
{
  jlong ptr = take_ptr(env, obj);
  if (ptr == 0)
    return;
  g_free((void*)(intptr_t)ptr);
}
