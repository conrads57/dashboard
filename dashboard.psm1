Import-Module PSAtera -Force
Set-AteraRecordLimit 500

$TechnicianEmail = ""
function Set-TechnicianEmail([string]$Email) { $script:TechnicianEmail = $Email }

$LastAlertRequest = Get-Date
$LastTicketRequest = Get-Date

$Colors = @{
  Warning = "FFB963";
  Critical = "FF6B63";
  Ticket = "63A9FF";
}
$Icons = @{
  Warning = "question_circle";
  Critical = "exclamation_triangle";
  Ticket = "ticket";
}

function Get-ToastedAlerts {
  $Cache:AteraAlerts.All `
    | Where-Object { (Get-Date $_.Created) -gt $LastAlertRequest } `
    | ForEach-Object {
      $Background = "#FF$($Colors[$_.Severity])"
      $Message = "$($_.DeviceName) - $($_.AlertMessage)"
      Show-UDToast -Title $_.CustomerName -Message $Message -BackgroundColor $Background -CloseOnClick -Broadcast -Icon $Icons[$_.Severity] -Duration 30000
    }
  $script:LastAlertRequest = Get-Date
}

function Get-ToastedTickets {
  $Cache:AteraTickets.All `
    | Where-Object { (Get-Date $_.TicketCreatedDate) -gt $LastTicketRequest } `
    | ForEach-Object {
      Show-UDToast -Title $_.CustomerName -Message $_.TicketTitle -BackgroundColor "#FF$($Colors.Ticket)" -CloseOnClick -Broadcast -Icon $Icons.Ticket -Duration 30000
    }
  $script:LastTicketRequest = Get-Date
}

function Get-Endpoints {
  $EveryFiveMinutes = New-UDEndpointSchedule -Every 5 -Minute
  $AlertEndpoint = New-UDEndpoint -Schedule $EveryFiveMinutes -Endpoint {
    $alerts = Get-AteraAlertsFiltered -Open
    $Cache:AteraAlerts = @{
      Warning = $alerts | Where-Object { $_.Severity -eq "Warning" };
      Critical = $alerts | Where-Object { $_.Severity -eq "Critical" };
      All = $alerts
    }
    Get-ToastedAlerts
  }
  $TicketEndpoint = New-UDEndpoint -Schedule $EveryFiveMinutes -Endpoint {
    $tickets = Get-AteraTicketsFiltered -Open -Pending -ErrorAction SilentlyContinue
    $Cache:AteraTickets = @{
      My = $tickets | Where-Object { $_.TechnicianEmail -eq $script:TechnicianEmail };
      Unassigned = $tickets | Where-Object { !$_.TechnicianEmail };
      All = $tickets | Where-Object { $_.TechnicianEmail -eq $script:TechnicianEmail -or !$_.TechnicianEmail }
    }
    Get-ToastedTickets
  }

  $GetAlerts = New-UDEndpoint -Url "/alerts" -Endpoint {
    $Cache:AteraAlerts | ConvertTo-Json
  }
  $GetTickets = New-UDEndpoint -Url "/tickets" -Endpoint {
    $Cache:AteraTickets | ConvertTo-Json
  }

  return @($AlertEndpoint, $TicketEndpoint, $GetAlerts, $GetTickets)
}

function Get-Content {
  return {
    New-UDLayout -Columns 4 -Content {
      New-UDCounter -Title "Critical Alerts" -AutoRefresh -RefreshInterval 10 -Icon $Icons.Critical -TextAlignment "Center" -TextSize "Large" -BackgroundColor "#80$($Colors.Critical)" -Endpoint {
        ([System.Array]$Cache:AteraAlerts.Critical).Count
      }
      New-UDCounter -Title "Warning Alerts" -AutoRefresh -RefreshInterval 10 -Icon $Icons.Warning -TextAlignment "Center" -TextSize "Large" -BackgroundColor "#80$($Colors.Warning)"  -Endpoint {
        ([System.Array]$Cache:AteraAlerts.Warning).Count
      }
      New-UDCounter -Title "My Tickets" -AutoRefresh -RefreshInterval 10 -Icon $Icons.Ticket -TextAlignment "Center" -TextSize "Large" -BackgroundColor "#80$($Colors.Ticket)" -Endpoint {
        $Cache:AteraTickets.My.Count
      }
      New-UDCounter -Title "Unassigned Tickets" -AutoRefresh -RefreshInterval 10 -Icon $Icons.Ticket -TextAlignment "Center" -TextSize "Large" -BackgroundColor "#80$($Colors.Ticket)" -Endpoint {
        $Cache:AteraTickets.Unassigned.Count
      }

      $ChartOptions = @{
        scales = @{
          yAxes = @(
            @{ ticks = @{ stepSize = 1; beginAtZeto = $true; suggestedMin = 0; suggestedMax = 10 } }
          )}
      }

      New-UDMonitor -Title "Critical Alerts" -Type Line -DataPointHistory 120 -RefreshInterval 60 -ChartBackgroundColor "#80$($Colors.Ticket)" -ChartBorderColor "#FF$($Colors.Ticket)" -Options $ChartOptions -Endpoint {
        ([System.Array]$Cache:AteraAlerts.Critical).Count | Out-UDMonitorData
      }
      New-UDMonitor -Title "Warning Alerts" -Type Line -DataPointHistory 120 -RefreshInterval 60 -ChartBackgroundColor "#80$($Colors.Warning)" -ChartBorderColor "#FF$($Colors.Warning)" -Options $ChartOptions -Endpoint {
        ([System.Array]$Cache:AteraAlerts.Warning).Count | Out-UDMonitorData
      }
      New-UDMonitor -Title "My Tickets" -Type Line -DataPointHistory 120 -RefreshInterval 60 -ChartBackgroundColor "#80$($Colors.Ticket)" -ChartBorderColor "#FF$($Colors.Ticket)" -Options $ChartOptions -Endpoint {
        $Cache:AteraTickets.My.Count | Out-UDMonitorData
      }
      New-UDMonitor -Title "Unassigned Tickets" -Type Line -DataPointHistory 120 -RefreshInterval 60 -ChartBackgroundColor "#80$($Colors.Ticket)" -ChartBorderColor "#FF$($Colors.Ticket)" -Options $ChartOptions -Endpoint {
        $Cache:AteraTickets.Unassigned.Count | Out-UDMonitorData
      }
    }

    New-UDGrid -Title "Open Tickets" -AutoRefresh -RefreshInterval 60 -Id "TicketGrid" -Endpoint {
      # TODO: Handle the case when $Cache:AteraTickets is null. Currently ForEach-Object errors in that case
      if (!$Cache:AteraTickets) { return }
      $Cache:AteraTickets.All | ForEach-Object {
        if ($_.Link) { return }
        $Link = New-UDLink -Text "Open" -Icon $Icons.Ticket -Url "https://app.atera.com/Admin#/ticket/$($_.TicketID)" -OpenInNewWindow
        $_ | Add-Member -MemberType NoteProperty -Name "Link" -Value $Link
      }
      $Cache:AteraTickets.All | Sort-Object LastEndUserCommentTimeStamp -Descending | Select-Object LastEndUserCommentTimeStamp, TicketTitle, CustomerName, TicketType, TicketStatus, TechnicianFullName, Link | Out-UDGridData
    }
  }
}

function Get-Theme {
  return New-UDTheme -Name "CustomerDark" -Parent "Azure" -Definition @{
    ".ud-counter .card-content svg" = @{
      "display" = "block";
      "margin" = "5px auto";
      "font-size" = "1.5rem";
    }
  }
}

function New-Dashboard {
  return New-UDDashboard -Title "Dashboard" -Theme (Get-Theme) -Content (Get-Content)
}

Export-ModuleMember -Function New-Dashboard,Get-Endpoints,Set-TechnicianEmail