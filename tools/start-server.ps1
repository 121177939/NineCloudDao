param(
    [int]$Port = 8787,
    [switch]$LocalOnly,
    [switch]$ConfigureFirewall
)

$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$BindAddress = if ($LocalOnly) { [System.Net.IPAddress]::Loopback } else { [System.Net.IPAddress]::Any }
$Listener = $null
$PidFile = Join-Path $Root '.nineclouddao-server.pid'

function Get-ListeningProcessIds {
    param([int]$TargetPort)

    $Ids = New-Object System.Collections.Generic.List[int]
    try {
        $Connections = @(Get-NetTCPConnection -LocalPort $TargetPort -State Listen -ErrorAction SilentlyContinue)
        foreach ($Connection in $Connections) {
            $OwnerId = [int]$Connection.OwningProcess
            if ($OwnerId -gt 0 -and -not $Ids.Contains($OwnerId)) { $Ids.Add($OwnerId) }
        }
    } catch {}

    if ($Ids.Count -eq 0) {
        try {
            $Lines = & netstat.exe -ano -p TCP 2>$null
            foreach ($Line in $Lines) {
                if ($Line -match ('^\s*TCP\s+\S+:' + $TargetPort + '\s+\S+\s+LISTENING\s+(\d+)\s*$')) {
                    $OwnerId = [int]$Matches[1]
                    if ($OwnerId -gt 0 -and -not $Ids.Contains($OwnerId)) { $Ids.Add($OwnerId) }
                }
            }
        } catch {}
    }

    return @($Ids)
}

function Get-ProcessCommandLine {
    param([int]$ProcessId)
    try {
        $ProcessInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop
        return [string]$ProcessInfo.CommandLine
    } catch {
        return ''
    }
}

function Test-IsNineCloudDaoServer {
    param([int]$ProcessId)

    $CommandLine = Get-ProcessCommandLine -ProcessId $ProcessId
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $false }

    return (
        $CommandLine -match '(?i)start-server\.ps1' -or
        $CommandLine -match '(?i)static-server\.ps1' -or
        $CommandLine -match '(?i)NineCloudDao_Game_V0\.'
    )
}

function Stop-PreviousNineCloudDaoServer {
    param([int]$TargetPort)

    $OwnerIds = @(Get-ListeningProcessIds -TargetPort $TargetPort)
    if ($OwnerIds.Count -eq 0) { return }

    $ForeignIds = New-Object System.Collections.Generic.List[int]
    foreach ($OwnerId in $OwnerIds) {
        if (Test-IsNineCloudDaoServer -ProcessId $OwnerId) {
            Write-Host "Closing previous NineCloudDao server on port $TargetPort (PID $OwnerId)..." -ForegroundColor Yellow
            try {
                Stop-Process -Id $OwnerId -Force -ErrorAction Stop
            } catch {
                throw "The previous game server could not be closed. Close its black window, then start again. PID: $OwnerId"
            }
        } else {
            $ForeignIds.Add($OwnerId)
        }
    }

    if ($ForeignIds.Count -gt 0) {
        throw "TCP port $TargetPort is being used by another application (PID: $($ForeignIds -join ', ')). Close that application and start again. The game will not change ports."
    }

    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        Start-Sleep -Milliseconds 150
        if (@(Get-ListeningProcessIds -TargetPort $TargetPort).Count -eq 0) { return }
    }

    throw "TCP port $TargetPort is still busy after closing the previous game server."
}

function Get-ContentType {
    param([string]$Path)
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.html' { return 'text/html; charset=utf-8' }
        '.css'  { return 'text/css; charset=utf-8' }
        '.js'   { return 'application/javascript; charset=utf-8' }
        '.json' { return 'application/json; charset=utf-8' }
        '.txt'  { return 'text/plain; charset=utf-8' }
        '.md'   { return 'text/markdown; charset=utf-8' }
        '.png'  { return 'image/png' }
        '.jpg'  { return 'image/jpeg' }
        '.jpeg' { return 'image/jpeg' }
        '.svg'  { return 'image/svg+xml' }
        '.ico'  { return 'image/x-icon' }
        '.webmanifest' { return 'application/manifest+json; charset=utf-8' }
        default { return 'application/octet-stream' }
    }
}

function Send-HttpResponse {
    param(
        [System.IO.Stream]$Stream,
        [int]$Status,
        [string]$StatusText,
        [byte[]]$Body,
        [string]$ContentType,
        [bool]$HeadOnly = $false
    )

    if ($null -eq $Body) { $Body = [byte[]]::new(0) }
    $HeaderLines = @(
        "HTTP/1.1 $Status $StatusText",
        "Content-Type: $ContentType",
        "Content-Length: $($Body.Length)",
        'Cache-Control: no-store, no-cache, must-revalidate',
        'Pragma: no-cache',
        'Access-Control-Allow-Origin: *',
        'Access-Control-Allow-Methods: GET, HEAD, OPTIONS',
        'Connection: close'
    )
    $Header = ($HeaderLines -join "`r`n") + "`r`n`r`n"
    $HeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($Header)
    $Stream.Write($HeaderBytes, 0, $HeaderBytes.Length)
    if (-not $HeadOnly -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
    $Stream.Flush()
}

function Get-LanIPv4Addresses {
    $Result = New-Object System.Collections.Generic.List[string]
    foreach ($Nic in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
        if ($Nic.OperationalStatus -ne [System.Net.NetworkInformation.OperationalStatus]::Up) { continue }
        if ($Nic.NetworkInterfaceType -eq [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) { continue }
        foreach ($Unicast in $Nic.GetIPProperties().UnicastAddresses) {
            $Address = $Unicast.Address
            if ($Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { continue }
            $Text = $Address.ToString()
            if ($Text.StartsWith('169.254.')) { continue }
            if (-not $Result.Contains($Text)) { $Result.Add($Text) }
        }
    }
    return $Result
}

function Configure-MobileFirewall {
    param([int]$TargetPort)

    $RuleName = 'NineCloudDao Mobile Test 8787'
    try {
        & netsh.exe advfirewall firewall delete rule name="$RuleName" | Out-Null
        & netsh.exe advfirewall firewall add rule name="$RuleName" dir=in action=allow protocol=TCP localport=$TargetPort profile=private | Out-Null
        return $true
    } catch {
        return $false
    }
}

try {
    Stop-PreviousNineCloudDaoServer -TargetPort $Port

    $Listener = [System.Net.Sockets.TcpListener]::new($BindAddress, $Port)
    $Listener.Start()
    [System.IO.File]::WriteAllText($PidFile, [string]$PID, [System.Text.Encoding]::ASCII)

    if (-not $LocalOnly -and $ConfigureFirewall) {
        if (Configure-MobileFirewall -TargetPort $Port) {
            Write-Host "Windows Firewall rule is ready for TCP port $Port." -ForegroundColor Green
        } else {
            Write-Host 'Could not update Windows Firewall automatically.' -ForegroundColor Yellow
            Write-Host 'Allow PowerShell on Private networks if Windows asks.' -ForegroundColor Yellow
        }
    }

    $LocalUrl = "http://127.0.0.1:$Port/"
    $AddressLines = New-Object System.Collections.Generic.List[string]
    $AddressLines.Add("Computer: $LocalUrl")

    Write-Host ''
    Write-Host '==================================================' -ForegroundColor DarkYellow
    Write-Host ' NineCloudDao Web Alpha 0.13.0 is running' -ForegroundColor Yellow
    Write-Host " Fixed port: $Port" -ForegroundColor Green
    Write-Host " Computer:  $LocalUrl" -ForegroundColor Green

    if (-not $LocalOnly) {
        $LanAddresses = @(Get-LanIPv4Addresses)
        foreach ($Ip in $LanAddresses) {
            $PhoneUrl = "http://${Ip}:$Port/"
            $AddressLines.Add("Phone: $PhoneUrl")
            Write-Host " Phone:     $PhoneUrl" -ForegroundColor Cyan
        }
        if ($LanAddresses.Count -eq 0) {
            Write-Host ' No LAN IPv4 address was found.' -ForegroundColor Yellow
        }
        Write-Host ' Phone and computer must use the same Wi-Fi.' -ForegroundColor Gray
    }

    Write-Host ' Keep this window open while playing.' -ForegroundColor Gray
    Write-Host ' Starting a newer version will close this server automatically.' -ForegroundColor Gray
    Write-Host ' Press Ctrl+C to stop the server.' -ForegroundColor Gray
    Write-Host '==================================================' -ForegroundColor DarkYellow
    Write-Host ''

    $AddressFile = Join-Path $Root 'PHONE_ADDRESS.txt'
    [System.IO.File]::WriteAllLines($AddressFile, $AddressLines, (New-Object System.Text.UTF8Encoding($false)))
    $ChineseAddressFile = Join-Path $Root ([string]([char]0x624B) + [char]0x673A + [char]0x8BBF + [char]0x95EE + [char]0x5730 + [char]0x5740 + '.txt')
    [System.IO.File]::WriteAllLines($ChineseAddressFile, $AddressLines, (New-Object System.Text.UTF8Encoding($true)))

    Start-Process $LocalUrl

    while ($true) {
        $Client = $Listener.AcceptTcpClient()
        $Stream = $null
        $Reader = $null
        try {
            $Client.ReceiveTimeout = 15000
            $Client.SendTimeout = 15000
            $Stream = $Client.GetStream()
            $Reader = [System.IO.StreamReader]::new($Stream, [System.Text.Encoding]::ASCII, $false, 4096, $true)
            $RequestLine = $Reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($RequestLine)) { continue }

            do {
                $HeaderLine = $Reader.ReadLine()
            } while ($null -ne $HeaderLine -and $HeaderLine -ne '')

            $Parts = $RequestLine.Split(' ')
            if ($Parts.Length -lt 2) {
                $Body = [System.Text.Encoding]::UTF8.GetBytes('Bad Request')
                Send-HttpResponse -Stream $Stream -Status 400 -StatusText 'Bad Request' -Body $Body -ContentType 'text/plain; charset=utf-8'
                continue
            }

            $Method = $Parts[0].ToUpperInvariant()
            if ($Method -eq 'OPTIONS') {
                Send-HttpResponse -Stream $Stream -Status 204 -StatusText 'No Content' -Body ([byte[]]::new(0)) -ContentType 'text/plain; charset=utf-8'
                continue
            }
            if ($Method -ne 'GET' -and $Method -ne 'HEAD') {
                $Body = [System.Text.Encoding]::UTF8.GetBytes('Method Not Allowed')
                Send-HttpResponse -Stream $Stream -Status 405 -StatusText 'Method Not Allowed' -Body $Body -ContentType 'text/plain; charset=utf-8'
                continue
            }

            $RawPath = $Parts[1].Split('?')[0]
            $DecodedPath = [System.Uri]::UnescapeDataString($RawPath).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($DecodedPath)) { $DecodedPath = 'index.html' }

            $Requested = [System.IO.Path]::GetFullPath((Join-Path $Root $DecodedPath))
            $RootWithSeparator = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (($Requested -ne $Root) -and (-not $Requested.StartsWith($RootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase))) {
                $Body = [System.Text.Encoding]::UTF8.GetBytes('Forbidden')
                Send-HttpResponse -Stream $Stream -Status 403 -StatusText 'Forbidden' -Body $Body -ContentType 'text/plain; charset=utf-8' -HeadOnly ($Method -eq 'HEAD')
                continue
            }

            if (Test-Path $Requested -PathType Leaf) {
                $Body = [System.IO.File]::ReadAllBytes($Requested)
                $ContentType = Get-ContentType -Path $Requested
                Send-HttpResponse -Stream $Stream -Status 200 -StatusText 'OK' -Body $Body -ContentType $ContentType -HeadOnly ($Method -eq 'HEAD')
            } else {
                $Body = [System.Text.Encoding]::UTF8.GetBytes('Not Found')
                Send-HttpResponse -Stream $Stream -Status 404 -StatusText 'Not Found' -Body $Body -ContentType 'text/plain; charset=utf-8' -HeadOnly ($Method -eq 'HEAD')
            }
        } catch {
            if ($null -ne $Stream) {
                try {
                    $Body = [System.Text.Encoding]::UTF8.GetBytes('Internal Server Error')
                    Send-HttpResponse -Stream $Stream -Status 500 -StatusText 'Internal Server Error' -Body $Body -ContentType 'text/plain; charset=utf-8'
                } catch {}
            }
        } finally {
            if ($null -ne $Reader) { $Reader.Dispose() }
            if ($null -ne $Stream) { $Stream.Dispose() }
            if ($null -ne $Client) { $Client.Close() }
        }
    }
} catch {
    Write-Host ''
    Write-Host 'Server failed to start: ' -ForegroundColor Red -NoNewline
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    Write-Host 'NineCloudDao always uses TCP port 8787 and will not switch ports.' -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
} finally {
    if ($null -ne $Listener) { $Listener.Stop() }
    try {
        if (Test-Path $PidFile) {
            $StoredPid = [System.IO.File]::ReadAllText($PidFile).Trim()
            if ($StoredPid -eq [string]$PID) { Remove-Item $PidFile -Force -ErrorAction SilentlyContinue }
        }
    } catch {}
}
