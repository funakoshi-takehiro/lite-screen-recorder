# =====================================================================
#  Zoom長時間録画ツール  -  本体スクリプト
#  画面(ddagrab)＋システム音声(virtual-audio-capturer)を低負荷で録画
# =====================================================================

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# --- パス解決 -------------------------------------------------------
$Root      = Split-Path $PSScriptRoot -Parent
$FfmpegExe = Join-Path $Root 'ffmpeg\ffmpeg.exe'
$ConfigIni = Join-Path $Root 'config.ini'
$SetupTxt  = Join-Path $Root 'セットアップ手順.txt'

function Show-And-Pause([string]$msg) {
    Write-Host ''
    Write-Host $msg -ForegroundColor Yellow
    Write-Host ''
    Write-Host '何かキーを押すと終了します...'
    [void][Console]::ReadKey($true)
}

# --- ffmpeg.exe 確認 -----------------------------------------------
if (-not (Test-Path $FfmpegExe)) {
    Show-And-Pause "ffmpeg.exe が見つかりません。`n`n  $FfmpegExe `n`n初回は『setup.bat』をダブルクリックして自動セットアップしてください。"
    exit 1
}

# --- config.ini 読み込み (簡易INIパーサ) ----------------------------
if (-not (Test-Path $ConfigIni)) { Show-And-Pause "config.ini が見つかりません: $ConfigIni"; exit 1 }

$cfg = @{}; $presets = @{}; $section = ''
foreach ($line in Get-Content -LiteralPath $ConfigIni -Encoding UTF8) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    if ($t -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
    if ($t -match '^\s*([^=]+?)\s*=\s*(.*)$') {
        $k = $Matches[1].Trim(); $v = $Matches[2].Trim()
        if ($section -eq 'presets') { $presets[$k] = $v } else { $cfg[$k] = $v }
    }
}

$presetName = if ($cfg.preset)          { $cfg.preset }          else { '中' }
$encoder    = if ($cfg.encoder)         { $cfg.encoder }         else { 'hardware' }
$segSec     = if ($cfg.segment_seconds) { [int]$cfg.segment_seconds } else { 1800 }
$outDirCfg  = if ($cfg.output_dir)      { $cfg.output_dir }      else { '録画データ' }
$audioDev   = if ($cfg.audio_device)    { $cfg.audio_device }    else { 'virtual-audio-capturer' }
$monIdx     = if ($cfg.monitor_index)   { [int]$cfg.monitor_index } else { 0 }
$audioGain  = if ($cfg.audio_gain_db)   { $cfg.audio_gain_db }    else { '6' }

if (-not $presets.ContainsKey($presetName)) {
    Show-And-Pause "config.ini の preset=$presetName が [presets] に定義されていません。"
    exit 1
}
$parts = $presets[$presetName].Split(',')
$W   = $parts[0].Trim()
$FPS = $parts[1].Trim()
$Q   = $parts[2].Trim()

# --- 出力先フォルダ (セッションごと) --------------------------------
if ([System.IO.Path]::IsPathRooted($outDirCfg)) { $outBase = $outDirCfg }
else { $outBase = Join-Path $Root $outDirCfg }
$stamp      = Get-Date -Format 'yyyyMMdd_HHmmss'
$sessionDir = Join-Path $outBase ("zoom_$stamp")
New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
$outPattern = Join-Path $sessionDir 'part_%03d.mp4'

# --- ディスク空き容量チェック --------------------------------------
try {
    $drive   = (Get-Item $outBase).PSDrive.Name
    $freeGB  = [math]::Round((Get-PSDrive $drive).Free / 1GB, 1)
    Write-Host ("空きディスク容量: {0} GB ({1}:)" -f $freeGB, $drive)
    if ($freeGB -lt 5) {
        Write-Host '警告: 空き容量が5GB未満です。長時間録画には不足する可能性があります。' -ForegroundColor Yellow
    }
} catch {}

# --- スリープ / 画面オフ抑止 (SetThreadExecutionState) --------------
if (-not ('Power.Sleep' -as [type])) {
    Add-Type -Namespace Power -Name Sleep -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint SetThreadExecutionState(uint esFlags);
'@
}
$ES_CONTINUOUS        = [uint32]2147483648   # 0x80000000
$ES_SYSTEM_REQUIRED   = [uint32]1            # 0x00000001
$ES_DISPLAY_REQUIRED  = [uint32]2            # 0x00000002
[void][Power.Sleep]::SetThreadExecutionState([uint32]($ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED -bor $ES_DISPLAY_REQUIRED))

# --- ffmpeg 引数組み立て -------------------------------------------
function Q([string]$s) { '"' + $s + '"' }

$common = @(
    '-hide_banner', '-y',
    '-thread_queue_size', '1024',
    '-f', 'dshow', '-i', (Q "audio=$audioDev")
)

if ($encoder -eq 'software') {
    $videoIn = @(
        '-f', 'gdigrab', '-framerate', $FPS, '-i', 'desktop'
    )
    $videoEnc = @(
        '-vf', (Q "scale=$($W):-2"),
        '-c:v', 'libx264', '-preset', 'ultrafast', '-crf', $Q, '-pix_fmt', 'yuv420p',
        '-map', '1:v', '-map', '0:a'
    )
} else {
    $fc = "ddagrab=output_idx=$($monIdx):framerate=$($FPS),hwdownload,format=bgra,scale=$($W):-2,format=nv12[v]"
    $videoIn = @(
        '-filter_complex', (Q $fc)
    )
    $videoEnc = @(
        '-map', '[v]', '-map', '0:a',
        '-c:v', 'h264_qsv', '-preset', 'veryfast', '-global_quality', $Q
    )
}

$outArgs = @(
    '-af', (Q "volume=$($audioGain)dB"),
    '-c:a', 'aac', '-b:a', '160k',
    '-movflags', '+frag_keyframe+empty_moov',
    '-f', 'segment', '-segment_time', "$segSec", '-reset_timestamps', '1',
    '-segment_format', 'mp4',
    (Q $outPattern)
)

$argLine = ($common + $videoIn + $videoEnc + $outArgs) -join ' '

# --- 録画開始 ------------------------------------------------------
Write-Host ''
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host '  Zoom録画ツール' -ForegroundColor Cyan
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host ("  画質プリセット : {0}  ({1}px / {2}fps / Q{3})" -f $presetName, $W, $FPS, $Q)
Write-Host ("  エンコーダ     : {0}" -f $encoder)
Write-Host ("  分割           : {0}分ごと" -f [math]::Round($segSec/60))
Write-Host ("  保存先         : {0}" -f $sessionDir)
Write-Host '------------------------------------------------------'
Write-Host '  ★ 停止するには、この画面で「q」キーを押してください ★' -ForegroundColor Green
Write-Host '======================================================' -ForegroundColor Cyan
Write-Host ''

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName               = $FfmpegExe
$psi.Arguments              = $argLine
$psi.UseShellExecute        = $false
$psi.RedirectStandardInput  = $true
$psi.WorkingDirectory       = $Root

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $psi

try {
    [void]$proc.Start()
    $startTime = Get-Date

    while (-not $proc.HasExited) {
        $stop = $false
        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq 'Q') { $stop = $true }
            }
        } catch {
            # コンソール未接続などでキー検出不可。プロセス終了を待つ。
            $proc.WaitForExit(); break
        }
        if ($stop) {
            Write-Host ''
            Write-Host '停止信号を送信しました。ファイルを確定しています...' -ForegroundColor Yellow
            try { $proc.StandardInput.WriteLine('q') } catch {}
            if (-not $proc.WaitForExit(15000)) { $proc.Kill() }
            break
        }
        Start-Sleep -Milliseconds 300
    }

    $elapsed = (Get-Date) - $startTime
    Write-Host ''
    Write-Host ('録画終了。記録時間: {0:hh\:mm\:ss}' -f $elapsed) -ForegroundColor Green
}
finally {
    # スリープ抑止を解除
    [void][Power.Sleep]::SetThreadExecutionState($ES_CONTINUOUS)
}

# --- 後処理: 保存フォルダを開く ------------------------------------
$files = Get-ChildItem -LiteralPath $sessionDir -Filter 'part_*.mp4' -ErrorAction SilentlyContinue
if ($files) {
    Write-Host ("生成ファイル: {0} 個" -f $files.Count)
    Write-Host ("保存先フォルダ: {0}" -f $sessionDir)
    Write-Host '複数ファイルを1本に結合するには scripts\merge.ps1 を実行してください。'
} else {
    Show-And-Pause "録画ファイルが生成されませんでした。`nffmpegのエラー表示を確認してください（音声デバイス名やffmpegビルドのddagrab/qsv対応をチェック）。"
}

Write-Host ''
Write-Host '何かキーを押すと閉じます...'
try { [void][Console]::ReadKey($true) } catch { Start-Sleep 3 }
