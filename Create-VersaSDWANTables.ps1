# Create-VersaSDWANTables.ps1
# This script creates Auxiliary tier tables for Versa SD WAN in a Log Analytics workspace
# It uses the ARM template approach for reliable deployment

param(
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionId,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [switch]$DeployAll = $true
)

Write-Host "Versa SD WAN Tables - Auxiliary Tier Creator" -ForegroundColor Yellow
Write-Host "===========================================" -ForegroundColor Yellow

# Check for Az PowerShell module and connect if needed
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    Write-Error "❌ Az PowerShell module not found. Please install it using 'Install-Module -Name Az -AllowClobber -Force'"
    exit 1
}

try {
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "`n🔑 Connecting to Azure..." -ForegroundColor Cyan
        Connect-AzAccount
    }
    else {
        Write-Host "`n✅ Already connected to Azure as: $($context.Account.Id)" -ForegroundColor Green
    }
}
catch {
    Write-Error "❌ Failed to connect to Azure: $($_.Exception.Message)"
    exit 1
}

# Step 1: Get and select subscription if not provided
if (-not $SubscriptionId) {
    $subs = Get-AzSubscription
    
    if ($subs.Count -eq 0) {
        Write-Error "❌ No subscriptions found"
        exit 1
    }
    
    Write-Host "`n📋 Available subscriptions:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $subs.Count; $i++) {
        $sub = $subs[$i]
        Write-Host "  $($i + 1). $($sub.Name) ($($sub.Id))" -ForegroundColor White
    }
    
    do {
        $selection = Read-Host "`n🎯 Select subscription (1-$($subs.Count))"
        $selectionIndex = [int]$selection - 1
    } while ($selectionIndex -lt 0 -or $selectionIndex -ge $subs.Count)
    
    $selectedSubscription = $subs[$selectionIndex]
    $SubscriptionId = $selectedSubscription.Id
    Write-Host "✅ Selected: $($selectedSubscription.Name)" -ForegroundColor Green
    
    # Set the selected subscription as current
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}
else {
    # Set the provided subscription as current
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

# Step 2: Get resource group name if not provided
if (-not $ResourceGroupName) {
    $ResourceGroupName = Read-Host "`n📂 Enter Resource Group name (must exist)"
}

# Step 3: Get workspace name if not provided
if (-not $WorkspaceName) {
    $WorkspaceName = Read-Host "`n🏢 Enter Log Analytics Workspace name (must exist)"
}

# Step 4: Get location if not provided or confirm the default
if ($Location -eq "eastus") {
    $confirm = Read-Host "`n🌍 Use default location 'eastus'? (Y/n)"
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        # Get the location from the existing workspace
        Write-Host "  🔍 Getting workspace location..." -ForegroundColor Cyan
        try {
            $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName
            $Location = $workspace.Location
            Write-Host "  ✅ Found workspace location: $Location" -ForegroundColor Green
        }
        catch {
            Write-Host "  ❌ Failed to get workspace location: $($_.Exception.Message)" -ForegroundColor Red
            $Location = Read-Host "  🌍 Enter location (e.g., eastus, westeurope)"
        }
    }
}

Write-Host "`n📋 Configuration Summary:" -ForegroundColor Yellow
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor White
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "  Workspace: $WorkspaceName" -ForegroundColor White
Write-Host "  Location: $Location" -ForegroundColor White
Write-Host "  Deploy All Tables: $DeployAll" -ForegroundColor White

$confirm = Read-Host "`n❓ Proceed with this configuration? (Y/n)"
if ($confirm -eq 'n' -or $confirm -eq 'N') {
    Write-Host "❌ Operation cancelled" -ForegroundColor Red
    exit 0
}

# Define Versa SD WAN table definitions - these are based on common schemas for Versa networks
# Each table definition contains:
# - Name: The name of the table (will be suffixed with _CL)
# - DisplayName: A user-friendly name for the table
# - Description: A description of the table's purpose
# - Columns: The schema columns for the table
$versaTables = @(
    @{
        Name = "VersaAnalytics"
        DisplayName = "Versa Analytics Events"
        Description = "Contains analytics events from Versa SD WAN"
        Columns = @(
            @{ name = "TimeGenerated"; type = "datetime" },
            @{ name = "DeviceVendor"; type = "string" },
            @{ name = "DeviceProduct"; type = "string" },
            @{ name = "DeviceVersion"; type = "string" },
            @{ name = "DeviceEventClassID"; type = "string" },
            @{ name = "LogSeverity"; type = "int" },
            @{ name = "AppName"; type = "string" },
            @{ name = "SrcIP"; type = "string" },
            @{ name = "DstIP"; type = "string" },
            @{ name = "SrcPort"; type = "int" },
            @{ name = "DstPort"; type = "int" },
            @{ name = "Protocol"; type = "string" },
            @{ name = "EventTime"; type = "datetime" },
            @{ name = "DeviceName"; type = "string" },
            @{ name = "TenantName"; type = "string" },
            @{ name = "BytesIn"; type = "long" },
            @{ name = "BytesOut"; type = "long" },
            @{ name = "SessionDuration"; type = "int" }
        )
    },
    @{
        Name = "VersaFlowStats"
        DisplayName = "Versa Flow Statistics"
        Description = "Contains flow statistics from Versa SD WAN devices"
        Columns = @(
            @{ name = "TimeGenerated"; type = "datetime" },
            @{ name = "DeviceVendor"; type = "string" },
            @{ name = "DeviceProduct"; type = "string" },
            @{ name = "DeviceEventClassID"; type = "string" },
            @{ name = "DeviceName"; type = "string" },
            @{ name = "Interface"; type = "string" },
            @{ name = "SrcIP"; type = "string" },
            @{ name = "DstIP"; type = "string" },
            @{ name = "Protocol"; type = "string" },
            @{ name = "TotalFlows"; type = "int" },
            @{ name = "ActiveFlows"; type = "int" },
            @{ name = "PeakFlows"; type = "int" },
            @{ name = "DroppedFlows"; type = "int" },
            @{ name = "BytesIn"; type = "long" },
            @{ name = "BytesOut"; type = "long" },
            @{ name = "PacketsIn"; type = "long" },
            @{ name = "PacketsOut"; type = "long" },
            @{ name = "Latency"; type = "real" },
            @{ name = "Jitter"; type = "real" },
            @{ name = "PacketLoss"; type = "real" }
        )
    },
    @{
        Name = "VersaSecurityEvents"
        DisplayName = "Versa Security Events"
        Description = "Contains security events from Versa SD WAN including firewall and threat detection"
        Columns = @(
            @{ name = "TimeGenerated"; type = "datetime" },
            @{ name = "DeviceVendor"; type = "string" },
            @{ name = "DeviceProduct"; type = "string" },
            @{ name = "DeviceVersion"; type = "string" },
            @{ name = "DeviceEventClassID"; type = "string" },
            @{ name = "Activity"; type = "string" },
            @{ name = "LogSeverity"; type = "int" },
            @{ name = "SrcIP"; type = "string" },
            @{ name = "DstIP"; type = "string" },
            @{ name = "SrcPort"; type = "int" },
            @{ name = "DstPort"; type = "int" },
            @{ name = "Protocol"; type = "string" },
            @{ name = "RuleName"; type = "string" },
            @{ name = "Action"; type = "string" },
            @{ name = "ThreatName"; type = "string" },
            @{ name = "ThreatSeverity"; type = "string" },
            @{ name = "PolicyName"; type = "string" },
            @{ name = "DeviceName"; type = "string" },
            @{ name = "SourceZone"; type = "string" },
            @{ name = "DestinationZone"; type = "string" }
        )
    },
    @{
        Name = "VersaDeviceStatus"
        DisplayName = "Versa Device Status"
        Description = "Contains device status information from Versa SD WAN appliances"
        Columns = @(
            @{ name = "TimeGenerated"; type = "datetime" },
            @{ name = "DeviceVendor"; type = "string" },
            @{ name = "DeviceProduct"; type = "string" },
            @{ name = "DeviceVersion"; type = "string" },
            @{ name = "DeviceName"; type = "string" },
            @{ name = "DeviceType"; type = "string" },
            @{ name = "DeviceStatus"; type = "string" },
            @{ name = "CPUUtilization"; type = "real" },
            @{ name = "MemoryUtilization"; type = "real" },
            @{ name = "DiskUtilization"; type = "real" },
            @{ name = "Uptime"; type = "long" },
            @{ name = "TenantName"; type = "string" },
            @{ name = "Serial"; type = "string" },
            @{ name = "Organization"; type = "string" },
            @{ name = "SiteName"; type = "string" },
            @{ name = "Model"; type = "string" },
            @{ name = "FirmwareVersion"; type = "string" }
        )
    },
    @{
        Name = "VersaNetworkPaths"
        DisplayName = "Versa Network Paths"
        Description = "Contains network path information from Versa SD WAN"
        Columns = @(
            @{ name = "TimeGenerated"; type = "datetime" },
            @{ name = "DeviceVendor"; type = "string" },
            @{ name = "DeviceProduct"; type = "string" },
            @{ name = "SourceDevice"; type = "string" },
            @{ name = "DestinationDevice"; type = "string" },
            @{ name = "PathID"; type = "string" },
            @{ name = "PathStatus"; type = "string" },
            @{ name = "PathType"; type = "string" },
            @{ name = "PathScore"; type = "int" },
            @{ name = "Latency"; type = "real" },
            @{ name = "Jitter"; type = "real" },
            @{ name = "PacketLoss"; type = "real" },
            @{ name = "MOS"; type = "real" },
            @{ name = "Bandwidth"; type = "long" },
            @{ name = "TenantName"; type = "string" },
            @{ name = "TransportType"; type = "string" }
        )
    }
)

# Function to deploy an ARM template with Versa table definition
function Deploy-VersaTable {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$TableDefinition
    )
    
    $tableName = "$($TableDefinition.Name)_CL"
    $templateName = "VersaTable-$($TableDefinition.Name)"
    $dceName = "$($TableDefinition.Name)-DCE"
    $dcrName = "$($TableDefinition.Name)-DCR"
    
    Write-Host "`n🔧 Creating table: $tableName..." -ForegroundColor Cyan
    Write-Host "  📝 $($TableDefinition.Description)" -ForegroundColor White
    
    # Create a temporary template file
    $tempFilePath = [System.IO.Path]::GetTempFileName() + ".json"
    
    try {
        # Create the ARM template for this table
        $armTemplate = @{
            '$schema' = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
            contentVersion = "1.0.0.0"
            parameters = @{
                workspaceName = @{
                    type = "String"
                    metadata = @{
                        description = "Specify the name of the Log Analytics workspace to use"
                    }
                }
                workspaceLocation = @{
                    defaultValue = $Location
                    type = "String"
                    metadata = @{
                        description = "Specify the location of the Log Analytics workspace"
                    }
                }
                dceName = @{
                    defaultValue = $dceName
                    type = "String"
                    metadata = @{
                        description = "Specify the name of the Data Collection Endpoint to create"
                    }
                }
                dcrName = @{
                    defaultValue = $dcrName
                    type = "String"
                    metadata = @{
                        description = "Specify the name of the new Data Collection Rule to create"
                    }
                }
                tableName = @{
                    defaultValue = $tableName
                    type = "String"
                    metadata = @{
                        description = "Specify the name of the new Table to be created"
                    }
                }
            }
            variables = @{
                workspaceId = "[resourceId('Microsoft.OperationalInsights/workspaces', parameters('workspaceName'))]"
                streamName = "[concat('Custom-', parameters('tableName'))]"
            }
            resources = @(
                @{
                    type = "Microsoft.Insights/dataCollectionEndpoints"
                    apiVersion = "2023-03-11"
                    name = "[parameters('dceName')]"
                    location = "[parameters('workspaceLocation')]"
                    properties = @{
                        networkAcls = @{
                            publicNetworkAccess = "Enabled"
                        }
                    }
                }
                @{
                    type = "Microsoft.OperationalInsights/workspaces/tables"
                    apiVersion = "2023-01-01-preview"
                    name = "[concat(parameters('workspaceName'), '/', parameters('tableName'))]"
                    properties = @{
                        schema = @{
                            name = "[parameters('tableName')]"
                            columns = $TableDefinition.Columns
                        }
                        totalRetentionInDays = 365
                        plan = "Auxiliary"
                    }
                }
                @{
                    type = "Microsoft.Insights/dataCollectionRules"
                    apiVersion = "2023-03-11"
                    kind = "Direct"
                    name = "[parameters('dcrName')]"
                    location = "[parameters('workspaceLocation')]"
                    dependsOn = @(
                        "[resourceId('Microsoft.Insights/dataCollectionEndpoints', parameters('dceName'))]"
                        "[resourceId('Microsoft.OperationalInsights/workspaces/tables', parameters('workspaceName'), parameters('tableName'))]"
                    )
                    properties = @{
                        dataCollectionEndpointId = "[resourceId('Microsoft.Insights/dataCollectionEndpoints', parameters('dceName'))]"
                        streamDeclarations = @{
                            "[variables('streamName')]" = @{
                                columns = $TableDefinition.Columns
                            }
                        }
                        destinations = @{
                            logAnalytics = @(
                                @{
                                    workspaceResourceId = "[variables('workspaceId')]"
                                    name = "[parameters('workspaceName')]"
                                }
                            )
                        }
                        dataFlows = @(
                            @{
                                streams = @(
                                    "[variables('streamName')]"
                                )
                                destinations = @(
                                    "[parameters('workspaceName')]"
                                )
                                outputStream = "[concat('Custom-', parameters('tableName'))]"
                            }
                        )
                    }
                }
            )
        }
        
        # Save the ARM template to a temporary file
        $armTemplate | ConvertTo-Json -Depth 20 | Out-File -FilePath $tempFilePath -Encoding utf8
        
        # Deploy the ARM template
        $deploymentName = "VersaTable-$($TableDefinition.Name)-$(Get-Random)"
        
        Write-Host "  🚀 Deploying template: $deploymentName..." -ForegroundColor Cyan
        
        $deploymentParameters = @{
            workspaceName = $WorkspaceName
            workspaceLocation = $Location
            dceName = $dceName
            dcrName = $dcrName
            tableName = $tableName
        }
        
        $deployment = New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
                                                 -Name $deploymentName `
                                                 -TemplateFile $tempFilePath `
                                                 -TemplateParameterObject $deploymentParameters `
                                                 -ErrorAction SilentlyContinue
        
        if ($deployment.ProvisioningState -eq "Succeeded") {
            Write-Host "  ✅ Successfully deployed table: $tableName" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host "  ⚠️ Deployment failed or had warnings:" -ForegroundColor Yellow
            Write-Host "     Status: $($deployment.ProvisioningState)" -ForegroundColor Yellow
            
            # Try to get more detailed error info if available
            if ($deployment.Error) {
                Write-Host "     Error: $($deployment.Error.Message)" -ForegroundColor Red
                if ($deployment.Error.Details) {
                    foreach ($detail in $deployment.Error.Details) {
                        Write-Host "       $($detail.Message)" -ForegroundColor Red
                    }
                }
            }
            
            # Fallback to direct API call for table creation
            Write-Host "  🔄 Trying direct API method for table creation..." -ForegroundColor Yellow
            try {
                # Get an access token
                $token = (Get-AzAccessToken).Token
                $headers = @{
                    'Authorization' = "Bearer $token"
                    'Content-Type' = 'application/json'
                }
                
                $apiVersion = "2023-01-01-preview"
                $tableBody = @{
                    properties = @{
                        schema = @{
                            name = $tableName
                            columns = $TableDefinition.Columns
                        }
                        totalRetentionInDays = 365
                        plan = "Auxiliary"
                    }
                } | ConvertTo-Json -Depth 10
                
                $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName/tables/$tableName`?api-version=$apiVersion"
                
                Write-Host "     Calling REST API: $uri" -ForegroundColor Gray
                $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method PUT -Body $tableBody
                
                Write-Host "  ✅ Successfully created table via direct API call" -ForegroundColor Green
                return $true
            }
            catch {
                Write-Host "  ❌ Failed to create table via direct API: $($_.Exception.Message)" -ForegroundColor Red
                return $false
            }
        }
    }
    catch {
        Write-Host "  ❌ Error deploying table template: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        # Clean up the temporary file
        if (Test-Path $tempFilePath) {
            Remove-Item -Path $tempFilePath -Force
        }
    }
}

# Process all tables
$results = @()

if ($DeployAll) {
    # Deploy all Versa tables
    Write-Host "`n🚀 Deploying all Versa SD WAN tables..." -ForegroundColor Yellow
    
    foreach ($table in $versaTables) {
        $success = Deploy-VersaTable -TableDefinition $table
        $results += [PSCustomObject]@{
            TableName = "$($table.Name)_CL"
            Success = $success
        }
    }
}
else {
    # Let user select which tables to deploy
    Write-Host "`n📋 Available Versa SD WAN tables:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $versaTables.Count; $i++) {
        $table = $versaTables[$i]
        Write-Host "  $($i + 1). $($table.DisplayName) ($($table.Name)_CL)" -ForegroundColor White
    }
    
    $selections = Read-Host "`n🎯 Enter table numbers to deploy (comma-separated, e.g. '1,3,5') or 'all'"
    
    if ($selections -eq "all") {
        foreach ($table in $versaTables) {
            $success = Deploy-VersaTable -TableDefinition $table
            $results += [PSCustomObject]@{
                TableName = "$($table.Name)_CL"
                Success = $success
            }
        }
    }
    else {
        $selectedIndices = $selections -split "," | ForEach-Object { [int]$_.Trim() - 1 }
        
        foreach ($index in $selectedIndices) {
            if ($index -ge 0 -and $index -lt $versaTables.Count) {
                $table = $versaTables[$index]
                $success = Deploy-VersaTable -TableDefinition $table
                $results += [PSCustomObject]@{
                    TableName = "$($table.Name)_CL"
                    Success = $success
                }
            }
            else {
                Write-Host "  ⚠️ Invalid selection: $($index + 1)" -ForegroundColor Yellow
            }
        }
    }
}

# Display summary of results
Write-Host "`n📋 Deployment Summary:" -ForegroundColor Yellow
foreach ($result in $results) {
    if ($result.Success) {
        Write-Host "  ✅ $($result.TableName): Success" -ForegroundColor Green
    }
    else {
        Write-Host "  ❌ $($result.TableName): Failed" -ForegroundColor Red
    }
}

Write-Host "`n⏰ IMPORTANT TIMING INFORMATION:" -ForegroundColor Magenta
Write-Host "   Auxiliary tier tables can take 15-30 minutes to appear in the portal" -ForegroundColor White
Write-Host "   This is normal Azure behavior and does not indicate a failure" -ForegroundColor White

Write-Host "`n📊 To view your tables in the Azure Portal:" -ForegroundColor Yellow
Write-Host "   1. Go to: https://portal.azure.com" -ForegroundColor White
Write-Host "   2. Navigate to Resource Group: $ResourceGroupName" -ForegroundColor White
Write-Host "   3. Open Log Analytics workspace: $WorkspaceName" -ForegroundColor White
Write-Host "   4. Click on 'Tables' under Settings" -ForegroundColor White
Write-Host "   5. If tables don't appear immediately, wait 15-30 minutes and refresh" -ForegroundColor White
Write-Host "   6. Verify that your tables show 'Auxiliary' under the Plan column" -ForegroundColor White

Write-Host "`n🚀 Script Complete!" -ForegroundColor Cyan