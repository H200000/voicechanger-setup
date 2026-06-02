#Requires -Version 5.1
<#
.SYNOPSIS
    Installeur clean d'Applio (entrainement de voix RVC) sur Windows.
    Applio produit des modeles RVC (.pth + .index) chargeables en temps reel
    dans VCClient (installe par install.ps1).

.DESCRIPTION
    Script idempotent : on peut le relancer sans casser une install existante.
    IMPORTANT : Applio ne doit PAS tourner en administrateur. Ce script ne
    s'eleve donc pas. Lance-le en utilisateur normal (double-clic).

    Etapes :
      1. Verification systeme (Windows 64 bits, GPU NVIDIA, espace disque, chemin ASCII)
      2. Telechargement de la derniere release Applio (source) depuis GitHub
      3. Lancement de run-install.bat (bootstrappe Miniconda + dependances)
      4. Creation d'un raccourci "Applio (Training)" sur le Bureau
      5. Instructions : preparer le dataset, entrainer, exporter vers VCClient

.PARAMETER InstallDir
    Dossier d'installation d'Applio. DOIT etre un chemin ASCII sans espaces
    (conda et les chemins de modeles n'aiment pas les espaces/accents).
    Defaut : C:\Applio

.PARAMETER Tag
    Force une version Applio precise (ex: 3.6.2). Par defaut : derniere release.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-applio.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-applio.ps1 -InstallDir D:\Applio
#>
[CmdletBinding()]
param(
    [string]$InstallDir = 'C:\Applio',
    [string]$Tag = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'Continue'

# Sources verifiees (2026-06)
$GH_REPO       = 'IAHispano/Applio'
$GH_LATEST_API = "https://api.github.com/repos/$GH_REPO/releases/latest"
$GH_ARCHIVE    = "https://github.com/$GH_REPO/archive/refs/tags"  # /<tag>.zip

# ---------------------------------------------------------------------------
# Helpers d'affichage
# ---------------------------------------------------------------------------
function Write-Step  ([string]$m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok    ([string]$m) { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2 ([string]$m) { Write-Host "    [!]  $m" -ForegroundColor Yellow }
function Write-Err2  ([string]$m) { Write-Host "    [X]  $m" -ForegroundColor Red }

# ---------------------------------------------------------------------------
# Garde-fou : NE PAS tourner en administrateur (Applio le refuse)
# ---------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if (Test-Admin) {
    Write-Warn2 "Applio ne doit PAS etre lance en administrateur."
    Write-Warn2 "Ferme cette fenetre et relance install-applio.ps1 en utilisateur normal (double-clic)."
    Write-Host "`nAppuie sur une touche pour fermer..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
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

    # Chemin ASCII sans espaces (conda + chemins modeles)
    if ($InstallDir -notmatch '^[\x00-\x7F]+$') {
        throw "Le dossier d'installation contient des caracteres non-ASCII : '$InstallDir'. Utilise un chemin simple comme C:\Applio."
    }
    if ($InstallDir -match '\s') {
        throw "Le dossier d'installation contient un espace : '$InstallDir'. Conda echoue avec les espaces. Utilise C:\Applio."
    }
    Write-Ok "Chemin d'installation ASCII sans espace : $InstallDir"

    # Espace disque : Miniconda + torch + deps ~10 Go, pretrains au 1er training
    $driveLetter = (Split-Path -Qualifier $InstallDir).TrimEnd(':')
    $drive = Get-PSDrive -Name $driveLetter -ErrorAction SilentlyContinue
    if ($drive) {
        $freeGB = [math]::Round($drive.Free / 1GB, 1)
        if ($freeGB -lt 15) {
            Write-Warn2 "Espace disque faible sur ${driveLetter}: ($freeGB Go). ~25 Go recommandes (env conda + modeles)."
        } else {
            Write-Ok "Espace disque OK ($freeGB Go libres sur ${driveLetter}:)"
        }
    }

    # GPU
    $gpus = Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue
    $nv = $gpus | Where-Object { $_.Name -match 'NVIDIA' } | Select-Object -First 1
    if ($nv) {
        Write-Ok "GPU NVIDIA detecte : $($nv.Name)"
        # Avertissement carte serie RTX 50 (Blackwell, sm_120) -> CUDA 12.8+ requis
        if ($nv.Name -match 'RTX\s?50\d{2}') {
            Write-Warn2 "Carte RTX serie 50 (Blackwell) detectee : si l'entrainement plante avec 'sm_120' ou 'CUDA capability', voir la note RTX 50 dans le README (reinstaller torch en cu128)."
        }
    } else {
        Write-Warn2 "Aucun GPU NVIDIA detecte. Applio entraine SUR GPU NVIDIA. Sans, l'entrainement sera tres lent voire inexploitable."
    }
}

# ---------------------------------------------------------------------------
# 2. Resolution de la version + telechargement
# ---------------------------------------------------------------------------
function Get-LatestTag {
    if ($Tag) { return $Tag }
    Write-Host "    Recherche de la derniere release Applio sur GitHub..."
    $headers = @{ 'User-Agent' = 'voicechanger-setup' }
    $rel = Invoke-RestMethod -Uri $GH_LATEST_API -Headers $headers -UseBasicParsing -TimeoutSec 30
    if (-not $rel.tag_name) { throw "Impossible de determiner la derniere version Applio. Verifie https://github.com/$GH_REPO/releases" }
    return $rel.tag_name
}

function Find-ApplioRoot ([string]$base) {
    # Cherche le dossier contenant run-install.bat (zip GitHub = sous-dossier Applio-<tag>)
    $f = Get-ChildItem -Path $base -Filter 'run-install.bat' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($f) { return $f.Directory.FullName }
    return $null
}

function Install-Applio {
    Write-Step "Installation d'Applio (entrainement de voix)"

    # Deja installe ? (env conda present)
    $existing = Find-ApplioRoot $InstallDir
    if ($existing -and (Test-Path (Join-Path $existing 'env'))) {
        Write-Ok "Applio deja installe : $existing (env conda present). On saute."
        return $existing
    }

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    # Telechargement source si run-install.bat absent
    if (-not $existing) {
        $tag = Get-LatestTag
        Write-Ok "Version Applio : $tag"
        $url = "$GH_ARCHIVE/$tag.zip"
        $zip = Join-Path $InstallDir "applio_$tag.zip"

        Write-Host "    Source    : $url"
        Write-Warn2 "Telechargement de la source Applio..."
        try {
            Import-Module BitsTransfer -ErrorAction Stop
            Start-BitsTransfer -Source $url -Destination $zip -DisplayName "Applio $tag"
        } catch {
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        }

        Write-Host "    Extraction en cours..."
        Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
        Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue

        $existing = Find-ApplioRoot $InstallDir
        if (-not $existing) { throw "run-install.bat introuvable apres extraction dans $InstallDir." }
    }

    Write-Ok "Source Applio prete : $existing"

    # Lancer run-install.bat (bootstrappe Miniconda + deps). LONG (10-25 min).
    Write-Step "Setup de l'environnement Applio (Miniconda + dependances)"
    Write-Warn2 "Cette etape telecharge Miniconda et plusieurs Go de dependances. Compte 10 a 25 min."
    Write-Warn2 "Laisse la fenetre ouverte ; appuie sur une touche si 'run-install' te le demande a la fin."

    Push-Location $existing
    try {
        & cmd.exe /c "run-install.bat"
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if (-not (Test-Path (Join-Path $existing 'env'))) {
        throw "L'environnement Applio (dossier 'env') n'a pas ete cree. Le setup a echoue. Relance run-install.bat manuellement dans $existing."
    }
    Write-Ok "Environnement Applio installe."
    return $existing
}

# ---------------------------------------------------------------------------
# 3. Raccourci de lancement
# ---------------------------------------------------------------------------
function New-ApplioShortcut ([string]$applioDir) {
    Write-Step "Creation du raccourci de lancement"
    $bat = Join-Path $applioDir 'run-applio.bat'
    if (-not (Test-Path $bat)) { Write-Warn2 "run-applio.bat introuvable, raccourci ignore."; return $bat }
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnk = Join-Path $desktop 'Applio (Training).lnk'
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($lnk)
        $sc.TargetPath       = $bat
        $sc.WorkingDirectory = $applioDir
        $sc.IconLocation     = "$env:SystemRoot\System32\SndVol.exe,0"
        $sc.Description       = "Entrainer une voix avec Applio (RVC)"
        $sc.Save()
        Write-Ok "Raccourci cree sur le Bureau : Applio (Training)"
    } catch {
        Write-Warn2 "Impossible de creer le raccourci : $($_.Exception.Message)"
    }
    return $bat
}

# ---------------------------------------------------------------------------
# 4. Instructions finales
# ---------------------------------------------------------------------------
function Show-FinalInstructions ([string]$applioDir, [string]$bat) {
    Write-Host "`n==================================================================" -ForegroundColor Green
    Write-Host "  APPLIO INSTALLE (entrainement de voix)" -ForegroundColor Green
    Write-Host "==================================================================" -ForegroundColor Green
    Write-Host @"

  LANCER APPLIO :
    Double-clic sur le raccourci "Applio (Training)" du Bureau,
    ou execute : $bat
    (une interface s'ouvre dans ton navigateur, sur localhost)

  ENTRAINER UNE VOIX (resume) :
    1. Onglet "Train".
    2. Prepare un dataset PROPRE : 10-30 min d'audio, zero bruit/musique,
       une seule personne, intonations variees. (5 min = plancher, OK si voix
       tres distinctive ; <5 min -> prefere le zero-shot Seed-VC dans VCClient.)
    3. Donne un nom de modele, pointe vers ton dossier de dataset.
    4. "Preprocess Dataset" -> "Extract Features" -> "Train Model".
    5. Batch size : avec 8 Go de VRAM, mets 6-8 (pas plus).
    6. Ecoute les checkpoints sauvegardes : arrete quand la voix est bonne
       (trop d'epochs = voix robotique / sur-apprentissage).

  UTILISER LE MODELE DANS VCClient (temps reel) :
    Apres training, recupere les 2 fichiers dans :
      $applioDir\logs\<nom_du_modele>\
        - <nom>.pth     (le modele)
        - added_*.index (l'index)
    Dans VCClient : Model = RVC, charge le .pth ET le .index. Start. Parle.

"@ -ForegroundColor White

    Write-Warn2 "RTX serie 50 (Blackwell) : si le training plante (sm_120 / CUDA capability),"
    Write-Warn2 "voir la section 'RTX 50' du README pour reinstaller torch en cu128."
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  Applio - installeur d'entrainement de voix (RVC)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

try {
    Test-System
    $dir = Install-Applio
    $bat = New-ApplioShortcut -applioDir $dir
    Show-FinalInstructions -applioDir $dir -bat $bat
}
catch {
    Write-Err2 $_.Exception.Message
    Write-Host "`nInstallation interrompue. Corrige l'erreur ci-dessus et relance le script (il reprend la ou il en etait)." -ForegroundColor Red
    Write-Host "`nAppuie sur une touche pour fermer..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Host "`nAppuie sur une touche pour fermer..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
