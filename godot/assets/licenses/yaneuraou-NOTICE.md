# YaneuraOu and Suisho5

The game communicates with YaneuraOu as a separate process using USI.

Engine: YaneuraOu NNUE V9.00 Git, standard halfKP256 architecture.
Upstream: https://github.com/yaneurao/YaneuraOu
Release: https://github.com/yaneurao/YaneuraOu/releases/tag/V9.00
License: GNU GPL version 3 or later; see LICENSE.txt and source file headers.

The official Windows release archive is `yaneuraou-V900-git-win64-all.7z`.
Its published SHA-256 is
`6517997dd05ba049a2244a828216967a0ad351d975ec52a0f358e2883197dec6`.
The Windows executable uses the halfKP256 SSE4.2 tournament build.
The `source` folder bundled with that release is preserved in the accompanying
source archive. Android builds compile that same source without changing its
contents; the full compiler invocation is in `build_engine_android.py`.

Evaluation model: Suisho5, supplied by Tayayan (たややん).
Download: https://github.com/yaneurao/YaneuraOu/releases/tag/suisho5
Architecture: standard NNUE halfKP256. FV_SCALE is set to 24 as upstream directs.
The model archive contains only `nn.bin`, with no separate license file.
Its provenance is retained separately from the GPL license of the engine.
The upstream announcement describes publication in consultation with the author
and use with YaneuraOu or a custom search engine:
https://yaneuraou.yaneu.com/2024/06/23/suisho10-beta/
No MIT, CC0, or other model license is asserted by this project.

Source package: `assets/licenses/yaneuraou-source.zip` inside Android builds,
and `engines/yaneuraou/source` plus the build scripts in Windows distributions.
The source archive also includes the Windows process host, build scripts and
this notice. Source and binaries must stay together when distributing a build.
