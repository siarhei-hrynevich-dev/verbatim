# Third-Party Notices

Verbatim is released under the [MIT License](LICENSE). It is built with the open-source packages below, which are compiled and statically linked into the app. This file reproduces their copyright notices, license texts and NOTICE files. Binary releases of Verbatim ship a copy of this file.

Versions are those pinned in [`Package.resolved`](Verbatim.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved). Update this file whenever a package is added, removed or updated.

No AI model weights are included in the source code or in release binaries. Models are downloaded from the Hugging Face Hub only when the user asks for them in Settings; their licenses are listed in [AI models](#ai-models).

## Packages

"Linked" means the package has code compiled into the Verbatim app. "Resolved only" means Swift Package Manager resolves the package as a dependency of another package, but no part of it is built into the app on macOS (for example, a package used only by a command-line tool or by other platforms).

| Package | Version | License | Copyright | In the app |
| --- | --- | --- | --- | --- |
| [argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) | 1.1.1 | MIT; parts derived from swift-transformers under Apache-2.0 | Copyright (c) 2024 argmax, inc. | Linked |
| [EventSource](https://github.com/mattt/EventSource) | 1.6.0 | MIT | Copyright 2025 Mattt (https://mat.tt) | Linked |
| [mlx-swift](https://github.com/ml-explore/mlx-swift) | 0.31.4 | MIT | Copyright (c) 2023 ml-explore | Linked |
| [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) | 3.31.4 | MIT | Copyright (c) 2024 ml-explore | Linked |
| [SQLiteVecKit](https://github.com/carlosypunto/SQLiteVecKit) | 0.1.1 | MIT | Copyright (c) 2026 Carlos García | Linked |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.8.2 | Apache-2.0 with Runtime Library Exception | Copyright (c) 2020 Apple Inc. and the Swift project authors | Resolved only |
| [swift-asn1](https://github.com/apple/swift-asn1) | 1.7.4 | Apache-2.0 | Copyright 2022 The SwiftASN1 Project; Copyright (c) Apple Inc. and the SwiftASN1 project authors | Resolved only |
| [swift-collections](https://github.com/apple/swift-collections) | 1.7.5 | Apache-2.0 with Runtime Library Exception | Copyright (c) 2021 - 2026 Apple Inc. and the Swift project authors | Linked |
| [swift-crypto](https://github.com/apple/swift-crypto) | 4.5.2 | Apache-2.0 | Copyright 2019 The SwiftCrypto Project; Copyright (c) Apple Inc. and the SwiftCrypto project authors | Linked (on macOS it wraps Apple CryptoKit; its vendored BoringSSL is not built) |
| [swift-huggingface](https://github.com/huggingface/swift-huggingface) | 1.0.0 | Apache-2.0 | Copyright 2025 Hugging Face SAS. | Linked |
| [swift-jinja](https://github.com/huggingface/swift-jinja) | 3.0.0 | Apache-2.0 | Copyright 2022 Hugging Face SAS. | Linked |
| [swift-numerics](https://github.com/apple/swift-numerics) | 1.1.1 | Apache-2.0 with Runtime Library Exception | Copyright (c) 2019-2025 Apple Inc. and the Swift Numerics project authors | Linked |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | 603.0.2 | Apache-2.0 with Runtime Library Exception | Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors | Resolved only |
| [swift-transformers](https://github.com/huggingface/swift-transformers) | 1.4.0 | Apache-2.0 | Copyright 2022 Hugging Face SAS. | Linked |
| [yyjson](https://github.com/ibireme/yyjson) | 0.13.0 | MIT | Copyright (c) 2020 YaoYuan <ibireme@gmail.com> | Linked |

### Code vendored inside these packages

| Component | Included in | Version | License | Copyright |
| --- | --- | --- | --- | --- |
| [MLX](https://github.com/ml-explore/mlx) | mlx-swift | submodule of mlx-swift 0.31.4 | MIT | Copyright © 2023 Apple Inc. |
| [MLX C](https://github.com/ml-explore/mlx-c) | mlx-swift | submodule of mlx-swift 0.31.4 | MIT | Copyright (c) 2023 ml-explore |
| [metal-cpp](https://developer.apple.com/metal/cpp/) | mlx-swift | as vendored in mlx-swift 0.31.4 | Apache-2.0 | Copyright © 2024 Apple Inc. |
| [{fmt}](https://github.com/fmtlib/fmt) | mlx-swift | as vendored in mlx-swift 0.31.4 | MIT | Copyright (c) 2012 - present, Victor Zverovich and {fmt} contributors |
| [JSON for Modern C++](https://github.com/nlohmann/json) | mlx-swift | as vendored in mlx-swift 0.31.4 | MIT | Copyright (c) 2013-2022 Niels Lohmann |
| [sqlite-vec](https://github.com/asg017/sqlite-vec) | SQLiteVecKit | 0.1.9 | MIT OR Apache-2.0 (used here under MIT) | Copyright (c) 2024 Alex Garcia |

### System libraries

Verbatim links the SQLite library (`libsqlite3`) and Apple frameworks (ScreenCaptureKit, AVFoundation, AVKit, CoreML, Accelerate, AppKit, SwiftUI and others) that are part of macOS. They are not bundled with the app.

## NOTICE files

Apache-2.0 section 4(d) requires a readable copy of the attribution notices in a package's NOTICE file to be distributed with derivative works. The NOTICE files present in the packages above are reproduced here in full.

### swift-crypto (NOTICE.txt)

```text
                            The SwiftCrypto Project
                            =======================

Please visit the SwiftCrypto web site for more information:

  * https://github.com/apple/swift-crypto

Copyright 2019 The SwiftCrypto Project

The SwiftCrypto Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

Also, please refer to each LICENSE.<component>.txt file, which is located in
the 'license' directory of the distribution file, for the license terms of the
components that this product depends on.

-------------------------------------------------------------------------------

This product contains test vectors from Google's wycheproof project.

  * LICENSE (Apache License 2.0):
    * https://github.com/C2SP/wycheproof/blob/31387e2cd596587c859c611027b6a44d2e2b65ff/LICENSE
  * HOMEPAGE:
    * https://github.com/google/wycheproof

---

This product contains a derivation of various files from SwiftNIO.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-nio
```

### swift-asn1 (NOTICE.txt)

```text
                            The SwiftASN1 Project
                            =====================

Please visit the SwiftASN1 web site for more information:

  * https://github.com/apple/swift-asn1

Copyright 2022 The SwiftASN1 Project

The SwiftASN1 Project licenses this file to you under the Apache License,
version 2.0 (the "License"); you may not use this file except in compliance
with the License. You may obtain a copy of the License at:

  https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
License for the specific language governing permissions and limitations
under the License.

Also, please refer to each LICENSE.txt file, which is located in
the 'license' directory of the distribution file, for the license terms of the
components that this product depends on.

---

This product contains derivations of various scripts from SwiftNIO.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-nio

---

This product contains derivations of various scripts from Swift OpenAPI Generator.

  * LICENSE (Apache License 2.0):
    * https://www.apache.org/licenses/LICENSE-2.0
  * HOMEPAGE:
    * https://github.com/apple/swift-openapi-generator
```

### argmax-oss-swift (NOTICES)

The attribution part of the file is reproduced below. The file continues with the full Apache License 2.0 text, reproduced once in [Apache License 2.0](#apache-license-20).

```text
This file lists third-party software incorporated into Argmax OSS and the
license terms under which that software is distributed. Argmax OSS itself is
released under the MIT License (see LICENSE in the repository root).

================================================================================
swift-transformers
================================================================================

Portions of Argmax OSS (under Sources/ArgmaxCore/External) are derived from the
swift-transformers project:

  https://github.com/huggingface/swift-transformers

Copyright 2022 Hugging Face SAS.

These files have been modified by Argmax, Inc. Modifications are marked in the
source with "Argmax-modification:" comments, and each derived file retains its
original copyright notice in the file header.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use
these files except in compliance with the License. You may obtain a copy of the
License at:

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed
under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
CONDITIONS OF ANY KIND, either express or implied. See the License for the
specific language governing permissions and limitations under the License.

The full text of the Apache License, Version 2.0 follows.
```

### SQLiteVecKit (NOTICE and THIRD-PARTY-NOTICES.md)

SQLiteVecKit is MIT-licensed; its notice files are reproduced because they record the sqlite-vec attribution.

```text
SQLiteVecKit
Copyright (c) 2026 Carlos García
https://github.com/carlosypunto/SQLiteVecKit

Third-party notices -- including sqlite-vec's copyright, version, and dual
MIT/Apache-2.0 licensing -- are documented in THIRD-PARTY-NOTICES.md.
```

```text
# Third-Party Notices

SQLiteVecKit bundles third-party source code. Their licenses and copyright
notices are reproduced below and alongside the vendored files.

## sqlite-vec

- Upstream: https://github.com/asg017/sqlite-vec
- Vendored version: **v0.1.9** (pinned in `scripts/vendor-sqlite-vec.sh`)
- Files: `Sources/CSQLiteVec/sqlite-vec.c`, `Sources/CSQLiteVec/sqlite-vec.h`
- Modifications: **none** — the amalgamation is vendored verbatim.
- Copyright (c) 2024 Alex Garcia
- Licensed under **MIT OR Apache-2.0**. Full texts:
  `Sources/CSQLiteVec/LICENSE-MIT` and
  `Sources/CSQLiteVec/LICENSE-APACHE`.
- Integrity: SHA-256 checksums for `sqlite-vec.c`/`sqlite-vec.h` are locked in
  `Sources/CSQLiteVec/checksums.lock` and verified by
  `scripts/vendor-sqlite-vec.sh verify`, which runs in CI on every push/PR
  (`.github/workflows/vendor-check.yml`) and can optionally run as a local
  `pre-push` hook (`.githooks/pre-push`).
```

## License texts

### MIT License

The following text applies to each package and component listed above as MIT, with the copyright line given for it in the tables above in place of `<copyright>`.

```text
MIT License

<copyright>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### Apache License 2.0

The following text applies to each package and component listed above as Apache-2.0.

```text
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS
```

### Runtime Library Exception

swift-argument-parser, swift-collections, swift-numerics and swift-syntax add this exception to the Apache License 2.0:

```text
As an exception, if you use this Software to compile your source code and
    portions of this Software are embedded into the binary product as a result,
    you may redistribute such product without providing attribution as would
    otherwise be required by Sections 4(a), 4(b) and 4(d) of the License.
```

## AI models

Verbatim does not include or distribute model weights. When the user chooses to download a model in Settings, the app fetches it directly from the Hugging Face Hub, and the user receives it under the model's own license. Check each license before using a model, especially for commercial use. The catalog lives in [`SpeechModel.swift`](Verbatim/Models/SpeechModel.swift), [`LanguageModel.swift`](Verbatim/Models/LanguageModel.swift) and [`EmbeddingModel.swift`](Verbatim/Models/EmbeddingModel.swift).

| Purpose | Models in the catalog | Downloaded from | License |
| --- | --- | --- | --- |
| Transcription | Whisper Tiny, Base, Small, Large v3 Turbo (Core ML) | [argmaxinc/whisperkit-coreml](https://huggingface.co/argmaxinc/whisperkit-coreml) | MIT |
| Transcription (tokenizers) | Whisper tokenizer files | [openai/whisper-tiny](https://huggingface.co/openai/whisper-tiny), [openai/whisper-base](https://huggingface.co/openai/whisper-base), [openai/whisper-small](https://huggingface.co/openai/whisper-small), [openai/whisper-large-v3](https://huggingface.co/openai/whisper-large-v3) | Apache-2.0 as declared on these Hugging Face repositories; OpenAI publishes the original Whisper code and weights under [MIT](https://github.com/openai/whisper/blob/main/LICENSE) |
| Summaries | Qwen3 1.7B (4-bit MLX) | [mlx-community/Qwen3-1.7B-4bit](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit), converted from [Qwen/Qwen3-1.7B](https://huggingface.co/Qwen/Qwen3-1.7B) | Apache-2.0 |
| Summaries | Qwen3 4B Instruct 2507 (4-bit MLX) | [mlx-community/Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit), converted from [Qwen/Qwen3-4B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507) | Apache-2.0 |
| Summaries | Qwen3 30B-A3B Instruct 2507 (4-bit MLX) | [mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-30B-A3B-Instruct-2507-4bit), converted from [Qwen/Qwen3-30B-A3B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-30B-A3B-Instruct-2507) | Apache-2.0 |
| Semantic search | Multilingual E5 Small | [intfloat/multilingual-e5-small](https://huggingface.co/intfloat/multilingual-e5-small) | MIT |
| Semantic search | Multilingual E5 Base | [intfloat/multilingual-e5-base](https://huggingface.co/intfloat/multilingual-e5-base) | MIT |

Licenses are as declared by each repository's model card when this file was written. The model owners can change them; the model card at the pinned revision is authoritative.
