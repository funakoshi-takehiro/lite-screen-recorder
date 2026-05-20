# =====================================================================
#  lite-screen-recorder セットアップスクリプト
#  ffmpeg (BtbN win64-gpl) と screen-capture-recorder を自動で導入
#  ・既に揃っているものはスキップ（冪等）
#  ・UAC許諾は音声フィルタのインストール時に1回だけ必要
# =====================================================================

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ProgressPreference = 'SilentlyContinue'

$Root      = Split-Path $PSScriptRoot -Parent
$FfmpegDir = Join-Path $Root 'ffmpeg'
$FfmpegExe = Join-Path $FfmpegDir 'ffmpeg.exe'

$FfmpegUrl       = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
$AudioFilterUrl  = 'https://downloads.sourceforge.net/project/screencapturer/Setup%20Screen%20Capturer%20Recorder%20v0.13.3.exe'

function Write-Step([string]$msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "   OK: $msg" -ForegroundColor Green }
function Write-Warn([string]$msg) { Write-Host "   WARN: $msg" -ForegroundColor Yellow }

function Test-Ffmpeg {
    if (-not (Test-Path $FfmpegExe)) { return $false }
    try {
        $out = & $FfmpegExe -hide_banner -filters 2>&1 | Out-String
        return ($out -match 'ddagrab')
    } catch { return $false }
}

function Install-Ffmpeg {
    $zip = Join-Path $Root '_ffmpeg_dl.zip'
    $tmp = Join-Path $Root '_ffmpeg_tmp'
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Write-Host "   ダウンロード中... (約200MB、回線状況により数十秒〜数分)"
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    Invoke-WebRequest -Uri $FfmpegUrl -OutFile $zip -UseBasicParsing
    $sw.Stop()
    Write-Host ("   {0} MB を {1} 秒で取得" -f [math]::Round((Get-Item $zip).Length/1MB,1), [math]::Round($sw.Elapsed.TotalSeconds,1))
    Write-Host "   解凍中..."
    Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
    $exe = Get-ChildItem -LiteralPath $tmp -Recurse -Filter ffmpeg.exe | Select-Object -First 1
    if (-not $exe) { throw "ダウンロードしたアーカイブに ffmpeg.exe が見つかりません" }
    if (-not (Test-Path $FfmpegDir)) { New-Item -ItemType Directory -Path $FfmpegDir -Force | Out-Null }
    Copy-Item -LiteralPath $exe.FullName -Destination $FfmpegExe -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

function Test-AudioFilter {
    $audioCat = '{33D9A762-90C8-11d0-BD43-00A0C911CE86}'
    foreach ($view in 'CLSID', 'WOW6432Node\CLSID') {
        $path = "HKLM:\SOFTWARE\Classes\$view\$audioCat\Instance"
        if (Test-Path $path) {
            foreach ($k in Get-ChildItem $path -ErrorAction SilentlyContinue) {
                $name = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).FriendlyName
                if ($name -eq 'virtual-audio-capturer') { return $true }
            }
        }
    }
    return $false
}

function Install-AudioFilter {
    # ローカルにインストーラが既にあればそれを使う
    $local = Get-ChildItem -LiteralPath $Root -Filter 'Setup.Screen.Capturer.Recorder*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $local) {
        $dl = Join-Path $Root '_sc_recorder.exe'
        Write-Host "   インストーラをダウンロード中... (約58MB)"
        Invoke-WebRequest -Uri $AudioFilterUrl -OutFile $dl -UseBasicParsing
        $local = Get-Item $dl
    }
    Write-Host "   インストール実行（UACの確認が出たら『はい』を押してください）..."
    $p = Start-Process -FilePath $local.FullName -ArgumentList '/S' -PassThru -Wait
    Write-Host "   インストーラ終了コード: $($p.ExitCode)"
    # 一時的にダウンロードしたインストーラのみ削除
    $tmpInst = Join-Path $Root '_sc_recorder.exe'
    if (Test-Path $tmpInst) { Remove-Item $tmpInst -Force -ErrorAction SilentlyContinue }
}

# ============================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  lite-screen-recorder セットアップ" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

try {
    # --- FFmpeg ---
    Write-Step "FFmpeg を確認"
    if (Test-Ffmpeg) {
        Write-OK "ffmpeg.exe は配置済み（ddagrab対応を確認）"
    } else {
        Write-Host "   未配置または機能不足。ダウンロードします。"
        Install-Ffmpeg
        if (-not (Test-Ffmpeg)) { throw "FFmpeg の導入に失敗しました（ddagrab が見つかりません）" }
        Write-OK "ffmpeg.exe を配置しました"
    }

    # --- 音声フィルタ ---
    Write-Step "仮想音声フィルタ (virtual-audio-capturer) を確認"
    if (Test-AudioFilter) {
        Write-OK "既にインストール済み"
    } else {
        Write-Host "   未登録。インストーラを実行します。"
        Install-AudioFilter
        if (-not (Test-AudioFilter)) {
            Write-Warn "レジストリに virtual-audio-capturer が見つかりません。"
            Write-Warn "PCを再起動してから再度 setup.bat を実行してみてください。"
        } else {
            Write-OK "音声フィルタを登録しました"
        }
    }

    # --- 最終動作確認: ffmpegからデバイスが見えるか ---
    Write-Step "ffmpeg からデバイスが見えるか確認"
    $errFile = Join-Path $env:TEMP 'lsr_setup_check.txt'
    Start-Process -FilePath $FfmpegExe -ArgumentList '-hide_banner','-list_devices','true','-f','dshow','-i','dummy' -NoNewWindow -Wait -RedirectStandardError $errFile | Out-Null
    $devs = Get-Content $errFile -ErrorAction SilentlyContinue
    Remove-Item $errFile -Force -ErrorAction SilentlyContinue
    if ($devs | Select-String 'virtual-audio-capturer') {
        Write-OK "virtual-audio-capturer を認識"
    } else {
        Write-Warn "virtual-audio-capturer がffmpegから見えません。PC再起動後に再実行を。"
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "  セットアップ完了。start.bat で録画できます。" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host "  エラー: $_" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "手動セットアップ手順は README.md を参照してください。"
}

Write-Host ""
Write-Host "何かキーを押すと閉じます..."
try { [void][Console]::ReadKey($true) } catch { Start-Sleep 3 }
