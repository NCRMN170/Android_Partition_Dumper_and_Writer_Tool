<#
.SYNOPSIS
V50: Ghost Watcher Edition (Process Kill Patch)
     - Forces closes and cleans ADB/Fastboot background processes even if closed with (X).
     - WinRAR/7-Zip SFX compatible.
     - Strict Serial No-based folder filtering.
     - Super Dump restricted to Android mode.
     - Advanced Multi-Select feature.
     - 0 MB empty partitions are completely hidden.
#>

Set-Location -Path $PSScriptRoot
$Host.UI.RawUI.WindowTitle = "Advanced Partition Dumper & Writer V50"

# RELATIVE PATHS FOR TOOLS
$adb = Join-Path $PSScriptRoot "platform-tools_APDWT\adb.exe"
$fb = Join-Path $PSScriptRoot "platform-tools_APDWT\fastboot.exe"
$toolsDir = Join-Path $PSScriptRoot "platform-tools_APDWT"
$currentScript = $PSCommandPath

# GHOST WATCHER - 100% PROTECTION AGAINST (X) CLOSURE
if (-not $env:WATCHER_ACTIVE) {
    $env:WATCHER_ACTIVE = "1"
    # NEW: Force close ADB and Fastboot after Wait-Process (Stop-Process) and wait 1 second to release locks
    $watcherScript = "Wait-Process -Id $PID; Stop-Process -Name 'adb', 'fastboot' -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Remove-Item -Path '$toolsDir' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path '$currentScript' -Force -ErrorAction SilentlyContinue"
    $encodedWatcher = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watcherScript))
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedWatcher"
}

# CLEANUP AND NORMAL EXIT FUNCTION
function Cleanup-And-Exit {
    Write-Host "`nCleaning up tools and temporary files... Please wait." -ForegroundColor DarkGray
    
    # NEW: Close ADB server properly, then forcefully kill processes just to be safe
    if (Test-Path $adb) { & $adb kill-server 2>$null }
    Stop-Process -Name 'adb', 'fastboot' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1 # Short wait for file locks to be released
    
    if (Test-Path $toolsDir) { Remove-Item -Path $toolsDir -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path $currentScript) { Remove-Item -Path $currentScript -Force -ErrorAction SilentlyContinue }
    exit
}

function Show-Header {
    Clear-Host
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "     ANDROID PARTITION DUMPER & WRITER TOOL      " -ForegroundColor White
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host ""
}

# SMART GUARD MODULE (STRICT SERIAL NO MATCHING)
function Wait-TargetDevice {
    param ([string]$TargetFolder, [string]$RequiredMode, [string]$ActionTitle, [string]$TargetSerial = "")
    
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "    WAITING FOR DEVICE...                        " -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host $ActionTitle -ForegroundColor Yellow
        
        $tempDevices = @()
        $adbOutput = & $adb devices 2>&1
        $adbLines = @($adbOutput -split "\r?\n" | Where-Object { $_ -match "\b(device|recovery)\b" })
        foreach ($line in $adbLines) {
            $parts = $line -split "\s+"; $serial = $parts[0].Trim(); $devState = $parts[1].Trim()
            $devModel = (& $adb -s $serial shell getprop ro.product.device 2>$null) -join ""; $devModel = $devModel.Trim()
            if ([string]::IsNullOrWhiteSpace($devModel)) { $devModel = "Unknown" }
            $tempDevices += [PSCustomObject]@{ Serial = $serial; Model = $devModel; State = "ADB/$devState" }
        }

        $fbOutput = (& $fb devices 2>&1) -join "`n"
        $fbLines = @($fbOutput -split "\r?\n" | Where-Object { $_ -match "\bfastboot\b" })
        foreach ($line in $fbLines) {
            $serial = ($line -split "\s+")[0].Trim()
            $fbVar = (& $fb -s $serial getvar product 2>&1) -join "`n"
            $devModel = "Unknown"
            if ($fbVar -match "product:\s*([a-zA-Z0-9_-]+)") { $devModel = $Matches[1].Trim() }
            $tempDevices += [PSCustomObject]@{ Serial = $serial; Model = $devModel; State = "FASTBOOT" }
        }

        $matchedTemp = @()
        foreach ($d in $tempDevices) {
            $modeMatch = $false
            if ($RequiredMode -eq "FASTBOOT" -and $d.State -eq "FASTBOOT") { $modeMatch = $true }
            elseif ($RequiredMode -eq "RECOVERY" -and $d.State -match "recovery") { $modeMatch = $true }
            elseif ($RequiredMode -eq "ANDROID" -and $d.State -match "device") { $modeMatch = $true }
            
            $folderMatch = $true
            if (-not [string]::IsNullOrWhiteSpace($TargetFolder)) {
                if (-not ($TargetFolder -match [regex]::Escape($d.Serial))) { $folderMatch = $false }
            }
            if ($modeMatch -and $folderMatch) { $matchedTemp += $d }
        }

        $exactMatch = $null
        if ($TargetSerial) { $exactMatch = $matchedTemp | Where-Object { $_.Serial -eq $TargetSerial } }

        if ($exactMatch) {
            $finalSerial = $exactMatch[0].Serial
            Write-Host "`n[+] Expected device detected, proceeding! ($finalSerial)" -ForegroundColor Green
            Start-Sleep -Seconds 2
            return $finalSerial
        }
        elseif (-not $TargetSerial -and $matchedTemp.Count -eq 1) {
            $finalSerial = $matchedTemp[0].Serial
            Write-Host "`n[+] Compatible device detected, starting automatically! ($finalSerial)" -ForegroundColor Green
            Start-Sleep -Seconds 2
            return $finalSerial
        } 
        else {
            $devicesInRequiredMode = @($tempDevices | Where-Object {
                ($RequiredMode -eq "FASTBOOT" -and $_.State -eq "FASTBOOT") -or 
                ($RequiredMode -eq "RECOVERY" -and $_.State -match "recovery") -or
                ($RequiredMode -eq "ANDROID" -and $_.State -match "device")
            })

            if ($devicesInRequiredMode.Count -eq 0) {
                Write-Host "`n[INFO] Waiting for a device in $RequiredMode mode for the operation..." -ForegroundColor Yellow
                if ($TargetSerial) { Write-Host "Target Serial No: $TargetSerial" -ForegroundColor Cyan }
                Write-Host "Scanning automatically in the background, please wait... (Close the tool to exit)" -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
                continue 
            }

            Write-Host "`n[ATTENTION] Please select the target device!" -ForegroundColor Magenta
            if ($TargetFolder) { Write-Host "Target Folder: $TargetFolder" -ForegroundColor Cyan }
            if ($TargetSerial) { Write-Host "Expected Device: $TargetSerial" -ForegroundColor Cyan }
            Write-Host "Required Device Mode: $RequiredMode" -ForegroundColor Cyan
            Write-Host "-------------------------------------------------" -ForegroundColor Cyan
            Write-Host "CURRENTLY CONNECTED DEVICES:" -ForegroundColor White
            
            if ($tempDevices.Count -eq 0) { Write-Host " -> No device connected!" -ForegroundColor DarkGray }
            else {
                for ($i = 0; $i -lt $tempDevices.Count; $i++) {
                    $d = $tempDevices[$i]
                    $isFolderMatch = if (-not $TargetFolder) { $true } else { ($TargetFolder -match [regex]::Escape($d.Serial)) }
                    $isModeMatch = if (($RequiredMode -eq "FASTBOOT" -and $d.State -eq "FASTBOOT") -or 
                                       ($RequiredMode -eq "RECOVERY" -and $d.State -match "recovery") -or 
                                       ($RequiredMode -eq "ANDROID" -and $d.State -match "device")) { $true } else { $false }
                    
                    if ($isFolderMatch -and $isModeMatch) { $color = "Green" }
                    elseif ($isFolderMatch) { $color = "Yellow" }
                    else { $color = "DarkGray" }
                    
                    Write-Host ("{0}. Model: {1,-25} | Serial No: {2,-15} [{3}]" -f ($i+1), $d.Model, $d.Serial, $d.State) -ForegroundColor $color
                }
            }
            
            Write-Host "`n R. REFRESH (Update List)" -ForegroundColor Yellow
            Write-Host " G. GO BACK (Cancel)" -ForegroundColor DarkCyan
            
            $ans = Read-Host "`nYour choice"
            if ($ans -match "^[gG]$") { return "CANCEL" }
            elseif ($ans -match '^\d+$') {
                $idx = [int]$ans - 1
                if ($idx -ge 0 -and $idx -lt $tempDevices.Count) {
                    $sel = $tempDevices[$idx]
                    
                    $selModeMatch = if (($RequiredMode -eq "FASTBOOT" -and $sel.State -eq "FASTBOOT") -or 
                                        ($RequiredMode -eq "RECOVERY" -and $sel.State -match "recovery") -or
                                        ($RequiredMode -eq "ANDROID" -and $sel.State -match "device")) { $true } else { $false }
                    
                    $selFolderMatch = if (-not $TargetFolder) { $true } else { ($TargetFolder -match [regex]::Escape($sel.Serial)) }
                    
                    if ($selModeMatch) {
                        if (-not $selFolderMatch) {
                            Write-Host "`n[!] WARNING: Selected device seems incompatible with the folder (Serial No mismatch)!" -ForegroundColor Red
                            Write-Host "Force continuing anyway..." -ForegroundColor Magenta
                            Start-Sleep -Seconds 2
                        } else {
                            Write-Host "`n[+] Device selected and confirmed!" -ForegroundColor Green
                            Start-Sleep -Seconds 1
                        }
                        return $sel.Serial
                    } else {
                        Write-Host "`n[-] Selected device is not in the required $RequiredMode mode!" -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
            }
            elseif ($ans -match "^[rR]$") {
                Write-Host "Refreshing Devices..." -ForegroundColor DarkGray
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Common Variables
$excluded = @("super", "userdata", "system", "vendor", "product", "system_ext", "cust", "cache")
$state = "MAIN"; $operation = ""; $mode = ""; $isSuperMode = $false
$selectedFolder = $null; $partObjs = @(); $warningMessage = ""
$connectedDevices = @(); $matchingDevices = @(); $selectedDevice = $null; $targetSerial = ""
$selectedPartitions = @(); $global:lpdumpInfoText = ""

# Main Loop
while ($true) {

    if ($state -eq "MAIN") {
        $operation = ""; $mode = ""; $selectedFolder = $null; $isSuperMode = $false
        $partObjs = @(); $warningMessage = ""; $connectedDevices = @()
        $matchingDevices = @(); $selectedDevice = $null; $targetSerial = ""; $global:lpdumpInfoText = ""
        $selectedPartitions = @()

        Show-Header
        Write-Host "Select an operation" -ForegroundColor Yellow
        Write-Host "1. DUMP (Backup Physical Partitions)"
        Write-Host "2. WRITE (Flash Physical Partitions)"
        Write-Host "3. DYNAMIC PARTITION (SUPER) OPERATIONS" -ForegroundColor Magenta
        Write-Host "0. EXIT" -ForegroundColor DarkGray
        Write-Host " "
        Write-Host "IMPORTANT NOTE: " -ForegroundColor Red
        Write-Host "With some recovery software, the ADB connection may drop in and out or may not be stable while the recovery is booting." -ForegroundColor Yellow
	    Write-Host "Use a recovery with a stable connection, or use it with caution." -ForegroundColor Yellow
        Write-Host " "

        $opInput = Read-Host "`nYour choice"
        if ($opInput -match "^[12]$") { $operation = $opInput; $state = "MODE" } 
        elseif ($opInput -match "^3$") { $state = "SUPER_MAIN" }
        elseif ($opInput -eq "0") { Cleanup-And-Exit }
    }
    
    elseif ($state -eq "SUPER_MAIN") {
        Show-Header
        Write-Host "DYNAMIC PARTITION (SUPER) OPERATIONS" -ForegroundColor Magenta
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "1. DUMP (Backup Super Partitions to PC - Android Only - Root required)"
        Write-Host "2. WRITE (Flash to Super Partition from PC - FastbootD Only)"
        Write-Host "G. GO BACK (Main Menu)" -ForegroundColor DarkCyan
        
        $supIn = Read-Host "`nYour choice"
        if ($supIn -match "^1$") { 
            $operation = "1"; $isSuperMode = $true; $mode = "1"; $state = "DUMP_SCAN_DEVICES" 
        }
        elseif ($supIn -match "^2$") { 
            $operation = "2"; $isSuperMode = $true; $mode = "1"; $state = "FOLDER_MENU" 
        }
        elseif ($supIn -match "^[gG]$") { $state = "MAIN" }
    }

    elseif ($state -eq "MODE") {
        Show-Header
        if ($operation -eq "2") {
            Write-Host "Select write method" -ForegroundColor Yellow
            Write-Host "1. Bootloader-Recovery Hybrid Mode (Fastboot & Recovery DD Fallback) (Recommended)"
            Write-Host "2. Recovery Mode (TWRP/OrangeFox - Standard Write with DD)"
        } else {
            Write-Host "Select dump method" -ForegroundColor Yellow
            Write-Host "1. Android System (Device on - Root required)"
            Write-Host "2. Recovery Mode (TWRP/OrangeFox/Custom Recovery etc.) (Recommended)"
			Write-Host " "
			Write-Host "NOTE: " -NoNewline -ForegroundColor Red
            Write-Host "Dumping the Super partition in Recovery Mode is safer." -ForegroundColor Yellow
			Write-Host " "
        }
        
        Write-Host "G. GO BACK (Main Menu)" -ForegroundColor DarkCyan
        
        $modeInput = Read-Host "`nYour choice (1, 2 or G)"
        
        if ($modeInput -match "^[gG]$") { if ($isSuperMode) { $state = "SUPER_MAIN" } else { $state = "MAIN" } } 
        elseif ($modeInput -match "^[12]$") {
            $mode = $modeInput
            if ($operation -eq "1") { $state = "DUMP_SCAN_DEVICES" } else { $state = "FOLDER_MENU" }
        }
    }

    elseif ($state -eq "DUMP_SCAN_DEVICES") {
        Write-Host "`nScanning connected devices (ADB & Fastboot)..." -ForegroundColor Cyan
        $connectedDevices = @()
        
        $adbOutput = & $adb devices 2>&1
        $adbLines = @($adbOutput -split "\r?\n" | Where-Object { $_ -match "\b(device|recovery)\b" })

        foreach ($line in $adbLines) {
            $parts = $line -split "\s+"
            $serial = $parts[0].Trim(); $devState = $parts[1].Trim()
            $isRec = ($devState -eq "recovery")
            
            $devModel = (& $adb -s $serial shell getprop ro.product.device 2>$null) -join ""; $devModel = $devModel.Trim()
            if ([string]::IsNullOrWhiteSpace($devModel)) { $devModel = "Unknown" }
            $connectedDevices += [PSCustomObject]@{ Serial = $serial; Model = $devModel; IsFastboot = $false; IsRecovery = $isRec }
        }

        $fbOutput = (& $fb devices 2>&1) -join "`n"
        $fbLines = @($fbOutput -split "\r?\n" | Where-Object { $_ -match "\bfastboot\b" })
        foreach ($line in $fbLines) {
            $serial = ($line -split "\s+")[0].Trim()
            $fbVar = (& $fb -s $serial getvar product 2>&1) -join "`n"
            if ($fbVar -match "product:\s*([a-zA-Z0-9_-]+)") {
                $devModel = $Matches[1].Trim()
                if (-not ($connectedDevices | Where-Object { $_.Serial -eq $serial })) {
                    $connectedDevices += [PSCustomObject]@{ Serial = $serial; Model = $devModel; IsFastboot = $true; IsRecovery = $false }
                }
            }
        }

        if ($connectedDevices.Count -eq 0) { Write-Host "[-] ERROR: No devices found!" -ForegroundColor Red; pause; if($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"} } 
        elseif ($connectedDevices.Count -eq 1 -and -not $connectedDevices[0].IsFastboot) {
            $selectedDevice = $connectedDevices[0]; $targetSerial = $selectedDevice.Serial; $state = "PREPARE_DEVICE"
        } else { $state = "DUMP_DEVICE_SELECT" }
    }

    elseif ($state -eq "DUMP_DEVICE_SELECT") {
        Show-Header
        Write-Host "Multiple devices OR Fastboot device(s) found!" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        
        Write-Host "Please select the device you want to operate on:" -ForegroundColor White
        for ($i = 0; $i -lt $connectedDevices.Count; $i++) {
            $d = $connectedDevices[$i]
            $statusStr = if ($d.IsFastboot) { "[FASTBOOT]" } elseif ($d.IsRecovery) { "[RECOVERY]" } else { "[ANDROID]" }
            Write-Host ("{0}. Model: {1,-25} | Serial No: {2,-15} {3}" -f ($i+1), $d.Model, $d.Serial, $statusStr) -ForegroundColor Green
        }
        Write-Host "`nG. GO BACK (To Selection Screen)" -ForegroundColor DarkCyan

        $devIn = Read-Host "`nYour choice"
        if ($devIn -match "^[gG]$") { $connectedDevices = @(); if($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"} }
        elseif ($devIn -match '^\d+$') {
            $idx = [int]$devIn - 1
            if ($idx -ge 0 -and $idx -lt $connectedDevices.Count) {
                $selectedDevice = $connectedDevices[$idx]; $targetSerial = $selectedDevice.Serial; $state = "PREPARE_DEVICE"
            }
        }
    }

    elseif ($state -eq "FOLDER_MENU") {
        Show-Header
        
        $filterStr = if ($isSuperMode) { "^Backup_Super_[^_]+_[^_]+_[^_]+_[^_]+$" } else { "^Backup_(?!Super_)[^_]+_[^_]+_[^_]+_[^_]+$" }
        $backupFolders = @(Get-ChildItem -Path $PSScriptRoot -Directory | Where-Object { $_.Name -match $filterStr })
        
        if ($backupFolders.Count -eq 0) {
            Write-Host "[-] ERROR: No folder with a suitable format found in the same directory!" -ForegroundColor Red
            pause
            if ($isSuperMode) { $state = "SUPER_MAIN" } else { $state = "MODE" }
            continue
        }

        Write-Host "FOUND BACKUP FOLDERS:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $backupFolders.Count; $i++) { Write-Host ("{0,2}. {1}" -f ($i+1), $backupFolders[$i].Name) -ForegroundColor Cyan }
        Write-Host " G. GO BACK (To Selection Screen)" -ForegroundColor DarkCyan
        
        $folderInput = Read-Host "`nSelect the NUMBER of the folder to flash or type G"
        
        if ($folderInput -match "^[gG]$") { if ($isSuperMode) { $state = "SUPER_MAIN" } else { $state = "MODE" } } 
        elseif ($folderInput -match '^\d+$') {
            $folderIdx = [int]$folderInput
            if ($folderIdx -ge 1 -and $folderIdx -le $backupFolders.Count) {
                $selectedFolder = $backupFolders[$folderIdx - 1]; $state = "FOLDER_MATCH_CHECK"
            }
        }
    }

    elseif ($state -eq "FOLDER_MATCH_CHECK") {
        Write-Host "`nScanning connected devices and checking folder match..." -ForegroundColor Cyan
        $connectedDevices = @()
        
        $adbOutput = & $adb devices 2>&1
        $adbLines = @($adbOutput -split "\r?\n" | Where-Object { $_ -match "\b(device|recovery)\b" })
        foreach ($line in $adbLines) {
            $parts = $line -split "\s+"
            $serial = $parts[0].Trim(); $devState = $parts[1].Trim()
            $isRec = ($devState -eq "recovery")
            $devModel = (& $adb -s $serial shell getprop ro.product.device 2>$null) -join ""; $devModel = $devModel.Trim()
            if (-not [string]::IsNullOrWhiteSpace($devModel)) {
                $connectedDevices += [PSCustomObject]@{ Serial = $serial; Model = $devModel; IsFastboot = $false; IsRecovery = $isRec }
            }
        }

        $fbOutput = (& $fb devices 2>&1) -join "`n"
        $fbLines = @($fbOutput -split "\r?\n" | Where-Object { $_ -match "\bfastboot\b" })
        foreach ($line in $fbLines) {
            $serial = ($line -split "\s+")[0].Trim()
            $fbVar = (& $fb -s $serial getvar product 2>&1) -join "`n"
            if ($fbVar -match "product:\s*([a-zA-Z0-9_-]+)") {
                $devModel = $Matches[1].Trim()
                if (-not ($connectedDevices | Where-Object { $_.Serial -eq $serial })) {
                    $connectedDevices += [PSCustomObject]@{ Serial = $serial; Model = $devModel; IsFastboot = $true; IsRecovery = $false }
                }
            }
        }

        $matchingDevices = @($connectedDevices | Where-Object { 
            $selectedFolder.Name -match [regex]::Escape($_.Serial)
        })

        if ($matchingDevices.Count -eq 0) { $state = "NO_MATCH_WARN" } 
        elseif ($matchingDevices.Count -eq 1 -and (-not $matchingDevices[0].IsFastboot -or $mode -eq "1" -or $isSuperMode)) {
            $selectedDevice = $matchingDevices[0]; $targetSerial = $selectedDevice.Serial; $state = "PREPARE_DEVICE"
        } else { 
            $state = "WRITE_DEVICE_SELECT" 
        }
    }

    elseif ($state -eq "NO_MATCH_WARN") {
        Show-Header
        Write-Host "[-] WARNING: The 'SERIAL NO' of the selected folder and connected devices do not match!" -ForegroundColor Red
        Write-Host "Selected Folder Name : $($selectedFolder.Name)" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        
        Write-Host "CURRENTLY CONNECTED DEVICES (INFO):" -ForegroundColor White
        if ($connectedDevices.Count -gt 0) {
            for ($i = 0; $i -lt $connectedDevices.Count; $i++) {
                $d = $connectedDevices[$i]
                $statusStr = if ($d.IsFastboot) { "[FASTBOOT]" } elseif ($d.IsRecovery) { "[RECOVERY]" } else { "[ANDROID]" }
                Write-Host ("{0}. Model: {1,-25} | Serial No: {2,-15} {3}" -f ($i+1), $d.Model, $d.Serial, $statusStr) -ForegroundColor DarkGray
            }
        } else { Write-Host " -> No device connected (ADB/Fastboot) or unauthorized!" -ForegroundColor DarkGray }
        
        Write-Host "`n[!] Fully compatible device not found. You can manually select the device from the list." -ForegroundColor Magenta
        Write-Host "However, flashing ROM/Backup to the wrong device can HARD-BRICK it." -ForegroundColor Red
        Write-Host "All responsibility belongs to you!" -ForegroundColor Red
        Write-Host "R. REFRESH (Update List)" -ForegroundColor Yellow
        Write-Host "G. GO BACK (To Folder Selection)" -ForegroundColor DarkCyan
        
        $errIn = Read-Host "`nYour choice"
        if ($errIn -match "^[gG]$") { $connectedDevices = @(); $matchingDevices = @(); $state = "FOLDER_MENU" }
        elseif ($errIn -match "^[rR]$") { $state = "FOLDER_MATCH_CHECK" }
        elseif ($errIn -match '^\d+$') {
            $idx = [int]$errIn - 1
            if ($idx -ge 0 -and $idx -lt $connectedDevices.Count) {
                $selectedDevice = $connectedDevices[$idx]
                $targetSerial = $selectedDevice.Serial
                $state = "PREPARE_DEVICE"
            }
        }
    }

    elseif ($state -eq "WRITE_DEVICE_SELECT") {
        Show-Header
        Write-Host "Waiting for device selection..." -ForegroundColor Yellow
        Write-Host "Selected Folder: $($selectedFolder.Name)" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        Write-Host "Please select the target device by its Serial Number:" -ForegroundColor White
        for ($i = 0; $i -lt $matchingDevices.Count; $i++) {
            $d = $matchingDevices[$i]
            $statusStr = if ($d.IsFastboot) { "[FASTBOOT]" } elseif ($d.IsRecovery) { "[RECOVERY]" } else { "[ANDROID]" }
            Write-Host ("{0}. Model: {1,-25} | Serial No: {2,-15} {3}" -f ($i+1), $d.Model, $d.Serial, $statusStr) -ForegroundColor Green
        }
        Write-Host "`nG. GO BACK (To Folder Selection)" -ForegroundColor DarkCyan

        $devIn = Read-Host "`nYour choice"
        if ($devIn -match "^[gG]$") { $connectedDevices = @(); $matchingDevices = @(); $state = "FOLDER_MENU" }
        elseif ($devIn -match '^\d+$') {
            $idx = [int]$devIn - 1
            if ($idx -ge 0 -and $idx -lt $matchingDevices.Count) {
                $selectedDevice = $matchingDevices[$idx]
                $targetSerial = $selectedDevice.Serial
                $state = "PREPARE_DEVICE"
            }
        }
    }

    elseif ($state -eq "PREPARE_DEVICE") {
        if ($isSuperMode -and $operation -eq "2") {
            Write-Host "`n[INFO] Device must be switched to FastbootD mode for Super Write operation!" -ForegroundColor Yellow
            
            if (-not $selectedDevice.IsFastboot) {
                Write-Host "Switching device to FastbootD mode (adb reboot fastboot)..." -ForegroundColor Cyan
                & $adb -s $targetSerial reboot fastboot | Out-Null
            } else {
                Write-Host "Switching device to FastbootD mode (fastboot reboot fastboot)..." -ForegroundColor Cyan
                & $fb -s $targetSerial reboot fastboot | Out-Null
            }
            
            $waitRes = Wait-TargetDevice -TargetFolder $selectedFolder.Name -RequiredMode "FASTBOOT" -ActionTitle "Waiting for device in FastbootD mode..." -TargetSerial $targetSerial
            if ($waitRes -eq "CANCEL") { $state = "SUPER_MAIN"; continue }
            
            $selectedDevice.IsFastboot = $true
            $selectedDevice.IsRecovery = $false
            $targetSerial = $waitRes
            $state = "WRITE_INIT"
            continue
        }

        if ($selectedDevice.IsRecovery -and $operation -eq "1" -and $mode -eq "1") {
            if ($isSuperMode) {
                Show-Header
                Write-Host "[!] ERROR: Dynamic (Super) partition info can be acquired more accurately when the device is in normal Android (System) mode!" -ForegroundColor Red
                Write-Host "Selected device is currently in RECOVERY mode." -ForegroundColor Red
                
                Write-Host "`nWhat would you like to do?" -ForegroundColor White
                Write-Host "1. Reboot Device Normally (ADB Reboot - Return to Android)"
                Write-Host "G. GO BACK (To Selection Screen)" -ForegroundColor DarkCyan
                
                Write-Host ""
                $actIn = Read-Host "Your choice"
                while ($actIn -notmatch "^[1gG]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $actIn = Read-Host "Your choice" 
                }
                
                if ($actIn -match "^[gG]$") { $state = "DUMP_SCAN_DEVICES"; continue } 
                else {
                    Write-Host "`nBooting into normal Android system..." -ForegroundColor Cyan
                    & $adb -s $targetSerial reboot | Out-Null
                    
                    $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "ANDROID" -ActionTitle "Waiting for Android system to boot..." -TargetSerial $targetSerial
                    if ($waitRes -eq "CANCEL") { $state = "DUMP_SCAN_DEVICES"; continue }
                    
                    $selectedDevice.IsFastboot = $false
                    $selectedDevice.IsRecovery = $false
                    $selectedDevice.Serial = $waitRes
                    $targetSerial = $waitRes
                    $state = "ROOT_CHECK"
                }
            } else {
                Write-Host "`n[INFO] Device detected in Recovery mode. Operation is automatically switching to Recovery mode!" -ForegroundColor Green
                Start-Sleep -Seconds 2
                $mode = "2"; $state = "ROOT_CHECK"
            }
        }
        elseif ($selectedDevice.IsFastboot -and $operation -eq "1" -and $mode -eq "1") {
            Show-Header
            Write-Host "[!] INFO: To backup in Android mode, the device must be powered on (Android)!" -ForegroundColor Yellow
            Write-Host "Selected device is currently in FASTBOOT mode." -ForegroundColor Red
            
            Write-Host "`nWhat would you like to do?" -ForegroundColor White
            Write-Host "1. Reboot Device Normally (Fastboot Reboot - Return to Android)"
            Write-Host "G. GO BACK (To Selection Screen)" -ForegroundColor DarkCyan
            
            Write-Host ""
            $actIn = Read-Host "Your choice"
            while ($actIn -notmatch "^[1gG]$") { 
                try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                $actIn = Read-Host "Your choice" 
            }
            
            if ($actIn -match "^[gG]$") { $state = "DUMP_SCAN_DEVICES"; continue } 
            else {
                Write-Host "`nBooting into normal Android system..." -ForegroundColor Cyan
                $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
                $fbArgs += "reboot"
                & $fb $fbArgs | Out-Null
                
                $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "ANDROID" -ActionTitle "Waiting for Android system to boot..." -TargetSerial $targetSerial
                if ($waitRes -eq "CANCEL") { $state = "DUMP_SCAN_DEVICES"; continue }
                
                $selectedDevice.IsFastboot = $false
                $selectedDevice.IsRecovery = $false
                $selectedDevice.Serial = $waitRes
                $targetSerial = $waitRes
                $state = "ROOT_CHECK"
            }
        }
        elseif ($selectedDevice.IsFastboot -and (($operation -eq "1" -and $mode -eq "2") -or ($operation -eq "2" -and $mode -eq "2"))) {
            Write-Host "`n[INFO] Device detected in Fastboot mode but operation requires Recovery. Redirecting..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2; $state = "REBOOT_TO_RECOVERY"
        }
        elseif (-not $selectedDevice.IsFastboot -and -not $selectedDevice.IsRecovery -and (($operation -eq "1" -and $mode -eq "2") -or ($operation -eq "2" -and $mode -eq "2"))) {
            Write-Host "`n[INFO] Device detected in Android mode but operation requires Recovery!" -ForegroundColor Yellow
            Start-Sleep -Seconds 2; $state = "REBOOT_TO_RECOVERY"
        }
        elseif ($operation -eq "2" -and $mode -eq "1") {
            Write-Host "`n[INFO] Hybrid Mode (Fastboot) selected. Preparing list..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2; $state = "WRITE_INIT"
        }
        else {
            $state = "ROOT_CHECK"
        }
    }

    elseif ($state -eq "REBOOT_TO_RECOVERY") {
        Show-Header
        if ($selectedDevice.IsFastboot) {
            Write-Host "Selected device is currently in FASTBOOT mode!" -ForegroundColor Yellow
            Write-Host "Device must be booted into RECOVERY mode to continue." -ForegroundColor Cyan
            Write-Host "`nPlease select a method to boot the device into Recovery mode:" -ForegroundColor White
            Write-Host "1. Standard Command (fastboot reboot recovery)"
            Write-Host "2. OEM Command (fastboot oem reboot-recovery)"
            Write-Host "3. Manual (I will put the device into Recovery myself)"
            Write-Host "G. GO BACK (To Selection Screen)" -ForegroundColor DarkCyan
            
            Write-Host ""
            $rbIn = Read-Host "Your choice"
            while ($rbIn -notmatch "^[123gG]$") { 
                try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                $rbIn = Read-Host "Your choice" 
            }
            
            if ($rbIn -match "^[gG]$") { 
                if ($operation -eq "1") { $state = "DUMP_SCAN_DEVICES" } else { $state = "FOLDER_MENU" }
                continue 
            }
            
            $fbRebootArgs = @(); if ($targetSerial) { $fbRebootArgs += "-s"; $fbRebootArgs += $targetSerial }
            
            if ($rbIn -eq "1") { $fbRebootArgs += "reboot"; $fbRebootArgs += "recovery"; & $fb $fbRebootArgs | Out-Null }
            elseif ($rbIn -eq "2") { $fbRebootArgs += "oem"; $fbRebootArgs += "reboot-recovery"; & $fb $fbRebootArgs | Out-Null }
            else { Write-Host "Please put the device into Recovery mode manually..." -ForegroundColor Magenta }
        } else {
            Write-Host "Selected device is currently powered on in ANDROID mode!" -ForegroundColor Yellow
            Write-Host "Device must be booted into RECOVERY mode to continue." -ForegroundColor Cyan
            Write-Host "`nDevice is rebooting into Recovery mode automatically via command..." -ForegroundColor Green
            & $adb -s $targetSerial reboot recovery | Out-Null
        }
        
        Write-Host "`n[!!] PLEASE ATTENTION [!!]" -ForegroundColor Red
        Write-Host "ADB connection may drop and reconnect while Recovery is booting." -ForegroundColor Yellow
        Write-Host "Wait until you CLEARLY and COMPLETELY see the TWRP/OrangeFox menu on the screen." -ForegroundColor Yellow
        
        $fName = if ($selectedFolder) { $selectedFolder.Name } else { "" }
        $waitRes = Wait-TargetDevice -TargetFolder $fName -RequiredMode "RECOVERY" -ActionTitle "Waiting for device in Recovery mode to continue the operation..." -TargetSerial $targetSerial
        
        if ($waitRes -eq "CANCEL") { 
            if ($operation -eq "1") { $state = "DUMP_SCAN_DEVICES" } else { $state = "FOLDER_MENU" }
            continue 
        }
        
        $selectedDevice.IsFastboot = $false
        $selectedDevice.IsRecovery = $true
        $selectedDevice.Serial = $waitRes
        $targetSerial = $waitRes
        
        if ($operation -eq "1") { $state = "ROOT_CHECK" } else { $state = "WRITE_INIT" }
    }

    elseif ($state -eq "ROOT_CHECK") {
        if ($selectedDevice.IsRecovery) {
            Write-Host "`nDevice detected in RECOVERY mode!" -ForegroundColor Green
            Start-Sleep -Seconds 1
            if ($operation -eq "1") { $state = "DUMP_INIT" } else { $state = "WRITE_INIT" }
        }
        elseif ($mode -eq "1" -and $operation -eq "1") {
            Write-Host "`nChecking root access..." -ForegroundColor Cyan
            $rootCheck = (& $adb -s $targetSerial shell su -c id 2>&1) -join "`n"
            if ($rootCheck -match "uid=0") {
                Write-Host "[+] Root access verified successfully!" -ForegroundColor Green
                Start-Sleep -Seconds 1
                $state = "DUMP_INIT"
            } else {
                Write-Host "[-] ERROR: Root access could not be obtained! Please grant permission from the phone." -ForegroundColor Red; pause; if($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"}
            }
        } else {
            if ($operation -eq "1") { $state = "DUMP_INIT" } else { $state = "WRITE_INIT" }
        }
    }

    elseif ($state -eq "DUMP_INIT") {
        Write-Host "`nReading partitions and their sizes..." -ForegroundColor Cyan
        Start-Sleep -Seconds 1
        
        $readSuccess = $false
        
        if ($isSuperMode) {
            $global:lpdumpInfoText = ""
            while (-not $readSuccess) {
                $partitionsRaw = & $adb -s $targetSerial shell "su -c 'lpdump'" 2>&1
                $partitionsRaw = $partitionsRaw -join "`n"
                
                if ($partitionsRaw -match "not found" -or $partitionsRaw -match "offline" -or $partitionsRaw -match "Permission denied") {
                    Write-Host "[-] ERROR: lpdump could not be executed! Device connection might be weak or command is unsupported." -ForegroundColor Red
                    $retryAns = Read-Host "`n[R] Retry | [G] Go Back"
                    if ($retryAns -match "^[gG]$") { $state = "SUPER_MAIN"; break }
                    else { Write-Host "Attempting to reconnect..." -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
                } else { $readSuccess = $true }
            }
            if (-not $readSuccess) { continue }
            
            if ($partitionsRaw -match "Header flags:\s*(.*)") { $global:lpdumpInfoText += "Header Flags: $($Matches[1])`n" }
            
            if ($partitionsRaw -match "Block device table:[\s\S]*?Partition name: super[\s\S]*?Size:\s*(\d+)\s*bytes") {
                $superBytes = [long]$Matches[1]
                $superMB = [math]::Round($superBytes / 1MB, 2)
                $global:lpdumpInfoText += "Super Size: $superBytes Bytes (~$superMB MB)`n"
            }

            $groups = [regex]::Matches($partitionsRaw, "Name:\s*([\w-_]+)\s+Maximum size:\s*(\d+)\s*bytes")
            foreach ($g in $groups) {
                if ($g.Groups[1].Value -ne "default") {
                    $gBytes = [long]$g.Groups[2].Value
                    $gMB = [math]::Round($gBytes / 1MB, 2)
                    $global:lpdumpInfoText += "Group [$($g.Groups[1].Value)] Max Size: $gBytes Bytes (~$gMB MB)`n"
                }
            }
            
            $partNames = @()
            $nameMatches = [regex]::Matches($partitionsRaw, "Name:\s*([\w-_]+)\s+Group:")
            foreach ($m in $nameMatches) { $partNames += $m.Groups[1].Value }
            
            $sizeDict = @{}
            $layoutMatches = [regex]::Matches($partitionsRaw, "super:\s*\d+\s*\.\.\s*\d+:\s*([\w-_]+)\s*\((\d+)\s*sectors\)")
            foreach ($m in $layoutMatches) {
                $pName = $m.Groups[1].Value
                $sectors = [long]$m.Groups[2].Value
                $sizeMB = [math]::Round(($sectors * 512) / 1MB, 2)
                $sizeDict[$pName] = $sizeMB
            }

            $partObjs = @()
            foreach ($p in $partNames) {
                $pSize = if ($sizeDict.ContainsKey($p)) { $sizeDict[$p] } else { 0 }
                if ($pSize -eq 0) { continue }
                
                $isSelected = if ($excluded -contains $p) { $false } else { $true }
                $partObjs += [PSCustomObject]@{ Name = $p; SizeMB = $pSize; Selected = $isSelected }
            }
        } 
        else {
            $shScript = 'cd /dev/block/by-name && for p in *; do echo $p:$(blockdev --getsize64 $p 2>/dev/null); done'
            while (-not $readSuccess) {
                if ($mode -eq "1") { $partitionsRaw = & $adb -s $targetSerial shell "su -c '$shScript'" 2>&1 } 
                else { $partitionsRaw = & $adb -s $targetSerial shell "$shScript" 2>&1 }
                
                $partitionsRaw = $partitionsRaw -join "`n"

                if ([string]::IsNullOrWhiteSpace($partitionsRaw) -or $partitionsRaw -match "Permission denied" -or $partitionsRaw -match "syntax error" -or $partitionsRaw -match "not found" -or $partitionsRaw -match "offline") {
                    Write-Host "[-] ERROR: Partitions could not be read! Device might not be fully booted or missing ADB connection." -ForegroundColor Red
                    $retryAns = Read-Host "`n[R] Retry | [G] Go Back"
                    if ($retryAns -match "^[gG]$") { $state = "MODE"; break }
                    else { Write-Host "Attempting to reconnect..." -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
                } else { $readSuccess = $true }
            }
            if (-not $readSuccess) { continue } 

            $partObjs = @()
            foreach ($line in ($partitionsRaw -split "`n")) {
                $line = $line.Trim()
                if ($line -match "^([\w-]+):(\d*)$") {
                    $pName = $Matches[1]; $pSizeBytes = $Matches[2]
                    if ($pName -match "^mmcblk\d+" -or $pName -match "^sd[a-z]$" -or $pName -match "^loop" -or $pName -match "^ram") { continue }
                    $pSizeMB = if ($pSizeBytes) { [math]::Round([long]$pSizeBytes / 1MB, 2) } else { "Unknown" }
                    $isSelected = if ($excluded -contains $pName) { $false } else { $true }
                    $partObjs += [PSCustomObject]@{ Name = $pName; SizeMB = $pSizeMB; Selected = $isSelected }
                }
            }
        }
        
        if ($partObjs.Count -eq 0) { Write-Host "[-] ERROR: No valid partition found." -ForegroundColor Red; pause; if ($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"}; continue }
        $state = "DUMP_MENU"
    }

    elseif ($state -eq "DUMP_MENU") {
        Show-Header
        
        if ($isSuperMode) {
            Write-Host "--- LPDUMP INFO (partial) (SUPER PARTITION) ---" -ForegroundColor Magenta
            Write-Host $global:lpdumpInfoText -ForegroundColor Yellow
            Write-Host "---------------------------------------" -ForegroundColor Magenta
        }
        
        Write-Host "PARTITIONS TO DUMP:" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        for ($i = 0; $i -lt $partObjs.Count; $i++) {
            $status = if ($partObjs[$i].Selected) { "[X]" } else { "[ ]" }
            $color = if ($partObjs[$i].Selected) { "Cyan" } else { "DarkGray" }
            Write-Host ("{0,3}. {1} {2,-25} : {3} MB" -f ($i+1), $status, $partObjs[$i].Name, $partObjs[$i].SizeMB) -ForegroundColor $color
        }
        
        $hasABSlots = @($partObjs | Where-Object { $_.Name -match '_[ab]$' }).Count -gt 0
        
        Write-Host "`n=================================================" -ForegroundColor Cyan
        $selCount = @($partObjs | Where-Object { $_.Selected }).Count
        $totCount = $partObjs.Count
        Write-Host "   >>> SELECTED PARTITION COUNT : $selCount / $totCount <<<" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        
        if (-not $isSuperMode) {
            Write-Host "NOTE: " -NoNewline -ForegroundColor Red
            Write-Host "Since 'userdata' is an encrypted partition, backing it up " -NoNewline -ForegroundColor Yellow
            Write-Host "DOES NOT GUARANTEE the recovery of your personal data!!!" -ForegroundColor Red
        }
        
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
        Write-Host " -> For multiple selection, use spaces between numbers (e.g., 1 5 12 6)" -ForegroundColor White
        Write-Host " -> Type 'A' to SELECT ALL except userdata." -ForegroundColor Green
        Write-Host " -> Type 'H' to DESELECT ALL (Select none)." -ForegroundColor Green
        Write-Host " -> Type 'D' to return to DEFAULT selections." -ForegroundColor Green
        if ($hasABSlots) { Write-Host " -> Type 'S' to select a slot." -ForegroundColor Magenta }
        Write-Host " -> Type 'G' to GO BACK (To Device Mode Selection)." -ForegroundColor Yellow
        Write-Host ""
        Write-Host " -> Type 'B' to START OPERATION when selections are done." -ForegroundColor Green
        
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "    "
        Write-Host "TARGET DEVICE INFO:" -ForegroundColor Yellow
        Write-Host "Model: $($selectedDevice.Model) | Serial No: $($selectedDevice.Serial)" -ForegroundColor White
        
        $modeStr = if ($isSuperMode) { "Android" } elseif ($mode -eq "1") { "Android" } else { "Recovery" }
        Write-Host "Current Mode : $modeStr" -ForegroundColor DarkCyan
        
        $inputStr = Read-Host "`nYour choice"
        if ($inputStr -match "^[bB]$") { $state = "DUMP_EXECUTE" }
        elseif ($inputStr -match "^[gG]$") { $partObjs = @(); $selectedDevice = $null; $targetSerial = ""; if($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"} }
        elseif ($inputStr -match "^[aA]$") { foreach ($p in $partObjs) { $p.Selected = ($p.Name -ne "userdata") } }
        elseif ($inputStr -match "^[hH]$") { foreach ($p in $partObjs) { $p.Selected = $false } }
        elseif ($inputStr -match "^[dD]$") { foreach ($p in $partObjs) { $p.Selected = -not ($excluded -contains $p.Name) } }
        elseif ($inputStr -match "^[sS]$" -and $hasABSlots) {
            $slotAns = Read-Host "`nWhich slot should remain valid? (Type A / B)"
            if ($slotAns -match "^[aA]$" -or $slotAns -match "^[bB]$") {
                $tgtSlot = $slotAns.ToLower()
                $othSlot = if ($tgtSlot -eq "a") { "b" } else { "a" }
                $allNames = $partObjs | Select-Object -ExpandProperty Name
                
                foreach ($p in $partObjs) {
                    if ($p.Name -match "_$tgtSlot`$") {
                        if ($p.SizeMB -gt 0) { $p.Selected = -not ($excluded -contains $p.Name) }
                    }
                    elseif ($p.Name -match "_$othSlot`$") {
                        $p.Selected = $false
                    }
                    elseif ($p.Name -notmatch "_a`$" -and $p.Name -notmatch "_b`$") {
                        if ($allNames -contains "$($p.Name)_$tgtSlot") {
                            $p.Selected = $false
                        }
                    }
                }
            }
        }
        elseif ($inputStr -match '^[\d\s]+$') {
            $numArr = $inputStr -split '\s+' | Where-Object { $_ -ne "" }
            foreach ($nStr in $numArr) {
                $idx = [int]$nStr - 1
                if ($idx -ge 0 -and $idx -lt $partObjs.Count) { 
                    $partObjs[$idx].Selected = -not $partObjs[$idx].Selected 
                }
            }
        }
    }

    elseif ($state -eq "DUMP_EXECUTE") {
        $selectedPartitions = @($partObjs | Where-Object { $_.Selected })
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nNo partition selected!" -ForegroundColor Red; pause; $state="DUMP_MENU"; continue }

        $devModel = $selectedDevice.Model
        $devSerial = $selectedDevice.Serial
        $timestamp = Get-Date -Format "HHmm_ddMMyyyy"
        
        $folderName = if ($isSuperMode) { "Backup_Super_${devModel}_${devSerial}_$timestamp" } else { "Backup_${devModel}_${devSerial}_$timestamp" }
        $backupDir = Join-Path $PSScriptRoot $folderName
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

        Show-Header
        Write-Host "Target Folder: $folderName" -ForegroundColor Cyan
        
        $sArg = if ($targetSerial) { "-s $targetSerial" } else { "" }
        $successCount = 0; $failCount = 0

        foreach ($p in $selectedPartitions) {
            $pName = $p.Name
            $outFile = Join-Path $backupDir "$pName.img"
            
            $devCheck = & $adb $sArg get-state 2>&1
            if ($devCheck -match "offline" -or $devCheck -match "not found") {
                Write-Host "`n[-] CRITICAL ERROR: Device connection lost (Offline/Not Found)!" -ForegroundColor Red
                Write-Host "Canceling remaining operations..." -ForegroundColor Yellow
                $failCount++
                break
            }

            if ($isSuperMode) {
                $getBlkCmd = "realpath /dev/block/mapper/$pName 2>/dev/null || echo /dev/block/mapper/$pName"
            } else {
                $getBlkCmd = "realpath /dev/block/by-name/$pName 2>/dev/null || readlink -f /dev/block/by-name/$pName"
            }

            if ($mode -eq "1") { $realBlkRaw = cmd /c "`"$adb`" $sArg shell su -c `"$getBlkCmd`"" } 
            else { $realBlkRaw = cmd /c "`"$adb`" $sArg shell `"$getBlkCmd`"" }
            
            $realBlkRaw = $realBlkRaw -join ""
            $realBlk = if (-not [string]::IsNullOrWhiteSpace($realBlkRaw)) { $realBlkRaw.Trim() } else { "" }

            if (-not [string]::IsNullOrWhiteSpace($realBlk) -and ($realBlk -match "^/dev/block" -or $isSuperMode)) {
                $dumpSuccess = $false
                if ($mode -eq "2") {
                    Write-Host "`n[DUMPING] -> $pName ($($p.SizeMB) MB) [Mode: Recovery / ADB Pull]" -ForegroundColor Green
                    $pullOut = cmd /c "`"$adb`" $sArg pull `"$realBlk`" `"$outFile`"" 2>&1
                    if ($pullOut -match "error:" -or $pullOut -match "offline" -or $pullOut -match "failed" -or $pullOut -match "not found") {
                        Write-Host "   [-] ERROR: Pull operation failed or partition is unmounted!" -ForegroundColor Red
                        Write-Host "   >>> Log: $pullOut" -ForegroundColor DarkGray
                    } else { $dumpSuccess = $true }
                } 
                else {
                    Write-Host "`n[DUMPING] -> $pName ($($p.SizeMB) MB) [Mode: Android / GZip Base64 Transfer]" -ForegroundColor Green
                    
                    $b64File = "$outFile.b64"
                    $gzFile = "$outFile.gz"
                    
                    Write-Host "   -> Archiving and converting to text on Android..." -ForegroundColor DarkYellow
                    $ddOut = cmd /c "`"$adb`" $sArg exec-out `"su -c 'dd if=$realBlk 2>/dev/null | gzip -1 -c | base64'`" > `"$b64File`"" 2>&1
                    
                    $b64FileInfo = Get-Item $b64File -ErrorAction SilentlyContinue
                    if ($ddOut -match "error:" -or $ddOut -match "offline" -or $ddOut -match "not found" -or -not $b64FileInfo -or $b64FileInfo.Length -eq 0) {
                        Write-Host "   [-] ERROR: Data could not be read or device connection lost!" -ForegroundColor Red
                        if (-not [string]::IsNullOrWhiteSpace($ddOut)) { Write-Host "   >>> Log: $ddOut" -ForegroundColor DarkGray }
                    } else {
                        Write-Host "   -> Converting back to file on Windows..." -ForegroundColor DarkYellow
                        cmd /c "certutil -decode `"$b64File`" `"$gzFile`" 2>&1" | Out-Null
                        
                        Write-Host "   -> Extracting to Raw Image (IMG) File..." -ForegroundColor DarkYellow
                        try {
                            $inputStr = New-Object System.IO.FileStream $gzFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
                            $outputStr = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
                            $gzipStream = New-Object System.IO.Compression.GZipStream $inputStr, ([IO.Compression.CompressionMode]::Decompress)
                            $gzipStream.CopyTo($outputStr)
                            $gzipStream.Close(); $inputStr.Close(); $outputStr.Close()
                            $dumpSuccess = $true
                        } catch {
                            Write-Host "   [-] ERROR: Archive could not be extracted! File might be corrupted." -ForegroundColor Red
                        }
                    }
                    Remove-Item $b64File -ErrorAction SilentlyContinue
                    Remove-Item $gzFile -ErrorAction SilentlyContinue
                }
                if ($dumpSuccess) { $successCount++ } else { $failCount++ }
            } else {
                Write-Host "`n   [-] ERROR: No valid path found for '$pName' partition! (Path: '$realBlk')" -ForegroundColor Red
                $failCount++
            }
        }
        
        Write-Host "`n=================================================" -ForegroundColor Cyan
        if ($failCount -eq 0) {
            Write-Host "OPERATION COMPLETED! All backup files were successfully saved in the '$folderName' folder." -ForegroundColor Green
        } elseif ($successCount -gt 0) {
            Write-Host "OPERATION PARTIALLY COMPLETED! $successCount successful, $failCount failed operations." -ForegroundColor Yellow
            Write-Host "Files are in '$folderName' folder." -ForegroundColor Yellow
        } else {
            Write-Host "OPERATION FAILED! Device connection lost or no partitions could be fetched." -ForegroundColor Red
        }
        pause; $state = "MAIN"
    }

    elseif ($state -eq "WRITE_INIT") {
        $imgFiles = @(Get-ChildItem -Path $selectedFolder.FullName -Filter "*.img")
        if ($imgFiles.Count -eq 0) { Write-Host "[-] ERROR: No .img files found in the selected folder!" -ForegroundColor Red; pause; $state = "FOLDER_MENU"; continue }
        $imgNames = $imgFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }

        $partObjs = @()
        
        if ($isSuperMode) {
            Write-Host "`nGenerating Super partition list from backup folder (FastbootD Mode)..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2
            
            foreach ($img in $imgFiles) {
                $pName = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
                $pSizeMB = [math]::Round($img.Length / 1MB, 2)
                $isSelected = if ($excluded -contains $pName) { $false } else { $true }
                $partObjs += [PSCustomObject]@{ Name = $pName; SizeMB = $pSizeMB; Selected = $isSelected; HasImage = $true; FilePath = $img.FullName }
            }
            $state = "WRITE_MENU"
        }
        elseif ($selectedDevice.IsFastboot -or ($operation -eq "2" -and $mode -eq "1")) {
            Write-Host "`nGenerating partition list from backup folder (Hybrid/Fastboot Mode)..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2
            
            foreach ($img in $imgFiles) {
                $pName = [System.IO.Path]::GetFileNameWithoutExtension($img.Name)
                if ($pName -match "^mmcblk\d+" -or $pName -match "^sd[a-z]$" -or $pName -match "^loop" -or $pName -match "^ram") { continue }
                $pSizeMB = [math]::Round($img.Length / 1MB, 2)
                $isSelected = if ($excluded -contains $pName) { $false } else { $true }
                $partObjs += [PSCustomObject]@{ Name = $pName; SizeMB = $pSizeMB; Selected = $isSelected; HasImage = $true; FilePath = $img.FullName }
            }
            $state = "WRITE_MENU"
        } else {
            Write-Host "`nReading device partitions..." -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            
            $shScript = 'cd /dev/block/by-name && for p in *; do echo $p; done'
            
            $readSuccess = $false
            while (-not $readSuccess) {
                $partitionsRaw = & $adb shell "$shScript" 2>&1
                $partitionsRaw = $partitionsRaw -join "`n"
                
                if ([string]::IsNullOrWhiteSpace($partitionsRaw) -or $partitionsRaw -match "Permission denied" -or $partitionsRaw -match "syntax error" -or $partitionsRaw -match "not found" -or $partitionsRaw -match "offline") {
                    Write-Host "[-] ERROR: Partitions could not be read! Device might not be fully booted or missing ADB connection." -ForegroundColor Red
                    $retryAns = Read-Host "`n[R] Retry | [G] Go Back"
                    if ($retryAns -match "^[gG]$") { $state = "FOLDER_MENU"; break }
                    else { Write-Host "Attempting to reconnect..." -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
                } else { $readSuccess = $true }
            }
            if (-not $readSuccess) { continue } 
            
            foreach ($line in ($partitionsRaw -split "`n")) {
                $pName = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($pName)) { continue }
                if ($pName -match "^mmcblk\d+" -or $pName -match "^sd[a-z]$" -or $pName -match "^loop" -or $pName -match "^ram") { continue }
                
                $hasImage = $imgNames -contains $pName
                if ($hasImage) {
                    $fileInfo = $imgFiles | Where-Object { $_.Name -eq "$pName.img" }
                    $pSizeMB = [math]::Round($fileInfo.Length / 1MB, 2)
                    $isSelected = if ($excluded -contains $pName) { $false } else { $true }
                    $filePath = $fileInfo.FullName
                } else {
                    $pSizeMB = "YOK"; $isSelected = $false; $filePath = $null
                }
                $partObjs += [PSCustomObject]@{ Name = $pName; SizeMB = $pSizeMB; Selected = $isSelected; HasImage = $hasImage; FilePath = $filePath }
            }
            $state = "WRITE_MENU"
        }

        if ($partObjs.Count -eq 0) { Write-Host "[-] ERROR: Images in the folder did not match the partitions on the device!" -ForegroundColor Red; pause; $state = "FOLDER_MENU"; continue }
    }

    elseif ($state -eq "WRITE_MENU") {
        Show-Header
        
        Write-Host "FOLDER TO FLASH: $($selectedFolder.Name)" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $partObjs.Count; $i++) {
            if ($partObjs[$i].HasImage) {
                $status = if ($partObjs[$i].Selected) { "[X]" } else { "[ ]" }
                $color = if ($partObjs[$i].Selected) { "Green" } else { "DarkGray" }
                Write-Host ("{0,3}. {1} {2,-25} : {3} MB" -f ($i+1), $status, $partObjs[$i].Name, $partObjs[$i].SizeMB) -ForegroundColor $color
            } else {
                Write-Host ("{0,3}. [-] {1,-25} : " -f ($i+1), $partObjs[$i].Name) -NoNewline -ForegroundColor DarkGray
                Write-Host "NO FILE" -ForegroundColor Red
            }
        }

        $hasABSlots = @($partObjs | Where-Object { $_.Name -match '_[ab]$' }).Count -gt 0

        Write-Host "`n=================================================" -ForegroundColor Cyan
        $selCount = @($partObjs | Where-Object { $_.Selected }).Count
        $totCount = $partObjs.Count
        Write-Host "   >>> SELECTED PARTITION COUNT : $selCount / $totCount <<<" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan

        Write-Host "!!! VERY IMPORTANT WARNING !!!" -ForegroundColor Magenta
        Write-Host "THIS OPERATION IS RISKY! Device can brick due to connection loss or incorrect partition writing. IMEI, serial no, etc." -ForegroundColor Yellow
        Write-Host "information might be lost. If your device has no recovery options like edl/bootrom/bootloader, it" -ForegroundColor Yellow
        Write-Host "might become unrecoverable." -ForegroundColor Yellow
        
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
        Write-Host " -> For multiple selection, use spaces between numbers (e.g., 1 5 12 6)" -ForegroundColor White 
        Write-Host " -> Type 'A' to SELECT ALL IMGs with available files." -ForegroundColor Green
        Write-Host " -> Type 'H' to DESELECT ALL (Select none)." -ForegroundColor Green
        Write-Host " -> Type 'D' to return to DEFAULT selections." -ForegroundColor Green
        if ($hasABSlots) { Write-Host " -> Type 'S' to select a slot." -ForegroundColor Magenta }
        Write-Host " -> Type 'G' to GO BACK (To Folder Selection)." -ForegroundColor Yellow
        
        Write-Host ""
        if ($isSuperMode) {
            Write-Host " -> Type 'F' to WRITE WITH FASTBOOTD ONLY." -ForegroundColor Magenta
        } elseif ($mode -eq "1") {
            Write-Host " -> Type 'F' for FASTBOOT (HYBRID) QUICK WRITE (Advanced)." -ForegroundColor Magenta
        } else {
            Write-Host " -> Type 'B' for STANDARD WRITE WITH DD." -ForegroundColor Red
        }
        
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "   "
        Write-Host "TARGET DEVICE INFO:" -ForegroundColor Yellow
        Write-Host "Model: $($selectedDevice.Model) | Serial No: $($selectedDevice.Serial)" -ForegroundColor White
        
        $modeStr = if ($isSuperMode) { "FastbootD (Super Yazma)" } elseif ($mode -eq "1") { "Bootloader-Recovery Hybrid" } else { "Recovery Mode" }
        Write-Host "Current Mode : $modeStr`nSelected Folder: $($selectedFolder.Name)" -ForegroundColor DarkCyan
        
        if ($warningMessage -ne "") { Write-Host "`n>>> $warningMessage <<<" -ForegroundColor Yellow; $warningMessage = "" }

        $inputStr = Read-Host "`nYour choice"
        if ($inputStr -match "^[bB]$" -and $mode -eq "2" -and -not $isSuperMode) { $state = "WRITE_EXECUTE_DD" }
        elseif ($inputStr -match "^[fF]$" -and ($mode -eq "1" -or $isSuperMode)) { 
            if ($isSuperMode) { $state = "WRITE_EXECUTE_SUPER" } else { $state = "WRITE_EXECUTE_FASTBOOT" }
        }
        elseif ($inputStr -match "^[gG]$") { $partObjs = @(); $selectedDevice = $null; $targetSerial = ""; $warningMessage = ""; $state = "FOLDER_MENU" }
        elseif ($inputStr -match "^[aA]$") { foreach ($p in $partObjs) { if ($p.HasImage) { $p.Selected = $true } } }
        elseif ($inputStr -match "^[hH]$") { foreach ($p in $partObjs) { if ($p.HasImage) { $p.Selected = $false } } }
        elseif ($inputStr -match "^[dD]$") { foreach ($p in $partObjs) { if ($p.HasImage) { $p.Selected = -not ($excluded -contains $p.Name) } } }
        elseif ($inputStr -match "^[sS]$" -and $hasABSlots) {
            $slotAns = Read-Host "`nWhich slot should remain valid? (Type A / B)"
            if ($slotAns -match "^[aA]$" -or $slotAns -match "^[bB]$") {
                $tgtSlot = $slotAns.ToLower()
                $othSlot = if ($tgtSlot -eq "a") { "b" } else { "a" }
                $allNames = $partObjs | Select-Object -ExpandProperty Name
                
                foreach ($p in $partObjs) {
                    if ($p.Name -match "_$tgtSlot`$") {
                        if ($p.HasImage) { $p.Selected = -not ($excluded -contains $p.Name) }
                    }
                    elseif ($p.Name -match "_$othSlot`$") {
                        $p.Selected = $false
                    }
                    elseif ($p.Name -notmatch "_a`$" -and $p.Name -notmatch "_b`$") {
                        if ($allNames -contains "$($p.Name)_$tgtSlot") {
                            $p.Selected = $false
                        }
                    }
                }
            }
        }
        elseif ($inputStr -match '^[\d\s]+$') {
            $numArr = $inputStr -split '\s+' | Where-Object { $_ -ne "" }
            $warnFlag = $false
            foreach ($nStr in $numArr) {
                $idx = [int]$nStr - 1
                if ($idx -ge 0 -and $idx -lt $partObjs.Count) { 
                    if ($partObjs[$idx].HasImage) { 
                        $partObjs[$idx].Selected = -not $partObjs[$idx].Selected 
                    } else { 
                        $warnFlag = $true 
                    }
                }
            }
            if ($warnFlag) { $warningMessage = "WARNING: Backup files for some selected partitions could not be found, those partitions were skipped!" }
        }
    }

    elseif ($state -eq "WRITE_EXECUTE_SUPER") {
        $selectedPartitions = @($partObjs | Where-Object { $_.Selected })
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nNo partition selected!" -ForegroundColor Red; pause; $state="WRITE_MENU"; continue }

        Show-Header
        Write-Host "FASTBOOTD WRITE OPERATION STARTING... PLEASE DO NOT UNPLUG THE CABLE!" -ForegroundColor Red
        
        $successCount = 0; $failCount = 0

        foreach ($p in $selectedPartitions) {
            $pName = $p.Name; $inFile = $p.FilePath
            
            Write-Host "[FASTBOOTD] -> $pName flashing ($($p.SizeMB) MB) ..." -ForegroundColor Yellow
            $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
            $fbArgs += "flash"; $fbArgs += $pName; $fbArgs += $inFile
            
            $fbOutput = (& $fb $fbArgs 2>&1) -join "`n"
            
            if ($fbOutput -match "FAILED" -or $fbOutput -match "error:") {
                Write-Host "   [-] ERROR: Write operation failed!" -ForegroundColor Red
                Write-Host "   >>> Log: $fbOutput" -ForegroundColor DarkGray
                $failCount++
            } else {
                Write-Host "   [+] Successfully sent!`n" -ForegroundColor DarkCyan
                $successCount++
            }
        }
        
        Write-Host "=======================================" -ForegroundColor Cyan
        if ($failCount -eq 0) {
            Write-Host "ALL SUPER WRITE OPERATIONS COMPLETED SUCCESSFULLY!" -ForegroundColor Green
        } elseif ($successCount -gt 0) {
            Write-Host "OPERATION PARTIALLY COMPLETED! $successCount successful, $failCount failed write operations." -ForegroundColor Yellow
        } else {
            Write-Host "OPERATION FAILED! FastbootD error occurred." -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 2
        $state = "WRITE_POST_ACTION"
    }

    elseif ($state -eq "WRITE_EXECUTE_DD") {
        $selectedPartitions = @($partObjs | Where-Object { $_.Selected })
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nNo partition selected!" -ForegroundColor Red; pause; $state="WRITE_MENU"; continue }

        Show-Header
        Write-Host "WRITE OPERATION STARTING... PLEASE DO NOT UNPLUG THE CABLE!" -ForegroundColor Red
        
        $sArg = if ($targetSerial) { "-s $targetSerial" } else { "" }
        $successCount = 0; $failCount = 0

        foreach ($p in $selectedPartitions) {
            $pName = $p.Name; $inFile = $p.FilePath
            
            $devCheck = & $adb $sArg get-state 2>&1
            if ($devCheck -match "offline" -or $devCheck -match "not found") {
                Write-Host "`n[-] CRITICAL ERROR: Device connection lost!" -ForegroundColor Red
                $failCount++
                break
            }

            Write-Host "[DD WRITING] -> $pName writing ($($p.SizeMB) MB) ..." -ForegroundColor Yellow
            
            $ddOut = cmd /c "`"$adb`" $sArg exec-in dd of=/dev/block/by-name/$pName bs=4M < `"$inFile`"" 2>&1
            
            if ($ddOut -match "error:" -or $ddOut -match "offline") {
                Write-Host "   [-] ERROR: Write operation failed or connection lost!" -ForegroundColor Red
                if (-not [string]::IsNullOrWhiteSpace($ddOut)) { Write-Host "   >>> Log: $ddOut" -ForegroundColor DarkGray }
                $failCount++
            } else {
                Write-Host "   Successfully sent!`n" -ForegroundColor DarkCyan
                $successCount++
            }
        }
        
        Write-Host "=======================================" -ForegroundColor Cyan
        if ($failCount -eq 0) { Write-Host "ALL WRITE OPERATIONS COMPLETED SUCCESSFULLY!" -ForegroundColor Green } 
        elseif ($successCount -gt 0) { Write-Host "OPERATION PARTIALLY COMPLETED! $successCount successful, $failCount failed write operations." -ForegroundColor Yellow } 
        else { Write-Host "OPERATION FAILED! Device connection lost." -ForegroundColor Red }
        
        Start-Sleep -Seconds 2
        $state = "WRITE_POST_ACTION"
    }

    elseif ($state -eq "WRITE_EXECUTE_FASTBOOT") {
        $selectedPartitions = @($partObjs | Where-Object { $_.Selected })
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nNo partition selected!" -ForegroundColor Red; pause; $state="WRITE_MENU"; continue }

        Show-Header
        Write-Host "!!! IMPORTANT NOTIFICATION !!!" -ForegroundColor Magenta
        Write-Host "This mode SWITCHES to a Custom Recovery with ADB access in the second stage" -ForegroundColor Yellow
        Write-Host "to compensate for partitions that cannot be written via fastboot (e.g. TWRP, OrangeFox)." -ForegroundColor Yellow
        Write-Host "When the Fastboot stage is finished, your device must have a Custom Recovery installed." -ForegroundColor Yellow
        
        Write-Host ""
        $fbConf = Read-Host "Do you want to continue? (Y/N)"
        while ($fbConf -notmatch "^[yYnN]$") { 
            try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
            $fbConf = Read-Host "Do you want to continue? (Y/N)" 
        }
        if ($fbConf -match "^[nN]$") { $state = "WRITE_MENU"; continue }

        if (-not $selectedDevice.IsFastboot) {
            Show-Header
            Write-Host "Switching device to Bootloader (Fastboot) mode..." -ForegroundColor Cyan
            & $adb -s $targetSerial reboot bootloader | Out-Null
            
            $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Waiting for device in Fastboot mode to start the operation..." -TargetSerial $targetSerial
            if ($waitRes -eq "CANCEL") { $state = "MAIN"; continue }
            $targetSerial = $waitRes
            $selectedDevice.IsFastboot = $true
            $selectedDevice.IsRecovery = $false
        } else {
            $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Verifying target device..." -TargetSerial $targetSerial
            if ($waitRes -eq "CANCEL") { $state = "MAIN"; continue }
            $targetSerial = $waitRes
        }
        
        $failedPartitions = @()
        $successCount = 0; $failCount = 0
        
        Write-Host "`n================ FASTBOOT STAGE ================" -ForegroundColor Cyan
        foreach ($p in $selectedPartitions) {
            $pName = $p.Name; $inFile = $p.FilePath
            Write-Host "[FASTBOOT] -> $pName flashing..." -ForegroundColor Yellow
            
            $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
            $fbArgs += "flash"; $fbArgs += $pName; $fbArgs += $inFile
            
            $fbOutput = (& $fb $fbArgs 2>&1) -join "`n"
            
            if ($fbOutput -match "FAILED" -or $fbOutput -match "error:") {
                Write-Host "   [!] BLOCKED: $pName (Lock/Verification Protection). Queued for DD Fallback!" -ForegroundColor DarkYellow
                Write-Host "   >>> Log: $fbOutput" -ForegroundColor DarkGray
                $failedPartitions += $p
            } else { 
                Write-Host "   [+] Successful!" -ForegroundColor Green 
                $successCount++
            }
        }
        
        if ($failedPartitions.Count -gt 0) {
            Write-Host "`n================ RECOVERY STAGE ================" -ForegroundColor Cyan
            Write-Host "$($failedPartitions.Count) partitions are locked via Fastboot or missing." -ForegroundColor Magenta
            Write-Host "You need to switch to Recovery Mode for unwritten partitions!" -ForegroundColor Yellow
            
            Write-Host "`nPlease select a method to boot the device into Recovery mode:" -ForegroundColor White
            Write-Host "1. Standard Command (fastboot reboot recovery)"
            Write-Host "2. OEM Command (fastboot oem reboot-recovery)"
            Write-Host "3. Manual (I will put the device into Recovery myself)"
            
            Write-Host ""
            $rbIn = Read-Host "Your choice"
            while ($rbIn -notmatch "^[123]$") { 
                try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                $rbIn = Read-Host "Your choice" 
            }
            
            $fbRebootArgs = @(); if ($targetSerial) { $fbRebootArgs += "-s"; $fbRebootArgs += $targetSerial }
            
            if ($rbIn -eq "1") { $fbRebootArgs += "reboot"; $fbRebootArgs += "recovery"; & $fb $fbRebootArgs | Out-Null }
            elseif ($rbIn -eq "2") { $fbRebootArgs += "oem"; $fbRebootArgs += "reboot-recovery"; & $fb $fbRebootArgs | Out-Null }
            else { Write-Host "Please put the device into Recovery mode manually..." -ForegroundColor Magenta }
            
            Write-Host "`n[!!] PLEASE ATTENTION [!!]" -ForegroundColor Red
            Write-Host "ADB connection may drop and reconnect while Recovery is booting." -ForegroundColor Yellow
            
            $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "RECOVERY" -ActionTitle "Waiting for device in Recovery mode for DD Fallback operation..." -TargetSerial $targetSerial
            if ($waitRes -eq "CANCEL") { $state = "MAIN"; continue }
            $newSerial = $waitRes
            
            $selectedDevice.IsFastboot = $false
            $selectedDevice.IsRecovery = $true
            $targetSerial = $newSerial
            
            foreach ($p in $failedPartitions) {
                $pName = $p.Name; $inFile = $p.FilePath
                
                $devCheck = & $adb -s $targetSerial get-state 2>&1
                if ($devCheck -match "offline" -or $devCheck -match "not found") {
                    Write-Host "`n[-] CRITICAL ERROR: Device connection lost!" -ForegroundColor Red
                    $failCount++
                    break
                }
                
                Write-Host "[DD FALLBACK] -> $pName writing..." -ForegroundColor Yellow
                $ddOut = cmd /c "`"$adb`" -s $targetSerial exec-in dd of=/dev/block/by-name/$pName bs=4M < `"$inFile`"" 2>&1
                
                if ($ddOut -match "error:" -or $ddOut -match "offline") {
                    Write-Host "   [-] ERROR: Write failed!" -ForegroundColor Red
                    if (-not [string]::IsNullOrWhiteSpace($ddOut)) { Write-Host "   >>> Log: $ddOut" -ForegroundColor DarkGray }
                    $failCount++
                } else {
                    Write-Host "   [+] Written with DD!" -ForegroundColor DarkCyan
                    $successCount++
                }
            }
            Write-Host "`n=======================================" -ForegroundColor Cyan
            if ($failCount -eq 0) { Write-Host "HYBRID FLASHING COMPLETED SUCCESSFULLY!" -ForegroundColor Green } 
            else { Write-Host "OPERATION PARTIALLY COMPLETED! $successCount successful, $failCount failed write operations." -ForegroundColor Yellow }
        } else {
            Write-Host "`n=======================================" -ForegroundColor Cyan
            Write-Host "All partitions completely written via Fastboot!" -ForegroundColor Green
        }

        Start-Sleep -Seconds 2
        $state = "WRITE_POST_ACTION"
    }

    elseif ($state -eq "WRITE_POST_ACTION") {
        while ($true) {
            Clear-Host
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host "           WRITE OPERATIONS COMPLETED            " -ForegroundColor Green
            Write-Host "=================================================" -ForegroundColor Cyan
            
            $hasABSlots = @($partObjs | Where-Object { $_.Name -match '_[ab]$' }).Count -gt 0
            
            if ($hasABSlots -and -not $slotChanged) {
                Write-Host "`nA/B slot architecture detected on this device." -ForegroundColor DarkCyan
                
                $actAns = Read-Host "Do you want to change the 'Active Slot' of the device? (Y/N)"
                while ($actAns -notmatch "^[yYnN]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $actAns = Read-Host "Do you want to change the 'Active Slot' of the device? (Y/N)" 
                }
                
                if ($actAns -match "^[yY]$") {
                    if (-not $selectedDevice.IsFastboot) {
                        Write-Host "`nSwitching device to Fastboot mode..." -ForegroundColor Yellow
                        & $adb -s $targetSerial reboot bootloader | Out-Null
                        
                        $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Waiting for device in Fastboot mode for slot change..." -TargetSerial $targetSerial
                        if ($waitRes -ne "CANCEL") {
                            $targetSerial = $waitRes
                            $selectedDevice.IsFastboot = $true
                            $selectedDevice.IsRecovery = $false
                        }
                    }
                    
                    if ($selectedDevice.IsFastboot) {
                        $writtenA = @($selectedPartitions | Where-Object { $_.Name -match "_a`$" }).Count
                        $writtenB = @($selectedPartitions | Where-Object { $_.Name -match "_b`$" }).Count
                        
                        if ($writtenA -gt 0 -and $writtenB -eq 0) { Write-Host "`nHINT: The flashed backup files only contained slot 'A'." -ForegroundColor Magenta } 
                        elseif ($writtenB -gt 0 -and $writtenA -eq 0) { Write-Host "`nHINT: The flashed backup files only contained slot 'B'." -ForegroundColor Magenta }
                        
                        Write-Host ""
                        $slotAns = Read-Host "Which slot should be made active? (A / B)"
                        while ($slotAns -notmatch "^[aAbB]$") { 
                            try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                            $slotAns = Read-Host "Which slot should be made active? (A / B)" 
                        }
                        $tgtSlot = $slotAns.ToLower()
                        
                        Write-Host "`nSetting active slot to $tgtSlot..." -ForegroundColor Yellow
                        $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
                        $fbArgs += "set_active"; $fbArgs += $tgtSlot
                        
                        $fbOut = (& $fb $fbArgs 2>&1) -join "`n"
                        if ($fbOut -match "OKAY" -or $fbOut -match "Finished") { Write-Host "[+] Successful! Active slot set to '$tgtSlot'." -ForegroundColor Green } 
                        else {
                            Write-Host "[-] ERROR: Slot could not be changed!" -ForegroundColor Red
                            Write-Host "   >>> Log: $fbOut" -ForegroundColor DarkGray
                        }
                        Start-Sleep -Seconds 2
                        $slotChanged = $true 
                    }
                } else { $slotChanged = $true }
                continue 
            }
            
            Write-Host "`nCurrent device status: " -NoNewline -ForegroundColor White
            if ($selectedDevice.IsFastboot) { Write-Host "[FASTBOOT/FASTBOOTD]" -ForegroundColor Yellow } else { Write-Host "[ADB/RECOVERY]" -ForegroundColor Green }
            
            Write-Host "`n================ REBOOT & EXTRA MENU ================" -ForegroundColor Cyan
            if ($selectedDevice.IsFastboot) {
                Write-Host "1. Boot System (fastboot reboot)"
                Write-Host "2. Standard Recovery (fastboot reboot recovery)"
                Write-Host "3. OEM Recovery (fastboot oem reboot-recovery)"
                Write-Host "4. Wipe Device (fastboot -w)" -ForegroundColor Magenta
                Write-Host "5. Return to Main Menu"
                
                Write-Host ""
                $rbIn = Read-Host "Your choice"
                while ($rbIn -notmatch "^[12345]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $rbIn = Read-Host "Your choice" 
                }
                
                if ($rbIn -eq "5") { $state = "MAIN"; break }
                
                $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
                
                if ($rbIn -eq "1") { $fbArgs += "reboot"; & $fb $fbArgs | Out-Null; Write-Host "Booting system..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "2") { $fbArgs += "reboot"; $fbArgs += "recovery"; & $fb $fbArgs | Out-Null; Write-Host "Opening recovery..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "3") { $fbArgs += "oem"; $fbArgs += "reboot-recovery"; & $fb $fbArgs | Out-Null; Write-Host "Opening recovery..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "4") {
                    Write-Host "`n[!] WARNING: This operation will wipe ALL DATA on the device!" -ForegroundColor Red
                    
                    $wipeAns = Read-Host "Are you sure? (Y/N)"
                    while ($wipeAns -notmatch "^[yYnN]$") { 
                        try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                        $wipeAns = Read-Host "Are you sure? (Y/N)" 
                    }
                    
                    if ($wipeAns -match "^[yY]$") {
                        Write-Host "`nWiping data (fastboot -w)..." -ForegroundColor Yellow
                        $wipeArgs = @(); if ($targetSerial) { $wipeArgs += "-s"; $wipeArgs += $targetSerial }
                        $wipeArgs += "-w"
                        $wipeOut = (& $fb $wipeArgs 2>&1) -join "`n"
                        
                        Write-Host "   >>> Log: $wipeOut" -ForegroundColor DarkGray
                        
                        if ($wipeOut -match "error" -or $wipeOut -match "FAILED") { Write-Host "[-] Wipe failed!" -ForegroundColor Red } 
                        else { Write-Host "[+] Device wiped successfully!" -ForegroundColor Green }
                        Read-Host "`nPress ENTER to return to menu"
                    }
                }
            } else {
                Write-Host "1. Boot System (adb reboot)"
                Write-Host "2. Recovery (adb reboot recovery)"
                Write-Host "3. Bootloader (adb reboot bootloader)"
                Write-Host "4. Wipe Device (fastboot -w)" -ForegroundColor Magenta
                Write-Host "5. Return to Main Menu"
                
                Write-Host ""
                $rbIn = Read-Host "Your choice"
                while ($rbIn -notmatch "^[12345]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $rbIn = Read-Host "Your choice" 
                }
                
                if ($rbIn -eq "5") { $state = "MAIN"; break }
                
                if ($rbIn -eq "1") { & $adb -s $targetSerial reboot | Out-Null; Write-Host "Booting system..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "2") { & $adb -s $targetSerial reboot recovery | Out-Null; Write-Host "Opening recovery..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "3") { & $adb -s $targetSerial reboot bootloader | Out-Null; Write-Host "Opening bootloader..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "4") {
                    Write-Host "`n[!] WARNING: This operation will wipe ALL DATA on the device!" -ForegroundColor Red
                    
                    $wipeAns = Read-Host "Are you sure? (Y/N)"
                    while ($wipeAns -notmatch "^[yYnN]$") { 
                        try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                        $wipeAns = Read-Host "Are you sure? (Y/N)" 
                    }
                    
                    if ($wipeAns -match "^[yY]$") {
                        Write-Host "`nSwitching device to Fastboot mode..." -ForegroundColor Yellow
                        & $adb -s $targetSerial reboot bootloader | Out-Null
                        
                        $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Waiting for Fastboot for wipe..." -TargetSerial $targetSerial
                        if ($waitRes -ne "CANCEL") {
                            $targetSerial = $waitRes
                            $selectedDevice.IsFastboot = $true
                            $selectedDevice.IsRecovery = $false
                            
                            Write-Host "`nWiping data (fastboot -w)..." -ForegroundColor Yellow
                            $wipeArgs = @(); if ($targetSerial) { $wipeArgs += "-s"; $wipeArgs += $targetSerial }
                            $wipeArgs += "-w"
                            $wipeOut = (& $fb $wipeArgs 2>&1) -join "`n"
                            
                            Write-Host "   >>> Log: $wipeOut" -ForegroundColor DarkGray
                            
                            if ($wipeOut -match "error" -or $wipeOut -match "FAILED") { Write-Host "[-] Wipe failed!" -ForegroundColor Red } 
                            else { Write-Host "[+] Device wiped successfully!" -ForegroundColor Green }
                        }
                        Read-Host "`nPress ENTER to return to menu"
                    }
                }
            }
        }
    }
}
