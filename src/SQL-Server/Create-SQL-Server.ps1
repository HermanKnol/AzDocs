[CmdletBinding()]
param (
    # Basic Parameters
    [Parameter(Mandatory)][string] $SqlServerPassword,
    [Parameter(Mandatory)][string] $SqlServerUsername,
    [Parameter(Mandatory)][string] $SqlServerName,
    [Parameter(Mandatory)][string] $SqlServerResourceGroupName,
    [Parameter()][ValidateSet('1.0', '1.1', '1.2')][string] $SqlServerMinimalTlsVersion = '1.2',
    [Parameter()][bool] $SqlServerEnablePublicNetwork = $true,

    # VNET Whitelisting Parameters
    [Parameter()][string] $ApplicationVnetResourceGroupName,
    [Parameter()][string] $ApplicationVnetName,
    [Parameter()][string] $ApplicationSubnetName,

    # Private Endpoints
    [Alias("VnetResourceGroupName")]
    [Parameter()][string] $SqlServerPrivateEndpointVnetResourceGroupName,
    [Alias("VnetName")]
    [Parameter()][string] $SqlServerPrivateEndpointVnetName,
    [Parameter()][string] $SqlServerPrivateEndpointSubnetName,
    [Parameter()][string] $DNSZoneResourceGroupName,
    [Alias("PrivateDnsZoneName")]
    [Parameter()][string] $SqlServerPrivateDnsZoneName = "privatelink.database.windows.net",

    # Diagnostics
    [Alias("LogAnalyticsWorkspaceId")]
    [Parameter()][string] $LogAnalyticsWorkspaceResourceId,

    # Resource Tags
    [Parameter()][System.Object[]] $ResourceTags,

    # Azure AD SQL Admin
    [Parameter()][string] $SqlServerAzureAdAdminDisplayName,
    [Parameter()][string] $SqlServerAzureAdAdminObjectId,

    # Forcefully agree to this resource to be spun up to be publicly available
    [Parameter()][switch] $ForcePublic
)

#region ===BEGIN IMPORTS===
Import-Module "$PSScriptRoot\..\AzDocs.Common" -Force
#endregion ===END IMPORTS===

Write-Header -ScopedPSCmdlet $PSCmdlet

if ((!$ApplicationVnetResourceGroupName -or !$ApplicationVnetName -or !$ApplicationSubnetName) -and (!$SqlServerPrivateEndpointVnetResourceGroupName -or !$SqlServerPrivateEndpointVnetName -or !$SqlServerPrivateEndpointSubnetName -or !$DNSZoneResourceGroupName -or !$SqlServerPrivateDnsZoneName))
{
    # Check if we are making this resource public intentionally
    Assert-IntentionallyCreatedPublicResource -ForcePublic $ForcePublic
}

# Check TLS version
Assert-TLSVersion -TlsVersion $SqlServerMinimalTlsVersion

# Create SQL Server
$sqlServerId = (Invoke-Executable -AllowToFail az sql server show --name $SqlServerName --resource-group $SqlServerResourceGroupName | ConvertFrom-Json).id
if (!$sqlServerId)
{
    Invoke-Executable az sql server create --admin-password $SqlServerPassword --assign-identity --identity-type SystemAssigned --admin-user $SqlServerUsername --name $SqlServerName --resource-group $SqlServerResourceGroupName --enable-public-network $SqlServerEnablePublicNetwork --minimal-tls-version $SqlServerMinimalTlsVersion
    $sqlServerId = (Invoke-Executable -AllowToFail az sql server show --name $SqlServerName --resource-group $SqlServerResourceGroupName | ConvertFrom-Json).id
}
else
{
    # Check if we need to enable Public Networking
    if ($SqlServerEnablePublicNetwork -and $SqlServerEnablePublicNetwork -eq $true)
    {
        $publicNetworkAccess = "Enabled"
    }
    else
    {
        $publicNetworkAccess = "Disabled"
    }

    $body = @{
        identity   = @{
            type = "SystemAssigned"
        };
        properties = @{
            administratorLogin         = $SqlServerUsername;
            administratorLoginPassword = $SqlServerPassword;
            publicNetworkAccess        = $publicNetworkAccess;
            minimalTlsVersion          = $SqlServerMinimalTlsVersion
        }
    }

    if ($SqlServerAzureAdAdminObjectId -and $SqlServerAzureAdAdminDisplayName)
    {
        $body.properties += @{ administrators = @{ administratorType = 'ActiveDirectory' } }
    }

    Invoke-AzRestCall -Method PATCH -ResourceId $sqlServerId -ApiVersion "2021-02-01-preview" -Body $body
}

# Update Tags
if ($ResourceTags)
{
    Set-ResourceTagsForResource -ResourceId $sqlServerId -ResourceTags ${ResourceTags}
}

if ($SqlServerPrivateEndpointVnetResourceGroupName -and $SqlServerPrivateEndpointVnetName -and $SqlServerPrivateEndpointSubnetName -and $DNSZoneResourceGroupName -and $SqlServerPrivateDnsZoneName)
{
    Write-Host "A private endpoint is desired. Adding the needed components."
    # Fetch needed information
    $vnetId = (Invoke-Executable az network vnet show --resource-group $SqlServerPrivateEndpointVnetResourceGroupName --name $SqlServerPrivateEndpointVnetName | ConvertFrom-Json).id
    $sqlServerPrivateEndpointSubnetId = (Invoke-Executable az network vnet subnet show --resource-group $SqlServerPrivateEndpointVnetResourceGroupName --name $SqlServerPrivateEndpointSubnetName --vnet-name $SqlServerPrivateEndpointVnetName | ConvertFrom-Json).id
    $sqlServerPrivateEndpointName = "$($SqlServerName)-pvtsql"

    # Add private endpoint & Setup Private DNS
    Add-PrivateEndpoint -PrivateEndpointVnetId $vnetId -PrivateEndpointSubnetId $sqlServerPrivateEndpointSubnetId -PrivateEndpointName $sqlServerPrivateEndpointName -PrivateEndpointResourceGroupName $SqlServerResourceGroupName -TargetResourceId $sqlServerId -PrivateEndpointGroupId sqlServer -DNSZoneResourceGroupName $DNSZoneResourceGroupName -PrivateDnsZoneName $SqlServerPrivateDnsZoneName -PrivateDnsLinkName "$($SqlServerPrivateEndpointVnetName)-sql"
}


if ($ApplicationVnetResourceGroupName -and $ApplicationVnetName -and $ApplicationSubnetName)
{
    #REMOVE OLD NAMES
    $oldAccessRuleName = "$($ApplicationVnetName)_$($ApplicationSubnetName)_allow"
    Remove-VnetRulesIfExists -ServiceType 'sql' -ResourceGroupName $SqlServerResourceGroupName -ResourceName $SqlServerName -AccessRuleName $oldAccessRuleName
    # END REMOVE OLD NAMES

    Write-Host "VNET Whitelisting is desired. Adding the needed components."
    
    # Whitelist VNET
    & "$PSScriptRoot\Add-Network-Whitelist-to-Sql-Server.ps1" -SqlServerName $SqlServerName -SqlServerResourceGroupName $SqlServerResourceGroupName -SubnetToWhitelistSubnetName $ApplicationSubnetName -SubnetToWhitelistVnetName $ApplicationVnetName -SubnetToWhitelistVnetResourceGroupName $ApplicationVnetResourceGroupName
}

# Add AD Admin
if ($SqlServerAzureAdAdminObjectId -and $SqlServerAzureAdAdminDisplayName)
{
    Invoke-Executable az sql server ad-admin create --resource-group $SqlServerResourceGroupName --server $SqlServerName --object-id $SqlServerAzureAdAdminObjectId --display-name $SqlServerAzureAdAdminDisplayName
}

if ($LogAnalyticsWorkspaceResourceId)
{
    # Set auditing policy on SQL server
    Invoke-Executable az sql server audit-policy update --resource-group $SqlServerResourceGroupName --name $SqlServerName --state Enabled --lats Enabled --lawri $LogAnalyticsWorkspaceResourceId
}

Write-Footer -ScopedPSCmdlet $PSCmdlet