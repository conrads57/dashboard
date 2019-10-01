[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $AteraApiKey
)

Import-Module UniversalDashboard.Community


# Create the initialization that we'll use for the endpoints
$Modules = Join-Path "$PSScriptRoot" -ChildPath "modules" | Get-ChildItem | ForEach-Object {
    return $_.FullName
}
$EndpointInit = New-UDEndpointInitialization -Module $Modules -Variable @("AteraApiKey")

# Load in all of the Endpoints that generate the data for the dashboard
$Endpoints = Join-Path -Path $PSScriptRoot -ChildPath "endpoints" | Get-ChildItem | ForEach-Object {
    return (. $_.FullName)
}

$Theme = Get-UDTheme -Name "DarkDefault"
$Dashboard = New-UDDashboard -Theme $Theme -EndpointInitialization $EndpointInit  -Content {
    New-UDLayout -Columns 4 -Content {
        New-UDMonitor -Title "Open Alerts" -Type Line -DataPointHistory 20 -ChartBackgroundColor '#80FF6B63' -ChartBorderColor '#FFFF6B63'  -Endpoint {
            $Cache:AteraAlerts.Open | Out-UDMonitorData
        } -AutoRefresh -RefreshInterval 30
        New-UDCounter -Title "Critical Alerts" -Icon "exclamation_triangle" -BackgroundColor '#ff4000' -TextAlignment center -TextSize Large -Endpoint {
            $Cache:AteraAlerts.CriticalCount
        } -AutoRefresh -RefreshInterval 30
        New-UDCounter -Title "Warning Alerts" -Icon "exclamation_circle" -BackgroundColor '#ffbf00' -TextAlignment center -TextSize Large -Endpoint {
            $Cache:AteraAlerts.WarningCount
        } -AutoRefresh -RefreshInterval 30
        New-UDCard -Title "Latest from Channel Pro" -Id "channelpro-news-card" -Endpoint { 
            New-UDElement -Tag 'ul' -Id "channelpro-news"
        }

        New-UdMonitor -Title "Open Tickets" -Type Line -DataPointHistory 20 -ChartBackgroundColor '#80FF6B63' -ChartBorderColor '#FFFF6B63'  -Endpoint {
            $Cache:AteraTickets.Open | Out-UDMonitorData
        } -AutoRefresh -RefreshInterval 30
        New-UdChart -Title "Opened vs Closed Tickets Last 30 Days" -Type Bar -AutoRefresh -Endpoint {
            @{Label="Opened vs Closed"; Opened=$Cache:AteraTickets.OpenedLast30Days; Closed=$Cache:AteraTickets.ClosedLast30Days } `
                | Out-UDChartData -LabelProperty "Label" -Dataset @(
                    New-UdChartDataset -DataProperty "Opened" -Label "Opened" -BackgroundColor "#80962F23" -HoverBackgroundColor "#80962F23"
                    New-UdChartDataset -DataProperty "Closed" -Label "Closed" -BackgroundColor "#8014558C" -HoverBackgroundColor "#8014558C"
                )
        }
        New-UDCounter -Title "Contracts expiring in 30 days" -Icon "file_contract" -TextAlignment center -TextSize Large -Endpoint {
            $Cache:AteraContracts.Expiring30Days
        } -AutoRefresh -RefreshInterval 60
        
        New-UdMonitor -Title "Monitored Agents" -Type Line -DataPointHistory 20 -ChartBackgroundColor '#80FF6B63' -ChartBorderColor '#FFFF6B63'  -Endpoint {
            $Cache:AteraAgents.Count | Out-UDMonitorData
        } -AutoRefresh -RefreshInterval 600
        New-UDCounter -Title "Servers" -Icon "Server" -TextAlignment center -TextSize Large -Endpoint {
            $Cache:AteraAgents.ServerCount
        } -AutoRefresh -RefreshInterval 30
        New-UDCounter -Title "Monitored DCs" -Icon "Server" -TextAlignment center -TextSize Large -Endpoint {
            $Cache:AteraAgents.DCCount
        } -AutoRefresh -RefreshInterval 30
        New-UDCounter -Title "Monitored Workstations" -Icon "Desktop" -TextAlignment center -TextSize Large -Endpoint {
            $Cache:AteraAgents.WorkstationCount
        } -AutoRefresh -RefreshInterval 30
        
    }
}

Start-UDDashboard -Dashboard $Dashboard -Port 8001 -AutoReload -Endpoint $Endpoints 