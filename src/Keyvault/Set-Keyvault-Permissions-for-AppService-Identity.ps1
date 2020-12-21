[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [String] $appServiceName,

    [Parameter(Mandatory)]
    [String] $appServiceResourceGroupName,

    [Parameter(Mandatory)]
    [String] $keyvaultCertificatePermissions,

    [Parameter(Mandatory)]
    [String] $keyvaultKeyPermissions,

    [Parameter(Mandatory)]
    [String] $keyvaultSecretPermissions,

    [Parameter(Mandatory)]
    [String] $keyvaultStoragePermissions,

    [Parameter(Mandatory)]
    [String] $keyvaultName,

    [Parameter()]
    [String] $AppServiceSlotName
)

#region ===BEGIN IMPORTS===
. "$PSScriptRoot\..\common\Invoke-Executable.ps1"
#endregion ===END IMPORTS===

$additionalParameters = @()
if ($AppServiceSlotName) {
    $additionalParameters += '--slot' , $AppServiceSlotName
}

$identityId = (Invoke-Executable az webapp identity show --resource-group $appServiceResourceGroupName --name $appServiceName @additionalParameters | ConvertFrom-Json).principalId
if (-not $identityId) {
    throw "Could not find identity for $appServiceName"
}
Write-Host "Identity ID: $identityId"

$kvcp = $keyvaultCertificatePermissions -split ' '
$kvkp = $keyvaultKeyPermissions -split ' '
$kvsp = $keyvaultSecretPermissions -split ' '
$kvstp = $keyvaultStoragePermissions -split ' '

Invoke-Executable az keyvault set-policy --certificate-permissions @kvcp --key-permissions @kvkp --secret-permissions @kvsp --storage-permissions @kvstp --object-id $identityId --name $keyvaultName