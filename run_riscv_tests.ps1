#Claude wrote this
# Build and run the official riscv-tests rv64ui suite against the core.
# Cross-compilation happens inside WSL (riscv64-unknown-elf-gcc); simulation
# stays on Windows iverilog. Requires:
#   wsl + `sudo apt install gcc-riscv64-unknown-elf`
#   external/riscv-tests   (git clone, already done)
New-Item -ItemType Directory -Force -Path build\riscv | Out-Null

# compile the simulator once
$rtl = (Get-ChildItem rtl\*.v).FullName
& iverilog -g2005 -o build\riscv\sim tb\tb_riscv.v @rtl
if ($LASTEXITCODE -ne 0) { exit 1 }

# fence_i: self-modifying code, impossible on split imem/dmem by construction
# ma_data: misaligned accesses, not implemented (and not required)
$skip = @('fence_i', 'ma_data')
$srcs = Get-ChildItem external\riscv-tests\isa\rv64ui\*.S |
        Where-Object { $skip -notcontains $_.BaseName }

$pass = 0; $fail = 0
foreach ($s in $srcs) {
    $name = $s.BaseName
    $elf = "build/riscv/$name.elf"
    $hex = "build/riscv/$name.hex"

    # forward slashes + relative paths on purpose: WSL inherits the cwd
    wsl riscv64-unknown-elf-gcc -march=rv64i -mabi=lp64 -static -nostdlib -nostartfiles -I riscv_env -I external/riscv-tests/isa/macros/scalar -T riscv_env/link.ld "external/riscv-tests/isa/rv64ui/$name.S" -o $elf
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BUILD FAIL  $name" -ForegroundColor Red
        $fail++
        continue
    }
    wsl riscv64-unknown-elf-objcopy -O verilog $elf $hex
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BUILD FAIL  $name (objcopy)" -ForegroundColor Red
        $fail++
        continue
    }

    $out = (& vvp build\riscv\sim "+hex=$hex" 2>&1) | Out-String
    if ($out -match 'TEST PASSED') {
        Write-Host "PASS  $name" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "FAIL  $name" -ForegroundColor Red
        $out -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "      $_" }
        $fail++
    }
}
Write-Host "---- $pass passed, $fail failed (skipped: $($skip -join ', '))"
if ($fail -gt 0) { exit 1 }
