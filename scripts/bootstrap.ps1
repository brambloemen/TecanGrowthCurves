<#
    Bootstrap + launcher for the Tecan Growth Curve Analyzer (Streamlit app).

    First run: silently provisions a private Python environment into the user's
    own %LOCALAPPDATA% folder. No administrator rights are required and nothing
    outside that folder is touched -- in particular PATH is not modified and any
    Python or conda already installed on the machine is left alone.

    Later runs: detects the existing environment and starts the app in seconds.
    The environment is rebuilt automatically whenever config/environment.yml
    changes.

    Users never run this directly -- they double-click "Start Tecan Analyzer.bat".
#>
[CmdletBinding()]
param(
    # Force a clean rebuild of the private environment.
    [switch]$Reinstall
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
#  Paths
# ---------------------------------------------------------------------------
$RepoRoot    = Split-Path -Parent $PSScriptRoot
$InstallRoot = Join-Path $env:LOCALAPPDATA 'TecanGrowthCurves'
$MiniforgeDir= Join-Path $InstallRoot 'miniforge'
$EnvPrefix   = Join-Path $InstallRoot 'env'
$HashFile    = Join-Path $InstallRoot '.env-hash'
$EnvYaml     = Join-Path $RepoRoot 'config\environment.yml'
$AppScript   = Join-Path $RepoRoot 'tecan_streamlit.py'
$PythonExe   = Join-Path $EnvPrefix 'python.exe'

$MiniforgeUrl = 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Windows-x86_64.exe'

# ---------------------------------------------------------------------------
#  Friendly output helpers
# ---------------------------------------------------------------------------
function Write-Step { param([string]$Message) Write-Host "  -> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "  OK  $Message" -ForegroundColor Green }
function Write-Note { param([string]$Message) Write-Host "      $Message" -ForegroundColor DarkGray }

function Stop-WithMessage {
    param([string]$Problem, [string]$Suggestion)
    Write-Host ''
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Red
    Write-Host "  Something went wrong: $Problem" -ForegroundColor Red
    if ($Suggestion) {
        Write-Host ''
        Write-Host "  What to try: $Suggestion" -ForegroundColor Yellow
    }
    Write-Host '  ---------------------------------------------------------------' -ForegroundColor Red
    Write-Host ''
    Write-Host '  Press any key to close this window.'
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    exit 1
}

Write-Host ''
Write-Host '  ===============================================================' -ForegroundColor White
Write-Host '   Tecan Growth Curve Analyzer' -ForegroundColor White
Write-Host '  ===============================================================' -ForegroundColor White
Write-Host ''

# ---------------------------------------------------------------------------
#  Sanity checks
# ---------------------------------------------------------------------------
if (-not (Test-Path $AppScript)) {
    Stop-WithMessage "Could not find tecan_streamlit.py next to this launcher." `
        "Make sure you extracted the whole ZIP file, not just the .bat file, and that all files stayed together in one folder."
}
if (-not (Test-Path $EnvYaml)) {
    Stop-WithMessage "Could not find config\environment.yml next to this launcher." `
        "Make sure you extracted the whole ZIP file, keeping the 'config' folder alongside the .bat file."
}

# ---------------------------------------------------------------------------
#  Is the private environment already good to go?
# ---------------------------------------------------------------------------
$WantHash = (Get-FileHash -Path $EnvYaml -Algorithm SHA256).Hash
$HaveHash = if (Test-Path $HashFile) { (Get-Content $HashFile -Raw).Trim() } else { '' }
$NeedsInstall = $Reinstall -or (-not (Test-Path $PythonExe)) -or ($HaveHash -ne $WantHash)

if ($NeedsInstall) {

    if ($Reinstall) {
        Write-Host '  Rebuilding the analysis environment from scratch...' -ForegroundColor Yellow
    } elseif ($HaveHash -and $HaveHash -ne $WantHash) {
        Write-Host '  The list of required packages changed - updating...' -ForegroundColor Yellow
    } else {
        Write-Host '  FIRST-TIME SETUP' -ForegroundColor Yellow
        Write-Host ''
        Write-Note 'This happens only once. It downloads about 100 MB and usually'
        Write-Note 'takes 3-10 minutes depending on your connection.'
        Write-Note 'Nothing is installed system-wide and no admin rights are needed.'
        Write-Note "Everything goes into: $InstallRoot"
    }
    Write-Host ''

    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null

    # Use the machine's configured proxy, with the signed-in user's credentials.
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $sysProxy = [System.Net.WebRequest]::GetSystemWebProxy()
        $sysProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
        [System.Net.WebRequest]::DefaultWebProxy = $sysProxy
    } catch {
        Write-Note 'Could not read the system proxy settings; continuing with a direct connection.'
    }

    # -- Step 1: Miniforge (a self-contained Python distribution) --------------
    $condaBat = Join-Path $MiniforgeDir 'condabin\conda.bat'
    if (-not (Test-Path $condaBat)) {
        $installer = Join-Path $env:TEMP 'Miniforge3-Windows-x86_64.exe'

        Write-Step 'Downloading Python (Miniforge)...'
        try {
            $ProgressPreference = 'SilentlyContinue'   # a visible progress bar makes this ~10x slower
            Invoke-WebRequest -Uri $MiniforgeUrl -OutFile $installer -UseBasicParsing
        } catch {
            Stop-WithMessage "The download failed. ($($_.Exception.Message))" `
                "Check that you are connected to the internet. If you are on a work network, the download may be blocked - ask IT to allow github.com, or use the offline HTML tool included in this folder instead."
        }

        # Best-effort integrity check against the checksum GitHub publishes
        # alongside the installer. HTTPS from github.com is the primary trust
        # anchor; this is a second line of defence.
        try {
            $expected = (Invoke-WebRequest -Uri "$MiniforgeUrl.sha256" -UseBasicParsing).Content
            $expected = ($expected -split '\s+' | Where-Object { $_ -match '^[0-9a-fA-F]{64}$' } | Select-Object -First 1)
            if ($expected) {
                $actual = (Get-FileHash -Path $installer -Algorithm SHA256).Hash
                if ($actual -ne $expected.ToUpper()) {
                    Remove-Item $installer -Force -ErrorAction SilentlyContinue
                    Stop-WithMessage 'The downloaded Python installer did not match its published checksum.' `
                        'This usually means the download was corrupted or intercepted. Try again; if it keeps happening, report it.'
                }
                Write-Note 'Download verified against its published checksum.'
            }
        } catch {
            Write-Note 'Checksum file unavailable; relying on the secure HTTPS connection to github.com.'
        }
        Write-Ok 'Downloaded.'

        Write-Step 'Installing Python (no admin rights needed)...'
        # NSIS quirk: /D must be last and must NOT be quoted, even if the path
        # contains spaces (e.g. a user name with a space in it).
        $installArgs = "/InstallationType=JustMe /RegisterPython=0 /AddToPath=0 /S /D=$MiniforgeDir"
        $proc = Start-Process -FilePath $installer -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0 -or -not (Test-Path $condaBat)) {
            Stop-WithMessage "The Python installer did not finish (exit code $($proc.ExitCode))." `
                "Your antivirus may have blocked it. Try running the launcher again, and if it still fails, ask IT whether Miniforge is permitted."
        }
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
        Write-Ok 'Python installed.'
    } else {
        Write-Ok 'Python is already installed.'
    }

    # -- Step 2: the analysis environment -------------------------------------
    Write-Step 'Installing the analysis packages (this is the slow part)...'
    Write-Note 'streamlit, pandas, numpy, scipy, openpyxl, plotly'

    if (Test-Path $EnvPrefix) { Remove-Item -Recurse -Force $EnvPrefix }
    & $condaBat env create --file $EnvYaml --prefix $EnvPrefix
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $PythonExe)) {
        Stop-WithMessage 'The analysis packages could not be installed.' `
            "This is almost always a network problem. Try running the launcher again - it will pick up where it left off. If it keeps failing, ask IT whether conda-forge.org is reachable."
    }

    Set-Content -Path $HashFile -Value $WantHash -NoNewline -Encoding ASCII
    Write-Ok 'Analysis packages installed.'
    Write-Host ''
    Write-Host '  Setup complete. Future launches will start in a few seconds.' -ForegroundColor Green
    Write-Host ''
}

# ---------------------------------------------------------------------------
#  Pick a free port so a second copy (or an unrelated service) does not clash
# ---------------------------------------------------------------------------
function Get-FreePort {
    param([int]$Start = 8501, [int]$Tries = 50)
    for ($p = $Start; $p -lt ($Start + $Tries); $p++) {
        $listener = $null
        try {
            $listener = New-Object -TypeName System.Net.Sockets.TcpListener `
                                   -ArgumentList ([System.Net.IPAddress]::Loopback), $p
            $listener.Start()
            $listener.Stop()
            return $p
        } catch {
            if ($listener) { try { $listener.Stop() } catch { } }
        }
    }
    return $Start
}
$Port = Get-FreePort

# ---------------------------------------------------------------------------
#  Launch
# ---------------------------------------------------------------------------
Write-Host '  ---------------------------------------------------------------' -ForegroundColor White
Write-Host '   Starting the analyzer - your browser will open automatically.' -ForegroundColor White
Write-Host ''
Write-Host "   If it does not, open:  http://localhost:$Port" -ForegroundColor White
Write-Host ''
Write-Host '   KEEP THIS WINDOW OPEN while you work.' -ForegroundColor Yellow
Write-Host '   Closing it stops the analyzer.' -ForegroundColor Yellow
Write-Host '  ---------------------------------------------------------------' -ForegroundColor White
Write-Host ''

Push-Location $RepoRoot
try {
    & $PythonExe -m streamlit run $AppScript `
        --server.port $Port `
        --server.headless false `
        --server.fileWatcherType none `
        --browser.gatherUsageStats false
} finally {
    Pop-Location
}

# 0 = clean exit, 0xC000013A = the user pressed Ctrl+C. Neither is a problem.
$CtrlC = -1073741510
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne $CtrlC) {
    Stop-WithMessage "The analyzer stopped unexpectedly (exit code $LASTEXITCODE)." `
        "Try running the launcher again. If the problem persists, run 'Uninstall.bat' and then start again to rebuild the environment from scratch."
}
