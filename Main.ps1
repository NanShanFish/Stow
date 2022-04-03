# TODO:
#   - Better parameter validation:
#       + The path must exists;
#       + The package to chain should not exists;
#       + If the chained package already exists it cannot be unchained if no
#         root is found;
#       + Trim input and remove last '\'.
#   - Better error handling and better messages to the user.

# This sets the default parameter set to A (basically chains files)
[CmdletBinding(DefaultParameterSetName = 'Pack')]
Param(
     [Parameter(Mandatory)][ValidateScript({Test-Path $_})][string] $Packdir,
     [Parameter(Mandatory)][ValidateScript({Test-Path $_})][string] $Source,

     # These are the actions the program can do.
     # All of the are mandatory but since they are in differenet parameter sets
     # only one can be used
     [Parameter(ParameterSetName='Pack',Mandatory,Position=0)][string[]] $Pack,
     [Parameter(ParameterSetName='Unpack',Mandatory)][string[]] $Unpack
)

# Getting the user's current role and the administrative role
$userRole = [Security.Principal.WindowsIdentity]::GetCurrent()
$adminRole = [Security.Principal.WindowsBuiltInRole]::Administrator

# Checking if the user has administrative privilages
$userStatus = New-Object Security.Principal.WindowsPrincipal($userRole)
if ( !($userStatus.IsInRole($adminRole)) ) {
     Write-Host "You gotta be administrator boyo!! Get off me."
     exit
}

# Choosing what the program should do based on the current parameter set.
# Basically if the user wants to Chain or Unchain.
switch ($PSCmdlet.ParameterSetName) {
     "Pack" { Write-Host "Packing files."; Break }
     "Unpack" { Write-Host "Unpacking files."; Break }
}

# TODO
#   The real workflow would be:
#       - Take everything that it's in there:
#           + A directory (exists?):
#               - Yes: do not create and go deeper
#               - No: link it
#           + A file (exists?):
#               - Yes: warn the user
#               - No: Link it
function Link-Files {
     Param(
          [Parameter(Mandatory)][string] $Pkg,
          [Parameter(Mandatory)][string] $Dst,
          [Parameter(Mandatory)][string] $Src
     )

     # Getting a list of all the files/directories in $Pkg (the package getting
     # packged by Packer, it could be the root package or a subfolder). Then
     # each element gets processed.
     Get-ChildItem $Src\$Pkg | ForEach-Object {
          # First we want to know whether the current file is already present.
          # This will eventually be useful for multiple reasons:
          #     - Avoid overwriting files/recreating directories;
          #     - Identify Packer's already present links.
          #
          # TODO: If $Dst\$_ is a link, check if it is owned by one of the
          #       packages getting packed.
          if (Test-Path $Dst\$_) {

               # If the current file is a directory then we don't need to
               # create it but just to get deeper into the directory structure.
               #
               # TODO: Check if it's not a file with the same name
               if ((Get-Item $Dst\$_) -is [System.IO.DirectoryInfo]) {
                    Link-Files -Pkg $_ -Dst $Dst\$_ -Src $Src\$Pkg
               } else {
                    Write-Host "File already exists."
                    exit
               }
          } else {
               Write-Verbose "LINK ($_) => $Dst\$_"
               New-Item -ItemType SymbolicLink -Path "$Dst\$_" -Target "$Src\$Pkg\$_" | Out-Null
          }
     }
}

# Tests
$Pack | ForEach-Object { Link-Files -Pkg $_ -Dst $Packdir -Src $Source }
