param()

$ErrorActionPreference = 'Stop'

$script:LabScript = Join-Path $PSScriptRoot 'Run-SpotxLab.ps1'
$script:LabRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'labs\spotx-lab'
$script:ProfilesPath = Join-Path $script:LabRoot 'profiles'
$script:WorkspacePath = Join-Path $script:LabRoot 'workspace'
$script:TempDir = Join-Path $env:TEMP 'SpotX-Lab-UI'

$script:Process = $null
$script:LogStd = Join-Path $script:TempDir 'session.out.log'
$script:LogErr = Join-Path $script:TempDir 'session.err.log'
$script:StdOffset = 0
$script:ErrOffset = 0
$script:SessionId = $null

function Get-SpotxLabProfiles {
    if (-not (Test-Path $script:ProfilesPath)) {
        return @()
    }
    Get-ChildItem -Path $script:ProfilesPath -Filter '*.json' -File | ForEach-Object {
        try {
            $json = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($json.Name) { return [pscustomobject]@{ Name = $json.Name; Path = $_.FullName } }
        } catch {}
        [pscustomobject]@{ Name = $_.BaseName; Path = $_.FullName }
    } | Sort-Object Name
}

function Ensure-WindowsForms {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop | Out-Null
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Error "Windows Forms is not available on this machine. This UI launcher requires Windows Forms."
        return $false
    }
}

function Append-Log {
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return }
    if ($script:OutputBox.IsDisposed) { return }

    if ($script:OutputBox.InvokeRequired) {
        $script:OutputBox.BeginInvoke([Action[string]]{ param($line)
            $script:OutputBox.AppendText($line + "`r`n")
            $script:OutputBox.SelectionStart = $script:OutputBox.Text.Length
            $script:OutputBox.ScrollToCaret()
        }, $Text) | Out-Null
    } else {
        $script:OutputBox.AppendText($Text + "`r`n")
        $script:OutputBox.SelectionStart = $script:OutputBox.Text.Length
        $script:OutputBox.ScrollToCaret()
    }
}

function Reset-LogState {
    $script:StdOffset = 0
    $script:ErrOffset = 0
    if (Test-Path $script:LogStd) { Remove-Item $script:LogStd -Force -ErrorAction SilentlyContinue }
    if (Test-Path $script:LogErr) { Remove-Item $script:LogErr -Force -ErrorAction SilentlyContinue }
    $script:OutputBox.Clear()
}

function Append-FileTail {
    param(
        [string]$Path,
        [ref]$Offset,
        [string]$Prefix
    )

    if (-not (Test-Path $Path)) { return }
    $text = Get-Content -Path $Path -Raw
    if ([string]::IsNullOrEmpty($text)) { return }

    if ($text.Length -gt $Offset.Value) {
        $newText = $text.Substring($Offset.Value)
        $Offset.Value = $text.Length
        if (-not [string]::IsNullOrEmpty($newText)) {
            Append-Log "$Prefix$newText"
        }
    }
}

function Set-RunningState {
    param([bool]$Running)
    $comboProfile.Enabled = -not $Running
    $inputSource.Enabled = -not $Running
    $inputExtraArgs.ReadOnly = $Running
    $checkForceRecreate.Enabled = -not $Running
    $checkPrepareOnly.Enabled = -not $Running
    $checkStartSpotify.Enabled = -not $Running
    $btnRun.Enabled = -not $Running
    $btnStop.Enabled = $Running
}

if (-not (Ensure-WindowsForms)) {
    throw 'SpotX Lab UI requires Windows Forms.'
}

$profiles = Get-SpotxLabProfiles
if ($profiles.Count -eq 0) {
    throw "No profiles found. Create a JSON profile under `"$($script:ProfilesPath)`"."
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SpotX Lab Launcher'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size 920, 640
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$font = New-Object System.Drawing.Font 'Segoe UI', 9

$lblProfile = New-Object System.Windows.Forms.Label
$lblProfile.Text = 'Profile'
$lblProfile.Font = $font
$lblProfile.Location = New-Object System.Drawing.Point 20, 16
$lblProfile.Size = New-Object System.Drawing.Size 90, 24
$form.Controls.Add($lblProfile)

$comboProfile = New-Object System.Windows.Forms.ComboBox
$comboProfile.Location = New-Object System.Drawing.Point 120, 14
$comboProfile.Size = New-Object System.Drawing.Size 420, 24
$comboProfile.DropDownStyle = 'DropDownList'
$comboProfile.Font = $font
foreach ($p in $profiles) { [void]$comboProfile.Items.Add($p) }
$comboProfile.DisplayMember = 'Name'
$comboProfile.ValueMember = 'Name'
$defaultProfile = $comboProfile.Items | Where-Object { $_.Name -eq 'default' } | Select-Object -First 1
if ($defaultProfile) {
    $comboProfile.SelectedItem = $defaultProfile
} else {
    $comboProfile.SelectedIndex = 0
}
$form.Controls.Add($comboProfile)

$lblSource = New-Object System.Windows.Forms.Label
$lblSource.Text = 'Spotify Source'
$lblSource.Font = $font
$lblSource.Location = New-Object System.Drawing.Point 20, 50
$lblSource.Size = New-Object System.Drawing.Size 90, 24
$form.Controls.Add($lblSource)

$inputSource = New-Object System.Windows.Forms.TextBox
$inputSource.Location = New-Object System.Drawing.Point 120, 48
$inputSource.Size = New-Object System.Drawing.Size 420, 24
$inputSource.Font = $font
$inputSource.Text = Join-Path $env:APPDATA 'Spotify'
$form.Controls.Add($inputSource)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = 'Browse...'
$btnBrowse.Font = $font
$btnBrowse.Location = New-Object System.Drawing.Point 550, 46
$btnBrowse.Size = New-Object System.Drawing.Size 90, 28
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $inputSource.Text = $dlg.SelectedPath
    }
})
$form.Controls.Add($btnBrowse)

$checkForceRecreate = New-Object System.Windows.Forms.CheckBox
$checkForceRecreate.Text = 'Force recreate workspace'
$checkForceRecreate.Location = New-Object System.Drawing.Point 120, 82
$checkForceRecreate.Size = New-Object System.Drawing.Size 190, 24
$checkForceRecreate.Font = $font
$form.Controls.Add($checkForceRecreate)

$checkPrepareOnly = New-Object System.Windows.Forms.CheckBox
$checkPrepareOnly.Text = 'Prepare only'
$checkPrepareOnly.Location = New-Object System.Drawing.Point 320, 82
$checkPrepareOnly.Size = New-Object System.Drawing.Size 120, 24
$checkPrepareOnly.Font = $font
$form.Controls.Add($checkPrepareOnly)

$checkStartSpotify = New-Object System.Windows.Forms.CheckBox
$checkStartSpotify.Text = 'Start Spotify after patch'
$checkStartSpotify.Location = New-Object System.Drawing.Point 450, 82
$checkStartSpotify.Size = New-Object System.Drawing.Size 190, 24
$checkStartSpotify.Checked = $true
$checkStartSpotify.Font = $font
$form.Controls.Add($checkStartSpotify)

$lblExtraArgs = New-Object System.Windows.Forms.Label
$lblExtraArgs.Text = 'Extra Args'
$lblExtraArgs.Font = $font
$lblExtraArgs.Location = New-Object System.Drawing.Point 20, 116
$lblExtraArgs.Size = New-Object System.Drawing.Size 90, 24
$form.Controls.Add($lblExtraArgs)

$inputExtraArgs = New-Object System.Windows.Forms.TextBox
$inputExtraArgs.Location = New-Object System.Drawing.Point 120, 114
$inputExtraArgs.Size = New-Object System.Drawing.Size 520, 24
$inputExtraArgs.Font = $font
$form.Controls.Add($inputExtraArgs)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Patch / Start'
$btnRun.Font = New-Object System.Drawing.Font(
    'Segoe UI',
    10.0,
    [System.Drawing.FontStyle]::Bold,
    [System.Drawing.GraphicsUnit]::Point
)
$btnRun.Location = New-Object System.Drawing.Point 120, 148
$btnRun.Size = New-Object System.Drawing.Size 160, 34
$form.Controls.Add($btnRun)

$btnStop = New-Object System.Windows.Forms.Button
$btnStop.Text = 'Stop Process'
$btnStop.Location = New-Object System.Drawing.Point 290, 148
$btnStop.Size = New-Object System.Drawing.Size 150, 34
$btnStop.Enabled = $false
$btnStop.ForeColor = [System.Drawing.Color]::DarkRed
$btnStop.Font = $font
$form.Controls.Add($btnStop)

$btnOpenWorkspace = New-Object System.Windows.Forms.Button
$btnOpenWorkspace.Text = 'Open Workspace'
$btnOpenWorkspace.Location = New-Object System.Drawing.Point 460, 148
$btnOpenWorkspace.Size = New-Object System.Drawing.Size 120, 34
$btnOpenWorkspace.Font = $font
$btnOpenWorkspace.Add_Click({ Start-Process explorer.exe -ArgumentList $script:WorkspacePath })
$form.Controls.Add($btnOpenWorkspace)

$btnOpenProfiles = New-Object System.Windows.Forms.Button
$btnOpenProfiles.Text = 'Open Profiles'
$btnOpenProfiles.Location = New-Object System.Drawing.Point 590, 148
$btnOpenProfiles.Size = New-Object System.Drawing.Size 120, 34
$btnOpenProfiles.Font = $font
$btnOpenProfiles.Add_Click({ Start-Process explorer.exe -ArgumentList $script:ProfilesPath })
$form.Controls.Add($btnOpenProfiles)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = 'Ready.'
$lblStatus.Font = $font
$lblStatus.Location = New-Object System.Drawing.Point 20, 192
$lblStatus.Size = New-Object System.Drawing.Size 860, 22
$form.Controls.Add($lblStatus)

$lblOutput = New-Object System.Windows.Forms.Label
$lblOutput.Text = 'Output'
$lblOutput.Font = $font
$lblOutput.Location = New-Object System.Drawing.Point 20, 214
$lblOutput.Size = New-Object System.Drawing.Size 80, 20
$form.Controls.Add($lblOutput)

$script:OutputBox = New-Object System.Windows.Forms.TextBox
$script:OutputBox.Multiline = $true
$script:OutputBox.ReadOnly = $true
$script:OutputBox.WordWrap = $false
$script:OutputBox.ScrollBars = 'Vertical'
$script:OutputBox.Location = New-Object System.Drawing.Point 20, 236
$script:OutputBox.Size = New-Object System.Drawing.Size 860, 350
$script:OutputBox.Font = New-Object System.Drawing.Font 'Consolas', 9
$form.Controls.Add($script:OutputBox)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
    if ($script:Process -eq $null) {
        return
    }

    if (Test-Path $script:LogStd) { Append-FileTail -Path $script:LogStd -Offset ([ref]$script:StdOffset) -Prefix '' }
    if (Test-Path $script:LogErr) { Append-FileTail -Path $script:LogErr -Offset ([ref]$script:ErrOffset) -Prefix '[ERR] ' }

    if ($script:Process.HasExited) {
        $timer.Stop()
        $exitCode = $script:Process.ExitCode
        Append-Log "[done] ExitCode=$exitCode"
        if ($exitCode -eq 0) {
            $lblStatus.Text = 'Completed successfully.'
        } else {
            $lblStatus.Text = "Failed with exit code $exitCode."
        }

        Set-RunningState -Running $false
        $script:Process = $null

        if (Test-Path $script:LogStd) { Append-FileTail -Path $script:LogStd -Offset ([ref]$script:StdOffset) -Prefix '' }
        if (Test-Path $script:LogErr) { Append-FileTail -Path $script:LogErr -Offset ([ref]$script:ErrOffset) -Prefix '[ERR] ' }
    }
})

$btnStop.Add_Click({
    if ($script:Process -and -not $script:Process.HasExited) {
        try {
            $script:Process.Kill($true)
            $lblStatus.Text = 'Stop requested.'
            Append-Log '[stop] Process terminated by user.'
        } catch {
            Append-Log "[stop-error] $($_.Exception.Message)"
        }
    }
})

$btnRun.Add_Click({
    if ($script:Process -ne $null) {
        return
    }
    if (-not (Test-Path $script:LabScript)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Missing launcher script:`n$($script:LabScript)",
            'SpotX Lab',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return
    }
    if (-not (Test-Path $inputSource.Text)) {
        [System.Windows.Forms.MessageBox]::Show(
            "Spotify source path is invalid:`n$($inputSource.Text)",
            'SpotX Lab',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    if (-not (Test-Path $script:TempDir)) {
        New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    }

    $script:SessionId = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $script:LogStd = Join-Path $script:TempDir "$($script:SessionId).out.log"
    $script:LogErr = Join-Path $script:TempDir "$($script:SessionId).err.log"
    Reset-LogState

    $profile = $comboProfile.SelectedItem.Name
    $args = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File'
        $script:LabScript
        '-Profile', $profile
        '-SpotifySourcePath', $inputSource.Text
    )
    if ($checkForceRecreate.Checked) { $args += '-ForceRecreate' }
    if ($checkPrepareOnly.Checked) { $args += '-PrepareOnly' }
    if ($checkStartSpotify.Checked) { $args += '-StartSpotify' }

    if (-not [string]::IsNullOrWhiteSpace($inputExtraArgs.Text)) {
        $tokens = [System.Management.Automation.PSParser]::Tokenize($inputExtraArgs.Text, [ref]$null)
        $args += ($tokens | ForEach-Object { $_.Content } | Where-Object { $_ -and $_ -ne "`r" -and $_ -ne "`n" })
    }

    $pwsh = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path $pwsh)) {
        $pwsh = Join-Path $PSHOME 'powershell.exe'
    }

    Append-Log "Launching: $pwsh $($args -join ' ')"
    Append-Log "Session: $($script:SessionId)"
    Append-Log "Logs: $($script:LogStd), $($script:LogErr)"
    $lblStatus.Text = 'Running...'
    Set-RunningState -Running $true

    try {
        $script:Process = Start-Process -FilePath $pwsh -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput $script:LogStd -RedirectStandardError $script:LogErr
        $timer.Start()
    } catch {
        Append-Log "[launch-error] $($_.Exception.Message)"
        $lblStatus.Text = 'Failed to launch run command.'
        Set-RunningState -Running $false
        $script:Process = $null
    }
})

$form.add_FormClosing({
    if ($script:Process -and -not $script:Process.HasExited) {
        $script:Process.Kill($true) | Out-Null
        $script:Process = $null
    }
    if ($timer.Enabled) { $timer.Stop() }
})

[void]$form.ShowDialog()
