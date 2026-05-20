# =====================================================================
#  セグメント結合ヘルパー
#  「録画データ」内のセッションフォルダを選び、part_*.mp4 を
#  無劣化(-c copy)で1本のmp4に結合します。
# =====================================================================

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$Root      = Split-Path $PSScriptRoot -Parent
$FfmpegExe = Join-Path $Root 'ffmpeg\ffmpeg.exe'
$OutBase   = Join-Path $Root '録画データ'

if (-not (Test-Path $FfmpegExe)) { Write-Host "ffmpeg.exe が見つかりません: $FfmpegExe" -ForegroundColor Red; pause; exit 1 }
if (-not (Test-Path $OutBase))   { Write-Host "録画データ フォルダがありません: $OutBase" -ForegroundColor Red; pause; exit 1 }

$sessions = Get-ChildItem -LiteralPath $OutBase -Directory | Sort-Object LastWriteTime -Descending
if (-not $sessions) { Write-Host '結合対象のセッションフォルダがありません。' -ForegroundColor Yellow; pause; exit 0 }

Write-Host '結合するセッションを選んでください:'
for ($i = 0; $i -lt $sessions.Count; $i++) {
    Write-Host ("  [{0}] {1}" -f $i, $sessions[$i].Name)
}
$sel = Read-Host '番号を入力 (Enterで最新[0])'
if ($sel -eq '') { $sel = 0 }
$session = $sessions[[int]$sel]

$parts = Get-ChildItem -LiteralPath $session.FullName -Filter 'part_*.mp4' | Sort-Object Name
if (-not $parts) { Write-Host 'part_*.mp4 が見つかりません。' -ForegroundColor Yellow; pause; exit 0 }

# concat 用リストファイル作成
$listFile = Join-Path $session.FullName '_concat_list.txt'
$lines = $parts | ForEach-Object { "file '" + ($_.FullName -replace '\\','/') + "'" }
Set-Content -LiteralPath $listFile -Value $lines -Encoding UTF8

$outFile = Join-Path $session.FullName ($session.Name + '_結合.mp4')
Write-Host ''
Write-Host ("結合中: {0} 個 -> {1}" -f $parts.Count, $outFile)

& $FfmpegExe -hide_banner -y -f concat -safe 0 -i $listFile -c copy $outFile

Remove-Item -LiteralPath $listFile -ErrorAction SilentlyContinue
if (Test-Path $outFile) {
    Write-Host '完了しました。' -ForegroundColor Green
    Write-Host ("出力ファイル: {0}" -f $outFile)
} else {
    Write-Host '結合に失敗しました。各 part_*.mp4 の整合性を確認してください。' -ForegroundColor Red
}
Write-Host ''
Write-Host '何かキーを押すと閉じます...'
try { [void][Console]::ReadKey($true) } catch { Start-Sleep 3 }
