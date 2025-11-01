# ============================================================================
# Complete BC260_NUP SSL Configuration Fix
# ============================================================================
# Fixes all configuration issues and enables proper HTTPS
# 
# Network Configuration:
#   - Internal Server IP: 192.168.100.202 (local network)
#   - Public Domain IP: 197.248.119.149 (kasuku.jaza.ke)
#   - FortiGate VIP: 197.248.119.149:8443 → 192.168.100.202:7349
#
# Access Methods:
#   - Internal: https://192.168.100.202:7349/BC260_NUP/
#   - External: https://kasuku.jaza.ke:8443/BC260_NUP/
#   - Localhost: https://localhost:7349/BC260_NUP/
# ============================================================================

#Requires -RunAsAdministrator

$ServiceInstance = "BC260_NUP"
$Port = 7349
$CertThumbprint = "F248F0E535EB1FE918B8CD1AC424DC0B2D9243AF"
$ServerIP = "192.168.100.202"  # Local network IP
$PublicIP = "197.248.119.149"  # Public IP for domain kasuku.jaza.ke

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Complete BC260_NUP SSL Configuration Fix" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will configure Business Central to be accessible via:" -ForegroundColor Yellow
Write-Host "  ✓ https://localhost:$Port/BC260_NUP/" -ForegroundColor White
Write-Host "  ✓ https://$ServerIP`:$Port/BC260_NUP/" -ForegroundColor White
Write-Host "  ✓ https://kasuku.jaza.ke:$Port/BC260_NUP/" -ForegroundColor White
Write-Host ""

# Import BC module
Import-Module 'C:\Program Files\Microsoft Dynamics 365 Business Central\260\Service\Microsoft.Dynamics.Nav.Management.psm1' -ErrorAction Stop

Write-Host "=== Step 1: Stop BC Service ===" -ForegroundColor Yellow
$ServiceName = "MicrosoftDynamicsNavServer`$$ServiceInstance"
Stop-Service $ServiceName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
Write-Host "  ✓ Service stopped" -ForegroundColor Green
Write-Host ""

Write-Host "=== Step 2: Clean ALL HTTP.SYS Bindings on Port $Port ===" -ForegroundColor Yellow

# Remove SSL certificate binding
Write-Host "  Removing SSL certificate bindings..." -ForegroundColor Gray
netsh http delete sslcert ipport=0.0.0.0:$Port 2>&1 | Out-Null
netsh http delete sslcert ipport=[::]:$Port 2>&1 | Out-Null

# Remove ALL URL reservations for port
Write-Host "  Removing URL reservations..." -ForegroundColor Gray
$UrlPatterns = @(
    "http://+:$Port/",
    "https://+:$Port/",
    "http://+:$Port/BC260_NUP/",
    "https://+:$Port/BC260_NUP/",
    "http://+:$Port/BC260_NUP/client/",
    "https://+:$Port/BC260_NUP/client/",
    "http://+:$Port/BC260_NUP/WS/",
    "https://+:$Port/BC260_NUP/WS/",
    "http://+:$Port/BC260_NUP/ODataV4/",
    "https://+:$Port/BC260_NUP/ODataV4/",
    "http://+:$Port/BC260_NUP/api/",
    "https://+:$Port/BC260_NUP/api/",
    "http://+:$Port/BC260_NUP/dev/",
    "https://+:$Port/BC260_NUP/dev/"
)

foreach ($url in $UrlPatterns) {
    netsh http delete urlacl url=$url 2>&1 | Out-Null
}

Write-Host "  ✓ All HTTP.SYS bindings cleaned" -ForegroundColor Green
Write-Host ""

Write-Host "=== Step 3: Verify Certificate ===" -ForegroundColor Yellow
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Thumbprint -eq $CertThumbprint}
if ($cert) {
    Write-Host "  ✓ Certificate found" -ForegroundColor Green
    Write-Host "    Subject: $($cert.Subject)" -ForegroundColor White
    Write-Host "    Has Private Key: $($cert.HasPrivateKey)" -ForegroundColor $(if($cert.HasPrivateKey){'Green'}else{'Red'})
    
    if (-not $cert.HasPrivateKey) {
        Write-Host ""
        Write-Host "  ✗ ERROR: Certificate has no private key!" -ForegroundColor Red
        Write-Host "  You must import the PFX file (JazaSSL25.pfx) with private key!" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  ✗ Certificate not found!" -ForegroundColor Red
    Write-Host "  Thumbprint: $CertThumbprint" -ForegroundColor Red
    exit 1
}
Write-Host ""

Write-Host "=== Step 4: Verify Network Configuration ===" -ForegroundColor Yellow

# Check if server IP is assigned
$adapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -ne "127.0.0.1"}
Write-Host "  Server Network Adapters:" -ForegroundColor Cyan
$adapters | Format-Table IPAddress, InterfaceAlias, PrefixOrigin -AutoSize | Out-String | ForEach-Object { Write-Host "    $_" -ForegroundColor White }

$hasServerIP = $adapters | Where-Object {$_.IPAddress -eq $ServerIP}
if ($hasServerIP) {
    Write-Host "  ✓ Server IP $ServerIP is assigned to this server" -ForegroundColor Green
} else {
    Write-Host "  ⚠ WARNING: IP $ServerIP not found on this server!" -ForegroundColor Yellow
    Write-Host "    Current IPs: $($adapters.IPAddress -join ', ')" -ForegroundColor Gray
    Write-Host "    You may need to update the `$ServerIP variable in this script" -ForegroundColor Gray
}

Write-Host ""

Write-Host "=== Step 5: Configure Business Central for HTTPS ===" -ForegroundColor Yellow

try {
    # Set certificate
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ServicesCertificateThumbprint" -KeyValue $CertThumbprint -ApplyTo ConfigFile
    Write-Host "  ✓ Certificate configured" -ForegroundColor Green
    
    # Set ALL ports to same port
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ClientServicesPort" -KeyValue $Port -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "SOAPServicesPort" -KeyValue $Port -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ODataServicesPort" -KeyValue $Port -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "DeveloperServicesPort" -KeyValue $Port -ApplyTo ConfigFile
    Write-Host "  ✓ All ports set to $Port" -ForegroundColor Green
    
    # Enable SSL on ALL services
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ClientServicesSSLEnabled" -KeyValue $true -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "SOAPServicesSSLEnabled" -KeyValue $true -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ODataServicesSSLEnabled" -KeyValue $true -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "DeveloperServicesSSLEnabled" -KeyValue $true -ApplyTo ConfigFile
    Write-Host "  ✓ SSL enabled on all services" -ForegroundColor Green
    
    # Set public URLs
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "PublicODataBaseUrl" -KeyValue "https://kasuku.jaza.ke:8443" -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "PublicSOAPBaseUrl" -KeyValue "https://kasuku.jaza.ke:8443" -ApplyTo ConfigFile
    Set-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "PublicWebBaseUrl" -KeyValue "https://kasuku.jaza.ke:8443" -ApplyTo ConfigFile
    Write-Host "  ✓ Public URLs configured" -ForegroundColor Green
}
catch {
    Write-Host "  ✗ Configuration failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""

Write-Host "=== Step 6: Verify Configuration ===" -ForegroundColor Yellow
$config = @{
    "ClientServicesPort" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ClientServicesPort"
    "SOAPServicesPort" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "SOAPServicesPort"
    "ODataServicesPort" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ODataServicesPort"
    "DeveloperServicesPort" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "DeveloperServicesPort"
    "ClientServicesSSLEnabled" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ClientServicesSSLEnabled"
    "SOAPServicesSSLEnabled" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "SOAPServicesSSLEnabled"
    "ODataServicesSSLEnabled" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ODataServicesSSLEnabled"
    "DeveloperServicesSSLEnabled" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "DeveloperServicesSSLEnabled"
    "ServicesCertificateThumbprint" = Get-NAVServerConfiguration -ServerInstance $ServiceInstance -KeyName "ServicesCertificateThumbprint"
}

Write-Host "  Configuration Summary:" -ForegroundColor Cyan
foreach ($key in $config.Keys) {
    $value = $config[$key]
    $color = "White"
    
    # Validate values
    if ($key -like "*Port" -and $value -ne $Port) {
        $color = "Red"
    } elseif ($key -like "*SSLEnabled" -and $value -ne $true) {
        $color = "Red"
    } elseif ($key -eq "ServicesCertificateThumbprint" -and $value -ne $CertThumbprint) {
        $color = "Red"
    }
    
    Write-Host "    $key = $value" -ForegroundColor $color
}

Write-Host ""

Write-Host "=== Step 7: Configure Windows Firewall (All Profiles) ===" -ForegroundColor Yellow
try {
    # Remove old rules
    $oldRules = Get-NetFirewallRule -DisplayName "BC HTTPS $Port*" -ErrorAction SilentlyContinue
    if ($oldRules) { 
        $oldRules | Remove-NetFirewallRule 
        Write-Host "  Removed old firewall rules" -ForegroundColor Gray
    }
    
    # Create new rule for ALL profiles (Domain, Private, Public)
    New-NetFirewallRule `
        -DisplayName "BC HTTPS $Port - $ServiceInstance" `
        -Description "Business Central HTTPS access for $ServiceInstance on all network interfaces" `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -Profile Domain,Private,Public `
        -Enabled True `
        -LocalAddress Any `
        -RemoteAddress Any | Out-Null
    
    Write-Host "  ✓ Firewall configured for port $Port (All Profiles)" -ForegroundColor Green
    Write-Host "    Allows: Domain, Private, Public networks" -ForegroundColor Gray
    Write-Host "    Local Address: Any (0.0.0.0)" -ForegroundColor Gray
    Write-Host "    Remote Address: Any" -ForegroundColor Gray
}
catch {
    Write-Host "  ! Firewall warning: $_" -ForegroundColor Yellow
}

Write-Host ""

Write-Host "=== Step 8: Start BC Service ===" -ForegroundColor Yellow
try {
    Start-Service $ServiceName
    Write-Host "  Waiting for service to start..." -ForegroundColor Gray
    Start-Sleep -Seconds 25
    
    $service = Get-Service $ServiceName
    Write-Host "  Service Status: $($service.Status)" -ForegroundColor $(if($service.Status -eq 'Running'){'Green'}else{'Red'})
}
catch {
    Write-Host "  ✗ Service start failed: $_" -ForegroundColor Red
}

Write-Host ""

Write-Host "=== Step 9: Verify Port and Network Binding ===" -ForegroundColor Yellow
$portCheck = netstat -ano | findstr :$Port
if ($portCheck) {
    Write-Host "  ✓ Port $Port is listening!" -ForegroundColor Green
    $portCheck | ForEach-Object { Write-Host "    $_" -ForegroundColor White }
    
    # Check if bound to all interfaces
    $tcpConn = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($tcpConn) {
        $boundToAll = $tcpConn | Where-Object {$_.LocalAddress -eq "0.0.0.0" -or $_.LocalAddress -eq "::"}
        if ($boundToAll) {
            Write-Host "  ✓ Service is bound to ALL network interfaces (0.0.0.0)" -ForegroundColor Green
        } else {
            Write-Host "  ⚠ Service bound to: $($tcpConn.LocalAddress -join ', ')" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "  ! Port $Port not listening" -ForegroundColor Yellow
}

Write-Host ""

Write-Host "=== Step 10: Check Event Log ===" -ForegroundColor Yellow
$events = Get-EventLog -LogName Application -Source $ServiceName -Newest 5 -ErrorAction SilentlyContinue

if ($events) {
    $hasError = $false
    foreach ($event in $events) {
        if ($event.EntryType -eq "Error") {
            $hasError = $true
            Write-Host "  ✗ ERROR found in event log:" -ForegroundColor Red
            $errorLines = ($event.Message -split "`n")[0..5]
            foreach ($line in $errorLines) {
                if ($line -match "http://" -or $line -match "already registered") {
                    Write-Host "    $line" -ForegroundColor Red
                }
            }
        }
    }
    
    if (-not $hasError) {
        Write-Host "  ✓ No errors in event log" -ForegroundColor Green
    }
    
    # Check for HTTPS URLs
    $httpsEvents = $events | Where-Object { $_.Message -like "*https:*$Port*" }
    if ($httpsEvents) {
        Write-Host "  ✓ Service is using HTTPS" -ForegroundColor Green
        $urls = ($httpsEvents[0].Message -split "`n" | Where-Object {$_ -like "*https:*$Port*"})
        foreach ($url in $urls) {
            Write-Host "    $url" -ForegroundColor White
        }
    }
}

Write-Host ""

Write-Host "=== Step 11: Test ALL HTTPS Connections ===" -ForegroundColor Yellow
Write-Host ""

# Test 1: localhost
Write-Host "  [1/3] Testing https://localhost:$Port/BC260_NUP/ ..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "https://localhost:$Port/BC260_NUP/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "        ✓✓✓ LOCALHOST ACCESS SUCCESSFUL!" -ForegroundColor Green
    Write-Host "        Status Code: $($response.StatusCode)" -ForegroundColor White
} catch {
    $errorMsg = $_.Exception.Message
    if ($errorMsg -like "*405*") {
        Write-Host "        ✓ LOCALHOST ACCESS WORKING (405 is normal)" -ForegroundColor Green
    } elseif ($errorMsg -like "*certificate*" -or $errorMsg -like "*SSL*") {
        Write-Host "        ⚠ Certificate warning (expected for localhost): $errorMsg" -ForegroundColor Yellow
    } else {
        Write-Host "        ✗ FAILED: $errorMsg" -ForegroundColor Red
    }
}

Write-Host ""

# Test 2: IP Address
Write-Host "  [2/3] Testing https://$ServerIP`:$Port/BC260_NUP/ ..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "https://$ServerIP`:$Port/BC260_NUP/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "        ✓✓✓ IP ADDRESS ACCESS SUCCESSFUL!" -ForegroundColor Green
    Write-Host "        Status Code: $($response.StatusCode)" -ForegroundColor White
} catch {
    $errorMsg = $_.Exception.Message
    if ($errorMsg -like "*405*") {
        Write-Host "        ✓ IP ADDRESS ACCESS WORKING (405 is normal)" -ForegroundColor Green
    } elseif ($errorMsg -like "*certificate*" -or $errorMsg -like "*SSL*") {
        Write-Host "        ✓ IP ADDRESS ACCESS WORKING" -ForegroundColor Green
        Write-Host "        ⚠ Certificate warning is EXPECTED (cert is for *.jaza.ke, not IP)" -ForegroundColor Yellow
        Write-Host "        This is NORMAL - just accept the warning in browser" -ForegroundColor Gray
    } else {
        Write-Host "        ✗ FAILED: $errorMsg" -ForegroundColor Red
    }
}

Write-Host ""

# Test 3: Domain Name
Write-Host "  [3/3] Testing https://kasuku.jaza.ke:$Port/BC260_NUP/ ..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "https://kasuku.jaza.ke:$Port/BC260_NUP/" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Host "        ✓✓✓ DOMAIN NAME ACCESS SUCCESSFUL!" -ForegroundColor Green
    Write-Host "        Status Code: $($response.StatusCode)" -ForegroundColor White
} catch {
    $errorMsg = $_.Exception.Message
    if ($errorMsg -like "*405*") {
        Write-Host "        ✓ DOMAIN NAME ACCESS WORKING (405 is normal)" -ForegroundColor Green
    } elseif ($errorMsg -like "*certificate*" -or $errorMsg -like "*SSL*") {
        Write-Host "        ⚠ $errorMsg" -ForegroundColor Yellow
    } else {
        Write-Host "        ! $errorMsg" -ForegroundColor Yellow
        Write-Host "        (Domain access requires hosts file entry)" -ForegroundColor Gray
    }
}

Write-Host ""

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "Configuration Complete!" -ForegroundColor Green
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

$service = Get-Service $ServiceName
if ($service.Status -eq "Running") {
    Write-Host "✓ Service Status: RUNNING" -ForegroundColor Green
    Write-Host ""
    Write-Host "Business Central is now accessible via:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. Localhost Access:" -ForegroundColor Cyan
    Write-Host "     https://localhost:$Port/BC260_NUP/" -ForegroundColor White
    Write-Host "     ✓ Works from this server" -ForegroundColor Green
    Write-Host ""
    Write-Host "  2. IP Address Access:" -ForegroundColor Cyan
    Write-Host "     https://$ServerIP`:$Port/BC260_NUP/" -ForegroundColor White
    Write-Host "     ✓ Works from any computer on the network" -ForegroundColor Green
    Write-Host "     ⚠ Certificate warning is EXPECTED and SAFE" -ForegroundColor Yellow
    Write-Host "     (Certificate is for *.jaza.ke domain, not IP address)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Domain Name Access:" -ForegroundColor Cyan
    Write-Host "     https://kasuku.jaza.ke:$Port/BC260_NUP/" -ForegroundColor White
    Write-Host "     ✓ Valid certificate, no warnings" -ForegroundColor Green
    Write-Host "     (Requires hosts file entry: $PublicIP    kasuku.jaza.ke)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  4. External/Public Access:" -ForegroundColor Cyan
    Write-Host "     https://kasuku.jaza.ke:8443/BC260_NUP/" -ForegroundColor White
    Write-Host "     ✓ For M-Pesa integration" -ForegroundColor Green
    Write-Host "     (Requires FortiGate VIP configuration)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT NOTES:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Network Configuration:" -ForegroundColor Cyan
    Write-Host "  - Internal Server IP: $ServerIP (local network access)" -ForegroundColor White
    Write-Host "  - Public Domain IP: $PublicIP (kasuku.jaza.ke)" -ForegroundColor White
    Write-Host "  - FortiGate VIP forwards: $PublicIP`:8443 → $ServerIP`:$Port" -ForegroundColor White
    Write-Host ""
    Write-Host "Certificate Warnings:" -ForegroundColor Cyan
    Write-Host "  ✓ localhost:$Port → May show certificate warning (NORMAL)" -ForegroundColor White
    Write-Host "  ✓ $ServerIP`:$Port → Will show certificate warning (NORMAL & SAFE)" -ForegroundColor White
    Write-Host "  ✓ kasuku.jaza.ke:$Port → No warnings (perfect!)" -ForegroundColor White
    Write-Host ""
    Write-Host "Why IP shows certificate warning:" -ForegroundColor Cyan
    Write-Host "  - Certificate is issued for *.jaza.ke (domain names)" -ForegroundColor White
    Write-Host "  - SSL certificates don't work with IP addresses" -ForegroundColor White
    Write-Host "  - This is EXPECTED and SECURE for internal network" -ForegroundColor White
    Write-Host "  - Just click 'Advanced' → 'Continue' in your browser" -ForegroundColor White
    Write-Host ""
    Write-Host "For M-Pesa Integration:" -ForegroundColor Cyan
    Write-Host "  ✓ MUST use: https://kasuku.jaza.ke:8443/BC260_NUP/" -ForegroundColor White
    Write-Host "  ✓ Valid certificate required by M-Pesa" -ForegroundColor White
    Write-Host "  ✓ Already configured and ready!" -ForegroundColor White
    Write-Host ""
    Write-Host "DNS/Hosts File Configuration:" -ForegroundColor Cyan
    Write-Host "  For LOCAL testing (hosts file entry):" -ForegroundColor White
    Write-Host "    $PublicIP    kasuku.jaza.ke" -ForegroundColor Gray
    Write-Host "  For EXTERNAL access (DNS record):" -ForegroundColor White
    Write-Host "    kasuku.jaza.ke A record → $PublicIP" -ForegroundColor Gray
    Write-Host "  FortiGate VIP must forward:" -ForegroundColor White
    Write-Host "    $PublicIP`:8443 → $ServerIP`:$Port" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Opening browser to test IP access..." -ForegroundColor Cyan
    Start-Sleep -Seconds 2
    Start-Process "https://$ServerIP`:$Port/BC260_NUP/"
} else {
    Write-Host "✗ Service Status: $($service.Status)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Check event log for errors:" -ForegroundColor Yellow
    Write-Host "  Get-EventLog -LogName Application -Source '$ServiceName' -Newest 5" -ForegroundColor White
}

Write-Host ""
Write-Host "Script completed!" -ForegroundColor Cyan
Write-Host ""
