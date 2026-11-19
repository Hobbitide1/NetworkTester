# Clear screen and show instructions
Clear-Host
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "           NETWORK DIAGNOSTIC TOOL                   " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Detecting your local network settings..." -ForegroundColor Yellow

# Automatically detect the Default Gateway
$gateway = (Get-NetRoute -DestinationPrefix "0.0.0.0/0" | Sort-Object RouteMetric | Select-Object -First 1).NextHop

if (-not $gateway) {
    Write-Host "Error: Could not find a Default Gateway. Are you connected to Wi-Fi or Ethernet?" -ForegroundColor Red
    Pause
    exit
}

Write-Host "Default Gateway found: $gateway" -ForegroundColor Green
Write-Host ""
Write-Host "Running 3 tests simultaneously. This will take about 10-15 seconds..." -ForegroundColor Yellow
Write-Host " - Test 1: Local Router ($gateway) - 20 pings"
Write-Host " - Test 2: Internet Connection (8.8.8.8) - 50 pings"
Write-Host " - Test 3: DNS Resolution (google.com) - 50 pings"
Write-Host ""

# Function to run pings in background jobs (preserves sequence including timeouts as -1)
$pingScript = {
    param($target, $count)
    $rawSequence = @()
    $validTimes  = @()
    $lost = 0

    for ($i = 1; $i -le $count; $i++) {
        $ping = Test-Connection -ComputerName $target -Count 1 -ErrorAction SilentlyContinue
        if ($ping) {
            $time = if ($null -ne $ping.ResponseTime) { [int]$ping.ResponseTime } else { [int]$ping.Latency }
            $validTimes  += $time
            $rawSequence += $time
        } else {
            $lost++
            $rawSequence += -1 # -1 represents a dropped packet
        }
        Start-Sleep -Milliseconds 200
    }
    
    $avg = if ($validTimes.Count -gt 0) { [math]::Round(($validTimes | Measure-Object -Average).Average, 1) } else { 0 }
    $max = if ($validTimes.Count -gt 0) { ($validTimes | Measure-Object -Maximum).Maximum } else { 0 }
    $lossPct = [math]::Round(($lost / $count) * 100, 1)

    return [PSCustomObject]@{
        Target      = $target
        Sent        = $count
        Received    = $validTimes.Count
        Lost        = $lost
        LossPct     = $lossPct
        AvgMs       = $avg
        MaxMs       = $max
        RawSequence = $rawSequence
    }
}

# Start all 3 tests at the exact same time
$jobLocal    = Start-Job -ScriptBlock $pingScript -ArgumentList $gateway, 20
$jobInternet = Start-Job -ScriptBlock $pingScript -ArgumentList "8.8.8.8", 50
$jobDNS      = Start-Job -ScriptBlock $pingScript -ArgumentList "google.com", 50

# Wait for all 3 jobs to finish while showing a progress spinner
$spinner = @('|', '/', '-', '\')
$spinIdx = 0
while ($jobLocal.State -eq 'Running' -or $jobInternet.State -eq 'Running' -or $jobDNS.State -eq 'Running') {
    Write-Host -NoNewline "`rTesting in progress... $($spinner[$spinIdx % 4])" -ForegroundColor Cyan
    $spinIdx++
    Start-Sleep -Milliseconds 250
}
Write-Host "`rTesting complete!               " -ForegroundColor Green
Write-Host ""

# Collect results
$resLocal    = Receive-Job -Job $jobLocal
$resInternet = Receive-Job -Job $jobInternet
$resDNS      = Receive-Job -Job $jobDNS

# Clean up background jobs
Remove-Job $jobLocal, $jobInternet, $jobDNS

# --- Evaluate Individual Tier Statuses for CLI ---
$localOk    = -not ($resLocal.Received -eq 0 -or $resLocal.LossPct -gt 10 -or $resLocal.AvgMs -gt 50)
$internetOk = -not ($resInternet.Received -eq 0 -or $resInternet.LossPct -gt 5 -or $resInternet.AvgMs -gt 150)
$dnsOk      = -not ($resDNS.Received -eq 0 -or $resDNS.LossPct -gt 5 -or ($resDNS.AvgMs -gt ($resInternet.AvgMs + 80)))

# --- Plain-English Diagnostic Logic ---
$diagnosisTitle = ""
$diagnosisColor = "#10b981" # Emerald Green
$diagnosisGlow  = "rgba(16, 185, 129, 0.15)"
$cliStatusColor = "Green"
$diagnosisText  = ""

if (-not $localOk) {
    $diagnosisTitle = "ISSUE DETECTED: Local Network / Wi-Fi Problem"
    $diagnosisColor = "#ef4444" # Red
    $diagnosisGlow  = "rgba(239, 68, 68, 0.15)"
    $cliStatusColor = "Red"
    $diagnosisText  = "Your computer is struggling to talk to your own router ($gateway). This means the issue is inside your home or office—not with your Internet Service Provider. Try moving closer to your Wi-Fi router, restarting your router, or plugging in an Ethernet cable."
}
elseif (-not $internetOk) {
    $diagnosisTitle = "ISSUE DETECTED: Internet Connection Problem"
    $diagnosisColor = "#ef4444" # Red
    $diagnosisGlow  = "rgba(239, 68, 68, 0.15)"
    $cliStatusColor = "Red"
    $diagnosisText  = "Your connection to your local router is fine, but data is getting lost or delayed once it leaves your house. This usually points to an outage, heavy congestion, or a bad line with your Internet Service Provider (ISP). Try restarting your modem, or contact your ISP."
}
elseif (-not $dnsOk) {
    $diagnosisTitle = "ISSUE DETECTED: DNS / Website Lookup Problem"
    $diagnosisColor = "#f59e0b" # Amber
    $diagnosisGlow  = "rgba(245, 158, 11, 0.15)"
    $cliStatusColor = "Yellow"
    $diagnosisText  = "Your raw internet connection is working, but your computer is having trouble translating website names (like google.com) into addresses. Websites may fail to load or take a long time to start loading. Restarting your router or changing your DNS settings (e.g., to 8.8.8.8 or 1.1.1.1) usually fixes this."
}
else {
    $diagnosisTitle = "ALL SYSTEMS HEALTHY!"
    $diagnosisColor = "#10b981" # Emerald Green
    $diagnosisGlow  = "rgba(16, 185, 129, 0.15)"
    $cliStatusColor = "Green"
    $diagnosisText  = "Your local network, internet connection, and DNS are all responding normally with low delay and minimal packet loss. If a specific website or game is acting up, the issue is likely on their end, not yours."
}

# --- Display Quick Summary & Diagnosis in PowerShell CLI ---
Write-Host "=================== QUICK RESULTS ===================" -ForegroundColor Cyan

# Line 1: Local
Write-Host -NoNewline " 1. Local Router : "
if ($localOk) { Write-Host -NoNewline "[ GOOD ]  " -ForegroundColor Green } else { Write-Host -NoNewline "[ ISSUE ] " -ForegroundColor Red }
Write-Host "Avg: $($resLocal.AvgMs) ms | Max: $($resLocal.MaxMs) ms | Loss: $($resLocal.LossPct)%"

# Line 2: Internet
Write-Host -NoNewline " 2. Internet     : "
if ($internetOk) { Write-Host -NoNewline "[ GOOD ]  " -ForegroundColor Green } else { Write-Host -NoNewline "[ ISSUE ] " -ForegroundColor Red }
Write-Host "Avg: $($resInternet.AvgMs) ms | Max: $($resInternet.MaxMs) ms | Loss: $($resInternet.LossPct)%"

# Line 3: DNS
Write-Host -NoNewline " 3. DNS Lookup   : "
if ($dnsOk) { Write-Host -NoNewline "[ GOOD ]  " -ForegroundColor Green } else { Write-Host -NoNewline "[ ISSUE ] " -ForegroundColor Yellow }
Write-Host "Avg: $($resDNS.AvgMs) ms | Max: $($resDNS.MaxMs) ms | Loss: $($resDNS.LossPct)%"

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "STATUS: $diagnosisTitle" -ForegroundColor $cliStatusColor
Write-Host $diagnosisText -ForegroundColor White
Write-Host ""

# --- Helper Function to Build Mini Sparkline Bar Graphs ---
function Build-SparklineHtml {
    param([array]$sequence, [double]$avgMs, [int]$maxMs)
    $scaleMax = [math]::Max($maxMs, 50)
    $barsHtml = ""
    $index = 1

    foreach ($val in $sequence) {
        if ($val -lt 0) {
            $barsHtml += "<div class='bar bar-drop' style='height: 100%;' title='Ping #$index : DROPPED (Timeout)'></div>"
        } else {
            $pct = [math]::Max(8, [math]::Round(($val / $scaleMax) * 100))
            $barClass = "bar-normal"
            if ($val -gt 150 -or ($avgMs -gt 0 -and $val -gt ($avgMs * 2.5) -and $val -gt 35)) {
                $barClass = "bar-spike"
            } elseif ($val -gt 75 -or ($avgMs -gt 0 -and $val -gt ($avgMs * 1.6) -and $val -gt 20)) {
                $barClass = "bar-warn"
            }
            $barsHtml += "<div class='bar $barClass' style='height: $pct%;' title='Ping #$index : $val ms'></div>"
        }
        $index++
    }
    return $barsHtml
}

# --- Helper Function to Format Raw Ping List ---
function Build-RawListHtml {
    param([array]$sequence)
    $items = foreach ($val in $sequence) {
        if ($val -lt 0) {
            "<span class='timeout-text'>TIMEOUT</span>"
        } else {
            "$val"
        }
    }
    return ($items -join ", ")
}

$graphLocal    = Build-SparklineHtml -sequence $resLocal.RawSequence -avgMs $resLocal.AvgMs -maxMs $resLocal.MaxMs
$graphInternet = Build-SparklineHtml -sequence $resInternet.RawSequence -avgMs $resInternet.AvgMs -maxMs $resInternet.MaxMs
$graphDNS      = Build-SparklineHtml -sequence $resDNS.RawSequence -avgMs $resDNS.AvgMs -maxMs $resDNS.MaxMs

$rawListLocal    = Build-RawListHtml -sequence $resLocal.RawSequence
$rawListInternet = Build-RawListHtml -sequence $resInternet.RawSequence
$rawListDNS      = Build-RawListHtml -sequence $resDNS.RawSequence

# --- Generate Dark Mode HTML Report ---
$reportPath = "$env:TEMP\NetworkDiagnosticReport.html"
$timestamp  = Get-Date -Format "MMMM dd, yyyy 'at' hh:mm tt"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Advanced Network Report</title>
    <style>
        :root {
            --bg-main: #0b1120;
            --bg-card: #131c31;
            --bg-sub: #0f172a;
            --border-subtle: #1e293b;
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --accent-cyan: #38bdf8;
        }
        * { box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background-color: var(--bg-main);
            background-image: radial-gradient(circle at top center, #172554 0%, var(--bg-main) 55%);
            color: var(--text-primary);
            margin: 0;
            padding: 40px 20px;
            min-height: 100vh;
        }
        .container {
            max-width: 960px;
            margin: 0 auto;
        }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: flex-end;
            margin-bottom: 24px;
            border-bottom: 1px solid var(--border-subtle);
            padding-bottom: 16px;
        }
        h1 {
            margin: 0;
            font-size: 1.9rem;
            letter-spacing: -0.5px;
            background: linear-gradient(90deg, #f8fafc, #38bdf8);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
        }
        .timestamp {
            color: var(--text-secondary);
            font-size: 0.9rem;
        }
        .diagnosis-box {
            border-left: 5px solid $diagnosisColor;
            background: linear-gradient(90deg, $diagnosisGlow 0%, var(--bg-card) 100%);
            border-top: 1px solid var(--border-subtle);
            border-right: 1px solid var(--border-subtle);
            border-bottom: 1px solid var(--border-subtle);
            padding: 22px 26px;
            border-radius: 12px;
            margin-bottom: 28px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.4);
        }
        .diagnosis-box h2 {
            margin: 0 0 8px 0;
            color: $diagnosisColor;
            font-size: 1.35rem;
        }
        .diagnosis-box p {
            margin: 0;
            line-height: 1.6;
            color: #e2e8f0;
            font-size: 1.02rem;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 28px;
        }
        .card {
            background-color: var(--bg-card);
            border: 1px solid var(--border-subtle);
            border-radius: 12px;
            padding: 22px;
            box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.35);
            display: flex;
            flex-direction: column;
        }
        .card-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-bottom: 1px solid var(--border-subtle);
            padding-bottom: 12px;
            margin-bottom: 14px;
        }
        .card h3 {
            margin: 0;
            color: var(--text-primary);
            font-size: 1.1rem;
        }
        .badge {
            font-size: 0.75rem;
            padding: 3px 8px;
            border-radius: 999px;
            background: var(--bg-sub);
            color: var(--accent-cyan);
            border: 1px solid #1e3a8a;
            font-family: Consolas, monospace;
        }
        .stat {
            display: flex;
            justify-content: space-between;
            margin: 7px 0;
            font-size: 0.94rem;
            color: var(--text-secondary);
        }
        .stat strong {
            color: var(--text-primary);
            font-weight: 600;
        }
        .graph-section {
            margin-top: 16px;
            padding-top: 14px;
            border-top: 1px solid var(--border-subtle);
        }
        .graph-label {
            display: flex;
            justify-content: space-between;
            font-size: 0.78rem;
            color: var(--text-secondary);
            margin-bottom: 8px;
        }
        .sparkline {
            display: flex;
            align-items: flex-end;
            gap: 2px;
            height: 64px;
            background-color: var(--bg-sub);
            padding: 8px 6px 4px 6px;
            border-radius: 8px;
            border: 1px solid var(--border-subtle);
        }
        .bar {
            flex: 1;
            border-radius: 2px 2px 0 0;
            transition: opacity 0.15s ease, transform 0.15s ease;
            cursor: crosshair;
        }
        .bar:hover {
            opacity: 0.8;
            transform: scaleY(1.06);
        }
        .bar-normal { background: linear-gradient(180deg, #38bdf8 0%, #0284c7 100%); }
        .bar-warn   { background: linear-gradient(180deg, #fbbf24 0%, #d97706 100%); }
        .bar-spike  { background: linear-gradient(180deg, #f87171 0%, #dc2626 100%); }
        .bar-drop   { background: repeating-linear-gradient(45deg, #ef4444, #ef4444 3px, #7f1d1d 3px, #7f1d1d 6px); }

        .raw-data {
            margin-top: 12px;
            padding: 10px 12px;
            background-color: var(--bg-sub);
            border: 1px solid var(--border-subtle);
            border-radius: 8px;
            font-size: 0.78rem;
            color: var(--text-secondary);
            line-height: 1.5;
            word-wrap: break-word;
            font-family: Consolas, monospace;
        }
        .raw-data strong {
            color: #cbd5e1;
            font-family: 'Segoe UI', system-ui, sans-serif;
            display: block;
            margin-bottom: 4px;
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.4px;
        }
        .timeout-text {
            color: #f87171;
            font-weight: bold;
        }

        .explainer {
            background-color: var(--bg-card);
            border: 1px solid var(--border-subtle);
            padding: 24px 28px;
            border-radius: 12px;
            font-size: 0.95rem;
            line-height: 1.65;
        }
        .explainer h3 {
            margin: 0 0 12px 0;
            color: var(--accent-cyan);
            font-size: 1.15rem;
        }
        .explainer ul {
            margin: 0;
            padding-left: 20px;
            color: #cbd5e1;
        }
        .explainer li {
            margin-bottom: 8px;
        }
        .explainer strong {
            color: var(--text-primary);
        }
        .legend {
            display: flex;
            gap: 16px;
            margin-top: 14px;
            padding-top: 12px;
            border-top: 1px solid var(--border-subtle);
            font-size: 0.82rem;
            color: var(--text-secondary);
            flex-wrap: wrap;
        }
        .legend-item { display: flex; align-items: center; gap: 6px; }
        .dot { width: 10px; height: 10px; border-radius: 2px; display: inline-block; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Advanced Network Report</h1>
            <div class="timestamp">Generated $timestamp</div>
        </div>

        <div class="diagnosis-box">
            <h2>$diagnosisTitle</h2>
            <p>$diagnosisText</p>
        </div>

        <div class="grid">
            <div class="card">
                <div class="card-header">
                    <h3>1. Local Connection</h3>
                    <span class="badge">$($resLocal.Target)</span>
                </div>
                <div class="stat"><span>Pings Sent / Recv:</span> <strong>$($resLocal.Sent) / $($resLocal.Received)</strong></div>
                <div class="stat"><span>Packet Loss:</span> <strong>$($resLocal.LossPct)%</strong></div>
                <div class="stat"><span>Average Latency:</span> <strong>$($resLocal.AvgMs) ms</strong></div>
                <div class="stat"><span>Highest Latency:</span> <strong>$($resLocal.MaxMs) ms</strong></div>
                <div class="graph-section">
                    <div class="graph-label"><span>Ping Timeline (20 tests)</span><span>Hover bars for ms</span></div>
                    <div class="sparkline">$graphLocal</div>
                </div>
                <div class="raw-data">
                    <strong>Individual Pings (ms)</strong>
                    $rawListLocal
                </div>
            </div>

            <div class="card">
                <div class="card-header">
                    <h3>2. Internet Connection</h3>
                    <span class="badge">$($resInternet.Target)</span>
                </div>
                <div class="stat"><span>Pings Sent / Recv:</span> <strong>$($resInternet.Sent) / $($resInternet.Received)</strong></div>
                <div class="stat"><span>Packet Loss:</span> <strong>$($resInternet.LossPct)%</strong></div>
                <div class="stat"><span>Average Latency:</span> <strong>$($resInternet.AvgMs) ms</strong></div>
                <div class="stat"><span>Highest Latency:</span> <strong>$($resInternet.MaxMs) ms</strong></div>
                <div class="graph-section">
                    <div class="graph-label"><span>Ping Timeline (50 tests)</span><span>Hover bars for ms</span></div>
                    <div class="sparkline">$graphInternet</div>
                </div>
                <div class="raw-data">
                    <strong>Individual Pings (ms)</strong>
                    $rawListInternet
                </div>
            </div>

            <div class="card">
                <div class="card-header">
                    <h3>3. DNS Lookup</h3>
                    <span class="badge">$($resDNS.Target)</span>
                </div>
                <div class="stat"><span>Pings Sent / Recv:</span> <strong>$($resDNS.Sent) / $($resDNS.Received)</strong></div>
                <div class="stat"><span>Packet Loss:</span> <strong>$($resDNS.LossPct)%</strong></div>
                <div class="stat"><span>Average Latency:</span> <strong>$($resDNS.AvgMs) ms</strong></div>
                <div class="stat"><span>Highest Latency:</span> <strong>$($resDNS.MaxMs) ms</strong></div>
                <div class="graph-section">
                    <div class="graph-label"><span>Ping Timeline (50 tests)</span><span>Hover bars for ms</span></div>
                    <div class="sparkline">$graphDNS</div>
                </div>
                <div class="raw-data">
                    <strong>Individual Pings (ms)</strong>
                    $rawListDNS
                </div>
            </div>
        </div>

        <div class="explainer">
            <h3>How to Read These Numbers</h3>
            <ul>
                <li><strong>Latency (ms):</strong> How fast a signal travels there and back in milliseconds. Lower is better. Under <strong>50 ms</strong> is great; over <strong>150 ms</strong> feels laggy.</li>
                <li><strong>Look for Latency Spikes:</strong> A healthy connection looks like a flat, steady row of short blue bars. If you see sudden tall yellow or red bars shooting up above the rest (latency spikes), your connection is jittery—this is what causes video calls to freeze, voice chat to cut out, or games to rubber-band even when your average speed looks fine.</li>
                <li><strong>Highest Latency:</strong> The single worst lag spike recorded during the test.</li>
                <li><strong>Packet Loss (%):</strong> Percentage of signals that never made it back (shown as striped red bars or <strong>TIMEOUT</strong> in the list). Anything above <strong>0%</strong> indicates an unstable connection.</li>
            </ul>
            <div class="legend">
                <div class="legend-item"><span class="dot" style="background:#38bdf8;"></span> Normal / Steady</div>
                <div class="legend-item"><span class="dot" style="background:#fbbf24;"></span> Moderate Jump</div>
                <div class="legend-item"><span class="dot" style="background:#ef4444;"></span> Latency Spike</div>
                <div class="legend-item"><span class="dot" style="background:repeating-linear-gradient(45deg,#ef4444,#ef4444 2px,#7f1d1d 2px,#7f1d1d 4px);"></span> Dropped Packet</div>
            </div>
        </div>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8

# Prompt the user to open the report
Write-Host "=====================================================" -ForegroundColor Cyan
$choice = Read-Host "Press ENTER to view 'Advanced Report' in your web browser (or type N to exit)"
if ($choice -ne "N" -and $choice -ne "n") {
    Start-Process $reportPath
}
