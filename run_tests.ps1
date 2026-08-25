#Claude wrote this
New-Item -ItemType Directory -Force -Path build | Out-Null
$rtl = (Get-ChildItem rtl\*.v).FullName
& iverilog -g2005 -DSIMULATION -o build\sim tb\tb_top.v @rtl
if ($LASTEXITCODE -ne 0) { exit 1 }

$pass = 0; $fail = 0
foreach ($d in Get-ChildItem tests -Directory) {
    $out = (& vvp build\sim "+testdir=tests/$($d.Name)/" 2>&1) | Out-String
    if ($out -match 'TEST PASSED') {
        Write-Host "PASS  $($d.Name)" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "FAIL  $($d.Name)" -ForegroundColor Red
        $out -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "      $_" }
        $fail++
    }
}
Write-Host "---- $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
