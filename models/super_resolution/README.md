# Super-resolution model packages

The app reads `manifest.json` from `main`, downloads the selected archive only
when the user asks for it, verifies its SHA-256, and installs it outside the
APK. The same manifest is bundled so model information remains visible when
GitHub is temporarily unreachable.

Current package:

- `realcugan-pro-2x-conservative` version `20261122`
- Real-CUGAN Pro 2× conservative
- source: https://github.com/nihui/realcugan-ncnn-vulkan
- model license: MIT

Every model entry includes its ID, version, scale, HTTPS download URLs, exact
archive size and SHA-256, maximum extracted size, and license information.
Archives are checked for path traversal, symbolic links, extraction size,
checksum and the required NCNN model files before installation.

See `REAL-CUGAN-2X-CONSERVATIVE.md` for the upstream files and checksums.
