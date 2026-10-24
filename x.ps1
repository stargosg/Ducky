$out = "$env:TEMP\ab_result.txt"
"Acid Burn was here" | Out-File $out
"User: $env:USERNAME" | Out-File $out -Append
"Host: $env:COMPUTERNAME" | Out-File $out -Append
