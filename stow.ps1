# @author: https://github.com/mattialancellotti

# This sets the default parameter set to A (basically chains files)
[CmdletBinding(DefaultParameterSetName = 'stow')]
Param(
    [Parameter(Mandatory = $false)][ValidateScript({Test-Path $_})][string] $t,
    [Parameter(Mandatory = $false)][ValidateScript({Test-Path $_})][string] $d,

    [Parameter(ParameterSetName = 'stow', ValueFromRemainingArguments,Mandatory)]
    [string[]] $Stow,

    [Parameter(ParameterSetName = 'unstow',Mandatory)]
    [string[]] $Unstow,

    [Parameter()][switch] $dotfile
)
if (-not $t) {
    $t = Split-Path -Path $PWD -Parent
} else {
    $t = $t.TrimEnd('\')
}
if (-not $d) {
    $d = $PWD
} else {
    $d = $d.TrimEnd('\')
}
# Getting the user's current role and the administrative role
$userRole = [Security.Principal.WindowsIdentity]::GetCurrent()
$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

# Is Admin
$userStatus = [Security.Principal.WindowsPrincipal]::new($userRole)
if (!($userStatus.IsInRole($adminRole))) {
     Write-Error -Category PermissionDenied 'You need administration permissions'
     exit 5
}

enum Codes {
     Owner = 0
     NotLink = 1
     FileNotFound = 2
     NotOwner = 3
}
# TODO: Documentation
# This function is needed because stow-package and unstow-package need to know
# if a file can be touched, if not this function will warn them.
function Check-Ownership {
     Param( [string] $File, [string] $Package )

     # Checking if the given file actually exists
     if (!(Test-Path $File)) { return [Codes]::FileNotFound }

     # Information about the complete path of the package we are stowing
     $AbsPackage = (Resolve-Path $d\$Package).ToString()
     $PkgLength  = $AbsPackage.Length

     # Complete path of the file
     $AbsFile = (Get-Item -Force $File | Select -ExpandProperty FullName)

     # Checking if the 2 strings are identical and returning the result
     $PackageRoot = $AbsFile.Substring(0, $PkgLength)
     if ($PackageRoot.Equals($AbsPackage)) {
          return [Codes]::Owner
     }

     return [Codes]::NotOwner
}
function Link-Ownership {
    Param( [string] $File, [string] $Package )

    # Checking if the file exists
    if (!(Test-Path $File)) { return [Codes]::FileNotFound }

    # Getting Link and Target information about the given file. Then checking
    # if the file is a link. If it's not this function is useless.
    $LinkFile = (Get-Item -Force $File | Select-Object -Property LinkType, Target)
    if ([string]::isNullorEmpty($LinkFile.LinkType)) { return [Codes]::NotLink }

    # If the file is a link than check if it is linked to the right target 
    return Check-Ownership -File $LinkFile.Target -Package $Package
}
function Get-RelativePackage {
     Param( [string] $File )

     # Checking if the file exists
     if (!(Test-Path $File)) { return [Codes]::FileNotFound }

     $UnstowstLength = $t.Length

     return $File.Remove(0, ($UnstowstLength + 1))
}


function Transform-Tar {
    param (
        [string] $TarDir,
        [string] $Path
    )

    if ($dotfile -and $Path -match '^dot-') {
        $Path = $Path -replace '^dot-', '.'
    }

    if ($Path -match '~$' -and $Path -ne "~") {
        $Path = $Path -replace '~$', ''
    }

    return Join-Path -Path $TarDir -ChildPath $Path
}

function Stow-Package {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )
    
    begin { $Content = @(Get-ChildItem -Name $Source) }

    process {
        foreach ($i in $Content) {
            $Transformed = Transform-Tar -TarDir "$Destination" -Path "$i"

            # 对应文件不存在
            if (!(Test-Path $Transformed)) { 
                # 文件夹以~结尾
                if ((Get-Item -Force $Source\$i) -is [System.IO.DirectoryInfo] -and $i -match '~$') {
                    Write-Verbose "MKDIR: $Transformed"
                    New-Item -ItemType Directory -Path $Transformed -Force | Out-Null
                    Stow-Package -Source $Source\$i -Destination $Transformed
                } else {
                    Write-Verbose "LINK $Transformed => $Source\$i"
                    New-Item -ItemType SymbolicLink -Path $Transformed -Target $Source\$i | Out-Null
                }
                continue
            }


            switch (Link-Ownership -File $Transformed -Package $Packages[$StowCount]) {
                $([Codes]::FileNotFound) { Write-Error "Couldn't open file $Transformed" }
                $([Codes]::NotLink) {
                    # 对应文件是文件夹
                    if ((Get-Item -Force $Transformed) -is [System.IO.DirectoryInfo]) {
                        Stow-Package -Source $Source\$i -Destination $Transformed
                    } else { # 对应文件已存在
                        Write-Host "$Transformed : File exists and is not a link."
                    }
                }
                $([Codes]::NotOwner) {
                    if ((Get-Item $Transformed) -is [System.IO.FileInfo]) {
                        Write-Host "$Transformed is a file owned by someone else."
                        exit 1
                    }

                    $Packages | %{
                        $p = Link-Ownership -File $Transformed -Package $_

                        if ($p -eq $([Codes]::Owner)) {
                            Write-Verbose "INFO ($Transformed) Found conflict with $_."
                            Write-Verbose "UNLINK ($d\$_\$i) <= $Transformed"
                            (Get-Item "$Transformed").Delete()
                            New-Item -ItemType Directory -Path "$Transformed" | Out-Null
                            $tmp = Get-RelativePackage -File "$Transformed"
                            Stow-Package -Source "$d\$_\$tmp" -Destination "$Transformed"
                            Stow-Package -Source "$Source\$i" -Destination "$Transformed"

                            break
                        }
                    }
                    Write-Host "$Transformed file's root is not"$Packages[$StowCount]
                }
                $([Codes]::Owner) {
                    Write-Verbose "UNLINK ($Source\$i) <= $Transformed"
                    (Get-Item "$Transformed").Delete()
                    Write-Verbose "LINK ($Source\$i) => $Transformed"
                    New-Item -ItemType SymbolicLink -Path $Transformed -Target $Source\$i | Out-Null
                }
            }
        }
    }
}


function Unstow-Package {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Destination
    )

    begin { $Content = @(Get-ChildItem -Name $Source) }

    process {
        foreach ($i in $Content) {
            $Transformed = Transform-Tar -TarDir "$Destination" -Path "$i"

            Write-Verbose "UNLINK $Transformed => $Source\$i"
            if (Test-Path $Transformed) {
                $item = Get-Item -Force $Transformed
                switch ($item) {
                    { $_.PSIsContainer } {
                        Write-Verbose "Directory found: $Transformed"
                        Unstow-Package -Source "$Source/$i" -Destination "$Transformed"
                        $subItems = Get-ChildItem -Path $Transformed
                        if ($subItems.Count -eq 0 -and $i -match "~$") {
                            Remove-Item -Path "$Transformed"
                        }
                    }
                    { $_.LinkType -eq "SymbolicLink" } {
                        $linkTarget = $item.Target
                        $expectedTarget = Join-Path -Path $Source -ChildPath $i

                        if ($linkTarget -eq $expectedTarget) {
                            Write-Verbose "Removing symbolic link: $Transformed"
                            Remove-Item -Path $Transformed -Force
                        } else {
                            Write-Host "Skipping $Transformed Link points to a different target."
                        }
                    }
                    default {
                    }
                }
            } else {
                Write-Host "Package path does not exist: $Transformed"
            }
        }
    }
}


# Initializing stowing counter
$StowCount = -1
$Packages = @(if ($Stow) { $Stow } else { $Unstow })

# Choosing what the program should do based on the current parameter set.
# Basically if the user wants to stow or unstow.
switch ($PSCmdlet.ParameterSetName) {
    'stow' { 
        $Packages | ForEach-Object { 
            ++$StowCount
            Stow-Package -Source "$d\$_" -Destination $t
        }
    }
    'unstow' { 
        $Packages | ForEach-Object { 
            Unstow-Package -Source "$d\$_" -Destination $t
        }
    }
}