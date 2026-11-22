#include <jni.h>

#include <algorithm>
#include <android/bitmap.h>
#include <android/log.h>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "ncnn/gpu.h"
#include "ncnn/net.h"

namespace {

constexpr int kPrePadding = 18;
constexpr char kLogTag[] = "SuperResolution";
constexpr int kBackendAuto = 0;
constexpr int kBackendGpu = 1;
constexpr int kBackendCpu = 2;

struct BackendState {
    ncnn::Net net;
    std::mutex mutex;
    std::string param_path;
    std::string weights_path;
};

BackendState g_cpu_backend;
BackendState g_gpu_backend;
std::once_flag g_vulkan_init_once;
bool g_vulkan_available = false;
std::string g_vulkan_device_name;
ncnn::VulkanDevice* g_vulkan_device = nullptr;

std::string to_string(JNIEnv* env, jstring value)
{
    if (!value)
        return {};
    const char* chars = env->GetStringUTFChars(value, nullptr);
    if (!chars)
        return {};
    std::string result(chars);
    env->ReleaseStringUTFChars(value, chars);
    return result;
}

void initialize_vulkan()
{
#if NCNN_VULKAN
    const int init_result = ncnn::create_gpu_instance();
    if (init_result != 0) {
        __android_log_print(
            ANDROID_LOG_WARN,
            kLogTag,
            "Vulkan initialization failed: %d",
            init_result);
        return;
    }
    if (ncnn::get_gpu_count() <= 0) {
        __android_log_write(
            ANDROID_LOG_WARN,
            kLogTag,
            "Vulkan initialized without a usable GPU");
        return;
    }
    const int device_index = std::max(0, ncnn::get_default_gpu_index());
    g_vulkan_device = ncnn::get_gpu_device(device_index);
    if (!g_vulkan_device) {
        __android_log_write(
            ANDROID_LOG_WARN,
            kLogTag,
            "Unable to acquire the default Vulkan device");
        return;
    }
    const char* device_name = g_vulkan_device->info.device_name();
    g_vulkan_device_name = device_name ? device_name : "";
    g_vulkan_available = true;
#else
    __android_log_write(
        ANDROID_LOG_WARN,
        kLogTag,
        "NCNN was built without Vulkan support");
#endif
}

void ensure_vulkan_initialized()
{
    std::call_once(g_vulkan_init_once, initialize_vulkan);
}

bool load_model(
    BackendState& backend,
    bool use_vulkan,
    const std::string& param_path,
    const std::string& weights_path,
    int threads)
{
    if (use_vulkan) {
        ensure_vulkan_initialized();
        if (!g_vulkan_available || !g_vulkan_device)
            return false;
    }
    if (backend.param_path == param_path &&
        backend.weights_path == weights_path) {
        backend.net.opt.num_threads = std::max(1, threads);
        return true;
    }

    backend.net.clear();
    backend.param_path.clear();
    backend.weights_path.clear();
    backend.net.opt.use_vulkan_compute = use_vulkan;
    backend.net.opt.use_fp16_packed = true;
    backend.net.opt.use_fp16_storage = true;
    backend.net.opt.use_fp16_arithmetic = false;
    backend.net.opt.use_int8_storage = true;
    backend.net.opt.num_threads = std::max(1, threads);
    if (use_vulkan)
        backend.net.set_vulkan_device(g_vulkan_device);

    if (backend.net.load_param(param_path.c_str()) != 0) {
        backend.net.clear();
        return false;
    }
    if (backend.net.load_model(weights_path.c_str()) != 0) {
        backend.net.clear();
        return false;
    }
    backend.param_path = param_path;
    backend.weights_path = weights_path;
    return true;
}

void copy_replicated_border(
    const ncnn::Mat& source,
    ncnn::Mat& destination,
    int top,
    int bottom,
    int left,
    int right,
    const ncnn::Option& opt)
{
    ncnn::copy_make_border(
        source,
        destination,
        top,
        bottom,
        left,
        right,
        ncnn::BORDER_REPLICATE,
        0.f,
        opt);
}

bool process_bitmap(
    ncnn::Net& net,
    const uint8_t* input,
    uint8_t* output,
    int width,
    int height,
    int input_stride,
    int output_stride,
    int tile_size)
{
    const int output_width = width * 2;
    const int x_tiles = (width + tile_size - 1) / tile_size;
    const int y_tiles = (height + tile_size - 1) / tile_size;

    for (int tile_y = 0; tile_y < y_tiles; ++tile_y) {
        const int output_y0 = tile_y * tile_size;
        const int output_h =
            std::min((tile_y + 1) * tile_size, height) - output_y0;
        int bottom_padding = kPrePadding + (output_h + 1) / 2 * 2 - output_h;
        const int input_y0 = std::max(output_y0 - kPrePadding, 0);
        const int input_y1 =
            std::min((tile_y + 1) * tile_size + bottom_padding, height);

        for (int tile_x = 0; tile_x < x_tiles; ++tile_x) {
            const int output_x0 = tile_x * tile_size;
            const int output_w =
                std::min((tile_x + 1) * tile_size, width) - output_x0;
            int right_padding =
                kPrePadding + (output_w + 1) / 2 * 2 - output_w;
            const int input_x0 = std::max(output_x0 - kPrePadding, 0);
            const int input_x1 =
                std::min((tile_x + 1) * tile_size + right_padding, width);

            const int input_w = input_x1 - input_x0;
            const int input_h = input_y1 - input_y0;
            const uint8_t* tile_pixels =
                input +
                static_cast<size_t>(input_y0) * input_stride + input_x0 * 4;
            ncnn::Mat source = ncnn::Mat::from_pixels(
                tile_pixels,
                ncnn::Mat::PIXEL_RGBA2RGB,
                input_w,
                input_h,
                input_stride);

            const int top = std::max(kPrePadding - output_y0, 0);
            const int bottom = std::max(
                std::min(
                    (tile_y + 1) * tile_size + bottom_padding - height,
                    bottom_padding),
                0);
            const int left = std::max(kPrePadding - output_x0, 0);
            const int right = std::max(
                std::min(
                    (tile_x + 1) * tile_size + right_padding - width,
                    right_padding),
                0);

            ncnn::Mat padded;
            copy_replicated_border(
                source,
                padded,
                top,
                bottom,
                left,
                right,
                net.opt);

            ncnn::Extractor extractor = net.create_extractor();
            if (extractor.input("Input1", padded) != 0)
                return false;

            ncnn::Mat result;
            if (extractor.extract("Eltwise4", result) != 0)
                return false;

            const int destination_x = output_x0 * 2;
            const int destination_y = output_y0 * 2;
            const int destination_w = output_w * 2;
            const int destination_h = output_h * 2;
            if (result.w < destination_w || result.h < destination_h)
                return false;

            std::vector<uint8_t> rgba(
                static_cast<size_t>(result.w) * result.h * 4);
            result.to_pixels(
                rgba.data(),
                ncnn::Mat::PIXEL_RGB2RGBA,
                result.w * 4);
            for (int y = 0; y < destination_h; ++y) {
                const uint8_t* source_row =
                    rgba.data() + static_cast<size_t>(y) * result.w * 4;
                uint8_t* destination_row =
                    output +
                    static_cast<size_t>(destination_y + y) * output_stride +
                    destination_x * 4;
                std::memcpy(
                    destination_row,
                    source_row,
                    static_cast<size_t>(destination_w) * 4);
            }
        }
    }
    return output_width > 0;
}

bool run_backend(
    BackendState& backend,
    bool use_vulkan,
    const uint8_t* input,
    uint8_t* output,
    int width,
    int height,
    int input_stride,
    int output_stride,
    const std::string& param_path,
    const std::string& weights_path,
    int threads,
    int tile_size)
{
    std::lock_guard<std::mutex> lock(backend.mutex);
    if (!load_model(
            backend,
            use_vulkan,
            param_path,
            weights_path,
            threads)) {
        return false;
    }
    return process_bitmap(
        backend.net,
        input,
        output,
        width,
        height,
        input_stride,
        output_stride,
        tile_size);
}

}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_jmcomic3_yee_SuperResolutionBridge_nativeIsVulkanAvailable(
    JNIEnv*,
    jobject)
{
    ensure_vulkan_initialized();
    return g_vulkan_available ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_jmcomic3_yee_SuperResolutionBridge_nativeVulkanDeviceName(
    JNIEnv* env,
    jobject)
{
    ensure_vulkan_initialized();
    return env->NewStringUTF(g_vulkan_device_name.c_str());
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_jmcomic3_yee_SuperResolutionBridge_nativeUpscale(
    JNIEnv* env,
    jobject,
    jobject input_bitmap,
    jobject output_bitmap,
    jstring param_path,
    jstring weights_path,
    jint threads,
    jint tile_size,
    jint backend_preference)
{
    AndroidBitmapInfo input_info{};
    AndroidBitmapInfo output_info{};
    if (AndroidBitmap_getInfo(env, input_bitmap, &input_info) !=
            ANDROID_BITMAP_RESULT_SUCCESS ||
        AndroidBitmap_getInfo(env, output_bitmap, &output_info) !=
            ANDROID_BITMAP_RESULT_SUCCESS) {
        return JNI_FALSE;
    }
    if (input_info.format != ANDROID_BITMAP_FORMAT_RGBA_8888 ||
        output_info.format != ANDROID_BITMAP_FORMAT_RGBA_8888 ||
        output_info.width != input_info.width * 2 ||
        output_info.height != input_info.height * 2) {
        return JNI_FALSE;
    }

    void* input_pixels = nullptr;
    void* output_pixels = nullptr;
    if (AndroidBitmap_lockPixels(env, input_bitmap, &input_pixels) !=
        ANDROID_BITMAP_RESULT_SUCCESS) {
        return JNI_FALSE;
    }
    if (AndroidBitmap_lockPixels(env, output_bitmap, &output_pixels) !=
        ANDROID_BITMAP_RESULT_SUCCESS) {
        AndroidBitmap_unlockPixels(env, input_bitmap);
        return JNI_FALSE;
    }

    if (backend_preference != kBackendCpu)
        ensure_vulkan_initialized();

    const std::string resolved_param_path = to_string(env, param_path);
    const std::string resolved_weights_path = to_string(env, weights_path);
    const int resolved_tile_size =
        std::max(64, std::min(512, static_cast<int>(tile_size)));
    const bool try_gpu =
        backend_preference == kBackendGpu ||
        (backend_preference == kBackendAuto && g_vulkan_available);
    bool success = false;

    if (try_gpu) {
        success = run_backend(
            g_gpu_backend,
            true,
            static_cast<const uint8_t*>(input_pixels),
            static_cast<uint8_t*>(output_pixels),
            static_cast<int>(input_info.width),
            static_cast<int>(input_info.height),
            static_cast<int>(input_info.stride),
            static_cast<int>(output_info.stride),
            resolved_param_path,
            resolved_weights_path,
            threads,
            resolved_tile_size);
        if (success) {
            __android_log_write(
                ANDROID_LOG_INFO,
                kLogTag,
                "Inference completed on Vulkan");
        } else if (backend_preference == kBackendGpu) {
            __android_log_write(
                ANDROID_LOG_WARN,
                kLogTag,
                "GPU-only inference failed");
        } else {
            __android_log_write(
                ANDROID_LOG_WARN,
                kLogTag,
                "Automatic mode is falling back to CPU");
        }
    }

    if (!success && backend_preference != kBackendGpu) {
        success = run_backend(
            g_cpu_backend,
            false,
            static_cast<const uint8_t*>(input_pixels),
            static_cast<uint8_t*>(output_pixels),
            static_cast<int>(input_info.width),
            static_cast<int>(input_info.height),
            static_cast<int>(input_info.stride),
            static_cast<int>(output_info.stride),
            resolved_param_path,
            resolved_weights_path,
            threads,
            resolved_tile_size);
        if (success) {
            __android_log_write(
                ANDROID_LOG_INFO,
                kLogTag,
                "Inference completed on CPU");
        }
    }

    AndroidBitmap_unlockPixels(env, output_bitmap);
    AndroidBitmap_unlockPixels(env, input_bitmap);
    return success ? JNI_TRUE : JNI_FALSE;
}
