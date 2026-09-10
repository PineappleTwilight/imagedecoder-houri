#include <cstddef>
#include <cstdint>
#include <string>

#include <glib.h>
#include <jni.h>
#include <vips/vips8>

using namespace vips;

static jclass findClassChecked(JNIEnv* env, const char* name) {
  jclass local = env->FindClass(name);
  if (local == nullptr) {
    if (env->ExceptionCheck()) env->ExceptionClear();
    return nullptr;
  }
  return local;
}

static void throwNewChecked(JNIEnv* env, const char* clsName, const char* msg) {
  if (env->ExceptionCheck()) env->ExceptionClear();
  jclass cls = findClassChecked(env, clsName);
  if (cls == nullptr) return;
  env->ThrowNew(cls, msg);
  env->DeleteLocalRef(cls);
}

static void throw_vips_error(JNIEnv* env, const vips::VError& e) {
  std::string msg = e.what();
  vips_error_clear();
  if (env->ExceptionCheck()) env->ExceptionClear();
  const char* cls = msg.find("not in a known format") != std::string::npos
                        ? "ca/mpreg/imagedecoder/ImageDecoder$UnknownFormatException"
                        : "ca/mpreg/imagedecoder/ImageDecoder$DecodeException";
  jclass jcls = findClassChecked(env, cls);
  if (jcls != nullptr) {
    env->ThrowNew(jcls, msg.c_str());
    env->DeleteLocalRef(jcls);
  }
}

jint JNI_OnLoad(JavaVM* vm, void*) {
  if (VIPS_INIT("VipsDecoder")) return JNI_ERR;
  vips_concurrency_set(1);
  vips_cache_set_max(0);
  JNIEnv* env = nullptr;
  if (vm->GetEnv((void**)&env, JNI_VERSION_1_6) != JNI_OK || env == nullptr) return JNI_ERR;
  return JNI_VERSION_1_6;
}

static jlong get_ptr(JNIEnv* env, jobject obj) {
  if (env == nullptr || obj == nullptr) return 0;
  if (env->ExceptionCheck()) env->ExceptionClear();
  jclass cls = env->GetObjectClass(obj);
  if (cls == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); return 0; }
  jfieldID fid = env->GetFieldID(cls, "ptr", "J");
  if (fid == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(cls); return 0; }
  jlong v = env->GetLongField(obj, fid);
  if (env->ExceptionCheck()) { env->ExceptionClear(); v = 0; }
  env->DeleteLocalRef(cls);
  return v;
}

static jlong take_ptr(JNIEnv* env, jobject obj) {
  if (env == nullptr || obj == nullptr) return 0;
  if (env->ExceptionCheck()) env->ExceptionClear();
  jclass cls = env->GetObjectClass(obj);
  if (cls == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); return 0; }
  jfieldID fid = env->GetFieldID(cls, "ptr", "J");
  if (fid == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(cls); return 0; }
  jlong ptr = env->GetLongField(obj, fid);
  if (env->ExceptionCheck()) { env->ExceptionClear(); ptr = 0; }
  else { env->SetLongField(obj, fid, 0L); if (env->ExceptionCheck()) env->ExceptionClear(); }
  env->DeleteLocalRef(cls);
  return ptr;
}

struct Decoder {
  uint8_t* buffer = nullptr;
  size_t buffer_size = 0;
  int pages = 0;
  int* durations = nullptr;
  int durations_count = 0;
};

static Decoder* decoder_new() {
  Decoder* d = static_cast<Decoder*>(g_try_malloc0(sizeof(Decoder)));
  return d;
}

static void decoder_free(Decoder* d) {
  if (!d) return;
  if (d->buffer) g_free(d->buffer);
  if (d->durations) g_free(d->durations);
  g_free(d);
}

static constexpr size_t kMaxImageBytes = 80 * 1024 * 1024;
static constexpr int kMaxDimension = 16384;

static uint8_t* read_all(JNIEnv* env, jobject jstream, size_t* out_size) {
  if (out_size) *out_size = 0;
  if (env == nullptr || jstream == nullptr || out_size == nullptr) return nullptr;
  if (env->ExceptionCheck()) env->ExceptionClear();

  jclass cls = env->GetObjectClass(jstream);
  if (cls == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); return nullptr; }
  jmethodID readMethod = env->GetMethodID(cls, "read", "([B)I");
  if (readMethod == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(cls); return nullptr; }

  jbyteArray buf = env->NewByteArray(8192);
  if (buf == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(cls); return nullptr; }

  GByteArray* result = g_byte_array_new();
  if (result == nullptr) { env->DeleteLocalRef(buf); env->DeleteLocalRef(cls); return nullptr; }

  while (true) {
    jint n = env->CallIntMethod(jstream, readMethod, buf);
    if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
    if (n <= 0) break;
    if (n > 8192) n = 8192;
    size_t add = static_cast<size_t>(n);
    if (result->len > kMaxImageBytes || add > kMaxImageBytes - result->len) {
      g_byte_array_free(result, TRUE);
      env->DeleteLocalRef(buf);
      env->DeleteLocalRef(cls);
      throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Image too large (>80MB)");
      return nullptr;
    }
    jbyte* bytes = env->GetByteArrayElements(buf, nullptr);
    if (bytes == nullptr) { if (env->ExceptionCheck()) env->ExceptionClear(); break; }
    g_byte_array_append(result, reinterpret_cast<const guint8*>(bytes), static_cast<guint>(n));
    env->ReleaseByteArrayElements(buf, bytes, JNI_ABORT);
    if (env->ExceptionCheck()) { env->ExceptionClear(); break; }
  }

  env->DeleteLocalRef(buf);
  env->DeleteLocalRef(cls);

  if (result->len == 0) { g_byte_array_free(result, TRUE); return nullptr; }
  *out_size = result->len;
  uint8_t* data = static_cast<uint8_t*>(g_byte_array_free(result, FALSE));
  return data;
}

extern "C" JNIEXPORT jobject JNICALL Java_ca_mpreg_imagedecoder_ImageDecoder_new(JNIEnv* env, jclass, jobject jstream) {
  if (env == nullptr || jstream == nullptr) {
    throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Null image stream");
    return nullptr;
  }
  Decoder* decoder = decoder_new();
  if (decoder == nullptr) {
    throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Out of memory");
    return nullptr;
  }
  decoder->buffer = read_all(env, jstream, &decoder->buffer_size);
  if (env->ExceptionCheck()) {
    decoder_free(decoder);
    return nullptr;
  }
  if (decoder->buffer_size == 0 || decoder->buffer == nullptr) {
    decoder_free(decoder);
    if (env->ExceptionCheck()) env->ExceptionClear();
    throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Empty or unreadable image stream");
    return nullptr;
  }

  try {
    vips::VImage image = vips::VImage::new_from_buffer(decoder->buffer, decoder->buffer_size, "");
    decoder->pages = image.get_typeof(VIPS_META_N_PAGES) != 0 ? image.get_int(VIPS_META_N_PAGES) : 1;
    if (decoder->pages < 0) decoder->pages = 1;
    if (decoder->pages > 1024) decoder->pages = 1024;
    if (decoder->pages > 0 && image.get_typeof("delay") != 0) {
      int* delays = nullptr; int n = 0;
      try { image.get_array_int("delay", &delays, &n); } catch (...) { delays = nullptr; n = 0; }
      if (n > 0 && delays != nullptr) {
        if (n > decoder->pages) n = decoder->pages;
        decoder->durations = static_cast<int*>(g_try_malloc_n(static_cast<size_t>(n), sizeof(int)));
        if (decoder->durations != nullptr) {
          memcpy(decoder->durations, delays, static_cast<size_t>(n) * sizeof(int));
          decoder->durations_count = n;
        } else {
          decoder->durations_count = 0;
        }
      }
    }
    bool is_hdr = false;
    try { is_hdr = image.interpretation() == VIPS_INTERPRETATION_scRGB; } catch (...) { is_hdr = false; }
    std::string loader_str;
    try {
      const char* loader_cstr = image.get_typeof("vips-loader") != 0 ? image.get_string("vips-loader") : "";
      loader_str = loader_cstr ? loader_cstr : "";
    } catch (...) { loader_str = ""; }
    image = vips::VImage();
    jstring jloader = env->NewStringUTF(loader_str.c_str());
    if (jloader == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); decoder_free(decoder); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to allocate loader string"); return nullptr; }
    jclass cls = findClassChecked(env, "ca/mpreg/imagedecoder/ImageDecoder");
    if (cls == nullptr) { decoder_free(decoder); env->DeleteLocalRef(jloader); if (!env->ExceptionCheck()) throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "ImageDecoder class not found"); return nullptr; }
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(JIIZLjava/lang/String;)V");
    if (ctor == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(jloader); env->DeleteLocalRef(cls); decoder_free(decoder); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "ImageDecoder constructor not found"); return nullptr; }
    jobject obj = env->NewObject(cls, ctor, reinterpret_cast<jlong>(decoder), (jint)decoder->pages, (jint)0, (jboolean)is_hdr, jloader);
    env->DeleteLocalRef(jloader);
    env->DeleteLocalRef(cls);
    if (obj == nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); decoder_free(decoder); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to create ImageDecoder"); return nullptr; }
    return obj;
  } catch (const vips::VError& e) {
    decoder_free(decoder);
    throw_vips_error(env, e);
    return nullptr;
  } catch (...) {
    decoder_free(decoder);
    throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Unknown decoder error");
    return nullptr;
  }
}

extern "C" JNIEXPORT void JNICALL Java_ca_mpreg_imagedecoder_ImageDecoder_free(JNIEnv* env, jobject obj) {
  if (env == nullptr || obj == nullptr) return;
  jlong ptr = take_ptr(env, obj);
  if (ptr == 0) return;
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);
  decoder_free(decoder);
}

extern "C" JNIEXPORT void JNICALL Java_ca_mpreg_imagedecoder_ImageDecoder_nativeFree(JNIEnv* env, jclass, jlong ptr) {
  if (env == nullptr || ptr == 0) return;
  if (env->ExceptionCheck()) env->ExceptionClear();
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);
  decoder_free(decoder);
}

extern "C" JNIEXPORT jobject JNICALL Java_ca_mpreg_imagedecoder_ImageDecoder_getInfo(JNIEnv* env, jclass, jobject jstream) {
  if (env == nullptr || jstream == nullptr) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Null image stream"); return nullptr; }
  size_t size = 0;
  uint8_t* buffer = read_all(env, jstream, &size);
  if (env->ExceptionCheck()) { if (buffer) g_free(buffer); return nullptr; }
  if (buffer == nullptr || size == 0) {
    if (buffer) g_free(buffer);
    if (!env->ExceptionCheck()) throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Empty or unreadable image stream");
    return nullptr;
  }
  try {
    vips::VImage image = vips::VImage::new_from_buffer(buffer, size, "");
    int w = 0, h = 0; try { w = image.width(); } catch (...) { w = 0; } try { h = image.height(); } catch (...) { h = 0; }
    if (w <= 0 || h <= 0 || w > kMaxDimension || h > kMaxDimension) { g_free(buffer); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Image dimensions out of range"); return nullptr; }
    int pages = 1; try { pages = image.get_typeof(VIPS_META_N_PAGES) != 0 ? image.get_int(VIPS_META_N_PAGES) : 1; } catch (...) { pages = 1; }
    if (pages < 1) pages = 1; if (pages > 1024) pages = 1024;
    bool isHdr = false; try { isHdr = image.interpretation() == VIPS_INTERPRETATION_scRGB; } catch (...) { isHdr = false; }
    int duration = 0;
    if (pages > 0 && image.get_typeof("delay") != 0) { int* delays = nullptr; int n = 0; try { image.get_array_int("delay", &delays, &n); if (n>0 && delays) duration = delays[0]; } catch (...) {} }
    std::string loaderStr; try { const char* c = image.get_typeof("vips-loader") != 0 ? image.get_string("vips-loader") : ""; loaderStr = c ? c : ""; } catch (...) { loaderStr = ""; }
    std::string norm;
    if (loaderStr.rfind("jpeg",0)==0) norm="jpeg"; else if (loaderStr.rfind("png",0)==0) norm="png"; else if (loaderStr.rfind("webp",0)==0) norm="webp"; else if (loaderStr.rfind("gif",0)==0) norm="gif"; else if (loaderStr.rfind("tiff",0)==0) norm="tiff"; else if (loaderStr.rfind("heif",0)==0) norm="heif"; else if (loaderStr.rfind("jxl",0)==0) norm="jxl"; else if (loaderStr.rfind("jp2k",0)==0) norm="jp2"; else { norm=loaderStr; const std::string a="load_buffer", b="load"; if (norm.size()>=a.size() && norm.compare(norm.size()-a.size(),a.size(),a)==0) norm.erase(norm.size()-a.size()); else if (norm.size()>=b.size() && norm.compare(norm.size()-b.size(),b.size(),b)==0) norm.erase(norm.size()-b.size()); }
    g_free(buffer);
    jstring jfmt = env->NewStringUTF(norm.c_str());
    if (jfmt==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to allocate format string"); return nullptr; }
    jclass cls = findClassChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$ImageInfo");
    if (cls==nullptr) { env->DeleteLocalRef(jfmt); if (!env->ExceptionCheck()) throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "ImageInfo class not found"); return nullptr; }
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(IIILjava/lang/String;ZI)V");
    if (ctor==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(jfmt); env->DeleteLocalRef(cls); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "ImageInfo constructor not found"); return nullptr; }
    jobject out = env->NewObject(cls, ctor, (jint)w, (jint)h, (jint)pages, jfmt, (jboolean)isHdr, (jint)duration);
    env->DeleteLocalRef(jfmt); env->DeleteLocalRef(cls);
    if (out==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to create ImageInfo"); return nullptr; }
    return out;
  } catch (const vips::VError& e) { g_free(buffer); throw_vips_error(env, e); return nullptr; } catch (...) { g_free(buffer); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Unknown getInfo error"); return nullptr; }
}

extern "C" JNIEXPORT jobject JNICALL Java_ca_mpreg_imagedecoder_ImageDecoder_decode(JNIEnv* env, jobject obj, jint page, jboolean crop, jboolean getTrim) {
  if (env==nullptr || obj==nullptr) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Null decoder"); return nullptr; }
  jlong ptr = get_ptr(env, obj);
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);
  if (decoder==nullptr || decoder->buffer==nullptr) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Decoder already closed"); return nullptr; }
  if (page < 0 || page >= decoder->pages) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Page index out of range"); return nullptr; }
  try {
    vips::VImage frame = vips::VImage::new_from_buffer(decoder->buffer, decoder->buffer_size, "", vips::VImage::option()->set("access", (crop||getTrim)?VIPS_ACCESS_RANDOM:VIPS_ACCESS_SEQUENTIAL)->set("page", (int)page));
    if (frame.interpretation()!=VIPS_INTERPRETATION_sRGB && frame.interpretation()!=VIPS_INTERPRETATION_scRGB) { try { frame = frame.colourspace(VIPS_INTERPRETATION_sRGB); } catch (...) {} }
    if (frame.bands() < 4) { try { frame = frame.bandjoin(255); } catch (...) {} }
    else if (frame.bands() > 4) { try { frame = frame.extract_band(0, vips::VImage::option()->set("n", 4)); } catch (...) {} }
    int width = 0, height = 0; try { width = frame.width(); height = frame.height(); } catch (...) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to get dimensions"); return nullptr; }
    if (width<=0 || height<=0 || width>kMaxDimension || height>kMaxDimension) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Decoded dimensions out of range"); return nullptr; }
    int duration=0; if (decoder->pages>0 && page < decoder->durations_count && decoder->durations) duration = decoder->durations[page];
    int trim_left=0, trim_top=0, trim_width=0, trim_height=0;
    if (crop || getTrim) {
      int tlw=0,ttw=0,tww=0,thw=0; int tlb=0,ttb=0,twb=0,thb=0;
      try { tlw = frame.find_trim(&ttw, &tww, &thw, vips::VImage::option()->set("line_art", true)); } catch (...) { tww=0; thw=0; }
      try { tlb = frame.find_trim(&ttb, &twb, &thb, vips::VImage::option()->set("line_art", true)->set("background", 0.0)); } catch (...) { twb=0; thb=0; }
      if (tww<=0 || thw<=0 || twb<=0 || thb<=0) { trim_left=0; trim_top=0; trim_width=width; trim_height=height; }
      else { trim_left = std::max(tlw, tlb); trim_top = std::max(ttw, ttb); trim_width = std::min(tww, twb); trim_height = std::min(thw, thb); trim_width = std::max(1, std::min(trim_width, width - trim_left)); trim_height = std::max(1, std::min(trim_height, height - trim_top)); if (trim_left<0) trim_left=0; if (trim_top<0) trim_top=0; }
    }
    if (crop) {
      if (trim_width>0 && trim_height>0 && trim_left>=0 && trim_top>=0 && trim_left+trim_width<=width && trim_top+trim_height<=height && !(trim_left==0 && trim_top==0 && trim_width==width && trim_height==height)) {
        try { frame = frame.crop(trim_left, trim_top, trim_width, trim_height); width = trim_width; height = trim_height; } catch (...) {}
      }
      trim_left=0; trim_top=0; trim_width=0; trim_height=0;
    }
    size_t size = 0; try { size = VIPS_IMAGE_SIZEOF_IMAGE(frame.get_image()); } catch (...) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to compute image size"); return nullptr; }
    if (size==0 || size > static_cast<size_t>(kMaxDimension)*kMaxDimension*4) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Image size out of range"); return nullptr; }
    if (size > static_cast<size_t>(G_MAXINT)) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Image too large for ByteBuffer"); return nullptr; }
    jclass bufferCls = findClassChecked(env, "java/nio/ByteBuffer");
    if (bufferCls==nullptr) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "ByteBuffer class not found"); return nullptr; }
    jmethodID allocateDirect = env->GetStaticMethodID(bufferCls, "allocateDirect", "(I)Ljava/nio/ByteBuffer;");
    if (allocateDirect==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(bufferCls); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "allocateDirect not found"); return nullptr; }
    jobject byteBuffer = env->CallStaticObjectMethod(bufferCls, allocateDirect, (jint)size);
    env->DeleteLocalRef(bufferCls);
    if (byteBuffer==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Out of memory"); return nullptr; }
    void* data = env->GetDirectBufferAddress(byteBuffer);
    if (data==nullptr) { if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to allocate direct byte buffer"); return nullptr; }
    jlong cap = env->GetDirectBufferCapacity(byteBuffer);
    if (cap < (jlong)size) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "ByteBuffer capacity mismatch"); return nullptr; }
    try { frame.write(vips::VImage::new_from_memory(data, size, width, height, frame.bands(), frame.format())); } catch (const vips::VError& e) { throw_vips_error(env, e); return nullptr; } catch (...) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to write image bytes"); return nullptr; }
    jclass cls = findClassChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeResult");
    if (cls==nullptr) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "DecodeResult class not found"); return nullptr; }
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(Ljava/nio/ByteBuffer;IIIIIII)V");
    if (ctor==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); env->DeleteLocalRef(cls); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "DecodeResult constructor not found"); return nullptr; }
    jobject res = env->NewObject(cls, ctor, byteBuffer, width, height, duration, trim_left, trim_top, trim_width, trim_height);
    env->DeleteLocalRef(cls);
    if (res==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to create DecodeResult"); return nullptr; }
    return res;
  } catch (const vips::VError& e) { throw_vips_error(env, e); return nullptr; } catch (...) { if (!env->ExceptionCheck()) throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Unknown decode error"); return nullptr; }
}

extern "C" JNIEXPORT jobject JNICALL Java_ca_mpreg_imagedecoder_ImageDecoder_encode(JNIEnv* env, jobject obj, jstring jsuffix, jint page) {
  if (env==nullptr || obj==nullptr || jsuffix==nullptr) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Null argument"); return nullptr; }
  jlong ptr = get_ptr(env, obj);
  Decoder* decoder = reinterpret_cast<Decoder*>(ptr);
  if (decoder==nullptr || decoder->buffer==nullptr) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Decoder closed"); return nullptr; }
  if (page < -1 || page >= decoder->pages) { throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Page index out of range"); return nullptr; }
  const char* suffix = env->GetStringUTFChars(jsuffix, nullptr);
  if (suffix==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to get suffix"); return nullptr; }
  std::string suffixStr(suffix);
  try {
    vips::VImage frame = vips::VImage::new_from_buffer(decoder->buffer, decoder->buffer_size, "", vips::VImage::option()->set("page", (int)page));
    size_t size=0; void* data=nullptr;
    frame.write_to_buffer(suffixStr.c_str(), &data, &size);
    env->ReleaseStringUTFChars(jsuffix, suffix);
    if (data==nullptr || size==0) { if (data) g_free(data); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Encode produced empty buffer"); return nullptr; }
    if (size > static_cast<size_t>(G_MAXINT)) { g_free(data); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Encoded size too large"); return nullptr; }
    jobject byteBuffer = env->NewDirectByteBuffer(data, (jlong)size);
    if (byteBuffer==nullptr || env->ExceptionCheck()) { g_free(data); if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to allocate direct byte buffer"); return nullptr; }
    jclass cls = findClassChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$EncodeResult");
    if (cls==nullptr) { g_free(data); env->DeleteLocalRef(byteBuffer); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "EncodeResult class not found"); return nullptr; }
    jmethodID ctor = env->GetMethodID(cls, "<init>", "(JLjava/nio/ByteBuffer;)V");
    if (ctor==nullptr || env->ExceptionCheck()) { if (env->ExceptionCheck()) env->ExceptionClear(); g_free(data); env->DeleteLocalRef(byteBuffer); env->DeleteLocalRef(cls); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "EncodeResult constructor not found"); return nullptr; }
    jobject res = env->NewObject(cls, ctor, (jlong)(intptr_t)data, byteBuffer);
    env->DeleteLocalRef(cls);
    if (res==nullptr || env->ExceptionCheck()) { g_free(data); if (env->ExceptionCheck()) env->ExceptionClear(); throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Failed to create EncodeResult"); return nullptr; }
    return res;
  } catch (const vips::VError& e) { env->ReleaseStringUTFChars(jsuffix, suffix); throw_vips_error(env, e); return nullptr; } catch (...) { env->ReleaseStringUTFChars(jsuffix, suffix); if (!env->ExceptionCheck()) throwNewChecked(env, "ca/mpreg/imagedecoder/ImageDecoder$DecodeException", "Unknown encode error"); return nullptr; }
}

extern "C" JNIEXPORT void JNICALL Java_ca_mpreg_imagedecoder_ImageDecoder_00024EncodeResult_free(JNIEnv* env, jobject obj) {
  if (env==nullptr || obj==nullptr) return;
  jlong ptr = take_ptr(env, obj);
  if (ptr==0) return;
  g_free((void*)(intptr_t)ptr);
}
