<#
.SYNOPSIS
V50: Ghost Watcher Edition (Process Kill Patch)
     - (X) ile kapatilsa bile arkada calisan ADB/Fastboot exe'lerini zorla kapatir ve siler.
     - WinRAR/7-Zip SFX uyumlu.
     - Sadece Seri No odaklı klasör filtreleme (Strict).
     - Android modunda Super Dump kısıtlaması.
     - Gelişmiş Çoklu Seçim (Multi-Select).
     - 0 MB boş bölümler tamamen gizlendi.
#>

Set-Location -Path $PSScriptRoot
$Host.UI.RawUI.WindowTitle = "Advanced Partition Dumper & Writer V50"

# ARAÇLARIN GÖRECELİ YOLLARI (Relative Paths)
$adb = Join-Path $PSScriptRoot "platform-tools_APDWT\adb.exe"
$fb = Join-Path $PSScriptRoot "platform-tools_APDWT\fastboot.exe"
$toolsDir = Join-Path $PSScriptRoot "platform-tools_APDWT"
$currentScript = $PSCommandPath

# HAYALET GÖZCÜ (GHOST WATCHER) - (X) İLE KAPATILMAYA KARŞI %100 KORUMA
if (-not $env:WATCHER_ACTIVE) {
    $env:WATCHER_ACTIVE = "1"
    # YENİ: Wait-Process bittikten sonra ADB ve Fastboot'u zorla kapat (Stop-Process) ve kilidin açılması için 1 saniye bekle
    $watcherScript = "Wait-Process -Id $PID; Stop-Process -Name 'adb', 'fastboot' -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1; Remove-Item -Path '$toolsDir' -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -Path '$currentScript' -Force -ErrorAction SilentlyContinue"
    $encodedWatcher = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($watcherScript))
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedWatcher"
}

# TEMİZLİK VE NORMAL ÇIKIŞ FONKSİYONU
function Cleanup-And-Exit {
    Write-Host "`nAraclar ve gecici dosyalar temizleniyor... Lutfen bekleyin." -ForegroundColor DarkGray
    
    # YENİ: ADB Sunucusunu düzgünce kapat, ardından garanti olsun diye işlemleri zorla öldür
    if (Test-Path $adb) { & $adb kill-server 2>$null }
    Stop-Process -Name 'adb', 'fastboot' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1 # Dosya kilitlerinin serbest kalması için kısa bir bekleme
    
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

# AKILLI BEKCI MODULU (SADECE SERI NO ESLESMESI)
function Wait-TargetDevice {
    param ([string]$TargetFolder, [string]$RequiredMode, [string]$ActionTitle, [string]$TargetSerial = "")
    
    while ($true) {
        Clear-Host
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "    CIHAZ BEKLENIYOR...                          " -ForegroundColor White
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host $ActionTitle -ForegroundColor Yellow
        
        $tempDevices = @()
        $adbOutput = & $adb devices 2>&1
        $adbLines = @($adbOutput -split "\r?\n" | Where-Object { $_ -match "\b(device|recovery)\b" })
        foreach ($line in $adbLines) {
            $parts = $line -split "\s+"; $serial = $parts[0].Trim(); $devState = $parts[1].Trim()
            $devModel = (& $adb -s $serial shell getprop ro.product.device 2>$null) -join ""; $devModel = $devModel.Trim()
            if ([string]::IsNullOrWhiteSpace($devModel)) { $devModel = "Bilinmiyor" }
            $tempDevices += [PSCustomObject]@{ Serial = $serial; Model = $devModel; State = "ADB/$devState" }
        }

        $fbOutput = (& $fb devices 2>&1) -join "`n"
        $fbLines = @($fbOutput -split "\r?\n" | Where-Object { $_ -match "\bfastboot\b" })
        foreach ($line in $fbLines) {
            $serial = ($line -split "\s+")[0].Trim()
            $fbVar = (& $fb -s $serial getvar product 2>&1) -join "`n"
            $devModel = "Bilinmiyor"
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
            Write-Host "`n[+] Beklenen cihaz algilandi, islem devam ediyor! ($finalSerial)" -ForegroundColor Green
            Start-Sleep -Seconds 2
            return $finalSerial
        }
        elseif (-not $TargetSerial -and $matchedTemp.Count -eq 1) {
            $finalSerial = $matchedTemp[0].Serial
            Write-Host "`n[+] Uyumlu cihaz algilandi, islem otomatik basliyor! ($finalSerial)" -ForegroundColor Green
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
                Write-Host "`n[BILGI] Islem icin $RequiredMode modunda bir cihaz bekleniyor..." -ForegroundColor Yellow
                if ($TargetSerial) { Write-Host "Hedeflenen Seri No: $TargetSerial" -ForegroundColor Cyan }
                Write-Host "Sistem arka planda otomatik taraniyor, lutfen bekleyin... (Cikmak icin araci kapatin)" -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
                continue 
            }

            Write-Host "`n[DIKKAT] Lutfen islem yapilacak cihazi secin!" -ForegroundColor Magenta
            if ($TargetFolder) { Write-Host "Hedef Klasor: $TargetFolder" -ForegroundColor Cyan }
            if ($TargetSerial) { Write-Host "Beklenen Cihaz: $TargetSerial" -ForegroundColor Cyan }
            Write-Host "Istenen Cihaz Modu: $RequiredMode" -ForegroundColor Cyan
            Write-Host "-------------------------------------------------" -ForegroundColor Cyan
            Write-Host "MEVCUT BAGLI CIHAZLAR:" -ForegroundColor White
            
            if ($tempDevices.Count -eq 0) { Write-Host " -> Hic cihaz bagli degil!" -ForegroundColor DarkGray }
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
                    
                    Write-Host ("{0}. Model: {1,-25} | Seri No: {2,-15} [{3}]" -f ($i+1), $d.Model, $d.Serial, $d.State) -ForegroundColor $color
                }
            }
            
            Write-Host "`n Y. YENILE (Listeyi Guncelle)" -ForegroundColor Yellow
            Write-Host " G. IPTAL ET (Geri Don)" -ForegroundColor DarkCyan
            
            $ans = Read-Host "`nSeciminiz"
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
                            Write-Host "`n[!] UYARI: Secilen cihaz klasorle uyumsuz gorunuyor (Seri No uymuyor)!" -ForegroundColor Red
                            Write-Host "Yine de zorla devam ediliyor..." -ForegroundColor Magenta
                            Start-Sleep -Seconds 2
                        } else {
                            Write-Host "`n[+] Cihaz secildi ve onaylandi!" -ForegroundColor Green
                            Start-Sleep -Seconds 1
                        }
                        return $sel.Serial
                    } else {
                        Write-Host "`n[-] Secilen cihaz istenen $RequiredMode modunda degil!" -ForegroundColor Red
                        Start-Sleep -Seconds 2
                    }
                }
            }
            elseif ($ans -match "^[yY]$") {
                Write-Host "Cihazlar Yenileniyor..." -ForegroundColor DarkGray
                Start-Sleep -Seconds 1
            }
        }
    }
}

# Ortak Degiskenler
$excluded = @("super", "userdata", "system", "vendor", "product", "system_ext", "cust", "cache")
$state = "MAIN"; $operation = ""; $mode = ""; $isSuperMode = $false
$selectedFolder = $null; $partObjs = @(); $warningMessage = ""
$connectedDevices = @(); $matchingDevices = @(); $selectedDevice = $null; $targetSerial = ""
$selectedPartitions = @(); $global:lpdumpInfoText = ""

# Ana Dongu
while ($true) {

    if ($state -eq "MAIN") {
        $operation = ""; $mode = ""; $selectedFolder = $null; $isSuperMode = $false
        $partObjs = @(); $warningMessage = ""; $connectedDevices = @()
        $matchingDevices = @(); $selectedDevice = $null; $targetSerial = ""; $global:lpdumpInfoText = ""
        $selectedPartitions = @()

        Show-Header
        Write-Host "Yapmak istediginiz islemi seciniz." -ForegroundColor Yellow
        Write-Host "1. DUMP (Fiziksel Bolumleri Yedekle)"
        Write-Host "2. WRITE (Fiziksel Bolumleri Yazdir)"
        Write-Host "3. DINAMIK BOLUM (SUPER) ISLEMLERI" -ForegroundColor Magenta
        Write-Host "0. CIKIS" -ForegroundColor DarkGray
        Write-Host " "
	    Write-Host "ONEMLI NOT: " -ForegroundColor Red
        Write-Host "Bazi Recovery yazilimlarinda recovery acilirken adb baglantisi gidip gelebilir veya stabil baglanti olmayabilir." -ForegroundColor Yellow
	    Write-Host "Stabil baglantisi olan recovery kullanin veya dikkatli kullanin." -ForegroundColor Yellow
        Write-Host " "

        $opInput = Read-Host "`nSeciminiz"
        if ($opInput -match "^[12]$") { $operation = $opInput; $state = "MODE" } 
        elseif ($opInput -match "^3$") { $state = "SUPER_MAIN" }
        elseif ($opInput -eq "0") { Cleanup-And-Exit }
    }
    
    elseif ($state -eq "SUPER_MAIN") {
        Show-Header
        Write-Host "DINAMIK BOLUM (SUPER) ISLEMLERI" -ForegroundColor Magenta
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "1. DUMP (Super Bolumlerini PC'ye Yedek Al - Sadece Android - Root gerekli)"
        Write-Host "2. WRITE (PC'den Super Bolumune Yazdir - Sadece FastbootD)"
        Write-Host "G. GERI DON (Ana Menu)" -ForegroundColor DarkCyan
        
        $supIn = Read-Host "`nSeciminiz"
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
            Write-Host "Yazma yontemini secin" -ForegroundColor Yellow
            Write-Host "1. Bootloader-Recovery Hibrit Mod  (Fastboot & Recovery DD Fallback) (Tavsiye edilen)"
            Write-Host "2. Recovery Mod  (TWRP/OrangeFox - DD ile Standart Yazma)"
        } else {
            Write-Host "Dump yontemini secin" -ForegroundColor Yellow
            Write-Host "1. Android Sistemi  (Cihaz acik - Root gerekli)"
            Write-Host "2. Recovery Modu  (TWRP/OrangeFox/Custom Recovery vs.) (Tavsiye edilen)"
			Write-Host " "
			Write-Host "NOT: " -NoNewline -ForegroundColor Red
            Write-Host "Super bolumunu Recovery Modunda dump etmek daha guvenilirdir." -ForegroundColor Yellow
			Write-Host " "
        }
        
        Write-Host "G. GERI DON (Ana Menu)" -ForegroundColor DarkCyan
        
        $modeInput = Read-Host "`nSeciminiz (1, 2 veya G)"
        
        if ($modeInput -match "^[gG]$") { if ($isSuperMode) { $state = "SUPER_MAIN" } else { $state = "MAIN" } } 
        elseif ($modeInput -match "^[12]$") {
            $mode = $modeInput
            if ($operation -eq "1") { $state = "DUMP_SCAN_DEVICES" } else { $state = "FOLDER_MENU" }
        }
    }

    elseif ($state -eq "DUMP_SCAN_DEVICES") {
        Write-Host "`nBagli cihazlar taraniyor (ADB & Fastboot)..." -ForegroundColor Cyan
        $connectedDevices = @()
        
        $adbOutput = & $adb devices 2>&1
        $adbLines = @($adbOutput -split "\r?\n" | Where-Object { $_ -match "\b(device|recovery)\b" })

        foreach ($line in $adbLines) {
            $parts = $line -split "\s+"
            $serial = $parts[0].Trim(); $devState = $parts[1].Trim()
            $isRec = ($devState -eq "recovery")
            
            $devModel = (& $adb -s $serial shell getprop ro.product.device 2>$null) -join ""; $devModel = $devModel.Trim()
            if ([string]::IsNullOrWhiteSpace($devModel)) { $devModel = "Bilinmiyor" }
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

        if ($connectedDevices.Count -eq 0) { Write-Host "[-] HATA: Hicbir cihaz bulunamadi!" -ForegroundColor Red; pause; if($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"} } 
        elseif ($connectedDevices.Count -eq 1 -and -not $connectedDevices[0].IsFastboot) {
            $selectedDevice = $connectedDevices[0]; $targetSerial = $selectedDevice.Serial; $state = "PREPARE_DEVICE"
        } else { $state = "DUMP_DEVICE_SELECT" }
    }

    elseif ($state -eq "DUMP_DEVICE_SELECT") {
        Show-Header
        Write-Host "Birden fazla cihaz VEYA Fastboot cihaz(lar)i bulundu!" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        
        Write-Host "Lutfen islem yapmak istediginiz cihazi secin:" -ForegroundColor White
        for ($i = 0; $i -lt $connectedDevices.Count; $i++) {
            $d = $connectedDevices[$i]
            $statusStr = if ($d.IsFastboot) { "[FASTBOOT]" } elseif ($d.IsRecovery) { "[RECOVERY]" } else { "[ANDROID]" }
            Write-Host ("{0}. Model: {1,-25} | Seri No: {2,-15} {3}" -f ($i+1), $d.Model, $d.Serial, $statusStr) -ForegroundColor Green
        }
        Write-Host "`nG. GERI DON (Secim Ekranina)" -ForegroundColor DarkCyan

        $devIn = Read-Host "`nSeciminiz"
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
        
        $filterStr = if ($isSuperMode) { "^Yedek_Super_[^_]+_[^_]+_[^_]+_[^_]+$" } else { "^Yedek_(?!Super_)[^_]+_[^_]+_[^_]+_[^_]+$" }
        $backupFolders = @(Get-ChildItem -Path $PSScriptRoot -Directory | Where-Object { $_.Name -match $filterStr })
        
        if ($backupFolders.Count -eq 0) {
            Write-Host "[-] HATA: Ayni dizinde isleme uygun formatli klasor bulunamadi!" -ForegroundColor Red
            pause
            if ($isSuperMode) { $state = "SUPER_MAIN" } else { $state = "MODE" }
            continue
        }

        Write-Host "BULUNAN YEDEK KLASORLERI:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $backupFolders.Count; $i++) { Write-Host ("{0,2}. {1}" -f ($i+1), $backupFolders[$i].Name) -ForegroundColor Cyan }
        Write-Host " G. GERI DON (Secim Ekranina)" -ForegroundColor DarkCyan
        
        $folderInput = Read-Host "`nYazdirilacak klasorun NUMARASINI secin veya G yazin"
        
        if ($folderInput -match "^[gG]$") { if ($isSuperMode) { $state = "SUPER_MAIN" } else { $state = "MODE" } } 
        elseif ($folderInput -match '^\d+$') {
            $folderIdx = [int]$folderInput
            if ($folderIdx -ge 1 -and $folderIdx -le $backupFolders.Count) {
                $selectedFolder = $backupFolders[$folderIdx - 1]; $state = "FOLDER_MATCH_CHECK"
            }
        }
    }

    elseif ($state -eq "FOLDER_MATCH_CHECK") {
        Write-Host "`nBagli cihazlar taranarak klasorle eslesmesi kontrol ediliyor..." -ForegroundColor Cyan
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
        Write-Host "[-] UYARI: Secilen klasor ile bagli cihazlarin 'SERI NO'su uyusmuyor!" -ForegroundColor Red
        Write-Host "Secilen Klasor Adi : $($selectedFolder.Name)" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        
        Write-Host "MEVCUT BAGLI CIHAZLAR (BILGI):" -ForegroundColor White
        if ($connectedDevices.Count -gt 0) {
            for ($i = 0; $i -lt $connectedDevices.Count; $i++) {
                $d = $connectedDevices[$i]
                $statusStr = if ($d.IsFastboot) { "[FASTBOOT]" } elseif ($d.IsRecovery) { "[RECOVERY]" } else { "[ANDROID]" }
                Write-Host ("{0}. Model: {1,-25} | Seri No: {2,-15} {3}" -f ($i+1), $d.Model, $d.Serial, $statusStr) -ForegroundColor DarkGray
            }
        } else { Write-Host " -> Hic cihaz bagli degil (ADB/Fastboot) veya yetki yok!" -ForegroundColor DarkGray }
        
        Write-Host "`n[!] Tam uyumlu cihaz bulunamadi. Cihazi listeden manuel olarak secebilirsiniz." -ForegroundColor Magenta
        Write-Host "Ancak yanlis cihaza ROM/Yedek atmak cihazi HARD-BRICK yapabilir." -ForegroundColor Red
        Write-Host "Tum sorumluluk size aittir!" -ForegroundColor Red
        Write-Host "Y. YENILE (Listeyi Guncelle)" -ForegroundColor Yellow
        Write-Host "G. GERI DON (Klasor Secimine)" -ForegroundColor DarkCyan
        
        $errIn = Read-Host "`nSeciminiz"
        if ($errIn -match "^[gG]$") { $connectedDevices = @(); $matchingDevices = @(); $state = "FOLDER_MENU" }
        elseif ($errIn -match "^[yY]$") { $state = "FOLDER_MATCH_CHECK" }
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
        Write-Host "Cihaz secimi bekleniyor..." -ForegroundColor Yellow
        Write-Host "Secilen Klasor: $($selectedFolder.Name)" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        Write-Host "Lutfen islem yapmak istediginiz cihazi Seri Numarasina gore secin:" -ForegroundColor White
        for ($i = 0; $i -lt $matchingDevices.Count; $i++) {
            $d = $matchingDevices[$i]
            $statusStr = if ($d.IsFastboot) { "[FASTBOOT]" } elseif ($d.IsRecovery) { "[RECOVERY]" } else { "[ANDROID]" }
            Write-Host ("{0}. Model: {1,-25} | Seri No: {2,-15} {3}" -f ($i+1), $d.Model, $d.Serial, $statusStr) -ForegroundColor Green
        }
        Write-Host "`nG. GERI DON (Klasor Secimine)" -ForegroundColor DarkCyan

        $devIn = Read-Host "`nSeciminiz"
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
            Write-Host "`n[BILGI] Super Write islemi icin cihaz FastbootD moduna alinmalidir!" -ForegroundColor Yellow
            
            if (-not $selectedDevice.IsFastboot) {
                Write-Host "Cihaz FastbootD moduna aliniyor (adb reboot fastboot)..." -ForegroundColor Cyan
                & $adb -s $targetSerial reboot fastboot | Out-Null
            } else {
                Write-Host "Cihaz FastbootD moduna aliniyor (fastboot reboot fastboot)..." -ForegroundColor Cyan
                & $fb -s $targetSerial reboot fastboot | Out-Null
            }
            
            $waitRes = Wait-TargetDevice -TargetFolder $selectedFolder.Name -RequiredMode "FASTBOOT" -ActionTitle "FastbootD modunda cihaz bekleniyor..." -TargetSerial $targetSerial
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
                Write-Host "[!] HATA: Dinamik (Super) bolum bilgileri cihaz normal Android (Sistem) modundayken daha dogru alinabilir!" -ForegroundColor Red
                Write-Host "Secilen cihaz su an RECOVERY modunda." -ForegroundColor Red
                
                Write-Host "`nNe yapmak istersiniz?" -ForegroundColor White
                Write-Host "1. Cihazi Normal Baslat (ADB Reboot - Android'e don)"
                Write-Host "G. GERI DON (Secim Ekranina)" -ForegroundColor DarkCyan
                
                Write-Host ""
                $actIn = Read-Host "Seciminiz"
                while ($actIn -notmatch "^[1gG]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $actIn = Read-Host "Seciminiz" 
                }
                
                if ($actIn -match "^[gG]$") { $state = "DUMP_SCAN_DEVICES"; continue } 
                else {
                    Write-Host "`nCihaz normal Android sistemi baslatiliyor..." -ForegroundColor Cyan
                    & $adb -s $targetSerial reboot | Out-Null
                    
                    $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "ANDROID" -ActionTitle "Android sisteminin acilmasi bekleniyor..." -TargetSerial $targetSerial
                    if ($waitRes -eq "CANCEL") { $state = "DUMP_SCAN_DEVICES"; continue }
                    
                    $selectedDevice.IsFastboot = $false
                    $selectedDevice.IsRecovery = $false
                    $selectedDevice.Serial = $waitRes
                    $targetSerial = $waitRes
                    $state = "ROOT_CHECK"
                }
            } else {
                Write-Host "`n[BILGI] Cihaz Recovery modunda algilandi. Islem otomatik olarak Recovery moduna cevriliyor!" -ForegroundColor Green
                Start-Sleep -Seconds 2
                $mode = "2"; $state = "ROOT_CHECK"
            }
        }
        elseif ($selectedDevice.IsFastboot -and $operation -eq "1" -and $mode -eq "1") {
            Show-Header
            Write-Host "[!] BILGI: Android modunda yedek almak icin cihaz acik (Android) olmalidir!" -ForegroundColor Yellow
            Write-Host "Secilen cihaz su an FASTBOOT modunda." -ForegroundColor Red
            
            Write-Host "`nNe yapmak istersiniz?" -ForegroundColor White
            Write-Host "1. Cihazi Normal Baslat (Fastboot Reboot - Android'e don)"
            Write-Host "G. GERI DON (Secim Ekranina)" -ForegroundColor DarkCyan
            
            Write-Host ""
            $actIn = Read-Host "Seciminiz"
            while ($actIn -notmatch "^[1gG]$") { 
                try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                $actIn = Read-Host "Seciminiz" 
            }
            
            if ($actIn -match "^[gG]$") { $state = "DUMP_SCAN_DEVICES"; continue } 
            else {
                Write-Host "`nCihaz normal Android sistemi baslatiliyor..." -ForegroundColor Cyan
                $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
                $fbArgs += "reboot"
                & $fb $fbArgs | Out-Null
                
                $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "ANDROID" -ActionTitle "Android sisteminin acilmasi bekleniyor..." -TargetSerial $targetSerial
                if ($waitRes -eq "CANCEL") { $state = "DUMP_SCAN_DEVICES"; continue }
                
                $selectedDevice.IsFastboot = $false
                $selectedDevice.IsRecovery = $false
                $selectedDevice.Serial = $waitRes
                $targetSerial = $waitRes
                $state = "ROOT_CHECK"
            }
        }
        elseif ($selectedDevice.IsFastboot -and (($operation -eq "1" -and $mode -eq "2") -or ($operation -eq "2" -and $mode -eq "2"))) {
            Write-Host "`n[BILGI] Cihaz Fastboot modunda algilandi ama islem Recovery gerektiriyor. Yonlendiriliyor..." -ForegroundColor Yellow
            Start-Sleep -Seconds 2; $state = "REBOOT_TO_RECOVERY"
        }
        elseif (-not $selectedDevice.IsFastboot -and -not $selectedDevice.IsRecovery -and (($operation -eq "1" -and $mode -eq "2") -or ($operation -eq "2" -and $mode -eq "2"))) {
            Write-Host "`n[BILGI] Cihaz Android modunda algilandi ama islem Recovery gerektiriyor!" -ForegroundColor Yellow
            Start-Sleep -Seconds 2; $state = "REBOOT_TO_RECOVERY"
        }
        elseif ($operation -eq "2" -and $mode -eq "1") {
            Write-Host "`n[BILGI] Hibrit Mod (Fastboot) secildi. Liste hazirlaniyor..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2; $state = "WRITE_INIT"
        }
        else {
            $state = "ROOT_CHECK"
        }
    }

    elseif ($state -eq "REBOOT_TO_RECOVERY") {
        Show-Header
        if ($selectedDevice.IsFastboot) {
            Write-Host "Secilen cihaz su an FASTBOOT modunda!" -ForegroundColor Yellow
            Write-Host "Isleme devam edebilmek icin cihazin RECOVERY moduna alinmasi gerekiyor." -ForegroundColor Cyan
            Write-Host "`nLutfen cihazi Recovery moduna baslatmak icin bir yontem secin:" -ForegroundColor White
            Write-Host "1. Standart Komut (fastboot reboot recovery)"
            Write-Host "2. OEM Komutu (fastboot oem reboot-recovery)"
            Write-Host "3. Manuel (Cihazi kendim Recovery'e alacagim)"
            Write-Host "G. GERI DON (Secim Ekranina)" -ForegroundColor DarkCyan
            
            Write-Host ""
            $rbIn = Read-Host "Seciminiz"
            while ($rbIn -notmatch "^[123gG]$") { 
                try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                $rbIn = Read-Host "Seciminiz" 
            }
            
            if ($rbIn -match "^[gG]$") { 
                if ($operation -eq "1") { $state = "DUMP_SCAN_DEVICES" } else { $state = "FOLDER_MENU" }
                continue 
            }
            
            $fbRebootArgs = @(); if ($targetSerial) { $fbRebootArgs += "-s"; $fbRebootArgs += $targetSerial }
            
            if ($rbIn -eq "1") { $fbRebootArgs += "reboot"; $fbRebootArgs += "recovery"; & $fb $fbRebootArgs | Out-Null }
            elseif ($rbIn -eq "2") { $fbRebootArgs += "oem"; $fbRebootArgs += "reboot-recovery"; & $fb $fbRebootArgs | Out-Null }
            else { Write-Host "Lutfen cihazi kendiniz Recovery moduna alin..." -ForegroundColor Magenta }
        } else {
            Write-Host "Secilen cihaz su an ANDROID modunda acik durumda!" -ForegroundColor Yellow
            Write-Host "Isleme devam edebilmek icin cihazin RECOVERY moduna alinmasi gerekiyor." -ForegroundColor Cyan
            Write-Host "`nCihaz otomatik olarak komutuyla Recovery moduna yeniden baslatiliyor..." -ForegroundColor Green
            & $adb -s $targetSerial reboot recovery | Out-Null
        }
        
        Write-Host "`n[!!] LUTFEN DIKKAT [!!]" -ForegroundColor Red
        Write-Host "Recovery acilirken ADB baglantisi kopup tekrar baglanabilir." -ForegroundColor Yellow
        Write-Host "Ekranda TWRP/OrangeFox menusunu TAMAMEN ve NET bir sekilde gorene kadar bekleyin." -ForegroundColor Yellow
        
        $fName = if ($selectedFolder) { $selectedFolder.Name } else { "" }
        $waitRes = Wait-TargetDevice -TargetFolder $fName -RequiredMode "RECOVERY" -ActionTitle "Isleme devam edebilmek icin cihaz Recovery modunda bekleniyor..." -TargetSerial $targetSerial
        
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
            Write-Host "`nCihaz RECOVERY modunda algilandi!" -ForegroundColor Green
            Start-Sleep -Seconds 1
            if ($operation -eq "1") { $state = "DUMP_INIT" } else { $state = "WRITE_INIT" }
        }
        elseif ($mode -eq "1" -and $operation -eq "1") {
            Write-Host "`nRoot erisimi kontrol ediliyor..." -ForegroundColor Cyan
            $rootCheck = (& $adb -s $targetSerial shell su -c id 2>&1) -join "`n"
            if ($rootCheck -match "uid=0") {
                Write-Host "[+] Root yetkisi basariyla dogrulandi!" -ForegroundColor Green
                Start-Sleep -Seconds 1
                $state = "DUMP_INIT"
            } else {
                Write-Host "[-] HATA: Root yetkisi alinamadi! Lutfen telefondan izin verin." -ForegroundColor Red; pause; if($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"}
            }
        } else {
            if ($operation -eq "1") { $state = "DUMP_INIT" } else { $state = "WRITE_INIT" }
        }
    }

    elseif ($state -eq "DUMP_INIT") {
        Write-Host "`nBolumler ve boyutlari okunuyor..." -ForegroundColor Cyan
        Start-Sleep -Seconds 1
        
        $readSuccess = $false
        
        if ($isSuperMode) {
            $global:lpdumpInfoText = ""
            while (-not $readSuccess) {
                $partitionsRaw = & $adb -s $targetSerial shell "su -c 'lpdump'" 2>&1
                $partitionsRaw = $partitionsRaw -join "`n"
                
                if ($partitionsRaw -match "not found" -or $partitionsRaw -match "offline" -or $partitionsRaw -match "Permission denied") {
                    Write-Host "[-] HATA: lpdump calistirilamadi! Cihaz baglantisi zayif veya komut desteklenmiyor olabilir." -ForegroundColor Red
                    $retryAns = Read-Host "`n[Y] Yeniden Dene | [G] Geri Don"
                    if ($retryAns -match "^[gG]$") { $state = "SUPER_MAIN"; break }
                    else { Write-Host "Tekrar baglanti kurulmaya calisiliyor..." -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
                } else { $readSuccess = $true }
            }
            if (-not $readSuccess) { continue }
            
            if ($partitionsRaw -match "Header flags:\s*(.*)") { $global:lpdumpInfoText += "Header Flags: $($Matches[1])`n" }
            
            if ($partitionsRaw -match "Block device table:[\s\S]*?Partition name: super[\s\S]*?Size:\s*(\d+)\s*bytes") {
                $superBytes = [long]$Matches[1]
                $superMB = [math]::Round($superBytes / 1MB, 2)
                $global:lpdumpInfoText += "Super Boyutu: $superBytes Bayt (~$superMB MB)`n"
            }

            $groups = [regex]::Matches($partitionsRaw, "Name:\s*([\w-_]+)\s+Maximum size:\s*(\d+)\s*bytes")
            foreach ($g in $groups) {
                if ($g.Groups[1].Value -ne "default") {
                    $gBytes = [long]$g.Groups[2].Value
                    $gMB = [math]::Round($gBytes / 1MB, 2)
                    $global:lpdumpInfoText += "Grup [$($g.Groups[1].Value)] Maks. Boyutu: $gBytes Bayt (~$gMB MB)`n"
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
                    Write-Host "[-] HATA: Bolumler okunamadi! Cihaz henuz tam baslamamis veya ADB baglantisi yok." -ForegroundColor Red
                    $retryAns = Read-Host "`n[Y] Yeniden Dene | [G] Geri Don"
                    if ($retryAns -match "^[gG]$") { $state = "MODE"; break }
                    else { Write-Host "Tekrar baglanti kurulmaya calisiliyor..." -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
                } else { $readSuccess = $true }
            }
            if (-not $readSuccess) { continue } 

            $partObjs = @()
            foreach ($line in ($partitionsRaw -split "`n")) {
                $line = $line.Trim()
                if ($line -match "^([\w-]+):(\d*)$") {
                    $pName = $Matches[1]; $pSizeBytes = $Matches[2]
                    if ($pName -match "^mmcblk\d+" -or $pName -match "^sd[a-z]$" -or $pName -match "^loop" -or $pName -match "^ram") { continue }
                    $pSizeMB = if ($pSizeBytes) { [math]::Round([long]$pSizeBytes / 1MB, 2) } else { "Bilinmiyor" }
                    $isSelected = if ($excluded -contains $pName) { $false } else { $true }
                    $partObjs += [PSCustomObject]@{ Name = $pName; SizeMB = $pSizeMB; Selected = $isSelected }
                }
            }
        }
        
        if ($partObjs.Count -eq 0) { Write-Host "[-] HATA: Gecerli partition bulunamadi." -ForegroundColor Red; pause; if ($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"}; continue }
        $state = "DUMP_MENU"
    }

    elseif ($state -eq "DUMP_MENU") {
        Show-Header
        
        if ($isSuperMode) {
            Write-Host "--- LPDUMP BILGILERI (bir kismi) (SUPER BOLUMU) ---" -ForegroundColor Magenta
            Write-Host $global:lpdumpInfoText -ForegroundColor Yellow
            Write-Host "---------------------------------------" -ForegroundColor Magenta
        }
        
        Write-Host "DUMP EDILECEK BOLUMLER:" -ForegroundColor Yellow
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
        Write-Host "   >>> SECILEN BOLUM SAYISI : $selCount / $totCount <<<" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan
        
        if (-not $isSuperMode) {
            Write-Host "NOT: " -NoNewline -ForegroundColor Red
            Write-Host "'userdata' sifreli bir bolum oldugu icin yedeklemek kisisel verilerinizi " -NoNewline -ForegroundColor Yellow
            Write-Host "KESIN OLARAK KURTARMAZ!!!" -ForegroundColor Red
        }
        
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
        Write-Host " -> Coklu secim icin araya bosluk birakarak yazin (Orn: 1 5 12 6)" -ForegroundColor White
        Write-Host " -> Userdata haric TUMUNU SECMEK icin 'A' yazin." -ForegroundColor Green
        Write-Host " -> TUM SECIMLERI KALDIRMAK (Hicbirini Secme) icin 'H' yazin." -ForegroundColor Green
        Write-Host " -> VARSAYILAN secimlere donmek icin 'V' yazin." -ForegroundColor Green
        if ($hasABSlots) { Write-Host " -> Slot secmek icin 'S' yazin." -ForegroundColor Magenta }
        Write-Host " -> GERI DONMEK (Cihaz Modu Secimine) icin 'G' yazin." -ForegroundColor Yellow
        Write-Host ""
        Write-Host " -> Secimler bitince ISLEMI BASLATMAK icin 'B' yazin." -ForegroundColor Green
        
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "    "
        Write-Host "HEDEF CIHAZ BILGISI:" -ForegroundColor Yellow
        Write-Host "Model: $($selectedDevice.Model) | Seri No: $($selectedDevice.Serial)" -ForegroundColor White
        
        $modeStr = if ($isSuperMode) { "Android" } elseif ($mode -eq "1") { "Android" } else { "Recovery" }
        Write-Host "Gecerli Mod : $modeStr" -ForegroundColor DarkCyan
        
        $inputStr = Read-Host "`nSeciminiz"
        if ($inputStr -match "^[bB]$") { $state = "DUMP_EXECUTE" }
        elseif ($inputStr -match "^[gG]$") { $partObjs = @(); $selectedDevice = $null; $targetSerial = ""; if($isSuperMode){$state="SUPER_MAIN"}else{$state="MODE"} }
        elseif ($inputStr -match "^[aA]$") { foreach ($p in $partObjs) { $p.Selected = ($p.Name -ne "userdata") } }
        elseif ($inputStr -match "^[hH]$") { foreach ($p in $partObjs) { $p.Selected = $false } }
        elseif ($inputStr -match "^[vV]$") { foreach ($p in $partObjs) { $p.Selected = -not ($excluded -contains $p.Name) } }
        elseif ($inputStr -match "^[sS]$" -and $hasABSlots) {
            $slotAns = Read-Host "`nHangi slot gecerli kalsin? (A / B yazin)"
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
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nHicbir bolum secilmedi!" -ForegroundColor Red; pause; $state="DUMP_MENU"; continue }

        $devModel = $selectedDevice.Model
        $devSerial = $selectedDevice.Serial
        $timestamp = Get-Date -Format "HHmm_ddMMyyyy"
        
        $folderName = if ($isSuperMode) { "Yedek_Super_${devModel}_${devSerial}_$timestamp" } else { "Yedek_${devModel}_${devSerial}_$timestamp" }
        $backupDir = Join-Path $PSScriptRoot $folderName
        if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir | Out-Null }

        Show-Header
        Write-Host "Hedef Klasor: $folderName" -ForegroundColor Cyan
        
        $sArg = if ($targetSerial) { "-s $targetSerial" } else { "" }
        $successCount = 0; $failCount = 0

        foreach ($p in $selectedPartitions) {
            $pName = $p.Name
            $outFile = Join-Path $backupDir "$pName.img"
            
            $devCheck = & $adb $sArg get-state 2>&1
            if ($devCheck -match "offline" -or $devCheck -match "not found") {
                Write-Host "`n[-] KRITIK HATA: Cihaz baglantisi koptu (Offline/Not Found)!" -ForegroundColor Red
                Write-Host "Kalan islemler iptal ediliyor..." -ForegroundColor Yellow
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
                    Write-Host "`n[DUMPING] -> $pName ($($p.SizeMB) MB) [Mod: Recovery / ADB Pull]" -ForegroundColor Green
                    $pullOut = cmd /c "`"$adb`" $sArg pull `"$realBlk`" `"$outFile`"" 2>&1
                    if ($pullOut -match "error:" -or $pullOut -match "offline" -or $pullOut -match "failed" -or $pullOut -match "not found") {
                        Write-Host "   [-] HATA: Cekme islemi basarisiz veya bolum unmounted!" -ForegroundColor Red
                        Write-Host "   >>> Log: $pullOut" -ForegroundColor DarkGray
                    } else { $dumpSuccess = $true }
                } 
                else {
                    Write-Host "`n[DUMPING] -> $pName ($($p.SizeMB) MB) [Mod: Android / GZip Base64 Aktarim]" -ForegroundColor Green
                    
                    $b64File = "$outFile.b64"
                    $gzFile = "$outFile.gz"
                    
                    Write-Host "   -> Android Uzerinde arsivleniyor ve metne cevriliyor..." -ForegroundColor DarkYellow
                    $ddOut = cmd /c "`"$adb`" $sArg exec-out `"su -c 'dd if=$realBlk 2>/dev/null | gzip -1 -c | base64'`" > `"$b64File`"" 2>&1
                    
                    $b64FileInfo = Get-Item $b64File -ErrorAction SilentlyContinue
                    if ($ddOut -match "error:" -or $ddOut -match "offline" -or $ddOut -match "not found" -or -not $b64FileInfo -or $b64FileInfo.Length -eq 0) {
                        Write-Host "   [-] HATA: Veri okunamadi veya cihaz baglantisi koptu!" -ForegroundColor Red
                        if (-not [string]::IsNullOrWhiteSpace($ddOut)) { Write-Host "   >>> Log: $ddOut" -ForegroundColor DarkGray }
                    } else {
                        Write-Host "   -> Windows Uzerinde dosyaya ceviriliyor..." -ForegroundColor DarkYellow
                        cmd /c "certutil -decode `"$b64File`" `"$gzFile`" 2>&1" | Out-Null
                        
                        Write-Host "   -> Ham Kalip (IMG) Dosyasina Cikariliyor..." -ForegroundColor DarkYellow
                        try {
                            $inputStr = New-Object System.IO.FileStream $gzFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
                            $outputStr = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
                            $gzipStream = New-Object System.IO.Compression.GZipStream $inputStr, ([IO.Compression.CompressionMode]::Decompress)
                            $gzipStream.CopyTo($outputStr)
                            $gzipStream.Close(); $inputStr.Close(); $outputStr.Close()
                            $dumpSuccess = $true
                        } catch {
                            Write-Host "   [-] HATA: Arsiv cikarilamadi! Dosya bozuk olabilir." -ForegroundColor Red
                        }
                    }
                    Remove-Item $b64File -ErrorAction SilentlyContinue
                    Remove-Item $gzFile -ErrorAction SilentlyContinue
                }
                if ($dumpSuccess) { $successCount++ } else { $failCount++ }
            } else {
                Write-Host "`n   [-] HATA: '$pName' bolumu icin gecerli bir yol bulunamadi! (Yol: '$realBlk')" -ForegroundColor Red
                $failCount++
            }
        }
        
        Write-Host "`n=================================================" -ForegroundColor Cyan
        if ($failCount -eq 0) {
            Write-Host "ISLEM TAMAMLANDI! Tum yedek dosyalariniz '$folderName' klasorune basariyla kaydedildi." -ForegroundColor Green
        } elseif ($successCount -gt 0) {
            Write-Host "ISLEM KISMEN TAMAMLANDI! $successCount basarili, $failCount hatali islem." -ForegroundColor Yellow
            Write-Host "Dosyalar '$folderName' klasorunde." -ForegroundColor Yellow
        } else {
            Write-Host "ISLEM BASARISIZ! Cihaz baglantisi koptu veya hicbir bolum alinamadi." -ForegroundColor Red
        }
        pause; $state = "MAIN"
    }

    elseif ($state -eq "WRITE_INIT") {
        $imgFiles = @(Get-ChildItem -Path $selectedFolder.FullName -Filter "*.img")
        if ($imgFiles.Count -eq 0) { Write-Host "[-] HATA: Secilen klasorde hic .img dosyasi yok!" -ForegroundColor Red; pause; $state = "FOLDER_MENU"; continue }
        $imgNames = $imgFiles | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }

        $partObjs = @()
        
        if ($isSuperMode) {
            Write-Host "`nSuper bolum listesi yedek klasorunden olusturuluyor (FastbootD Modu)..." -ForegroundColor Cyan
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
            Write-Host "`nBolum listesi yedek klasorunden olusturuluyor (Hibrit/Fastboot Modu)..." -ForegroundColor Cyan
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
            Write-Host "`nCihaz bolumleri okunuyor..." -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            
            $shScript = 'cd /dev/block/by-name && for p in *; do echo $p; done'
            
            $readSuccess = $false
            while (-not $readSuccess) {
                $partitionsRaw = & $adb shell "$shScript" 2>&1
                $partitionsRaw = $partitionsRaw -join "`n"
                
                if ([string]::IsNullOrWhiteSpace($partitionsRaw) -or $partitionsRaw -match "Permission denied" -or $partitionsRaw -match "syntax error" -or $partitionsRaw -match "not found" -or $partitionsRaw -match "offline") {
                    Write-Host "[-] HATA: Bolumler okunamadi! Cihaz henuz tam baslamamis veya ADB baglantisi yok." -ForegroundColor Red
                    $retryAns = Read-Host "`n[Y] Yeniden Dene | [G] Geri Don"
                    if ($retryAns -match "^[gG]$") { $state = "FOLDER_MENU"; break }
                    else { Write-Host "Tekrar baglanti kurulmaya calisiliyor..." -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
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

        if ($partObjs.Count -eq 0) { Write-Host "[-] HATA: Klasordeki imajlar cihazdaki bolumlerle eslesmedi!" -ForegroundColor Red; pause; $state = "FOLDER_MENU"; continue }
    }

    elseif ($state -eq "WRITE_MENU") {
        Show-Header
        
        Write-Host "YUKLENECEK KLASOR: $($selectedFolder.Name)" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $partObjs.Count; $i++) {
            if ($partObjs[$i].HasImage) {
                $status = if ($partObjs[$i].Selected) { "[X]" } else { "[ ]" }
                $color = if ($partObjs[$i].Selected) { "Green" } else { "DarkGray" }
                Write-Host ("{0,3}. {1} {2,-25} : {3} MB" -f ($i+1), $status, $partObjs[$i].Name, $partObjs[$i].SizeMB) -ForegroundColor $color
            } else {
                Write-Host ("{0,3}. [-] {1,-25} : " -f ($i+1), $partObjs[$i].Name) -NoNewline -ForegroundColor DarkGray
                Write-Host "DOSYA YOK" -ForegroundColor Red
            }
        }

        $hasABSlots = @($partObjs | Where-Object { $_.Name -match '_[ab]$' }).Count -gt 0

        Write-Host "`n=================================================" -ForegroundColor Cyan
        $selCount = @($partObjs | Where-Object { $_.Selected }).Count
        $totCount = $partObjs.Count
        Write-Host "   >>> SECILEN BOLUM SAYISI : $selCount / $totCount <<<" -ForegroundColor Yellow
        Write-Host "=================================================" -ForegroundColor Cyan

        Write-Host "!!! COK ONEMLI UYARI !!!" -ForegroundColor Magenta
        Write-Host "BU ISLEM RISKLIDIR! Baglanti kopmasi, hatali bolum yazimi sonucu cihaz brick olabilir, IMEI, seri no vb." -ForegroundColor Yellow
        Write-Host "bilgiler kaybolabilir. Cihazinizin edl/bootrom/bootloader gibi yollardan kurtarma imkani yoksa cihaziniz" -ForegroundColor Yellow
        Write-Host "kurtarilamayabilir." -ForegroundColor Yellow
        
        Write-Host "-------------------------------------------------" -ForegroundColor Cyan
        Write-Host " -> Coklu secim icin araya bosluk birakarak yazin (Orn: 1 5 12 6)" -ForegroundColor White 
        Write-Host " -> Dosyasi bulunan TUM IMG'leri SECMEK icin 'A' yazin." -ForegroundColor Green
        Write-Host " -> TUM SECIMLERI KALDIRMAK (Hicbirini Secme) icin 'H' yazin." -ForegroundColor Green
        Write-Host " -> VARSAYILAN secimlere donmek icin 'V' yazin." -ForegroundColor Green
        if ($hasABSlots) { Write-Host " -> Slot secmek icin 'S' yazin." -ForegroundColor Magenta }
        Write-Host " -> GERI DONMEK (Klasor Secimine) icin 'G' yazin." -ForegroundColor Yellow
        
        Write-Host ""
        if ($isSuperMode) {
            Write-Host " -> SADECE FASTBOOTD ILE YAZMAK icin 'F' yazin." -ForegroundColor Magenta
        } elseif ($mode -eq "1") {
            Write-Host " -> FASTBOOT (HIBRIT) HIZLI YAZMAK icin 'F' yazin (Ileri Duzey)." -ForegroundColor Magenta
        } else {
            Write-Host " -> DD ILE STANDART YAZMAK icin 'B' yazin." -ForegroundColor Red
        }
        
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "   "
        Write-Host "HEDEF CIHAZ BILGISI:" -ForegroundColor Yellow
        Write-Host "Model: $($selectedDevice.Model) | Seri No: $($selectedDevice.Serial)" -ForegroundColor White
        
        $modeStr = if ($isSuperMode) { "FastbootD (Super Yazma)" } elseif ($mode -eq "1") { "Bootloader-Recovery Hibrit" } else { "Recovery Mod" }
        Write-Host "Gecerli Mod : $modeStr`nSecilen Klasor: $($selectedFolder.Name)" -ForegroundColor DarkCyan
        
        if ($warningMessage -ne "") { Write-Host "`n>>> $warningMessage <<<" -ForegroundColor Yellow; $warningMessage = "" }

        $inputStr = Read-Host "`nSeciminiz"
        if ($inputStr -match "^[bB]$" -and $mode -eq "2" -and -not $isSuperMode) { $state = "WRITE_EXECUTE_DD" }
        elseif ($inputStr -match "^[fF]$" -and ($mode -eq "1" -or $isSuperMode)) { 
            if ($isSuperMode) { $state = "WRITE_EXECUTE_SUPER" } else { $state = "WRITE_EXECUTE_FASTBOOT" }
        }
        elseif ($inputStr -match "^[gG]$") { $partObjs = @(); $selectedDevice = $null; $targetSerial = ""; $warningMessage = ""; $state = "FOLDER_MENU" }
        elseif ($inputStr -match "^[aA]$") { foreach ($p in $partObjs) { if ($p.HasImage) { $p.Selected = $true } } }
        elseif ($inputStr -match "^[hH]$") { foreach ($p in $partObjs) { if ($p.HasImage) { $p.Selected = $false } } }
        elseif ($inputStr -match "^[vV]$") { foreach ($p in $partObjs) { if ($p.HasImage) { $p.Selected = -not ($excluded -contains $p.Name) } } }
        elseif ($inputStr -match "^[sS]$" -and $hasABSlots) {
            $slotAns = Read-Host "`nHangi slot gecerli kalsin? (A / B yazin)"
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
            if ($warnFlag) { $warningMessage = "UYARI: Secilen bazi bolumler icin yedek dosyasi bulunamadi, o bolumler atlandi!" }
        }
    }

    elseif ($state -eq "WRITE_EXECUTE_SUPER") {
        $selectedPartitions = @($partObjs | Where-Object { $_.Selected })
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nHicbir bolum secilmedi!" -ForegroundColor Red; pause; $state="WRITE_MENU"; continue }

        Show-Header
        Write-Host "FASTBOOTD YAZMA ISLEMI BASLIYOR... LUTFEN KABLOYU CIKARMAYIN!" -ForegroundColor Red
        
        $successCount = 0; $failCount = 0

        foreach ($p in $selectedPartitions) {
            $pName = $p.Name; $inFile = $p.FilePath
            
            Write-Host "[FASTBOOTD] -> $pName flashlaniyor ($($p.SizeMB) MB) ..." -ForegroundColor Yellow
            $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
            $fbArgs += "flash"; $fbArgs += $pName; $fbArgs += $inFile
            
            $fbOutput = (& $fb $fbArgs 2>&1) -join "`n"
            
            if ($fbOutput -match "FAILED" -or $fbOutput -match "error:") {
                Write-Host "   [-] HATA: Yazma islemi basarisiz!" -ForegroundColor Red
                Write-Host "   >>> Log: $fbOutput" -ForegroundColor DarkGray
                $failCount++
            } else {
                Write-Host "   [+] Basariyla gonderildi!`n" -ForegroundColor DarkCyan
                $successCount++
            }
        }
        
        Write-Host "=======================================" -ForegroundColor Cyan
        if ($failCount -eq 0) {
            Write-Host "TUM SUPER YAZMA ISLEMLERI BASARIYLA TAMAMLANDI!" -ForegroundColor Green
        } elseif ($successCount -gt 0) {
            Write-Host "ISLEM KISMEN TAMAMLANDI! $successCount basarili, $failCount hatali yazma islemei." -ForegroundColor Yellow
        } else {
            Write-Host "ISLEM BASARISIZ! FastbootD hatasi olustu." -ForegroundColor Red
        }
        
        Start-Sleep -Seconds 2
        $state = "WRITE_POST_ACTION"
    }

    elseif ($state -eq "WRITE_EXECUTE_DD") {
        $selectedPartitions = @($partObjs | Where-Object { $_.Selected })
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nHicbir bolum secilmedi!" -ForegroundColor Red; pause; $state="WRITE_MENU"; continue }

        Show-Header
        Write-Host "YAZMA ISLEMI BASLIYOR... LUTFEN KABLOYU CIKARMAYIN!" -ForegroundColor Red
        
        $sArg = if ($targetSerial) { "-s $targetSerial" } else { "" }
        $successCount = 0; $failCount = 0

        foreach ($p in $selectedPartitions) {
            $pName = $p.Name; $inFile = $p.FilePath
            
            $devCheck = & $adb $sArg get-state 2>&1
            if ($devCheck -match "offline" -or $devCheck -match "not found") {
                Write-Host "`n[-] KRITIK HATA: Cihaz baglantisi koptu!" -ForegroundColor Red
                $failCount++
                break
            }

            Write-Host "[DD WRITING] -> $pName yaziliyor ($($p.SizeMB) MB) ..." -ForegroundColor Yellow
            
            $ddOut = cmd /c "`"$adb`" $sArg exec-in dd of=/dev/block/by-name/$pName bs=4M < `"$inFile`"" 2>&1
            
            if ($ddOut -match "error:" -or $ddOut -match "offline") {
                Write-Host "   [-] HATA: Yazma islemi basarisiz veya baglanti koptu!" -ForegroundColor Red
                if (-not [string]::IsNullOrWhiteSpace($ddOut)) { Write-Host "   >>> Log: $ddOut" -ForegroundColor DarkGray }
                $failCount++
            } else {
                Write-Host "   Basariyla gonderildi!`n" -ForegroundColor DarkCyan
                $successCount++
            }
        }
        
        Write-Host "=======================================" -ForegroundColor Cyan
        if ($failCount -eq 0) { Write-Host "TUM YAZMA ISLEMLERI BASARIYLA TAMAMLANDI!" -ForegroundColor Green } 
        elseif ($successCount -gt 0) { Write-Host "ISLEM KISMEN TAMAMLANDI! $successCount basarili, $failCount hatali yazma islemei." -ForegroundColor Yellow } 
        else { Write-Host "ISLEM BASARISIZ! Cihaz baglantisi koptu." -ForegroundColor Red }
        
        Start-Sleep -Seconds 2
        $state = "WRITE_POST_ACTION"
    }

    elseif ($state -eq "WRITE_EXECUTE_FASTBOOT") {
        $selectedPartitions = @($partObjs | Where-Object { $_.Selected })
        if ($selectedPartitions.Count -eq 0) { Write-Host "`nHicbir bolum secilmedi!" -ForegroundColor Red; pause; $state="WRITE_MENU"; continue }

        Show-Header
        Write-Host "!!! ONEMLI BILGILENDIRME !!!" -ForegroundColor Magenta
        Write-Host "Bu mod, fastboot ile yazilamayan bolumleri telafi etmek icin ikinci asamada" -ForegroundColor Yellow
        Write-Host "TWRP,OrangeFox gibi ADB baglantisine sahip bir Custom Recovery'ye GECIS YAPAR." -ForegroundColor Yellow
        Write-Host "Fastboot asamasi bittiginde cihazinizde Custom Recovery yuklu olmalidir. " -ForegroundColor Yellow
        
        Write-Host ""
        $fbConf = Read-Host "Devam etmek istiyor musunuz? (E/H)"
        while ($fbConf -notmatch "^[eEhH]$") { 
            try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
            $fbConf = Read-Host "Devam etmek istiyor musunuz? (E/H)" 
        }
        if ($fbConf -match "^[hH]$") { $state = "WRITE_MENU"; continue }

        if (-not $selectedDevice.IsFastboot) {
            Show-Header
            Write-Host "Cihaz Bootloader (Fastboot) moduna aliniyor..." -ForegroundColor Cyan
            & $adb -s $targetSerial reboot bootloader | Out-Null
            
            $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Islem baslamasi icin cihaz Fastboot modunda bekleniyor..." -TargetSerial $targetSerial
            if ($waitRes -eq "CANCEL") { $state = "MAIN"; continue }
            $targetSerial = $waitRes
            $selectedDevice.IsFastboot = $true
            $selectedDevice.IsRecovery = $false
        } else {
            $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Hedef cihaz dogrulaniyor..." -TargetSerial $targetSerial
            if ($waitRes -eq "CANCEL") { $state = "MAIN"; continue }
            $targetSerial = $waitRes
        }
        
        $failedPartitions = @()
        $successCount = 0; $failCount = 0
        
        Write-Host "`n================ FASTBOOT ASAMASI ================" -ForegroundColor Cyan
        foreach ($p in $selectedPartitions) {
            $pName = $p.Name; $inFile = $p.FilePath
            Write-Host "[FASTBOOT] -> $pName flashlaniyor..." -ForegroundColor Yellow
            
            $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
            $fbArgs += "flash"; $fbArgs += $pName; $fbArgs += $inFile
            
            $fbOutput = (& $fb $fbArgs 2>&1) -join "`n"
            
            if ($fbOutput -match "FAILED" -or $fbOutput -match "error:") {
                Write-Host "   [!] ENGELLENDI: $pName (Kilit/Dogrulama Korumasi). DD Fallback sirasina alindi!" -ForegroundColor DarkYellow
                Write-Host "   >>> Log: $fbOutput" -ForegroundColor DarkGray
                $failedPartitions += $p
            } else { 
                Write-Host "   [+] Basarili!" -ForegroundColor Green 
                $successCount++
            }
        }
        
        if ($failedPartitions.Count -gt 0) {
            Write-Host "`n================ RECOVERY ASAMASI ================" -ForegroundColor Cyan
            Write-Host "$($failedPartitions.Count) adet bolum Fastboot uzerinden kilitli veya yok." -ForegroundColor Magenta
            Write-Host "Yazilamayan bolumler icin Recovery Moduna gecilmesi gerekiyor!" -ForegroundColor Yellow
            
            Write-Host "`nLutfen cihazi Recovery moduna baslatmak icin bir yontem secin:" -ForegroundColor White
            Write-Host "1. Standart Komut (fastboot reboot recovery)"
            Write-Host "2. OEM Komutu (fastboot oem reboot-recovery)"
            Write-Host "3. Manuel (Cihazi kendim Recovery'e alacagim)"
            
            $rbIn = Read-Host "Seciminiz"
            while ($rbIn -notmatch "^[123]$") { 
                try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                $rbIn = Read-Host "Seciminiz" 
            }
            
            $fbRebootArgs = @(); if ($targetSerial) { $fbRebootArgs += "-s"; $fbRebootArgs += $targetSerial }
            
            if ($rbIn -eq "1") { $fbRebootArgs += "reboot"; $fbRebootArgs += "recovery"; & $fb $fbRebootArgs | Out-Null }
            elseif ($rbIn -eq "2") { $fbRebootArgs += "oem"; $fbRebootArgs += "reboot-recovery"; & $fb $fbRebootArgs | Out-Null }
            else { Write-Host "Lutfen cihazi Recovery moduna alin..." -ForegroundColor Magenta }
            
            Write-Host "`n[!!] LUTFEN DIKKAT [!!]" -ForegroundColor Red
            Write-Host "Recovery acilirken ADB baglantisi kopup tekrar baglanabilir." -ForegroundColor Yellow
            
            $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "RECOVERY" -ActionTitle "DD Fallback islemi icin cihaz Recovery modunda bekleniyor..." -TargetSerial $targetSerial
            if ($waitRes -eq "CANCEL") { $state = "MAIN"; continue }
            $newSerial = $waitRes
            
            $selectedDevice.IsFastboot = $false
            $selectedDevice.IsRecovery = $true
            $targetSerial = $newSerial
            
            foreach ($p in $failedPartitions) {
                $pName = $p.Name; $inFile = $p.FilePath
                
                $devCheck = & $adb -s $targetSerial get-state 2>&1
                if ($devCheck -match "offline" -or $devCheck -match "not found") {
                    Write-Host "`n[-] KRITIK HATA: Cihaz baglantisi koptu!" -ForegroundColor Red
                    $failCount++
                    break
                }
                
                Write-Host "[DD FALLBACK] -> $pName yaziliyor..." -ForegroundColor Yellow
                $ddOut = cmd /c "`"$adb`" -s $targetSerial exec-in dd of=/dev/block/by-name/$pName bs=4M < `"$inFile`"" 2>&1
                
                if ($ddOut -match "error:" -or $ddOut -match "offline") {
                    Write-Host "   [-] HATA: Yazma basarisiz!" -ForegroundColor Red
                    if (-not [string]::IsNullOrWhiteSpace($ddOut)) { Write-Host "   >>> Log: $ddOut" -ForegroundColor DarkGray }
                    $failCount++
                } else {
                    Write-Host "   [+] DD ile yazildi!" -ForegroundColor DarkCyan
                    $successCount++
                }
            }
            Write-Host "`n=======================================" -ForegroundColor Cyan
            if ($failCount -eq 0) { Write-Host "HIBRIT YUKLEME BASARIYLA TAMAMLANDI!" -ForegroundColor Green } 
            else { Write-Host "ISLEM KISMEN TAMAMLANDI! $successCount basarili, $failCount hatali yazma islemi." -ForegroundColor Yellow }
        } else {
            Write-Host "`n=======================================" -ForegroundColor Cyan
            Write-Host "Tum bolumler Fastboot ile eksiksiz yazildi!" -ForegroundColor Green
        }

        Start-Sleep -Seconds 2
        $state = "WRITE_POST_ACTION"
    }

    elseif ($state -eq "WRITE_POST_ACTION") {
        while ($true) {
            Clear-Host
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host "           YAZMA ISLEMLERI TAMAMLANDI            " -ForegroundColor Green
            Write-Host "=================================================" -ForegroundColor Cyan
            
            $hasABSlots = @($partObjs | Where-Object { $_.Name -match '_[ab]$' }).Count -gt 0
            
            if ($hasABSlots -and -not $slotChanged) {
                Write-Host "`nBu cihazda A/B slot mimarisi tespit edildi." -ForegroundColor DarkCyan
                
                $actAns = Read-Host "Cihazin 'Aktif Slotunu' degistirmek ister misiniz? (E/H)"
                while ($actAns -notmatch "^[eEhH]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $actAns = Read-Host "Cihazin 'Aktif Slotunu' degistirmek ister misiniz? (E/H)" 
                }
                
                if ($actAns -match "^[eE]$") {
                    if (-not $selectedDevice.IsFastboot) {
                        Write-Host "`nCihaz Fastboot moduna aliniyor..." -ForegroundColor Yellow
                        & $adb -s $targetSerial reboot bootloader | Out-Null
                        
                        $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Slot degisimi icin cihaz Fastboot modunda bekleniyor..." -TargetSerial $targetSerial
                        if ($waitRes -ne "CANCEL") {
                            $targetSerial = $waitRes
                            $selectedDevice.IsFastboot = $true
                            $selectedDevice.IsRecovery = $false
                        }
                    }
                    
                    if ($selectedDevice.IsFastboot) {
                        $writtenA = @($selectedPartitions | Where-Object { $_.Name -match "_a`$" }).Count
                        $writtenB = @($selectedPartitions | Where-Object { $_.Name -match "_b`$" }).Count
                        
                        if ($writtenA -gt 0 -and $writtenB -eq 0) { Write-Host "`nIPUCU: Yuklenen yedek dosyalarinda yalnizca 'A' slotu vardi." -ForegroundColor Magenta } 
                        elseif ($writtenB -gt 0 -and $writtenA -eq 0) { Write-Host "`nIPUCU: Yuklenen yedek dosyalarinda yalnizca 'B' slotu vardi." -ForegroundColor Magenta }
                        
                        Write-Host ""
                        $slotAns = Read-Host "Hangi slot aktif edilsin? (A / B)"
                        while ($slotAns -notmatch "^[aAbB]$") { 
                            try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                            $slotAns = Read-Host "Hangi slot aktif edilsin? (A / B)" 
                        }
                        $tgtSlot = $slotAns.ToLower()
                        
                        Write-Host "`nAktif slot $tgtSlot olarak ayarlaniyor..." -ForegroundColor Yellow
                        $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
                        $fbArgs += "set_active"; $fbArgs += $tgtSlot
                        
                        $fbOut = (& $fb $fbArgs 2>&1) -join "`n"
                        if ($fbOut -match "OKAY" -or $fbOut -match "Finished") { Write-Host "[+] Basarili! Aktif slot '$tgtSlot' olarak ayarlandi." -ForegroundColor Green } 
                        else {
                            Write-Host "[-] HATA: Slot degistirilemedi!" -ForegroundColor Red
                            Write-Host "   >>> Log: $fbOut" -ForegroundColor DarkGray
                        }
                        Start-Sleep -Seconds 2
                        $slotChanged = $true 
                    }
                } else { $slotChanged = $true }
                continue 
            }
            
            Write-Host "`nSu anki cihaz durumu: " -NoNewline -ForegroundColor White
            if ($selectedDevice.IsFastboot) { Write-Host "[FASTBOOT/FASTBOOTD]" -ForegroundColor Yellow } else { Write-Host "[ADB/RECOVERY]" -ForegroundColor Green }
            
            Write-Host "`n================ REBOOT & EKSTRA MENUSU ================" -ForegroundColor Cyan
            if ($selectedDevice.IsFastboot) {
                Write-Host "1. Sistemi Baslat (fastboot reboot)"
                Write-Host "2. Standart Recovery (fastboot reboot recovery)"
                Write-Host "3. OEM Recovery (fastboot oem reboot-recovery)"
                Write-Host "4. Cihazi Sifirla (fastboot -w)" -ForegroundColor Magenta
                Write-Host "5. Ana Menu'ye Don"
                
                Write-Host ""
                $rbIn = Read-Host "Seciminiz"
                while ($rbIn -notmatch "^[12345]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $rbIn = Read-Host "Seciminiz" 
                }
                
                if ($rbIn -eq "5") { $state = "MAIN"; break }
                
                $fbArgs = @(); if ($targetSerial) { $fbArgs += "-s"; $fbArgs += $targetSerial }
                
                if ($rbIn -eq "1") { $fbArgs += "reboot"; & $fb $fbArgs | Out-Null; Write-Host "Sistem baslatiliyor..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "2") { $fbArgs += "reboot"; $fbArgs += "recovery"; & $fb $fbArgs | Out-Null; Write-Host "Recovery aciliyor..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "3") { $fbArgs += "oem"; $fbArgs += "reboot-recovery"; & $fb $fbArgs | Out-Null; Write-Host "Recovery aciliyor..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "4") {
                    Write-Host "`n[!] UYARI: Bu islem cihazdaki TUM VERILERI silecektir!" -ForegroundColor Red
                    
                    $wipeAns = Read-Host "Emin misiniz? (E/H)"
                    while ($wipeAns -notmatch "^[eEhH]$") { 
                        try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                        $wipeAns = Read-Host "Emin misiniz? (E/H)" 
                    }
                    
                    if ($wipeAns -match "^[eE]$") {
                        Write-Host "`nVeriler siliniyor (fastboot -w)..." -ForegroundColor Yellow
                        $wipeArgs = @(); if ($targetSerial) { $wipeArgs += "-s"; $wipeArgs += $targetSerial }
                        $wipeArgs += "-w"
                        $wipeOut = (& $fb $wipeArgs 2>&1) -join "`n"
                        
                        Write-Host "   >>> Log: $wipeOut" -ForegroundColor DarkGray
                        
                        if ($wipeOut -match "error" -or $wipeOut -match "FAILED") { Write-Host "[-] Sifirlama basarisiz oldu!" -ForegroundColor Red } 
                        else { Write-Host "[+] Cihaz basariyla sifirlandi!" -ForegroundColor Green }
                        Read-Host "`nMenuye donmek icin ENTER'a basin"
                    }
                }
            } else {
                Write-Host "1. Sistemi Baslat (adb reboot)"
                Write-Host "2. Recovery (adb reboot recovery)"
                Write-Host "3. Bootloader (adb reboot bootloader)"
                Write-Host "4. Cihazi Sifirla (fastboot -w)" -ForegroundColor Magenta
                Write-Host "5. Ana Menu'ye Don"
                
                Write-Host ""
                $rbIn = Read-Host "Seciminiz"
                while ($rbIn -notmatch "^[12345]$") { 
                    try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                    $rbIn = Read-Host "Seciminiz" 
                }
                
                if ($rbIn -eq "5") { $state = "MAIN"; break }
                
                if ($rbIn -eq "1") { & $adb -s $targetSerial reboot | Out-Null; Write-Host "Sistem baslatiliyor..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "2") { & $adb -s $targetSerial reboot recovery | Out-Null; Write-Host "Recovery aciliyor..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "3") { & $adb -s $targetSerial reboot bootloader | Out-Null; Write-Host "Bootloader aciliyor..." -ForegroundColor Green; Start-Sleep -Seconds 2; $state = "MAIN"; break }
                elseif ($rbIn -eq "4") {
                    Write-Host "`n[!] UYARI: Bu islem cihazdaki TUM VERILERI silecektir!" -ForegroundColor Red
                    
                    $wipeAns = Read-Host "Emin misiniz? (E/H)"
                    while ($wipeAns -notmatch "^[eEhH]$") { 
                        try { $p=$Host.UI.RawUI.CursorPosition; $p.Y-=1; $Host.UI.RawUI.CursorPosition=$p; Write-Host (" " * 100) -NoNewline; $Host.UI.RawUI.CursorPosition=$p } catch{}
                        $wipeAns = Read-Host "Emin misiniz? (E/H)" 
                    }
                    
                    if ($wipeAns -match "^[eE]$") {
                        Write-Host "`nCihaz Fastboot moduna aliniyor..." -ForegroundColor Yellow
                        & $adb -s $targetSerial reboot bootloader | Out-Null
                        
                        $waitRes = Wait-TargetDevice -TargetFolder "" -RequiredMode "FASTBOOT" -ActionTitle "Sifirlama icin Fastboot bekleniyor..." -TargetSerial $targetSerial
                        if ($waitRes -ne "CANCEL") {
                            $targetSerial = $waitRes
                            $selectedDevice.IsFastboot = $true
                            $selectedDevice.IsRecovery = $false
                            
                            Write-Host "`nVeriler siliniyor (fastboot -w)..." -ForegroundColor Yellow
                            $wipeArgs = @(); if ($targetSerial) { $wipeArgs += "-s"; $wipeArgs += $targetSerial }
                            $wipeArgs += "-w"
                            $wipeOut = (& $fb $wipeArgs 2>&1) -join "`n"
                            
                            Write-Host "   >>> Log: $wipeOut" -ForegroundColor DarkGray
                            
                            if ($wipeOut -match "error" -or $wipeOut -match "FAILED") { Write-Host "[-] Sifirlama basarisiz oldu!" -ForegroundColor Red } 
                            else { Write-Host "[+] Cihaz basariyla sifirlandi!" -ForegroundColor Green }
                        }
                        Read-Host "`nMenuye donmek icin ENTER'a basin"
                    }
                }
            }
        }
    }
}
