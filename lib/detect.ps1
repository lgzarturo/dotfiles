# lib/detect.ps1 — detección de OS y hardware para Windows

function Get-DotfilesOS {
    $os = [PSCustomObject]@{
        Name           = "windows"
        Version        = [System.Environment]::OSVersion.Version.ToString()
        Build          = [System.Environment]::OSVersion.Version.Build
        Edition        = (Get-CimInstance Win32_OperatingSystem).Caption
        IsAdmin        = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        IsWSL          = $false
        PackageManager = $null
    }

    # Este script es PowerShell nativo — nunca corre dentro de WSL.
    # $os.IsWSL siempre es $false aquí; el flag solo existe por simetría con setup.sh.
    $os.IsWSL = $false

    if (Get-Command winget -ErrorAction SilentlyContinue) { $os.PackageManager = "winget" }
    elseif (Get-Command choco   -ErrorAction SilentlyContinue) { $os.PackageManager = "choco" }
    elseif (Get-Command scoop   -ErrorAction SilentlyContinue) { $os.PackageManager = "scoop" }

    return $os
}

function Get-DotfilesHardware {
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)

    $gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1

    $isLaptop = $false
    $chassis = Get-CimInstance Win32_SystemEnclosure | Select-Object -First 1
    if ($chassis) {
        # 1=desktop, 2=laptop, 8,9,10,11,14,30,31,32 = portable
        $types = $chassis.ChassisTypes
        if ($types -contains 2 -or $types -contains 8 -or $types -contains 9 -or $types -contains 10 -or $types -contains 11 -or $types -contains 14) {
            $isLaptop = $true
        }
    }

    $storageType = "unknown"
    $disk = Get-PhysicalDisk | Select-Object -First 1
    if ($disk) {
        switch ($disk.MediaType) {
            "SSD" { $storageType = "ssd" }
            "NVMe" { $storageType = "nvme" }
            "HDD" { $storageType = "hdd" }
            "Unspecified" { if ($disk.BusType -eq "NVMe") { $storageType = "nvme" } else { $storageType = "ssd" } }
            default { $storageType = "ssd" }
        }
    }

    $cpuProfile = "other"
    $cpuName = $cpu.Name.ToLower()
    if ($cpuName -match "ryzen.*9") { $cpuProfile = "ryzen9" }
    elseif ($cpuName -match "ryzen.*7") { $cpuProfile = "ryzen7" }
    elseif ($cpuName -match "ryzen.*5") { $cpuProfile = "ryzen5" }
    elseif ($cpuName -match "apple.*m2") { $cpuProfile = "m2" }
    elseif ($cpuName -match "apple.*m4") { $cpuProfile = "m4" }
    elseif ($cpuName -match "apple.*m1") { $cpuProfile = "m1" }
    elseif ($cpuName -match "intel|core") { $cpuProfile = "intel" }
    elseif ($cpuName -match "amd") { $cpuProfile = "amd-other" }

    $hasGPU = $false
    $hasGPUApple = $false
    $hasGPUNVIDIA = $false
    $hasGPUAMD = $false
    if ($gpu) {
        $hasGPU = $true
        $gpuName = $gpu.Name.ToLower()
        if ($gpuName -match "nvidia") { $hasGPUNVIDIA = $true }
        elseif ($gpuName -match "amd|radeon") { $hasGPUAMD = $true }
        elseif ($gpuName -match "apple") { $hasGPUApple = $true }
    }

    return [PSCustomObject]@{
        CpuModel     = $cpu.Name
        CpuProfile   = $cpuProfile
        CpuCores     = $cpu.NumberOfCores
        CpuThreads   = $cpu.NumberOfLogicalProcessors
        RamGB        = $ram
        StorageType  = $storageType
        IsLaptop     = $isLaptop
        GpuName      = $gpu.Name
        HasGPU       = $hasGPU
        HasGPUApple  = $hasGPUApple
        HasGPUNVIDIA = $hasGPUNVIDIA
        HasGPUAMD    = $hasGPUAMD
    }
}
