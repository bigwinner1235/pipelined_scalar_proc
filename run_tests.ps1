#Claude wrote this
New-Item -ItemType Directory -Force -Path build | Out-Null
$rtl = (Get-ChildItem rtl\*.v).FullName
& iverilog -g2005 -DSIMULATION -o build\sim tb\tb_top.v @rtl
if ($LASTEXITCODE -ne 0) { exit 1 }

$pass = 0; $fail = 0
$cpiSum = 0.0; $cpiCount = 0
foreach ($d in Get-ChildItem tests -Directory) {
    $out = (& vvp build\sim "+testdir=tests/$($d.Name)/" 2>&1) | Out-String
    $cpiTxt = ''
    if ($out -match 'perf: cycles_after_fill=(\d+) retired=(\d+)') {
        $cpi = [double]$Matches[1] / [double]$Matches[2]
        $cpiSum += $cpi; $cpiCount++
        $cpiTxt = '  (CPI {0:N3})' -f $cpi
    }
    if ($out -match 'TEST PASSED') {
        Write-Host "PASS  $($d.Name)$cpiTxt" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "FAIL  $($d.Name)$cpiTxt" -ForegroundColor Red
        $out -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "      $_" }
        $fail++
    }
}
if ($cpiCount -gt 0) {
    Write-Host ('---- {0} passed, {1} failed, avg CPI {2:N3} over {3} tests' -f $pass, $fail, ($cpiSum / $cpiCount), $cpiCount)
} else {
    Write-Host "---- $pass passed, $fail failed"
}
if ($fail -gt 0) { exit 1 }
