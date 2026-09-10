# 将棋 · Shogi Studio

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

Android・Windows 向けの無料将棋アプリです。Godot 4.7.2 と、やねうら王のローカル解析エンジンを使用します。現在のバージョンは **0.25.0**。**既存の機能はすべて無料で、会員制度・購入画面・有料解除はありません。**

![木製の将棋盤](docs/images/board-0.20.png)

## インストール

[Releases](https://github.com/DipperHide/shogi-studio/releases) から `Shogi-0.25.0-android-arm64.apk` をダウンロードしてください。ARM64 対応 Android 端末向けの完全な APK です。Windows は `Shogi-0.25.0-windows-x64.zip` を展開し、`Shogi.exe` を実行します。`engines` フォルダーは同じ場所に置いてください。

Android のパッケージ名は `org.shogistudio.artpreview`、versionCode は 43 です。release テンプレートで書き出し、上書き更新のため従来の開発用署名を継続しています。秘密鍵は含めません。異なる署名のビルドを入れる前に棋譜をバックアップしてください。

## 主な機能

- 6 段階のコンピューター、同じ端末での二人対局、エンジン同士の対局、IP 直接接続、Android Bluetooth。合法手・成り・持駒の打ち込み・禁手を確認します。
- 2D／3D 盤、明暗テーマ、配色、反転、ドラッグ、座標表示、縦横比を保つ持駒。0.20 では木製盤を明るく、幅広くしました。
- メイン画面の待った、アニメーション付き棋譜再生、解析結果、候補手順の再生、選択局面からの対局再開。
- 1～5 本の候補手順、簡易／詳細解析、推奨手順、悪手通知、推定勝率、失敗手の練習、局面段階別統計。
- 0.21 では棋士名を独立した行に表示し、勝者のトロフィー、段階の長さに応じたスコアバー、折り返す指標欄を追加しました。タッチ・キーボードで詳細を開けます。将棋用のレーティング推定は未校正のため「—」です。
- JSON・KIF・CSA・USI・SFEN の入出力、局面編集、対話型レッスン、棋譜保存、バックアップと復元。アイコンは龍王の「龍」です。
- 0.22 の評価グラフは先後の優勢領域と重要な着手のアイコンを表示します。アイコン選択、キーボード・ドラッグ操作、段階境界の位置合わせに対応します。
- 0.23 では分類統計を折りたたみ表示にし、品質グラフに重み付き割合を明記しました。説明表示、回転、キーボード選択、分類から棋譜への移動に対応します。
- 0.24 では再生位置を素早く変更しても、表示中の駒の位置・大きさ・成りの裏返しを引き継ぎます。駒取り、駒打ち、逆再生、盤の反転に対応します。
- 0.25 では入れ子の変化、二段の指し手欄、長押しによる本譜への昇格、削除の取り消し、変化ごとの注釈に対応します。本譜を残すか自動で置き換えるかを選べます。全変化の保存・出力・バックアップには JSON を使用します。

[変化の使い方](docs/VARIATIONS.md) · [0.25 の検証結果](docs/TESTING-0.25.md)（中国語）

高度な画面とレッスン本文は主に中国語です。基本ナビゲーションは中・英・日文に対応しますが、三言語 README はアプリ全体の翻訳完了を意味しません。

## 日本の大会棋譜の更新

最近の一覧には **26 局**を収録し、現在の最新は **2026 年 9 月 8～9 日の王位戦第 6 局、140 手**です。別途、過去の完全棋譜 **195 局・23,115 手**をオフラインで利用できます。

[定期更新ワークフロー](.github/workflows/update-tournaments.yml) が毎日日本時間 06:23 頃に公式中継ページを確認します。アプリは最近の大会一覧を開くと 1 日に 1 回 HTTPS 経由で確認し、「刷新」で手動更新もできます。新しい対局ごとの APK 再インストールは不要です。GitHub の実行には遅延があり、デフォルトブランチでワークフローを有効にしておく必要があります。

公開一覧には対局情報、公式リンク、指し手ハッシュのみを含めます。対局を選ぶと公式公開 KIF を取得し、UTF-8／CP932 の判別、解説の除去、ハッシュと全指し手の合法性確認を経て端末に保存します。更新に失敗しても既存データは残り、取得済み棋譜と過去棋譜はオフラインで再生できます。

公式公開状況に応じて王位・王座・棋王・棋聖・叡王・竜王戦の入口を確認します。最近の完全 KIF が取得できない大会もあり、全大会・有料棋譜・進行中の対局を網羅するものではありません。[公式棋戦一覧](https://www.shogi.or.jp/match/) と [更新の運用説明](docs/TOURNAMENT-UPDATES.md) を参照してください。

## ビルド・テスト

Windows、Python 3.11 以降、Godot **4.7.2** と対応テンプレート、JDK 17、Android SDK 36、Build Tools 36.0.0、NDK 28.1.13356709 を使用します。[toolchain.example.json](toolchain.example.json) のパスを変更して `%USERPROFILE%/Development/toolchain.json` に保存してください。

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r requirements-dev.txt
./scripts/build_android.ps1
./scripts/build_windows.ps1 -OutputDirectory builds/windows-0.25.0
./scripts/test_chessis20.ps1
./scripts/test_chessis20.ps1 -CoreOnly -Network
./scripts/test_chessis23.ps1
./scripts/test_chessis24.ps1
./scripts/test_chessis25.ps1 -CoreOnly
./scripts/test_chessis25.ps1
```

開発時は Godot で `godot/project.godot` を開きます。実行用素材、エンジン、NNUE は同梱し、対応するエンジンソースはビルド時に同梱アーカイブから展開します。release APK にはローカルで `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`、`GODOT_ANDROID_KEYSTORE_RELEASE_USER`、`GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` を設定し、`./scripts/build_android.ps1 -Release` を実行します。署名情報をコミットしないでください。

[CI](.github/workflows/ci.yml) は push・PR 時にコアテストを実行します。ローカルでは 4 種類の画面サイズ、先後反転、明暗、駒取り・成り・駒打ち、連続フレームの動き、実エンジンも確認します。[0.23 分類統計の検証](docs/TESTING-0.23.md) と [0.20 盤・大会更新の検証](docs/TESTING-0.20.md) を参照してください。バグが完全になくなる保証はできません。今回は Android 実機未接続のため、Bluetooth 二台接続やバックグラウンド復帰は実機確認が必要です。

検証用 Windows PC では、空のウィンドウでも約 450 ミリ秒の描画停止が発生し、未解決です。すべての端末で常に滑らかな動作を保証するものではありません。[0.24 アニメーション検証](docs/TESTING-0.24.md) を参照してください。

## データ・クレジット

保存先は従来の `ShogiStudio` ユーザーディレクトリです。Android ではアプリ専用領域を使い、大会棋譜は `user://tournaments/` に保存します。更新時に個人の対局を送信しません。

独立した将棋 UI 適応プロジェクトであり、Chessis、日本将棋連盟、各大会主催者とは関係がありません。元アプリの全機能・全画面の再現をうたうものではありません。[既知の差異](docs/CHESSIS-PARITY.md) を参照してください。やねうら王は対応する GPL ソースを同梱し、菱湖書体、フォント、評価関数、参考 UI にはそれぞれの条件を適用します。MIT として再許諾していません。[第三者素材の説明](THIRD_PARTY_NOTICES.md) を参照してください。
