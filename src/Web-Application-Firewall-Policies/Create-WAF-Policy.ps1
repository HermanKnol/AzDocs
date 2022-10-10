[CmdletBinding()]
param (
    [Parameter(Mandatory)][string] $WafPolicyName, 
    [Alias('WafPolicyResourceGroup')]
    [Parameter(Mandatory)][string] $WafPolicyResourceGroupName, 
    [Parameter(Mandatory)][string][ValidateSet('Classic_AzureFrontDoor', 'Premium_AzureFrontDoor', 'Standard_AzureFrontDoor')] $WafPolicySku,
    [Parameter()][string][ValidateSet('Detection', 'Prevention')] $WafPolicyFirewallMode = "Detection",
    [Parameter()][string] $WafPolicyRedirectUrl,
    [Parameter()][System.Object[]] $ResourceTags
)

#region ===BEGIN IMPORTS===
Import-Module "$PSScriptRoot\..\AzDocs.Common" -Force
#endregion ===END IMPORTS===

Write-Header -ScopedPSCmdlet $PSCmdlet

# Add extension for front-door
Invoke-Executable az config set extension.use_dynamic_install=yes_without_prompt

$optionalParameters = @()
if ($WafPolicyRedirectUrl) {
    $optionalParameters += "--redirect-url", $WafPolicyRedirectUrl
}

$wafPolicyId = (Invoke-Executable az network front-door waf-policy create --name $WafPolicyName --resource-group $WafPolicyResourceGroupName --sku $WafPolicySku @optionalParameters | ConvertFrom-Json).id

# Update Tags
if ($ResourceTags) {
    Set-ResourceTagsForResource -ResourceId $wafPolicyId -ResourceTags ${ResourceTags}
}

Write-Footer -ScopedPSCmdlet $PSCmdlet