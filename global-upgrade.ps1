param(
    [Parameter(Mandatory=$true)][string]$RepositoryPath
)

$ErrorActionPreference = 'Stop'
$Version = '1.17'
$Owner = 'Suenee'
$Branch = 'main'
$RepoName = 'GlobalUpgrade'
$GitHubApi = 'https://api.github.com'
$Headers = @{ 'User-Agent' = "GlobalUpgrade/$Version"; 'Accept' = 'application/vnd.github+json' }

function Invoke-Git {
    param([Parameter(Mandatory=$true)][string[]]$ArgumentList,[string]$WorkingDirectory=$RepositoryPath,[switch]$Capture)
    $old = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        Push-Location -LiteralPath $WorkingDirectory
        try {
            if ($Capture) { $out = & git.exe @ArgumentList 2>&1 | ForEach-Object { "$_" } }
            else { & git.exe @ArgumentList; $out = @() }
            $code = $LASTEXITCODE
        } finally { Pop-Location }
    } finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw "git.exe $($ArgumentList -join ' ') failed with exit code $code. $($out -join ' ')" }
    if ($Capture) { return ($out -join [Environment]::NewLine).Trim() }
}

function Set-SafeDirectory([string]$Path) {
    $env:GIT_CONFIG_COUNT='1'
    $env:GIT_CONFIG_KEY_0='safe.directory'
    $env:GIT_CONFIG_VALUE_0=$Path
}

function Normalize-Version([string]$Value) {
    if([string]::IsNullOrWhiteSpace($Value)){ return '' }
    $text=$Value.Trim()
    $m=[regex]::Match($text,'(?<!\d)(\d+)\.(\d+)(?:\.(\d+))?')
    if(-not $m.Success){ return $text }
    if($m.Groups[3].Success -and $m.Groups[3].Value -ne '0'){
        return ('{0}.{1}.{2}' -f $m.Groups[1].Value,$m.Groups[2].Value,$m.Groups[3].Value)
    }
    return ('{0}.{1}' -f $m.Groups[1].Value,$m.Groups[2].Value)
}

function Get-VersionFromProjectFile([string]$ProjectFile) {
    try {
        [xml]$xml=Get-Content -Raw -LiteralPath $ProjectFile
        $v=@($xml.Project.PropertyGroup | ForEach-Object { $_.Version } | Where-Object { $_ } | Select-Object -First 1)
        if($v){ return (Normalize-Version ([string]$v[0])) }
    } catch {}
    return ''
}

function Get-Version([string]$Path) {
    if(-not (Test-Path -LiteralPath $Path -PathType Container)){ return '' }

    foreach($name in @('VERSION','version.txt')){
        $vf=Join-Path $Path $name
        if(Test-Path -LiteralPath $vf){
            try {
                $v=Normalize-Version ((Get-Content -LiteralPath $vf -TotalCount 1).Trim())
                if($v){ return $v }
            } catch {}
        }
    }

    foreach($name in @('package.json','manifest.json')){
        $jsonPath=Join-Path $Path $name
        if(Test-Path -LiteralPath $jsonPath){
            try {
                $obj=Get-Content -Raw -LiteralPath $jsonPath | ConvertFrom-Json
                $v=Normalize-Version ([string]$obj.version)
                if($v){ return $v }
            } catch {}
        }
    }

    $props=Join-Path $Path 'Directory.Build.props'
    if(Test-Path -LiteralPath $props){
        $v=Get-VersionFromProjectFile $props
        if($v){ return $v }
    }

    # Prefer application projects over helper/test projects. Search only likely source trees.
    $candidateRoots=@($Path)
    foreach($sub in @('source','src','app')){
        $p=Join-Path $Path $sub
        if(Test-Path -LiteralPath $p -PathType Container){ $candidateRoots += $p }
    }

    $repoName=Split-Path -Leaf $Path
    $projects=New-Object System.Collections.Generic.List[object]
    foreach($root in $candidateRoots | Select-Object -Unique){
        Get-ChildItem -LiteralPath $root -Filter *.csproj -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '[\\/](bin|obj|build|packages|test|tests|testing)[\\/]' } |
            ForEach-Object {
                $depth=(($_.DirectoryName.Substring($Path.Length)).TrimStart('\\') -split '[\\/]').Count
                $score=100
                if($_.BaseName -ieq $repoName){ $score-=50 }
                if($_.BaseName -match '(?i)(test|tests|cli|tool|helper|core|library|bridge)$'){ $score+=30 }
                if($_.FullName -match '(?i)[\\/](source|src)[\\/]'){ $score-=10 }
                $score += $depth
                $projects.Add([pscustomobject]@{File=$_;Score=$score})
            }
    }
    foreach($p in @($projects | Sort-Object Score,@{Expression={$_.File.FullName}})){
        $v=Get-VersionFromProjectFile $p.File.FullName
        if($v){ return $v }
    }

    # Last resort for script projects: inspect likely root metadata files, not build outputs.
    foreach($name in @('pyproject.toml','setup.cfg','setup.py')){
        $file=Join-Path $Path $name
        if(Test-Path -LiteralPath $file){
            try {
                $text=Get-Content -Raw -LiteralPath $file
                $m=[regex]::Match($text,'(?im)^\s*(?:version|__version__)\s*=\s*["'']([^"'']+)["'']')
                if($m.Success){
                    $v=Normalize-Version $m.Groups[1].Value
                    if($v){ return $v }
                }
            } catch {}
        }
    }

    return ''
}

function Test-PreviousUpgradeFailed([string]$LocalDir) {
    $log=Join-Path $LocalDir 'logs\upgrade.log'
    if(-not (Test-Path -LiteralPath $log -PathType Leaf)){ return $false }
    try {
        $tail=@(Get-Content -LiteralPath $log -Tail 80 -ErrorAction Stop)
        $status=@($tail | Where-Object { $_ -match '^STATUS:\s+' } | Select-Object -Last 1)
        if($status.Count -gt 0 -and [string]$status[0] -match '^STATUS:\s+FAILED\b'){ return $true }
    } catch {}
    return $false
}

function Get-HttpStatus($Exception) {
    try { return [int]$Exception.Response.StatusCode } catch { return 0 }
}

function Get-ManagedRepositories {
    $all=@(); $page=1
    do {
        $response=Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri "$GitHubApi/users/$Owner/repos?per_page=100&page=$page"
        $r=@($response)
        if($r.Count -eq 1 -and $r[0] -is [System.Array]){
            $r=@($r[0])
        }
        $all += $r
        $page++
    } while($r.Count -eq 100)

    Write-Host ("[DISCOVERY] Public repositories returned by GitHub: {0}" -f $all.Count)
    foreach($x in $all){
        $b=$x.default_branch
        Write-Host ''
        Write-Host ("[DISCOVERY] Checking {0}; default={1}" -f $x.name,$b)

        try {
            Invoke-RestMethod -UseBasicParsing -Headers $Headers -Uri "$GitHubApi/repos/$Owner/$($x.name)/branches/devel" | Out-Null
            $b='devel'
            Write-Host ("[DISCOVERY] {0}: using devel" -f $x.name)
        } catch {
            Write-Host ("[DISCOVERY] {0}: devel unavailable, using {1}" -f $x.name,$b)
        }

        $upgradeUri="https://raw.githubusercontent.com/$Owner/$($x.name)/$b/upgrade.cmd"
        try {
            $resp=Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri $upgradeUri
            Write-Host ("[DISCOVERY] {0}: upgrade.cmd HTTP {1}" -f $x.name,$resp.StatusCode)
            [pscustomobject]@{Name=$x.name;Branch=$b}
        } catch {
            $status=Get-HttpStatus $_.Exception
            if($status -eq 0){ $status='n/a' }
            Write-Host ("[DISCOVERY] {0}: upgrade.cmd not usable; HTTP/status={1}; {2}" -f $x.name,$status,$_.Exception.Message)
        }
    }
}

function Invoke-ProjectUpdater([string]$LocalDir) {
    $launcher=Join-Path $LocalDir 'upgrade.cmd'
    if(-not (Test-Path -LiteralPath $launcher -PathType Leaf)){ throw "upgrade.cmd is missing: $launcher" }
    $proc=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c','call upgrade.cmd') -WorkingDirectory $LocalDir -NoNewWindow -Wait -PassThru
    return [int]$proc.ExitCode
}

function Install-AuthoritativeUpdater([string]$Name,[string]$SelectedBranch,[string]$LocalDir) {
    $uri="https://raw.githubusercontent.com/$Owner/$Name/$SelectedBranch/upgrade.cmd"
    $text=(Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri $uri).Content
    $text=[Text.RegularExpressions.Regex]::Replace($text, '\r?\n', "`r`n")
    [IO.File]::WriteAllText((Join-Path $LocalDir 'upgrade.cmd'),$text,(New-Object Text.UTF8Encoding($false)))
}

Write-Host "GlobalUpgrade $Version"
Write-Host ''
Write-Host '[SELF-UPDATE] Checking GlobalUpgrade...'
$RepositoryPath=[IO.Path]::GetFullPath($RepositoryPath).TrimEnd('\')
if(-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)){ throw "Repository path does not exist: $RepositoryPath" }
if(-not (Get-Command git.exe -ErrorAction SilentlyContinue)){ throw 'Git was not found in PATH.' }
Set-SafeDirectory $RepositoryPath
if((Invoke-Git @('rev-parse','--is-inside-work-tree') -Capture) -notmatch 'true'){ throw 'GlobalUpgrade directory is not a Git repository.' }
Invoke-Git @('fetch','origin',$Branch)
$local=(Invoke-Git @('rev-parse','HEAD') -Capture).Split([Environment]::NewLine)[-1].Trim()
$remote=(Invoke-Git @('rev-parse',"origin/$Branch") -Capture).Split([Environment]::NewLine)[-1].Trim()
if($local -ne $remote){
    $dirty=& git.exe -C $RepositoryPath status --porcelain --untracked-files=no
    $rc=$LASTEXITCODE
    if($rc -ne 0){ throw 'Cannot inspect GlobalUpgrade working tree.' }
    if($dirty){ throw 'GlobalUpgrade contains tracked or staged local changes. Commit or revert them before updating.' }
    Write-Host '[SELF-UPDATE] New GlobalUpgrade revision found.'
    Invoke-Git @('reset','--hard',"origin/$Branch")
    Write-Host '[SELF-UPDATE] Repository synchronized.'
} else { Write-Host '[SELF-UPDATE] Current.' }
Write-Host ''

$root=Split-Path -Parent $RepositoryPath
$results=New-Object System.Collections.Generic.List[object]
$stateDir=Join-Path $RepositoryPath '.state'
if(-not (Test-Path -LiteralPath $stateDir)){ New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
Write-Host 'Discovering managed repositories...'
try { $managed=@(Get-ManagedRepositories) }
catch { throw "GitHub repository discovery failed: $($_.Exception.Message)" }

Write-Host ("[DISCOVERY] Managed repositories found: {0}" -f $managed.Count)
foreach($m in $managed){ Write-Host ("[DISCOVERY] {0} [{1}]" -f $m.Name,$m.Branch) }
if($managed.Count -eq 0){
    Write-Host '[DISCOVERY] ERROR: No managed repositories were detected.' -ForegroundColor Red
}

foreach($item in $managed){
    $name=$item.Name; $selected=$item.Branch; $dir=Join-Path $root $name
    Write-Host ''
    Write-Host "[$name] Checking..."
    $old=if(Test-Path -LiteralPath $dir){Get-Version $dir}else{''}
    $install=-not (Test-Path -LiteralPath (Join-Path $dir '.git'))
    try {
        if(-not (Test-Path -LiteralPath $dir)){ New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if($install){
            Install-AuthoritativeUpdater $name $selected $dir
        }
        $needs=$install
        $failureMarker=Join-Path $stateDir ($name + '.failed')
        if(-not $install){
            Set-SafeDirectory $dir
            try {
                Invoke-Git @('fetch','origin',$selected) $dir
                $lh=(Invoke-Git @('rev-parse','HEAD') $dir -Capture).Split([Environment]::NewLine)[-1].Trim()
                $rh=(Invoke-Git @('rev-parse',"origin/$selected") $dir -Capture).Split([Environment]::NewLine)[-1].Trim()
                $needs=($lh -ne $rh)
                $previousFailed=(Test-Path -LiteralPath $failureMarker) -or (Test-PreviousUpgradeFailed $dir)
                if($previousFailed -and -not $needs){
                    Write-Host "[$name] Previous upgrade attempt failed; retrying the current remote revision." -ForegroundColor Yellow
                    $needs=$true
                }
            } catch { $needs=$true }
        }
        if($needs){
            Write-Host "[$name] Starting project updater..."
            $projectRc=Invoke-ProjectUpdater $dir
            Write-Host "[$name] Project updater returned RC=$projectRc."
            Write-Host "[$name] Reading installed version..."
            $new=Get-Version $dir
            Write-Host "[$name] Installed version='$new'."
            if($projectRc -ne 0){
                Set-Content -LiteralPath $failureMarker -Value ("failed " + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')) -Encoding ASCII
                $results.Add([pscustomobject]@{Repository=$name;Old=$old;Version=$new;Status=if($install){'INSTALL'}else{'UPDATE'};Result='FAIL'})
                continue
            }
            if(-not $install){
                Write-Host "[$name] Verifying repository synchronization..."
                Set-SafeDirectory $dir
                try {
                    Write-Host "[$name] Reading local HEAD..."
                    $lhAfter=(Invoke-Git @('rev-parse','HEAD') $dir -Capture).Split([Environment]::NewLine)[-1].Trim()
                    Write-Host "[$name] Local HEAD=$lhAfter."
                    Write-Host "[$name] Reading origin/$selected HEAD..."
                    $rhAfter=(Invoke-Git @('rev-parse',"origin/$selected") $dir -Capture).Split([Environment]::NewLine)[-1].Trim()
                    Write-Host "[$name] Remote HEAD=$rhAfter."
                    if($lhAfter -ne $rhAfter){
                        Write-Host "[$name] ERROR: updater returned success but repository HEAD is not synchronized to origin/$selected." -ForegroundColor Red
                        Set-Content -LiteralPath $failureMarker -Value ("failed " + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')) -Encoding ASCII
                        $results.Add([pscustomobject]@{Repository=$name;Old=$old;Version=$new;Status='UPDATE';Result='FAIL'})
                        continue
                    }
                } catch {
                    Write-Host "[$name] ERROR: could not verify repository state after updater: $($_.Exception.Message)" -ForegroundColor Red
                    Set-Content -LiteralPath $failureMarker -Value ("failed " + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')) -Encoding ASCII
                    $results.Add([pscustomobject]@{Repository=$name;Old=$old;Version=$new;Status='UPDATE';Result='FAIL'})
                    continue
                }
            }
            Write-Host "[$name] Repository verification complete."
            if(Test-Path -LiteralPath $failureMarker){ Remove-Item -LiteralPath $failureMarker -Force -ErrorAction SilentlyContinue }
            $status=if($install){'INSTALLED'}else{'UPDATED'}
            if($old -eq $new){$oldShown=''}else{$oldShown=$old}
            $results.Add([pscustomobject]@{Repository=$name;Old=$oldShown;Version=$new;Status=$status;Result='OK'})
            Write-Host "[$name] Result recorded: $status / OK."
        } else {
            Write-Host "[$name] No update required; reading installed version..."
            $new=Get-Version $dir
            Write-Host "[$name] Installed version='$new'."
            $results.Add([pscustomobject]@{Repository=$name;Old='';Version=$new;Status='CURRENT';Result='OK'})
            Write-Host "[$name] Result recorded: CURRENT / OK."
        }
    } catch {
        if($failureMarker){ Set-Content -LiteralPath $failureMarker -Value ("failed " + (Get-Date -Format 'dd.MM.yyyy HH:mm:ss')) -Encoding ASCII }
        Write-Host "[$name] ERROR: $($_.Exception.Message)" -ForegroundColor Red
        $results.Add([pscustomobject]@{Repository=$name;Old=$old;Version=(Get-Version $dir);Status=if($install){'INSTALL'}else{'UPDATE'};Result='FAIL'})
    }
}

Write-Host ''
Write-Host "GLOBAL UPGRADE $Version"
Write-Host ('='*90)
Write-Host ('{0,-34} {1,-12} {2,-12} {3,-12} {4}' -f 'Repository','Old','Version','Status','Result')
Write-Host ('-'*90)
$ok=0;$fail=0
foreach($r in $results){
    $line=('{0,-34} {1,-12} {2,-12} {3,-12} {4}' -f $r.Repository,$r.Old,$r.Version,$r.Status,$r.Result)
    if($r.Result -eq 'OK'){
        if($r.Status -eq 'INSTALLED'){ Write-Host $line -ForegroundColor Blue }
        elseif($r.Status -eq 'CURRENT'){ Write-Host $line -ForegroundColor Yellow }
        else { Write-Host $line -ForegroundColor Green }
        $ok++
    } else {
        Write-Host $line -ForegroundColor Red
        $fail++
    }
}
Write-Host ('-'*90)
Write-Host ''
Write-Host "OK: $ok    FAIL: $fail"
Write-Host ''
if($fail -gt 0){exit 1}else{exit 0}
