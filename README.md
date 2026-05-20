# lite-screen-recorder

低スペックPCでも長時間（2〜3時間）安定して録画できる、軽量なWindows画面＋音声レコーダー。FFmpegの`ddagrab`フィルタとIntel QuickSyncハードウェアエンコードで、CPU負荷を最小化しています。

> A lightweight Windows screen + system-audio recorder built for long sessions on low-spec PCs. Uses FFmpeg `ddagrab` + Intel QuickSync to keep CPU usage minimal.

## 想定用途

- Zoom・Teams・ウェビナーの長時間視聴記録
- 講義・セミナーの録画
- 画面共有のアーカイブ

> ⚠️ 録画は主催者・配信者の許諾と、各組織のポリシーに従って実施してください。

## 動作環境

- Windows 10 / 11（64bit）
- Intel CPU の内蔵グラフィック（QuickSync）推奨
- QuickSync が無い環境では CPU エンコードへフォールバック可能（`config.ini` で切替）

## クイックスタート（3ステップ）

1. このリポジトリの `Code` → `Download ZIP` でダウンロードし、任意の場所に展開
2. `setup.bat` をダブルクリック  
   → FFmpegと音声フィルタが自動でセットアップされます（UAC同意が1回必要、初回数分）
3. `start.bat` をダブルクリックで録画開始。画面で **`q` キー** を押すと停止

録画ファイルは `録画データ/zoom_日時/part_NNN.mp4` に **30分ごとに分割保存** されます。途中でPCが落ちても直前まで再生可能です。

## 設定（config.ini）

| 項目 | 既定 | 説明 |
|---|---|---|
| `preset` | 中 | `低 / 中 / 高` の3段階。低=960px・8fps、中=1280px・10fps、高=1600px・12fps |
| `encoder` | hardware | `hardware`=Intel QuickSync / `software`=CPU(libx264) |
| `segment_seconds` | 1800 | 分割秒数（既定30分） |
| `audio_gain_db` | 6 | 音量増幅(dB)。0=そのまま、6=約2倍、12=約4倍 |
| `monitor_index` | 0 | 録画するモニタ番号（マルチモニタ時） |
| `output_dir` | 録画データ | 出力先 |
| `audio_device` | virtual-audio-capturer | 通常は変更不要 |

## 複数ファイルの結合

30分ごとに分割されたmp4を1本にまとめたいときは：

```cmd
powershell -ExecutionPolicy Bypass -File scripts\merge.ps1
```

無劣化（`-c copy`）で結合します。

## 仕組み

- **画面キャプチャ**: FFmpeg `ddagrab` フィルタ（Desktop Duplication API、GPU加速）
- **ハードウェアエンコード**: `h264_qsv`（Intel QuickSync）
- **システム音声**: [screen-capture-recorder](https://github.com/rdp/screen-capture-recorder-to-video-windows-free) の `virtual-audio-capturer`（WASAPIループバック取得。再生先を変えないため録画中も普通に音が聞こえます）
- **長時間耐性**: 30分ごとのセグメント分割 ＋ フラグメントmp4で異常終了に強い構造

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| 音が小さい／大きすぎる | `config.ini` の `audio_gain_db` を増減（音割れ時は下げる） |
| CPU負荷が高い・カクつく | `preset=低` に変更 |
| QSVが使えない／エラー | `encoder=software` に変更（CPUエンコードへフォールバック） |
| 画面が録れない | `setup.bat` を再実行。フルビルドのffmpegが `ffmpeg\ffmpeg.exe` に配置されているか確認 |
| 音声デバイスが見つからない | `setup.bat` を再実行。インストール後にPC再起動を試す |

## 手動セットアップ（setup.bat が動かない場合）

1. [BtbN FFmpeg Builds](https://github.com/BtbN/FFmpeg-Builds/releases) から `ffmpeg-master-latest-win64-gpl.zip` を取得 → 解凍し、`bin\ffmpeg.exe` を本ツールの `ffmpeg\ffmpeg.exe` に配置
2. [screen-capture-recorder](https://sourceforge.net/projects/screencapturer/) のインストーラを入手して実行

## クレジット

- [FFmpeg](https://ffmpeg.org/) — 録画エンジン
- [screen-capture-recorder](https://github.com/rdp/screen-capture-recorder-to-video-windows-free) by rdp — システム音声ループバック取得

## License

[MIT License](LICENSE)
