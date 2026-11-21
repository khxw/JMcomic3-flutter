# NCNN Android runtime

The bundled NCNN headers and libraries come from the official
`ncnn-20261020-android-shared.zip` release:

- release: https://github.com/Tencent/ncnn/releases/tag/20261020
- archive SHA-256:
  `c2f866782cb6b8337bcd062f12b0da1b75e703f4e90fc7905d00c7c74d669a87`

Bundled libraries:

| ABI | SHA-256 |
| --- | --- |
| `arm64-v8a/libncnn.so` | `cc52e8325edf691c720c3937efc7306931dfa990572e385d425a1aef45430859` |
| `armeabi-v7a/libncnn.so` | `c2c52b5181efd0e9c18ae99853756933fa53af943bae7a055085fb14c2491998` |

The shared release has Vulkan disabled and runs on the CPU. The app links only
the JNI upscaler against it. See `LICENSE.txt` for the BSD 3-Clause license and
the third-party notices included in the official NCNN distribution.
