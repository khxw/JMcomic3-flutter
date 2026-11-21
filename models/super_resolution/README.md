# Super-resolution model packages

The app reads `manifest.json` from `main`, downloads the selected archive only
when the user asks for it, verifies its SHA-256, and installs it outside the
APK. The same manifest is bundled so model information remains visible when
GitHub is temporarily unreachable.

Current package:

- `waifu2x-cunet-2x` version `20250915`
- waifu2x CUnet 2×, noise level 0
- source: https://github.com/nihui/waifu2x-ncnn-vulkan
- model license: MIT

Every model entry includes its ID, version, scale, HTTPS download URLs, exact
archive size and SHA-256, maximum extracted size, and license information.
Archives are checked for path traversal, symbolic links, extraction size,
checksum and the required NCNN model files before installation.

See `WAIFU2X-CUNET-2X.md` for the upstream files and checksums.
