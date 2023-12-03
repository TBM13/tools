#######################################################
# Settings
#######################################################
# Override Powershell's tab-completion with psreadline's
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
# Change color of history-based prediction
Set-PSReadLineOption -Colors @{ InlinePrediction = '#707070'}
# Press Ctrl+F to accept just a word of the autosuggestion
Set-PSReadLineKeyHandler -Chord "Ctrl+f" -Function ForwardWord

#######################################################
# Variables
#######################################################
$USL = "C:\USL"
$TERMUX_HOME = "/data/data/com.termux/files/home"

$SHELLAPP = New-Object -ComObject Shell.Application
$PD = $SHELLAPP.NameSpace('shell:Desktop').Self.Path
$PDOC = $SHELLAPP.NameSpace('shell:Personal').Self.Path
$PDL = $SHELLAPP.NameSpace('shell:Downloads').Self.Path

#######################################################
# Aliases
#######################################################
function base64decode { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($args)) }
function base64encode { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($args)) }
function dif { code --diff $args}
function gcd { git clone --depth=1 $args }
function gcds { git clone --depth=1 --single-branch $args }
function gcs { git clone --single-branch $args }
function md5sum { Get-FileHash -Algorithm md5 $args }
function rkunpack { RockchipUnpackImage $args }

#######################################################
# Program Launchers
#######################################################
function Notepad([Parameter(Mandatory=$false)][string]$file)
{
    $exe = $Env:Programfiles + "\Notepad++\notepad++.exe"
	& $exe $file
}

function ColoredLogcat {
	param (
		[Parameter(ValueFromRemainingArguments=$true, Position=0)][string[]]$extraArgs,
		[Parameter(ValueFromPipeline=$true)][string]$pipe,
		[Alias("f")][string]$file,
		[Alias("v")][string]$format,
		[Alias("p")][string]$priority,
		[Alias("pi")][string]$p_id,
		[Alias("t")][string]$tag,
		[Alias("m")][string]$msg
		)
		
	begin {	
		if ($file -ne "") {
			$extraArgs += "--file"
			$extraArgs += $file
		}
		if ($format -ne "") {
			$extraArgs += "--format"
			$extraArgs += $format
		}
		# if ($ignoreFile -ne "") {
		# 	if (!(Test-Path -Path $ignoreFile)) {
		# 		$ignoreFile = "$USL\ColoredLogcat\" + $ignoreFile
		# 	}

		# 	$extraArgs += "--ignore-file"
		# 	$extraArgs += $ignoreFile
		# }
		if ($priority -ne "") {
			$extraArgs += "--priority"
			$extraArgs += $priority
		}
		if ($p_id -ne "") {
			$extraArgs += "--pid"
			$extraArgs += $p_id
		}
		if ($tag -ne "") {
			$extraArgs += "--tag"
			$extraArgs += $tag
		}
		if ($msg -ne "") {
			$extraArgs += "--message"
			$extraArgs += $msg
		}

		$pipeStr = [System.Text.StringBuilder]""
	}

	process {
		if ($pipe -eq "") {
			return
		}

		$pipeStr.AppendLine($pipe) | Out-Null
	}

	end {
		$pStr = $pipeStr.ToString()
		if ("" -ne $pStr) {
			$pStr | py "$USL\ColoredLogcat\coloredlogcat.py" @extraArgs
			return
		}

		py "$USL\ColoredLogcat\coloredlogcat.py" @extraArgs
	}
}

#######################################################
# Windows
#######################################################
function mksymlink([string]$target, [string]$path) {
	if (($path -eq "./") -or ($path -eq ".\") -or ($path.Length -eq 0)) {
		# If target is C:\something.txt, make path be .\something.txt
		$path = ".\" + (Split-Path $target -leaf)
	}

	New-Item -ItemType SymbolicLink -Target $target -Path $path
}

function IsBatteryDischarging() {
	$status = (Get-CimInstance Win32_Battery).BatteryStatus
	return $status -eq 1
}

function GetMaxCpuPower([string]$activeScheme) {
	$maxPowerGuid = "bc5038f7-23e0-4960-96da-33abaf5935ec"
	$currentMaxPower = powercfg /QUERY $activeScheme | select-string $maxPowerGuid -Context 0,7
	if (IsBatteryDischarging) {
		$currentMaxPowerValue = $currentMaxPower.Context.PostContext[6]
	}
	else {
		$currentMaxPowerValue = $currentMaxPower.Context.PostContext[5]
	}

	$currentMaxPowerValue = $currentMaxPowerValue.Split(': ')[1]
	$currentMaxPowerValue =[Int32]$currentMaxPowerValue
	return $currentMaxPowerValue
}

function SetMaxCpuPower([int]$value) {
	if (($value -gt 100) -or ($value -lt 0)) {
		Write-Error "Value is a percentage, so it must be between 0 and 100"
		return
	}
	if ($value -lt 20) {
		Write-Warning "Safeguard: Value may be too low! Aborting..."
		return
	}

	$activeSchemeInfo = (powercfg /GETACTIVESCHEME).split(' ')
	$activeScheme = $activeSchemeInfo[5]
	$activeSchemeName = $activeSchemeInfo[7]
	Write-Host "Active scheme is $activeSchemeName"

	if (IsBatteryDischarging) {
		$powerArg = "-setdcvalueindex"
		$powerTypeName = "battery"
	}
	else {
		$powerArg = "-setacvalueindex"
		$powerTypeName = "charger"
	}
	Write-Host "Current Max CPU Power while on $powerTypeName : " -NoNewline
	Write-Host (GetMaxCpuPower $activeScheme)

	powercfg $powerArg $activeScheme SUB_PROCESSOR PROCTHROTTLEMAX $value
	Write-Host "New Max CPU Power while on $powerTypeName : " -NoNewline
	Write-Host (GetMaxCpuPower $activeScheme)

	Write-Host "Applying updated scheme..."
	POWERCFG /SETACTIVE $activeScheme
}

#######################################################
# WSL
#######################################################
function ForwardWslPort([int]$port) {
	$remoteport = bash.exe -c "ifconfig eth0 | grep 'inet '"
	$found = $remoteport -match '\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}'

	if (!($found)) {
		Write-Error "Couldn't find WSL2's Ip Address. Make sure ifconfig is installed"
		return
	}

	$remoteport = $matches[0]
	Write-Host "WSL2 Ip Address: $remoteport"
	# Multiple ports are supported
	$ports=@($port)
	$addr='0.0.0.0'
	$ports_a = $ports -join ","

	Write-Host "Trying to remove our firewall rule in case it already exists..."
	iex "Remove-NetFireWallRule -DisplayName 'WSL 2 Firewall Unlock' ";

	Write-Host "Adding our firewall rules..."
	iex "New-NetFireWallRule -DisplayName 'WSL 2 Firewall Unlock' -Direction Outbound -LocalPort $ports_a -Action Allow -Protocol TCP";
	iex "New-NetFireWallRule -DisplayName 'WSL 2 Firewall Unlock' -Direction Inbound -LocalPort $ports_a -Action Allow -Protocol TCP";

	for ($i = 0; $i -lt $ports.length; $i++ ) {
		$port = $ports[$i]
		iex "netsh interface portproxy delete v4tov4 listenport=$port listenaddress=$addr"
		iex "netsh interface portproxy add v4tov4 listenport=$port listenaddress=$addr connectport=$port connectaddress=$remoteport"
	}

	Write-Host "Done. You should probably remove the port forwarding once finished"
	Write-Host "You can do it with: netsh interface portproxy delete v4tov4 listenport=$port listenaddress=$addr"
}

#######################################################
# Android Online
#######################################################
function IsAdbConnected {
    $devices = adb devices -l | find "device product:"
    return $devices.length -gt 0
}

function AdbPush([string]$localFile, [string]$remoteDst) {
    if (!(IsAdbConnected)) {
		Write-Warning "Not pushing as no devices are connected"
        return
    }
    if (!(Test-Path $localFile)) {
        Write-Error "Local file not found: '$localFile'"
        return
    }

	adb push "$localFile" "$remoteDst"
}

function CompareAndroidFile([string]$androidFile, [string]$localFile)
{
    if (!(Test-Path $localFile)) {
        Write-Error "Local file path is invalid"
        return
    }
    if (!(IsAdbConnected)) {
        Write-Error "No devices connected"
        return
    }

	$localHash = md5sum($localFile).ToLower()
	$remoteOutput = (adb shell md5sum "$androidFile" 2>&1).ToString().ToUpper()
	$remoteHash=$remoteOutput.Split(' ')[0]
	if ($remoteHash.length -ne 32) {
		Write-Error "Remote: $remoteOutput"
		return
	}

	if ($localHash -eq $remoteHash) {
		Write-Host "Local & Remote hashes match ($localHash)" -ForegroundColor Green
	}
	else {
		Write-Host "Local:  $localHash" -ForegroundColor Yellow
		Write-Host "Remote: $remoteHash" -ForegroundColor Yellow
	}
}

function TermuxSSH() 
{
    if (!(IsAdbConnected)) {
        Write-Host "No devices found!"
        return
    }

    Write-Host "Forwarding port 8022..."
    adb forward tcp:8022 tcp:8022

    Write-Host "Connecting SSH..."
    Write-Host "Tip: Password is 1"
    ssh localhost -p 8022
}

#######################################################
# Android Offline
#######################################################
function ValidateTwrpBackup()
{
	$files = Get-ChildItem *.win*
	$progress = 0
	$progressIncreaser = 100 / $files.Count
	
	$files | Foreach-Object {
		$progress += $progressIncreaser
		if ($_.FullName -match '\.sha2$') {
			return
		}
		if ($_.FullName -match '\.md5$') {
			return
		}
		
		$isMd5 = $false
		$hashFile = $_.FullName + ".sha2"
		if (!(Test-Path -Path $hashFile)) {
			$hashFile = $_.FullName + ".md5"
			$isMd5 = $true
		}
		if (!(Test-Path -Path $hashFile)) {
			Write-Host ("SHA2/MD5 not found for " + $_.Name) -ForegroundColor Red
			return
		}
		
		Write-Progress -Activity ("Validating " + $_.Name) -Status " " -PercentComplete $progress 
		
		if (!$isMd5) {
			$hash = (Get-FileHash $_.FullName).Hash
		}
		else {
			$hash = md5sum($_.FullName).ToLower()
		}
		$actualHash = ((Get-Content $hashFile) -split " ")[0]
		
		if ($hash -ne $actualHash) {
			Write-Host ("SHA2/MD5 doesn't match! -> " + $_.Name)
			return
		}

		Write-Host ("Validated: " + $_.Name) -ForegroundColor Blue
	}
	
	Write-Host "Operation Finished" -ForegroundColor Cyan
}

function OpenAIK([int]$id) {
    if ($id -lt 0) {
        Write-Error "Invalid AIK ID."
        return
    }
    if ($id -eq 0) {
        $id = 1
    }

    $aikPath = "$USL\AIK" + $id.ToString()
    if (!(Test-Path $aikPath)) {
        Write-Error "AIK ($aikPath) not found."
        return
    }

    explorer.exe $aikPath
}

function UnpackImage([string]$imagePath, [Parameter(Mandatory=$false)][int]$id) 
{
    if (!(Test-Path $imagePath)) {
        Write-Error "Image path is invalid."
        return
    }
    if ($id -lt 0) {
        Write-Error "Invalid AIK ID."
        return
    }
    if ($id -eq 0) {
        $id = 1
    }

    $aikBasePath = "$USL\AIK"
    if (!(Test-Path $aikBasePath)) {
        Write-Error "Base AIK path ($aikBasePath) not found. Please setup symbolic link."
        return
    }

    $aikPath = $aikBasePath + $id.ToString()
    if (!(Test-Path $aikPath)) {
        Start-Process ($aikBasePath + "\cleanup.bat") -Wait
        Copy-Item $aikBasePath $aikPath -Recurse
    }

    $fullImagePath = Resolve-Path $imagePath
    Start-Process ($aikPath + "\unpackimg.bat") -ArgumentList "`"$fullImagePath`"" -Wait

    explorer.exe $aikPath
}

function RockchipUnpackImage([string]$imagePath) {
    if (!(Test-Path $imagePath)) {
        Write-Error "Image path is invalid."
        return
    }
    $rkRepackerPath = "$USL\RKRepacker"
    if (!(Test-Path $rkRepackerPath)) {
        Write-Error "RK Repacker ($rkRepackerPath) not found. Please setup symbolic link."
        return
    }

    $fullImagePath = Resolve-Path $imagePath
    Start-Process ($rkRepackerPath + "\imgRePackerRK.exe") -ArgumentList "/log `"$fullImagePath`"" -Wait

	# Since we can't read the process output, lets print the tool's log and delete it
	$log = Get-Content -Raw "$fullImagePath.log"
	Write-Host $log.Substring(
		$log.IndexOf("==========================[ START ]==========================") - 20
	)
	Remove-Item "$fullImagePath.log"
}

function ZipMagiskModule([Parameter(Mandatory=$false)][string]$path) 
{
    if ($path -eq "") {
        $path = Get-Location
    }
    if (!($path.EndsWith("\")) -and !($path.EndsWith("/"))) {
        $path += "\"
    }

    if (!(Test-Path $path -PathType Container)) {
        Write-Error "Path doesn't exist or is not a folder."
        return
    }

    if (!(Test-Path ($path + "module.prop"))) {
        Write-Warning "module.prop doesn't exist. Is this a Magisk module?"
        return
    }

    $pathName = Split-Path -Path $path -Leaf
    $out = "./" + $pathName + ".zip"
    $path += "*"

    if (Test-Path $out) {
        Remove-Item $out
    }

    Compress-Archive $path $out
    AdbPush "$out" "/sdcard/"
}

function CreateMagiskModule([string]$id, [string]$path, [Parameter(Mandatory=$false)]$targetPath) {
	if (!(Test-Path $path)) {
		Write-Error "Path doesn't exist. Specify a valid file or folder"
		Write-Host "Usage: CreateMagiskModule my-id somefile.so [/system/vendor/lib/]"
		return
	}
	$base = "$USL/MagiskModuleBase"
	if (!(Test-Path $base)) {
		Write-Error "Module base doesn't exist. Setup it on $base"
		return
	}
	$dir = "./$id"
	if (Test-Path $dir) {
		Write-Error "Directory $dir already exists"
		return
	}

	Copy-Item $base $dir -Recurse
	Write-Output "id=$id`nname=$id`nversion=0`nversionCode=0`nauthor=TBM13`ndescription=$id" > "$dir/module.prop"

	$targetPath = "$dir/$targetPath"
	if (!(Test-Path $targetPath)) {
		New-Item $targetPath -Force -ItemType Directory		
	}
	Copy-Item $path $targetPath -Recurse

	ZipMagiskModule $dir
}