// libFuzzer harness for LibRaw — drives the full decode pipeline
// (open_buffer -> unpack -> unpack_thumb -> raw2image -> dcraw_process)
// across every camera-vendor format LibRaw auto-detects.
//
// Unlike treating the input as a parameter-prefixed blob, the entire
// input is passed directly to open_buffer() as the raw file content, so
// hand-placed or real-sample seed files (which start with each vendor's
// real magic bytes / TIFF structure at offset 0) stay intact and usable
// without an extra encoding step. Several postprocessing/interpolation
// options are exercised with fixed values to reach more of
// dcraw_process() without adding another input-encoding layer.

#include <cstddef>
#include <cstdint>
#include <vector>

#include <libraw.h>

extern "C" int LLVMFuzzerTestOneInput(const std::uint8_t *data, std::size_t size) {
    // Matches the size ceiling used by LibRaw's own upstream fuzz target;
    // keeps individual runs bounded.
    if (size > 15000000) {
        return 0;
    }

    static const int kInterpolationOptions[] = {
        0,  // Linear
        1,  // VNG
        3,  // AHD
        11, // DHT
    };

    LibRaw lib_raw;
    lib_raw.imgdata.rawparams.max_raw_memory_mb = 300;

    int result = lib_raw.open_buffer(data, size);
    if (result != LIBRAW_SUCCESS) {
        return 0;
    }

    result = lib_raw.unpack();
    if (result != LIBRAW_SUCCESS) {
        return 0;
    }

    // Non-fatal: thumbnails are optional and many vendor formats omit them.
    lib_raw.unpack_thumb();

    result = lib_raw.raw2image();
    if (result != LIBRAW_SUCCESS) {
        return 0;
    }
    lib_raw.free_image();

    // Demosaic/interpolation cost scales with pixel count; skip
    // postprocessing for implausibly huge mutated dimensions so the
    // fuzzer's time goes toward exploring parsing logic rather than
    // waiting out legitimately-slow (but not buggy) huge-image loops.
    const auto &sizes = lib_raw.imgdata.sizes;
    const long long pixels =
        static_cast<long long>(sizes.raw_width) * static_cast<long long>(sizes.raw_height);
    if (pixels > 4000000) {
        return 0;
    }

    for (int option : kInterpolationOptions) {
        lib_raw.output_params_ptr()->user_qual = option;
        lib_raw.dcraw_process();
    }

    return 0;
}
