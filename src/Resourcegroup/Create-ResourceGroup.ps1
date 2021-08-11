[CmdletBinding()]
param (
    [Alias("Location")]
    [Parameter(Mandatory)][string] $ResourceGroupLocation,
    [Parameter(Mandatory)][string] $ResourceGroupName,
    [Parameter(Mandatory)][string[]] $ResourceTags
)

#region ===BEGIN IMPORTS===
Import-Module "$PSScriptRoot\..\AzDocs.Common" -Force
#endregion ===END IMPORTS===

Write-Header -ScopedPSCmdlet $PSCmdlet

$resourceGroupId = (Invoke-Executable az group create --location $ResourceGroupLocation --name $ResourceGroupName --tags @ResourceTags).id

# Update Tags
Set-ResourceTagsForResource -ResourceId $resourceGroupId -ResourceTags ${ResourceTags}

Write-Footer -ScopedPSCmdlet $PSCmdlet