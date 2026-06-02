#Requires -Version 5.1
<#
.SYNOPSIS
    Installeur clean d'un voice changer temps reel sur Windows.
    Stack : w-okada VCClient (moteur) + VB-CABLE (routage audio).

.DESCRIPTION
    Script idempotent : on peut le relancer sans casser une install existante.
    Etapes :
      1. Auto-elevation administrateur
      2. Verification systeme (Windows 64 bits, GPU NVIDIA, espace disque)
      3. Installation VB-CABLE (cable audio virtuel) si absent
      4. Telechargement + extraction de VCClient (build CUDA NVIDIA par defaut)
      5. Creation d'un raccourci de lancement sur le Bureau
      6. Affichage des instructions de configuration finales

.PARAMETER InstallDir
    Dossier d'installation de VCClient. DOIT etre un chemin ASCII (pas d'accents,
    pas d'espaces) sinon onnxruntime plante. Defaut : C:\vcclient

.PARAMETER Edition
    Build VCClient : auto | cuda | dml | cpu
      auto -> detecte le GPU (NVIDIA=cuda, sinon dml)
      cuda -> NVIDIA (recommande)
      dml  -> AMD / Intel GPU (DirectML)
      cpu  -> sans GPU (lent, deconseille pour le temps reel)

.PARAMETER SkipVBCable
    Ne pas installer VB-CABLE (si deja present ou si tu utilises VoiceMeeter).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1 -Edition cuda -InstallDir C:\vcclient
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\vcclient',
    [ValidateSet('auto', 'cuda', 'dml', 'cpu')]
    [string]$Edition = 'auto',
    [switch]$SkipVBCable
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# Sources verifiees (2026-06)
$HF_REPO       = 'wok000/vcclient000'
$HF_TREE_API   = "https://huggingface.co/api/models/$HF_REPO/tree/main"
$HF_RESOLVE    = "https://huggingface.co/$HF_REPO/resolve/main"
$VBCABLE_PAGE  = 'https://vb-audio.com/Cable/'
$VBCABLE_FALLBACK = 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack43.zip'

# ---------------------------------------------------------------------------
# Helpers d'affichage
# ---------------------------------------------------------------------------
function Write-Step  ([string]$m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok    ([string]$m) { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2 ([string]$m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Write-Err2  ([string]$m) { Write-Host "    [X]  $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Auto-elevation administrateur
# ---------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host "Droits administrateur requis : relance avec elevation..." -ForegroundColor Yellow
    $argline = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -InstallDir `"$InstallDir`" -Edition $Edition"
    if ($SkipVBCable) { $argline += " -SkipVBCable" }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argline
    } catch {
        Write-Err2 "Elevation refusee. Relance ce script via un PowerShell 'Executer en tant qu'administrateur'."
    }
    exit
}

# ---------------------------------------------------------------------------
# 1. Verification systeme
# ---------------------------------------------------------------------------
function Test-System {
    Write-Step "Verification du systeme"

    if (-not [Environment]::Is64BitOperatingSystem) {
        throw "Windows 64 bits requis. Systeme 32 bits detecte."
    }
    Write-Ok "Windows 64 bits"

    # Espace disque sur le lecteur cible (besoin ~10 Go)
    $driveLetter = (Split-Path -Qualifier $InstallDir).TrimEnd(':')
    $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if ($drive) {
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        if ($freeGB -lt 10) {
            Write-Warn2 "Espace disque faible sur ${driveLetter}: ($freeGB Go). ~10 Go recommandes."
        } else {
            Write-Ok "Espace disque OK ($freeGB Go libres sur ${driveLetter}:)"
        }
    }

    # Chemin ASCII obligatoire
    if ($InstallDir -notmatch '^[\x00-\x7F]+$') {
        throw "Le dossier d'installation contient des caracteres non-ASCII : '$InstallDir'. Utilise un chemin simple comme C:\vcclient."
    }
    Write-Ok "Chemin d'installation ASCII : $InstallDir"
}

function Get-GpuKind {
    # Retourne 'nvidia', 'other' ou 'none'
    $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
    if ($gpus | Where-Object { $_.Name -match 'NVIDIA' }) { return 'nvidia' }
    if ($gpus) { return 'other' }
    return 'none'
}

function Resolve-Edition {
    if ($Edition -ne 'auto') { return $Edition }

    Write-Step "Detection du GPU"
    $kind = Get-GpuKind
    switch ($kind) {
        'nvidia' {
            $name = (Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1).Name
            Write-Ok "GPU NVIDIA detecte : $name -> build CUDA"
            if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
                $drv = (& nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null) -join ''
                if ($drv) { Write-Ok "Driver NVIDIA : $drv" }
            } else {
                Write-Warn2 "nvidia-smi introuvable. Verifie que le pilote NVIDIA est bien installe : https://www.nvidia.com/Download/index.aspx"
            }
            return 'cuda'
        }
        'other' {
            Write-Warn2 "GPU non-NVIDIA detecte -> build DirectML (dml). Pour de meilleures perfs, un GPU NVIDIA est recommande."
            return 'dml'
        }
        default {
            Write-Warn2 "Aucun GPU dedie detecte -> build CPU (temps reel difficile, deconseille)."
            return 'cpu'
        }
    }
}

# ---------------------------------------------------------------------------
# 2. VB-CABLE
# ---------------------------------------------------------------------------
function Test-VBCable {
    $snd = Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue
    return [bool]($snd | Where-Object { $_.Name -match 'VB-Audio|CABLE' })
}

function Install-VBCable {
    Write-Step "Installation de VB-CABLE (cable audio virtuel)"

    if (Test-VBCable) {
        Write-Ok "VB-CABLE deja installe (peripherique VB-Audio detecte). On saute."
        return
    }

    $tmp = Join-Path $env:TEMP ("vbcable_" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'vbcable.zip'

    # Recuperer l'URL du zip depuis la page officielle, fallback sur le lien connu
    $zipUrl = $null
    try {
        $page = Invoke-WebRequest -Uri $VBCABLE_PAGE -UseBasicParsing -TimeoutSec 30
        $link = $page.Links | Where-Object { $_.href -match 'VBCABLE_Driver_Pack.*\.zip' } | Select-Object -First 1
        if ($link) {
            $zipUrl = $link.href
            if ($zipUrl -notmatch '^https?://') { $zipUrl = ([uri]$VBCABLE_PAGE).GetLeftPart([UriPartial]::Authority) + '/' + $zipUrl.TrimStart('/') }
        }
    } catch { }
    if (-not $zipUrl) { $zipUrl = $VBCABLE_FALLBACK }
    Write-Host "    Telechargement : $zipUrl"

    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $tmp -Force

    $setup = Get-ChildItem -Path $tmp -Filter 'VBCABLE_Setup_x64.exe' -Recurse | Select-Object -First 1
    if (-not $setup) { throw "VBCABLE_Setup_x64.exe introuvable dans l'archive telechargee." }

    Write-Warn2 "Windows peut afficher une demande d'autorisation du pilote VB-Audio : clique 'Installer'."
    Start-Process -FilePath $setup.FullName -ArgumentList '-i' -Verb RunAs -Wait

    Start-Sleep -Seconds 3
    if (Test-VBCable) {
        Write-Ok "VB-CABLE installe."
    } else {
        Write-Warn2 "VB-CABLE pas encore detecte : un REDEMARRAGE est probablement necessaire pour activer les peripheriques."
        $script:NeedReboot = $true
    }

    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# 3. VCClient (moteur w-okada)
# ---------------------------------------------------------------------------
function Get-VCClientAsset ([string]$edition) {
    # Interroge l'API HuggingFace pour trouver le .zip Windows le plus recent
    # correspondant a l'edition demandee. Evite de hardcoder une version qui change.
    $pattern = switch ($edition) {
        'cuda' { 'vcclient_win_cuda' }
        'dml'  { 'vcclient_win_dml' }
        'cpu'  { 'vcclient_win_std' }
    }

    Write-Host "    Recherche du dernier build '$edition' sur HuggingFace..."
    $files = Invoke-RestMethod -Uri $HF_TREE_API -UseBasicParsing -TimeoutSec 30
    $cands = $files | Where-Object { $_.path -match [regex]::Escape($pattern) -and $_.path -match '\.zip$' }

    if (-not $cands) {
        throw "Aucun build '$edition' trouve sur https://huggingface.co/$HF_REPO/tree/main. Verifie le repo manuellement."
    }

    # Trier par version semantique extraite du nom de fichier (best-effort)
    $best = $cands | Sort-Object -Property @{ Expression = {
        if ($_.path -match '(\d+)\.(\d+)\.(\d+)') {
            [version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
        } else { [version]'0.0.0' }
    } } -Descending | Select-Object -First 1

    return $best.path
}

function Install-VCClient ([string]$edition) {
    Write-Step "Installation de VCClient (moteur voice changer, build '$edition')"

    $launcher = Get-ChildItem -Path $InstallDir -Filter 'start_http.bat' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($launcher) {
        Write-Ok "VCClient deja present : $($launcher.FullName). On saute le telechargement."
        return $launcher.FullName
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    $assetPath = Get-VCClientAsset -edition $edition
    $fileName  = Split-Path $assetPath -Leaf
    $url       = "$HF_RESOLVE/$assetPath"
    $zip       = Join-Path $InstallDir $fileName

    Write-Host "    Fichier   : $fileName"
    Write-Host "    Source    : $url"
    Write-Warn2 "Telechargement volumineux (plusieurs Go). Cela peut prendre du temps."

    # BITS gere les gros fichiers + reprise ; fallback Invoke-WebRequest
    $downloaded = $false
    try {
        Import-Module BitsTransfer -ErrorAction Stop
        Start-BitsTransfer -Source $url -Destination $zip -DisplayName "VCClient $fileName"
        $downloaded = $true
    } catch {
        Write-Warn2 "BITS indisponible, bascule sur telechargement direct..."
    }
    if (-not $downloaded) {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    }

    Write-Host "    Extraction en cours..."
    Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
    Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue

    $launcher = Get-ChildItem -Path $InstallDir -Filter 'start_http.bat' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $launcher) {
        throw "start_http.bat introuvable apres extraction dans $InstallDir."
    }
    Write-Ok "VCClient installe : $($launcher.FullName)"
    return $launcher.FullName
}

# ---------------------------------------------------------------------------
# 4. Raccourci de lancement
# ---------------------------------------------------------------------------
function New-LaunchShortcut ([string]$batPath) {
    Write-Step "Creation du raccourci de lancement"
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnk = Join-Path $desktop 'Voice Changer.lnk'
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnk)
        $sc.TargetPath       = $batPath
        $sc.WorkingDirectory = Split-Path $batPath -Parent
        $sc.IconLocation     = "$env:SystemRoot\System32\SndVol.exe,0"
        $sc.Description       = 'Lancer le voice changer (VCClient)'
        $sc.Save()
        Write-Ok "Raccourci cree sur le Bureau : Voice Changer"
    } catch {
        Write-Warn2 "Impossible de creer le raccourci : $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# 5. Instructions finales
# ---------------------------------------------------------------------------
function Show-FinalInstructions ([string]$batPath) {
    Write-Host "`n==================================================================" -ForegroundColor Green
    Write-Host "  INSTALLATION TERMINEE" -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host @"

  LANCER :
    Double-clic sur le raccourci "Voice Changer" du Bureau,
    ou execute : $batPath
    (une interface s'ouvre dans ton navigateur, sur localhost)

  CONFIGURER dans l'interface VCClient :
    1. Input  (micro)   = ton micro reel
    2. Output (sortie)  = "CABLE Input (VB-Audio Virtual Cable)"
    3. Model            = charge un modele de voix :
         - Seed-VC (zero-shot : un echantillon ~15 s suffit, simple)
         - ou RVC (.pth + .index : qualite max)
       Modeles RVC tout faits : https://huggingface.co/models?search=rvc
    4. Regle "chunk" : petit = moins de latence, plus de charge GPU.
    5. Clique Start et parle.

  ENVOYER LA VOIX VERS DISCORD / OBS / JEU :
    Dans l'app cible, choisis le micro = "CABLE Output (VB-Audio Virtual Cable)"

    Flux : Micro -> VCClient -> CABLE Input -> CABLE Output -> Discord/OBS/jeu

"@ -ForegroundColor White

    if ($script:NeedReboot) {
        Write-Warn2 "REDEMARRE le PC avant le premier lancement pour activer VB-CABLE."
    }
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
$script:NeedReboot = $false

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Voice Changer Setup - installeur automatique" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

try {
    Test-System
    $ed = Resolve-Edition
    if (-not $SkipVBCable) { Install-VBCable } else { Write-Step "VB-CABLE saute (-SkipVBCable)" }
    $bat = Install-VCClient -edition $ed
    New-LaunchShortcut -batPath $bat
    Show-FinalInstructions -batPath $bat
}
catch {
    Write-Err2 $_.Exception.Message
    Write-Host "`nInstallation interrompue. Corrige l'erreur ci-dessus et relance le script (il reprend la ou il en etait)." -ForegroundColor Red
    exit 1
}

Write-Host "`nAppuie sur une touche pour fermer..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
