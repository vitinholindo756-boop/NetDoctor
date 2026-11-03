# NetDoctor - monitor e diagnostico de rede (janela principal)
# Use pelo NetDoctor.bat. Monitor e diagnostico sao somente leitura. Apenas as abas "Ferramentas DNS"
# e "Desempenho em jogos" alteram o PC, sempre com confirmacao (algumas pedem administrador).

$ErrorActionPreference = 'Continue'

# Um unico Add-Type para todas as chamadas nativas (cada Add-Type compila codigo e custa tempo de abertura).
try {
    Add-Type -Namespace NetDoctorNative -Name Api -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int msg, System.IntPtr wParam, string lParam);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr SendMessage(System.IntPtr hWnd, int msg, System.IntPtr wParam, System.IntPtr lParam);
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
[System.Runtime.InteropServices.DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[System.Runtime.InteropServices.DllImport("uxtheme.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)] public static extern int SetWindowTheme(System.IntPtr hWnd, string subApp, string subIdList);
[System.Runtime.InteropServices.DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int attrValue, int attrSize);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool DestroyIcon(System.IntPtr handle);
'@
    # Identidade propria na barra de tarefas (separa do icone do PowerShell).
    [void][NetDoctorNative.Api]::SetCurrentProcessExplicitAppUserModelID('NetDoctor.App')
    # Esconde a janela preta do PowerShell. O NetDoctor-diagnostico.bat define NETDOCTOR_SHOWCONSOLE=1.
    if (-not $env:NETDOCTOR_SHOWCONSOLE) {
        $hcon = [NetDoctorNative.Api]::GetConsoleWindow()
        if ($hcon -ne [System.IntPtr]::Zero) { [void][NetDoctorNative.Api]::ShowWindow($hcon, 0) }
    }
} catch { }

. (Join-Path $PSScriptRoot 'NetDoctor.engine.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.bg.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.dns.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.games.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.hw.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.insights.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.update.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.contato.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.i18n.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.support.ps1')
. (Join-Path $PSScriptRoot 'NetDoctor.wifi.ps1')
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Set-Cue($tb, [string]$texto) {
    try { [void][NetDoctorNative.Api]::SendMessage($tb.Handle, 0x1501, [System.IntPtr]1, $texto) } catch { }
}
[System.Windows.Forms.Application]::EnableVisualStyles()
# Erros inesperados de desenho/eventos vao para o erro.log (com o rastreamento) em vez de abrir a caixa de erro do .NET.
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({ param($sender, $e) try { Log-Error ('ThreadException: ' + $e.Exception.ToString()) } catch { } })
} catch { }

# ------------------------------------------------------------ estado
$script:Cfg = Load-Config
Add-Type -AssemblyName System.Drawing
$script:SpikeMs = [int]$script:Cfg.SpikeMs
$script:Targets = New-Object System.Collections.ArrayList
foreach ($c in @($script:Cfg.Targets)) { [void]$script:Targets.Add((New-TargetState $c)) }
$script:Q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$script:BgQ = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$script:Workers = New-Object System.Collections.ArrayList
$script:Retiring = New-Object System.Collections.ArrayList
$script:Ctl = $null; $script:Running = $false; $script:Csv = $null; $script:CsvPath = ''
$script:SessionStart = $null; $script:LastSample = $null; $script:Sel = 0
$script:DiagLines = New-Object System.Collections.ArrayList
$script:DiagFindings = New-Object System.Collections.ArrayList
$script:DiagMeta = @{}
$script:DiagJob = $null; $script:ScanJob = $null; $script:SnapJob = $null; $script:DnsJob = $null; $script:PubJob = $null
$script:DnsItems = New-Object System.Collections.ArrayList
$script:GamesLoaded = $false; $script:AutoApplyAfterTest = $false; $script:AdIdx = @(); $script:NetSig = ''; $script:DnsSig = ''; $script:NetTick = 0
$script:NetJob = $null; $script:DnsInfoJob = $null; $script:DnsInfoPending = $false; $script:GameJob = $null; $script:GameDirty = $false
$script:LastInfo = $null; $script:LastInfoTime = [datetime]::MinValue; $script:AdFilling = $false
$script:DnsCache = @{ IfIndex = 0; Servers = @(); V6 = @(); Modo = '' }
$script:DiagColored = New-Object System.Collections.ArrayList
$script:HwLoaded = $false; $script:DiskLoaded = $false; $script:HwCtl = $null
$script:HwInfoJob = $null; $script:HwLiveJob = $null; $script:DiskJob = $null
$script:HwStats = @{ Cpu = (New-HwStat); Gpu = (New-HwStat) }
$script:AssistJob = $null; $script:RouteJob = $null; $script:RouteCtl = $null; $script:HistJob = $null; $script:ReportJob = $null
$script:AssistColored = New-Object System.Collections.ArrayList
$script:UpdCheckJob = $null; $script:UpdDlJob = $null; $script:UpdReleases = @(); $script:UpdLatest = $null
$script:UpdAvailable = $false; $script:UpdChecking = $false; $script:UpdManual = $false; $script:UpdMsg = ''
$script:UpdLastCheck = [datetime]::MinValue; $script:UpdNotified = ''; $script:UpdExpectedSha = ''; $script:UpdOk = $false
$script:UpdLines = New-Object System.Collections.ArrayList
$script:WifiJob = $null; $script:WifiData = $null; $script:WifiLoaded = $false; $script:FbJob = $null; $script:FbLast = [datetime]::MinValue
$script:LastScores = $null; $script:LastAnatel = $null; $script:HistData = $null; $script:HistLoaded = $false
$script:ExitRequested = $false; $script:AlertTick = 0; $script:trayNormal = $null; $script:trayAlert = $null
$script:HwLastLive = $null; $script:DiskRows = @(); $script:DiskVols = @(); $script:DiskSmart = $true

# ------------------------------------------------------------ tema (claro / escuro)
$script:PalDef = @{
    claro = @{
        Back = @(240,240,240); Surface = @(255,255,255); Text = @(30,30,30); Muted = @(105,105,105); Info = @(236,240,246)
        Grid = @(225,225,225); Btn = @(225,225,225); BtnBorder = @(173,173,173); BtnHover = @(208,222,238); Header = @(30,41,59)
        TabSel = @(255,255,255); TabIdle = @(224,227,231); Accent = @(0,120,190)
        RowOk = @(226,246,232); RowWarn = @(255,244,214); RowBad = @(253,228,228)
        Line = @(0,120,190); Dash = @(230,150,40); Red = @(210,40,40)
        CCyan = @(0,105,160); CYellow = @(170,105,0); CGreen = @(20,125,60); CRed = @(190,30,30); CDarkRed = @(150,0,0); CDarkGray = @(140,140,140); CDefault = @(60,60,60)
    }
    escuro = @{
        Back = @(32,33,36); Surface = @(24,25,28); Text = @(230,230,232); Muted = @(165,168,175); Info = @(44,50,62)
        Grid = @(60,63,70); Btn = @(55,58,64); BtnBorder = @(88,91,99); BtnHover = @(74,80,92); Header = @(18,22,30)
        TabSel = @(32,33,36); TabIdle = @(22,23,26); Accent = @(90,180,240)
        RowOk = @(30,72,50); RowWarn = @(86,70,26); RowBad = @(92,38,38)
        Line = @(90,180,240); Dash = @(235,160,60); Red = @(240,90,90)
        CCyan = @(90,190,240); CYellow = @(235,185,80); CGreen = @(100,205,130); CRed = @(245,105,105); CDarkRed = @(225,95,95); CDarkGray = @(150,152,158); CDefault = @(220,220,222)
    }
}

function Get-SystemThemeName {
    try {
        $v = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop).AppsUseLightTheme
        if ([int]$v -eq 0) { return 'escuro' }
    } catch { }
    'claro'
}

function Resolve-ThemeName([string]$pref) {
    if ($pref -eq 'claro' -or $pref -eq 'escuro') { return $pref }
    Get-SystemThemeName
}

function Set-Pal([string]$name) {
    if (-not $script:PalDef.ContainsKey($name)) { $name = 'claro' }
    $pal = @{}
    foreach ($k in $script:PalDef[$name].Keys) {
        $a = $script:PalDef[$name][$k]
        $pal[$k] = [System.Drawing.Color]::FromArgb([int]$a[0], [int]$a[1], [int]$a[2])
    }
    $script:Pal = $pal
    $script:ThemeName = $name
}

function Get-RowColor([string]$kind) {
    switch ($kind) {
        'ok'   { return $script:Pal.RowOk }
        'warn' { return $script:Pal.RowWarn }
        'bad'  { return $script:Pal.RowBad }
        default { return $script:Pal.Surface }
    }
}

# ------------------------------------------------------------ utilidades de interface
function Get-UiColor([string]$n) {
    $k = 'CDefault'
    switch ($n) {
        'Cyan' { $k = 'CCyan' } 'Yellow' { $k = 'CYellow' } 'Green' { $k = 'CGreen' } 'Red' { $k = 'CRed' }
        'DarkRed' { $k = 'CDarkRed' } 'DarkGray' { $k = 'CDarkGray' }
    }
    $script:Pal[$k]
}

function Add-RtbLine($rtb, [string]$text, [string]$color) {
    $rtb.SelectionStart = $rtb.TextLength
    $rtb.SelectionLength = 0
    $rtb.SelectionColor = (Get-UiColor $color)
    $rtb.AppendText($text + "`r`n")
    $rtb.SelectionColor = $rtb.ForeColor
    $rtb.ScrollToCaret()
}

function Set-DoubleBuffered($ctl) {
    try { $ctl.GetType().GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic').SetValue($ctl, $true, $null) } catch { }
}

function Set-Status([string]$text) { $script:lblStatus.Text = (T $text) }

$script:BtnClick = {
    param($s, $e)
    try { $sb = $s.Tag; & $sb } catch { Log-Error $_; Set-Status ('Erro: ' + $_.Exception.Message) }
}

function New-Btn([string]$text, [scriptblock]$onClick, [int]$w = 120) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Width = $w
    $b.Height = 30
    $b.Margin = (New-Object System.Windows.Forms.Padding(3))
    $b.Tag = $onClick
    $b.Add_Click($script:BtnClick)
    $b
}

function New-Lbl([string]$text, [int]$w = 80) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Width = $w
    $l.Height = 30
    $l.TextAlign = 'MiddleLeft'
    $l.Margin = (New-Object System.Windows.Forms.Padding(3))
    $l
}

function New-Toolbar {
    $f = New-Object System.Windows.Forms.FlowLayoutPanel
    $f.Dock = 'Fill'
    $f.WrapContents = $false
    $f.Padding = (New-Object System.Windows.Forms.Padding(4, 4, 4, 0))
    $f
}

function New-Tlp([int]$rows) {
    $t = New-Object System.Windows.Forms.TableLayoutPanel
    $t.Dock = 'Fill'
    $t.ColumnCount = 1
    $t.RowCount = $rows
    [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    $t
}

function Add-Row($tlp, [string]$kind, [int]$size) {
    $st = [System.Windows.Forms.SizeType]::Absolute
    if ($kind -eq 'pct') { $st = [System.Windows.Forms.SizeType]::Percent }
    [void]$tlp.RowStyles.Add((New-Object System.Windows.Forms.RowStyle($st, $size)))
}

# ------------------------------------------------------------ informacoes do PC
$script:NetInfoLib = @'
function Get-NetInfo {
    $i = @{ Gateway = ''; Ip = ''; Adapter = ''; Link = ''; Dns = @(); Erros = ''; Speed = 0; IfIndex = 0; Wifi = $false }
    try {
        $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if ($r) {
            $i.Gateway = [string]$r.NextHop
            $i.IfIndex = [int]$r.InterfaceIndex
            $ad = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex
            if ($ad) {
                $i.Adapter = $ad.Name + ' (' + $ad.InterfaceDescription + ')'
                $i.Link = [string]$ad.LinkSpeed
                $i.Speed = $ad.Speed
                if ([string]$ad.PhysicalMediaType -match '802\.11|Wireless') { $i.Wifi = $true }
                $st = Get-NetAdapterStatistics -Name $ad.Name
                if ($st) { $i.Erros = [string]([int64]$st.ReceivedPacketErrors + [int64]$st.OutboundPacketErrors) }
            }
            $ip = Get-NetIPAddress -InterfaceIndex $r.InterfaceIndex -AddressFamily IPv4 | Select-Object -First 1
            if ($ip) { $i.Ip = [string]$ip.IPAddress }
            $i.Dns = @(Get-DnsClientServerAddress -InterfaceIndex $r.InterfaceIndex -AddressFamily IPv4 | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        }
    } catch { }
    $i
}
function Get-AdapterList {
    $o = New-Object System.Collections.ArrayList
    try {
        foreach ($a in @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' })) {
            [void]$o.Add([pscustomobject]@{ Index = [int]$a.InterfaceIndex; Label = ('{0}  [{1}]' -f $a.Name, $a.InterfaceDescription) })
        }
    } catch { }
    $o.ToArray()
}
'@
. ([scriptblock]::Create($script:NetInfoLib))

# Le rede, DNS e adaptadores em segundo plano (os cmdlets de rede sao lentos e travariam a janela).
$script:NetInfoCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    . ([scriptblock]::Create($Lib))
    $info = Get-NetInfo
    $ads = @(Get-AdapterList)
    $Q.Enqueue(@{ Kind = 'net-info'; Info = $info; Adapters = $ads; Why = $Why })
}

function Start-NetInfoAsync([string]$Why = 'manual') {
    if ($script:NetJob -and -not $script:NetJob.Handle.IsCompleted) { return $false }
    if ($script:NetJob) { Dispose-Bg $script:NetJob }
    $script:NetJob = Start-Bg $script:NetInfoCode @{ Q = $script:BgQ; Lib = $script:NetInfoLib; Why = $Why }
    $true
}

function Apply-NetInfo($info) {
    foreach ($t in $script:Targets) {
        if ($t.Auto -eq 'gateway' -and $info.Gateway) { $t.Destino = $info.Gateway }
        if ($t.Auto -eq 'dns') {
            # DNS local (127.x) vem de VPN/WARP/proxy: nao serve para medir a operadora
            $dnsReal = @($info.Dns | Where-Object { $_ -notlike '127.*' })
            if ($dnsReal.Count -gt 0) { $t.Destino = [string]$dnsReal[0] }
            elseif ($info.Dns.Count -gt 0) { $t.Destino = '' }
        }
    }
    $script:IsWifi = [bool]$info.Wifi
}

# Usa a leitura em cache (ate 30 s) para nao esperar; -Fresh forca uma leitura nova.
function Resolve-AutoTargets([switch]$Fresh) {
    $info = $script:LastInfo
    if ($Fresh -or -not $info -or ((Get-Date) - $script:LastInfoTime).TotalSeconds -gt 30) {
        $info = Get-NetInfo
        $script:LastInfo = $info; $script:LastInfoTime = Get-Date
    }
    Apply-NetInfo $info
    $info
}

function Sync-Cfg {
    $list = @()
    foreach ($t in $script:Targets) {
        $list += [pscustomobject]@{ Nome = $t.Nome; Destino = $t.Destino; Porta = $t.Porta; Role = $t.Role; Auto = $t.Auto }
    }
    $script:Cfg.Targets = $list
    Save-Config $script:Cfg
}

# ------------------------------------------------------------ monitor: lista, veredito, grafico
function Rebuild-List {
    $lv = $script:lv
    $lv.BeginUpdate()
    $lv.Items.Clear()
    foreach ($t in $script:Targets) {
        $it = New-Object System.Windows.Forms.ListViewItem($t.Nome)
        for ($k = 0; $k -lt 7; $k++) { [void]$it.SubItems.Add('-') }
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
    Refresh-List
}

function Set-SubText($it, [int]$k, [string]$v) { if ($it.SubItems[$k].Text -ne $v) { $it.SubItems[$k].Text = $v } }

function Refresh-List {
    $lv = $script:lv
    if ($lv.Items.Count -ne $script:Targets.Count) { Rebuild-List; return }
    $lv.BeginUpdate()
    for ($i = 0; $i -lt $script:Targets.Count; $i++) {
        $t = $script:Targets[$i]
        $it = $lv.Items[$i]
        $last = '-'
        if ($t.Total -gt 0) {
            if ($null -eq $t.Last) { $last = 'falha' } else { $last = (Fmt $t.Last 0) + ' ms' }
        }
        $avg = '-'; $mn = '-'; $mx = '-'
        if ($t.Ok -gt 0) { $avg = (Fmt (Get-Avg $t)) + ' ms'; $mn = (Fmt $t.Min 0) + ' ms'; $mx = (Fmt $t.Max 0) + ' ms' }
        $prob = '-'
        $pct = Get-Pct $t
        if ($t.Total -gt 0) { $prob = ('{0}%  ({1})' -f (Fmt $pct), ($t.Falhas + $t.Picos)) }
        Set-SubText $it 1 (Get-Endereco $t)
        Set-SubText $it 2 $last
        Set-SubText $it 3 $avg
        Set-SubText $it 4 $mn
        Set-SubText $it 5 $mx
        Set-SubText $it 6 $prob
        Set-SubText $it 7 ([string]$t.Total)
        if ($t.Total -eq 0) { $nc = (Get-RowColor 'none') }
        elseif ($pct -lt 1) { $nc = (Get-RowColor 'ok') }
        elseif ($pct -lt 3) { $nc = (Get-RowColor 'warn') }
        else { $nc = (Get-RowColor 'bad') }
        if ($it.BackColor.ToArgb() -ne $nc.ToArgb()) { $it.BackColor = $nc }
    }
    $lv.EndUpdate()
}

function Update-Verdict {
    $v = Get-Verdict $script:Targets
    $script:lblVerdict.Text = ($v.Lines -join "`r`n")
    switch ($v.Level) {
        'bad'  { $script:lblVerdict.BackColor = $script:Pal.RowBad }
        'warn' { $script:lblVerdict.BackColor = $script:Pal.RowWarn }
        'ok'   { $script:lblVerdict.BackColor = $script:Pal.RowOk }
        default { $script:lblVerdict.BackColor = $script:Pal.Info }
    }
}

function Draw-Chart($g, [int]$w, [int]$h) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear($script:Pal.Surface)
    $font = New-Object System.Drawing.Font('Segoe UI', [single]8.5)
    $mb = New-Object System.Drawing.SolidBrush($script:Pal.Muted)
    $t = $null
    if ($script:Sel -ge 0 -and $script:Sel -lt $script:Targets.Count) { $t = $script:Targets[$script:Sel] }
    if (-not $t -or $t.Hist.Count -eq 0) {
        $g.DrawString('Inicie o monitor e selecione um destino para ver o gráfico.', $font, $mb, 12, 12)
        $font.Dispose(); $mb.Dispose()
        return
    }
    $win = 150
    $data = $t.Hist.ToArray()
    if ($data.Length -gt $win) { $data = $data[($data.Length - $win)..($data.Length - 1)] }
    $n = $data.Length
    $mx = 100.0
    foreach ($v in $data) { if ($v -gt $mx) { $mx = $v } }
    $ymax = [math]::Ceiling($mx / 100) * 100
    if ($ymax -gt 3000) { $ymax = 3000 }
    $left = 52; $top = 26; $right = $w - 12; $bottom = $h - 22
    $pw = $right - $left; $ph = $bottom - $top
    if ($pw -lt 50 -or $ph -lt 30) { $font.Dispose(); $mb.Dispose(); return }
    $grid = New-Object System.Drawing.Pen($script:Pal.Grid)
    foreach ($fr in 0, 0.5, 1) {
        $y = $bottom - $fr * $ph
        $g.DrawLine($grid, $left, $y, $right, $y)
        $g.DrawString(([string][math]::Round($ymax * $fr)) + ' ms', $font, $mb, 4, ($y - 8))
    }
    if ($script:SpikeMs -le $ymax) {
        $ys = $bottom - ($script:SpikeMs / $ymax) * $ph
        $dash = New-Object System.Drawing.Pen($script:Pal.Dash)
        $dash.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
        $g.DrawLine($dash, $left, $ys, $right, $ys)
        $dash.Dispose()
    }
    $step = $pw / ($win - 1)
    $pen = New-Object System.Drawing.Pen($script:Pal.Line, [single]1.8)
    $red = New-Object System.Drawing.Pen($script:Pal.Red, [single]2)
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -le $n; $i++) {
        $v = -2.0
        if ($i -lt $n) { $v = $data[$i] }
        if ($v -ge 0) {
            $x = $left + (($win - $n) + $i) * $step
            $yy = $bottom - ([math]::Min($v, $ymax) / $ymax) * $ph
            $pts.Add((New-Object System.Drawing.PointF([single]$x, [single]$yy)))
        } else {
            if ($pts.Count -ge 2) { $g.DrawLines($pen, $pts.ToArray()) }
            elseif ($pts.Count -eq 1) { $g.FillEllipse([System.Drawing.Brushes]::SteelBlue, ($pts[0].X - 2), ($pts[0].Y - 2), 4, 4) }
            $pts.Clear()
            if ($v -eq -1.0) {
                $x = $left + (($win - $n) + $i) * $step
                $g.DrawLine($red, [single]$x, $top, [single]$x, $bottom)
            }
        }
    }
    $info = '{0}: último {1}, média {2}, máx {3}, problemas {4}%  (linha laranja = pico, traço vermelho = falha)' -f $t.Nome, $(if ($null -eq $t.Last) { 'falha' } else { (Fmt $t.Last 0) + ' ms' }), (Fmt (Get-Avg $t)), (Fmt $t.Max 0), (Fmt (Get-Pct $t))
    $g.DrawString($info, $font, $mb, $left, 4)
    $grid.Dispose(); $pen.Dispose(); $red.Dispose(); $font.Dispose(); $mb.Dispose()
}

# ------------------------------------------------------------ monitor: controle
function Start-Monitor {
    if ($script:Running) { return }
    [void](Resolve-AutoTargets)
    $dir = Get-ReportDir
    $script:CsvPath = Join-Path $dir ('monitor_{0}.csv' -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    $script:Csv = New-Object System.IO.StreamWriter($script:CsvPath, $false, (New-Object System.Text.UTF8Encoding($false)))
    $script:Csv.AutoFlush = $true
    $script:Csv.WriteLine('DataHora,Destino,LatenciaMs,Status')
    $script:Ctl = [hashtable]::Synchronized(@{ Run = $true })
    $iv = [int]$script:numInt.Value * 1000
    $to = [int]$script:Cfg.TimeoutMs
    $vazios = 0
    for ($i = 0; $i -lt $script:Targets.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace([string]$script:Targets[$i].Destino)) { $vazios++; continue }
        [void]$script:Workers.Add((Start-Worker $i $script:Targets[$i] $script:Ctl $script:Q $iv $to))
    }
    if ($script:Workers.Count -eq 0) {
        $script:Csv.Dispose(); $script:Csv = $null; $script:Ctl.Run = $false
        Set-Status 'Sem rede detectada (nenhum destino para medir). Conecte-se à internet e clique em Iniciar de novo.'
        return
    }
    $script:Running = $true
    $script:btnStart.Enabled = $false; $script:btnStop.Enabled = $true
    $script:lblChip.Text = '● monitorando'
    Refresh-List
    $msg = 'Gravando em ' + $script:CsvPath
    if ($vazios -gt 0) { $msg += '  (' + $vazios + ' destino(s) sem endereço foram ignorados)' }
    Set-Status $msg
}

function Stop-Monitor {
    if (-not $script:Running) { return }
    $script:Ctl.Run = $false
    foreach ($w in $script:Workers) { Stop-Bg $w; [void]$script:Retiring.Add($w) }
    $script:Workers.Clear()
    $script:Running = $false
    try { Flush-HistBuckets } catch { }
    if ($script:Csv) { try { $script:Csv.Dispose() } catch { }; $script:Csv = $null }
    $script:btnStart.Enabled = $true; $script:btnStop.Enabled = $false
    $script:lblChip.Text = '○ parado'
    Set-Status ('Monitor parado. Log salvo em ' + $script:CsvPath)
}

function Reset-Monitor {
    foreach ($t in $script:Targets) { Reset-TargetState $t }
    $script:SessionStart = $null; $script:LastSample = $null
    Refresh-List; $script:chart.Invalidate(); Update-Verdict
}

function Show-AddDialog {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Adicionar destino'
    $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.ClientSize = New-Object System.Drawing.Size(380, 190)
    $labels = 'Nome', 'Endereço (IP ou site)', 'Porta (0 = ping)'
    $boxes = @()
    for ($i = 0; $i -lt 3; $i++) {
        $l = New-Object System.Windows.Forms.Label
        $l.Text = $labels[$i]; $l.Left = 12; $l.Top = 18 + $i * 38; $l.Width = 140
        $b = New-Object System.Windows.Forms.TextBox
        $b.Left = 160; $b.Top = 14 + $i * 38; $b.Width = 200
        $f.Controls.Add($l); $f.Controls.Add($b)
        $boxes += $b
    }
    $boxes[2].Text = '25565'
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Adicionar'; $ok.Left = 160; $ok.Top = 140; $ok.Width = 95
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancelar'; $cancel.Left = 265; $cancel.Top = 140; $cancel.Width = 95
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $f.Controls.Add($ok); $f.Controls.Add($cancel)
    $f.AcceptButton = $ok; $f.CancelButton = $cancel
    $res = $null
    if ($f.ShowDialog($script:form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $porta = 0
        if ([int]::TryParse($boxes[2].Text.Trim(), [ref]$porta) -and $boxes[0].Text.Trim() -and $boxes[1].Text.Trim() -and $porta -ge 0 -and $porta -le 65535) {
            $res = @{ Nome = $boxes[0].Text.Trim(); Destino = $boxes[1].Text.Trim(); Porta = $porta }
        } else {
            [void][System.Windows.Forms.MessageBox]::Show('Preencha nome, endereço e uma porta entre 0 e 65535.', 'NetDoctor')
        }
    }
    $f.Dispose()
    $res
}

function Add-TargetUi {
    $d = Show-AddDialog
    if (-not $d) { return }
    $t = New-TargetState ([pscustomobject]@{ Nome = $d.Nome; Destino = $d.Destino; Porta = $d.Porta; Role = 'destino'; Auto = '' })
    [void]$script:Targets.Add($t)
    if ($script:Running) {
        $idx = $script:Targets.Count - 1
        [void]$script:Workers.Add((Start-Worker $idx $t $script:Ctl $script:Q ([int]$script:numInt.Value * 1000) ([int]$script:Cfg.TimeoutMs)))
    }
    Sync-Cfg; Rebuild-List
}

function Remove-TargetUi {
    if ($script:Running) { [void][System.Windows.Forms.MessageBox]::Show('Pare o monitor antes de remover um destino.', 'NetDoctor'); return }
    if ($script:lv.SelectedIndices.Count -eq 0) { return }
    $i = $script:lv.SelectedIndices[0]
    $script:Targets.RemoveAt($i)
    if ($script:Sel -ge $script:Targets.Count) { $script:Sel = 0 }
    Sync-Cfg; Rebuild-List; $script:chart.Invalidate(); Update-Verdict
}

# ------------------------------------------------------------ diagnostico, rede, snapshot, suporte
function Start-Diag {
    if ($script:DiagJob -and -not $script:DiagJob.Handle.IsCompleted) { return }
    [void](Resolve-AutoTargets)
    $script:rtbDiag.Clear(); $script:DiagColored.Clear(); $script:DiagLines.Clear(); $script:DiagFindings.Clear(); $script:DiagMeta = @{}
    $tg = @()
    foreach ($t in $script:Targets) { $tg += @{ Nome = $t.Nome; Destino = $t.Destino; Porta = $t.Porta; Role = $t.Role } }
    $script:btnDiag.Enabled = $false
    $script:lblDiag.Text = 'Iniciando...'
    $script:DiagJob = Start-Bg $script:DiagCode @{ Q = $script:BgQ; Targets = $tg; PingExterno = '1.1.1.1'; DoSpeed = [bool]$script:chkSpeed.Checked; Lib = $script:NetTestLib; PlanoMbps = (Convert-PlanToMbps ([string]$script:Cfg.Plano)) }
}

function Start-Scan {
    if ($script:ScanJob -and -not $script:ScanJob.Handle.IsCompleted) { return }
    $script:lvNet.Items.Clear()
    $script:btnScan.Enabled = $false
    $script:lblScan.Text = 'Varrendo a rede...'
    $script:ScanJob = Start-Bg $script:ScanCode @{ Q = $script:BgQ }
}

function Start-Snap {
    if ($script:SnapJob -and -not $script:SnapJob.Handle.IsCompleted) { return }
    $out = Join-Path (Get-ReportDir) ('config_{0}.txt' -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    $script:btnSnap.Enabled = $false
    Set-Status 'Salvando configuração de rede...'
    $script:SnapJob = Start-Bg $script:SnapCode @{ Q = $script:BgQ; OutFile = $out }
}

function Gen-Support {
    $kind = 'operadora'
    if ($script:cmbKind.SelectedIndex -eq 1) { $kind = 'servidor' }
    $script:Cfg | Add-Member -NotePropertyName Provedor -NotePropertyValue $script:txtProv.Text -Force
    $script:Cfg | Add-Member -NotePropertyName Plano -NotePropertyValue $script:txtPlano.Text -Force
    Save-Config $script:Cfg
    $srv = $null
    if ($script:Sel -ge 0 -and $script:Sel -lt $script:Targets.Count -and $script:Targets[$script:Sel].Role -eq 'destino') { $srv = $script:Targets[$script:Sel] }
    if (-not $srv) { foreach ($t in $script:Targets) { if ($t.Role -eq 'destino') { $srv = $t; break } } }
    $v = Get-Verdict $script:Targets
    $script:txtSupport.Text = Build-SupportText $kind $script:Targets $script:Cfg $v $srv $script:DiagMeta
}

function Show-PcInfo($i) {
    $lines = @(
        ('Adaptador ativo:     ' + $i.Adapter),
        ('Velocidade do link:  ' + $i.Link),
        ('Endereço IP do PC:   ' + $i.Ip),
        ('Roteador (gateway):  ' + $i.Gateway),
        ('DNS em uso:          ' + ($i.Dns -join ', ')),
        ('Tipo de conexão:     ' + $(if ($i.Wifi) { 'Wi-Fi' } else { 'cabo (ou outro)' })),
        ('Erros de pacote na placa desde que o PC ligou: ' + $i.Erros),
        ''
    )
    if ($i.Dns.Count -gt 0 -and @($i.Dns | Where-Object { $_ -notlike '127.*' }).Count -eq 0) {
        $lines += 'AVISO: o DNS em uso é local (127.x), normalmente de uma VPN ou do Cloudflare WARP. O teste "DNS em uso" fica desligado e trocar o DNS aqui pode não ter efeito enquanto ele estiver ligado.'
    }
    if ($i.Speed -and $i.Speed -lt 1000000000) { $lines += 'ATENÇÃO: o link está abaixo de 1 Gbps, o que limita planos acima de 100 Mbps (confira cabo e conectores).' }
    $script:txtPc.Text = ($lines -join "`r`n")
    $script:GwCache = $i.Gateway
}

function Refresh-PcInfo { [void](Start-NetInfoAsync 'manual') }


# ------------------------------------------------------------ ferramentas DNS (interface)
function Get-SelectedIfIndex {
    $k = $script:cmbAd.SelectedIndex
    if ($k -ge 0 -and $k -lt $script:AdIdx.Count) { return [int]$script:AdIdx[$k] }
    0
}

function Set-DnsInfoText {
    $c = $script:DnsCache
    $txtModo = 'configuração não identificada'
    if ($c.Modo -eq 'automatico') { $txtModo = 'automático (vem do roteador/operadora)' }
    elseif ($c.Modo -eq 'manual') { $txtModo = 'manual (definido no Windows)' }
    $bk = Read-DnsBackup
    $txtBk = 'nenhum backup ainda'
    if ($bk) { $txtBk = 'backup de ' + [string]$bk.Data }
    $t = ('DNS atual neste adaptador: {0}   |   modo: {1}   |   {2}' -f (@($c.Servers) -join ', '), $txtModo, $txtBk)
    if (@($c.V6).Count -gt 0) { $t += ('   |   DNS IPv6: {0} (o Windows pode usar este em vez do IPv4 escolhido)' -f (@($c.V6) -join ', ')) }
    $script:lblDnsInfo.Text = $t
}

# Le o DNS do adaptador escolhido em segundo plano.
function Update-DnsInfo {
    $idx = Get-SelectedIfIndex
    if ($idx -le 0) { $script:lblDnsInfo.Text = 'Nenhum adaptador de rede ativo encontrado.'; return }
    if ($script:DnsInfoJob -and -not $script:DnsInfoJob.Handle.IsCompleted) { $script:DnsInfoPending = $true; return }
    if ($script:DnsInfoJob) { Dispose-Bg $script:DnsInfoJob }
    $script:DnsInfoJob = Start-Bg $script:DnsInfoCode @{ Q = $script:BgQ; Lib = $script:DnsLib; IfIndex = $idx }
}

function Get-CachedDnsServers([int]$idx) {
    if ([int]$script:DnsCache.IfIndex -eq $idx) { return @($script:DnsCache.Servers) }
    @(Get-DnsServers $idx)
}

function Get-CachedDnsServers6([int]$idx) {
    if ([int]$script:DnsCache.IfIndex -eq $idx) { return @($script:DnsCache.V6) }
    @(Get-DnsServers6 $idx)
}

function Fill-Adapters($list, [int]$act) {
    $keep = Get-SelectedIfIndex
    $script:AdFilling = $true
    $script:cmbAd.Items.Clear(); $script:AdIdx = @()
    $sel = -1; $selAct = -1
    foreach ($a in @($list)) {
        [void]$script:cmbAd.Items.Add([string]$a.Label)
        $script:AdIdx += [int]$a.Index
        $n = $script:cmbAd.Items.Count - 1
        if ([int]$a.Index -eq $keep) { $sel = $n }
        if ([int]$a.Index -eq $act) { $selAct = $n }
    }
    if ($script:cmbAd.Items.Count -gt 0) {
        if ($sel -lt 0) { $sel = $selAct }
        if ($sel -lt 0) { $sel = 0 }
        $script:cmbAd.SelectedIndex = $sel
    }
    $script:AdFilling = $false
    Update-DnsInfo
}

function Fill-DnsList {
    $lv = $script:lvDns
    $lv.BeginUpdate(); $lv.Items.Clear()
    $melhor = $null
    foreach ($d in $script:DnsItems) { if ($null -ne $d.Media -and ($null -eq $melhor -or $d.Media -lt $melhor)) { $melhor = $d.Media } }
    foreach ($d in $script:DnsItems) {
        $it = New-Object System.Windows.Forms.ListViewItem([string]$d.Nome)
        [void]$it.SubItems.Add([string]$d.Dns1); [void]$it.SubItems.Add([string]$d.Dns2)
        $m = '-'; if ($null -ne $d.Media) { $m = (Fmt $d.Media) + ' ms' } elseif ($d.Testado) { $m = 'sem resposta' }
        $f = '-'; if ($d.Testado) { $f = [string]$d.Falhas + ' de 5' }
        $pg = '-'; if ($null -ne $d.Ping) { $pg = (Fmt $d.Ping 0) + ' ms' }
        [void]$it.SubItems.Add($m); [void]$it.SubItems.Add($f); [void]$it.SubItems.Add($pg); [void]$it.SubItems.Add([string]$d.Nota)
        if ($d.Testado -and $null -eq $d.Media) { $it.BackColor = $script:Pal.RowBad }
        elseif ($null -ne $melhor -and $null -ne $d.Media -and $d.Media -eq $melhor) { $it.BackColor = $script:Pal.RowOk }
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
}

function Start-DnsTest {
    if ($script:DnsJob -and -not $script:DnsJob.Handle.IsCompleted) { return }
    $idx = Get-SelectedIfIndex
    $items = New-Object System.Collections.ArrayList
    if ($idx -gt 0) {
        foreach ($c in @(Get-CachedDnsServers $idx)) {
            [void]$items.Add([pscustomobject]@{ Nome = 'Atual (em uso)'; Dns1 = [string]$c; Dns2 = ''; Nota = 'configurado agora neste adaptador'; Media = $null; Falhas = 0; Ping = $null; Testado = $false; Filtra = $false })
        }
    }
    foreach ($p in $script:DnsProviders) {
        [void]$items.Add([pscustomobject]@{ Nome = $p.Nome; Dns1 = $p.Dns1; Dns2 = $p.Dns2; Nota = $p.Nota; Media = $null; Falhas = 0; Ping = $null; Testado = $false; Filtra = [bool]$p.Filtra })
    }
    $script:DnsItems = $items
    Fill-DnsList
    $payload = @()
    foreach ($it in $items) { $payload += @{ Dns = $it.Dns1 } }
    $script:btnDnsTest.Enabled = $false
    $script:lblDnsProg.Text = 'Iniciando teste...'
    $script:DnsJob = Start-Bg $script:DnsTestCode @{ Q = $script:BgQ; Items = $payload }
}

function Show-Msg([string]$text, [string]$icon = 'Information') {
    [void][System.Windows.Forms.MessageBox]::Show((T $text), 'NetDoctor', 'OK', $icon)
}

function Confirm-Dns([string]$text) {
    ([System.Windows.Forms.MessageBox]::Show((T $text), 'NetDoctor - DNS', 'YesNo', 'Question') -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Finish-DnsChange($r, [string]$okMsg) {
    if ($r.Ok) {
        Set-Status $okMsg
        $script:LastInfo = $null
        [void](Start-NetInfoAsync 'apply')
        Update-DnsInfo
        Notify-DnsChanged
        if ($script:Running) { Set-Status ($okMsg + '  Pare e inicie o monitor para medir o novo DNS.') }
    } else {
        Set-Status $r.Msg
        Show-Msg $r.Msg 'Warning'
        Update-DnsInfo
    }
}

function Apply-DnsPair([string]$nome, [string]$d1, [string]$d2) {
    $idx = Get-SelectedIfIndex
    if ($idx -le 0) { Show-Msg 'Nenhum adaptador de rede ativo.' 'Warning'; return }
    $lista = @($d1); if ($d2) { $lista += $d2 }
    $atual = ((Get-CachedDnsServers $idx) -join ', ')
    if (-not $atual) { $atual = '(automático)' }
    $q = ('Trocar o DNS deste adaptador?' + "`r`n`r`n" + 'Atual: ' + $atual + "`r`n" + 'Novo ({0}): {1}' + "`r`n`r`n" + 'O Windows vai pedir permissão de administrador. Um backup do DNS atual é salvo para você poder voltar.') -f $nome, ($lista -join ', ')
    if ($atual -like '127.*') { $q += ("`r`n`r`n" + 'Atenção: o DNS atual é local (127.x), geralmente de VPN ou Cloudflare WARP. A troca pode ser ignorada enquanto ele estiver ligado.') }
    $v6 = @(Get-CachedDnsServers6 $idx)
    if ($v6.Count -gt 0) { $q += ("`r`n`r`n" + 'Atenção: este adaptador também tem DNS IPv6 (' + ($v6 -join ', ') + '). O Windows pode continuar usando ele; o teste de velocidade vale para o IPv4.') }
    if (-not (Confirm-Dns $q)) { return }
    Save-DnsBackup $idx
    Set-Status 'Aguardando permissão de administrador...'
    $r = Invoke-DnsChange $idx $lista $false
    Finish-DnsChange $r ('DNS alterado para ' + ($lista -join ', ') + '.')
}

function Apply-DnsSelected {
    if ($script:lvDns.SelectedIndices.Count -eq 0) { Show-Msg 'Selecione um DNS na lista (clique em "Testar DNS" para ver qual responde mais rápido).'; return }
    $it = $script:DnsItems[$script:lvDns.SelectedIndices[0]]
    if ($it.Nome -like 'Atual*') { Show-Msg 'Esse já é o DNS em uso. Escolha outro da lista.'; return }
    Apply-DnsPair $it.Nome $it.Dns1 $it.Dns2
}

function Apply-DnsManual {
    $d1 = $script:txtDns1.Text.Trim(); $d2 = $script:txtDns2.Text.Trim()
    if (-not (Test-IPv4 $d1)) { Show-Msg 'Informe um DNS 1 válido (exemplo: 1.1.1.1).' 'Warning'; return }
    if ($d2 -and -not (Test-IPv4 $d2)) { Show-Msg 'O DNS 2 não é um endereço válido. Deixe em branco ou corrija.' 'Warning'; return }
    Apply-DnsPair 'manual' $d1 $d2
}

function Reset-DnsAuto {
    $idx = Get-SelectedIfIndex
    if ($idx -le 0) { Show-Msg 'Nenhum adaptador de rede ativo.' 'Warning'; return }
    if (-not (Confirm-Dns 'Voltar este adaptador para o DNS automático (o que o roteador/operadora entrega)?')) { return }
    Save-DnsBackup $idx
    Set-Status 'Aguardando permissão de administrador...'
    $r = Invoke-DnsChange $idx @() $true
    Finish-DnsChange $r 'DNS voltou para o modo automático.'
}

function Restore-DnsBackup {
    $bk = Read-DnsBackup
    if (-not $bk) { Show-Msg 'Ainda não há backup. Ele é criado automaticamente antes da primeira troca de DNS.'; return }
    $ad = $null
    try { $ad = Get-NetAdapter | Where-Object { [string]$_.InterfaceGuid -eq [string]$bk.Guid } | Select-Object -First 1 } catch { }
    if (-not $ad) { Show-Msg ('O adaptador do backup (' + [string]$bk.Nome + ') não está disponível agora.') 'Warning'; return }
    $servers = @($bk.Servers)
    $desc = ($servers -join ', ')
    if ([string]$bk.Modo -eq 'automatico' -or $servers.Count -eq 0) { $desc = 'automático' }
    if (-not (Confirm-Dns ('Restaurar o DNS de ' + [string]$bk.Data + ' no adaptador ' + [string]$bk.Nome + "`r`n`r`n" + 'Valor do backup: ' + $desc))) { return }
    Set-Status 'Aguardando permissão de administrador...'
    if ([string]$bk.Modo -eq 'automatico' -or $servers.Count -eq 0) { $r = Invoke-DnsChange ([int]$ad.InterfaceIndex) @() $true }
    else { $r = Invoke-DnsChange ([int]$ad.InterfaceIndex) ([string[]]$servers) $false }
    Finish-DnsChange $r ('DNS restaurado: ' + $desc + '.')
}

function Flush-DnsUi {
    Set-Status 'Aguardando permissão de administrador...'
    $r = Invoke-FlushDns
    if ($r.Ok) { Set-Status 'Cache de DNS limpo.' } else { Set-Status $r.Msg; Show-Msg $r.Msg 'Warning' }
}

function Apply-DnsFastestNow {
    $best = $script:DnsItems | Where-Object { $null -ne $_.Media -and -not $_.Filtra } | Select-Object -First 1
    if (-not $best) { Show-Msg 'Nenhum DNS respondeu no teste. Confira a internet e tente de novo.' 'Warning'; return }
    if ($best.Nome -like 'Atual*') {
        Show-Msg ('O DNS que você já usa ({0}) foi o mais rápido neste teste ({1} ms). Não há nada para trocar.' -f $best.Dns1, (Fmt $best.Media))
        return
    }
    Apply-DnsPair $best.Nome $best.Dns1 $best.Dns2
}

function Apply-DnsFastest {
    $feitos = @($script:DnsItems | Where-Object { $_.Testado })
    if ($feitos.Count -eq 0) {
        $script:AutoApplyAfterTest = $true
        Set-Status 'Testando os DNS antes de escolher o mais rápido...'
        Start-DnsTest
        return
    }
    Apply-DnsFastestNow
}

function Repair-NetUi {
    $q = 'Reparar a rede?' + "`r`n`r`n" + 'O que será feito:' + "`r`n" + '- limpar o cache de DNS' + "`r`n" + '- limpar o cache de endereços da rede local (ARP)' + "`r`n" + '- soltar e renovar o IP do DHCP (a internet cai por alguns segundos)' + "`r`n`r`n" + 'O Windows vai pedir permissão de administrador.'
    if (-not (Confirm-Dns $q)) { return }
    $ws = ([System.Windows.Forms.MessageBox]::Show('Também redefinir o Winsock e a pilha TCP/IP?' + "`r`n`r`n" + 'Só vale a pena se a conexão continuar com problema depois do reparo básico. Exige reiniciar o PC.', 'NetDoctor', 'YesNo', 'Question', 'Button2') -eq [System.Windows.Forms.DialogResult]::Yes)
    $r = Invoke-NetRepair $ws
    if ($r.Ok) {
        $m = 'Reparo iniciado: a conexão pode cair e voltar em alguns segundos.'
        if ($ws) { $m += ' Reinicie o PC para concluir a redefinição do Winsock/TCP-IP.' }
        Set-Status $m
    } else { Set-Status $r.Msg; Show-Msg $r.Msg 'Warning' }
}

function Start-Pub {
    if ($script:PubJob -and -not $script:PubJob.Handle.IsCompleted) { return }
    Set-Status 'Consultando o provedor (ipinfo.io)...'
    $script:PubJob = Start-Bg $script:PubCode @{ Q = $script:BgQ }
}

function Notify-DnsChanged {
    if ($script:Cfg.SomDns -ne $false) { Play-DnsSound }
}

function Get-NetSigLite {
    $parts = @()
    try {
        foreach ($n in [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) {
            if ($n.OperationalStatus -ne 'Up' -or $n.NetworkInterfaceType -eq 'Loopback') { continue }
            $ip = $n.GetIPProperties()
            $gw = @($ip.GatewayAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.Address.ToString() })
            $dns = @($ip.DnsAddresses | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.ToString() })
            $parts += ($n.Id + '=' + ($gw -join ',') + '/' + ($dns -join ','))
        }
    } catch { }
    (@($parts) | Sort-Object) -join ';'
}

# Barato (so .NET, sem CIM): roda a cada ~4 s. Se algo mudou, a leitura completa acontece em segundo plano.
function Check-NetChange {
    $sig = Get-NetSigLite
    if ($script:NetSig -and $sig -ne $script:NetSig) {
        if (Start-NetInfoAsync 'change') { $script:NetSig = $sig }
    }
}

# ------------------------------------------------------------ desempenho em jogos (interface)
function Confirm-Action([string]$text, [string]$title = 'NetDoctor') {
    ([System.Windows.Forms.MessageBox]::Show((T $text), $title, 'YesNo', 'Question') -eq [System.Windows.Forms.DialogResult]::Yes)
}

function Fill-GameList {
    $lv = $script:lvGame
    $marcados = @{}
    $selId = $null
    if ($lv.SelectedItems.Count -gt 0) { $selId = [string]$lv.SelectedItems[0].Tag }
    foreach ($it in $lv.Items) { if ($it.Checked) { $marcados[[string]$it.Tag] = $true } }
    $lv.BeginUpdate(); $lv.Items.Clear()
    foreach ($t in $script:GameTweaks) {
        $est = 'Verificando...'
        if ($script:GameStates.ContainsKey([string]$t.Id)) { $est = [string]$script:GameStates[[string]$t.Id] }
        $it = New-Object System.Windows.Forms.ListViewItem([string]$t.Nome)
        [void]$it.SubItems.Add([string]$t.Cat); [void]$it.SubItems.Add([string]$t.Risco)
        $adm = 'Não'; if ($t.Admin) { $adm = 'Sim' }
        [void]$it.SubItems.Add($adm); [void]$it.SubItems.Add($est)
        $it.Tag = [string]$t.Id
        if ($marcados.ContainsKey([string]$t.Id)) { $it.Checked = $true }
        if ($est -eq 'Ativa') { $it.BackColor = $script:Pal.RowOk }
        elseif ($est -eq 'Incompatível') { $it.ForeColor = $script:Pal.Muted }
        elseif ($est -eq 'Parcial') { $it.BackColor = $script:Pal.RowWarn }
        [void]$lv.Items.Add($it)
    }
    if ($selId) { foreach ($x in $lv.Items) { if ([string]$x.Tag -eq $selId) { $x.Selected = $true } } }
    $lv.EndUpdate()
}

# Estados (registro, tarefas agendadas, plano de energia) sao lidos em segundo plano.
function Start-GameStates {
    if ($script:GameJob -and -not $script:GameJob.Handle.IsCompleted) { $script:GameDirty = $true; return }
    if ($script:GameJob) { Dispose-Bg $script:GameJob }
    $script:GameJob = Start-Bg $script:GameStatesCode @{ Q = $script:BgQ; Lib = $script:GameStateLib; Tweaks = $script:GameTweaks }
}

function Refresh-GameList { Fill-GameList; Start-GameStates }

function Get-CheckedGameIds {
    $ids = @()
    foreach ($it in $script:lvGame.Items) { if ($it.Checked) { $ids += [string]$it.Tag } }
    $ids
}

function Mark-GameRec {
    foreach ($it in $script:lvGame.Items) {
        $t = Get-TweakById ([string]$it.Tag)
        $est = $it.SubItems[4].Text
        $it.Checked = ((Test-GameRecomendada $t) -and $est -ne 'Ativa' -and $est -ne 'Incompatível')
    }
}

function Clear-GameMarks { foreach ($it in $script:lvGame.Items) { $it.Checked = $false } }

function Apply-GamesUi {
    $ids = @(Get-CheckedGameIds)
    if ($ids.Count -eq 0) { Show-Msg 'Marque pelo menos uma otimização na lista (ou use "Marcar recomendadas").'; return }
    $pend = @()
    foreach ($id in $ids) {
        $e = Get-GameStateCached $id
        if ($e -ne 'Ativa' -and $e -ne 'Incompatível') { $pend += $id }
    }
    if ($pend.Count -eq 0) { Show-Msg 'As otimizações marcadas já estão ativas (ou não são compatíveis com este PC).'; return }
    $nomes = ($pend | ForEach-Object { '- ' + (Get-TweakById $_).Nome }) -join "`r`n"
    $q = 'Aplicar estas otimizações?' + "`r`n`r`n" + $nomes + "`r`n`r`n" + 'Cada ajuste guarda o valor original e pode ser revertido. Alguns pedem permissão de administrador.'
    if (-not (Confirm-Action $q 'NetDoctor - desempenho em jogos')) { return }
    if (Confirm-Action ('Criar um ponto de restauração do Windows antes?' + "`r`n`r`n" + 'É o jeito mais seguro de voltar atrás. Leva alguns segundos.') 'NetDoctor - ponto de restauração') {
        Set-Status 'Criando o ponto de restauração (aguardando permissão de administrador)...'
        $c = Invoke-RestorePoint
        if ($null -eq $c) { Set-Status 'Cancelado: a permissão de administrador não foi concedida.'; return }
        if ($c -eq 1) {
            if (-not (Confirm-Action 'Não foi possível criar o ponto de restauração (a Proteção do Sistema pode estar desligada). Aplicar as otimizações mesmo assim?')) { Set-Status 'Cancelado.'; return }
        }
    }
    Set-Status 'Aplicando otimizações...'
    $r = Invoke-GameApply $pend
    Refresh-GameList
    $m = ''
    if ($r.Ok.Count -gt 0) { $m += 'Aplicadas:' + "`r`n" + (($r.Ok | ForEach-Object { '- ' + $_ }) -join "`r`n") + "`r`n`r`n" }
    if ($r.Fail.Count -gt 0) {
        $m += 'Não foi possível aplicar:' + "`r`n" + (($r.Fail | ForEach-Object { '- ' + $_ }) -join "`r`n")
        if ($r.Cancelado) { $m += "`r`n" + '(a permissão de administrador foi recusada)' }
        $m += "`r`n`r`n"
    }
    if ($r.Skip.Count -gt 0) { $m += 'Ignoradas (incompatíveis com este PC):' + "`r`n" + (($r.Skip | ForEach-Object { '- ' + $_ }) -join "`r`n") + "`r`n`r`n" }
    $m += 'Parte das mudanças (plano de energia, mouse, animações, HAGS) só aparece por completo ao sair e entrar no Windows ou reiniciar o PC.'
    Set-Status ('Otimizações aplicadas: ' + $r.Ok.Count + '. Falhas: ' + $r.Fail.Count + '.')
    Show-Msg $m
}

function Revert-GamesUi([bool]$All) {
    if ($All) { $ids = @($script:GameTweaks | ForEach-Object { [string]$_.Id }) } else { $ids = @(Get-CheckedGameIds) }
    if ($ids.Count -eq 0) { Show-Msg 'Marque as otimizações que você quer reverter, ou use "Reverter tudo".'; return }
    $q = 'Reverter as otimizações para os valores originais guardados?'
    if ($All) { $q = 'Reverter TODAS as otimizações aplicadas por este programa para os valores originais?' }
    if (-not (Confirm-Action $q 'NetDoctor - reverter')) { return }
    Set-Status 'Revertendo...'
    $r = Invoke-GameRevert $ids
    Refresh-GameList
    if ($r.Cancelado) { Set-Status 'Cancelado: a permissão de administrador não foi concedida.'; Show-Msg 'A permissão de administrador foi recusada. Os ajustes que dependem dela continuam aplicados.' 'Warning'; return }
    if ($r.Falhou) { Set-Status 'Parte da reversão falhou.'; Show-Msg 'O Windows recusou parte da reversão. Tente de novo ou use o ponto de restauração.' 'Warning'; return }
    if ($r.Feitos -eq 0) { Set-Status 'Nada para reverter.'; Show-Msg 'Nada para reverter: essas otimizações não foram aplicadas por este programa.'; return }
    Set-Status ('Revertido: ' + $r.Feitos + ' ajuste(s).')
    Show-Msg 'Otimizações revertidas. Algumas só voltam ao normal depois de sair e entrar no Windows ou reiniciar.'
}

function Create-RestoreUi {
    if (-not (Confirm-Action ('Criar um ponto de restauração do Windows agora?' + "`r`n`r`n" + 'O Windows pede permissão de administrador e só permite um ponto novo a cada 24 horas.') 'NetDoctor - ponto de restauração')) { return }
    Set-Status 'Criando o ponto de restauração...'
    $c = Invoke-RestorePoint
    if ($null -eq $c) { Set-Status 'Cancelado: a permissão de administrador não foi concedida.'; return }
    if ($c -eq 0) { Set-Status 'Ponto de restauração criado.'; Show-Msg 'Ponto de restauração criado.' }
    elseif ($c -eq 2) { Set-Status 'Já existe um ponto de restauração recente.'; Show-Msg 'O Windows só cria um ponto novo a cada 24 horas; já existe um recente, que serve de backup.' }
    else { Set-Status 'Não foi possível criar o ponto de restauração.'; Show-Msg 'Não foi possível criar. A Proteção do Sistema pode estar desligada (Configurações > Sistema > Sobre > Proteção do sistema).' 'Warning' }
}

function Start-GameToolUi([string]$Tool, [string]$Aviso) {
    if (-not (Confirm-Action $Aviso 'NetDoctor - desempenho em jogos')) { return }
    $r = Start-GameTool $Tool
    if ($null -eq $r) { Set-Status 'Cancelado: a permissão de administrador não foi concedida.' }
    else { Set-Status 'Uma janela foi aberta para acompanhar o progresso.' }
}

# ------------------------------------------------------------ aplicar o tema nos controles
function Apply-ThemeTo($c) {
    $p = $script:Pal
    $tag = ''
    if ($c.Tag -is [string]) { $tag = [string]$c.Tag }
    if ($tag -eq 'keep') { return }
    if ($tag -eq 'surface') { $c.BackColor = $p.Surface; return }
    if ($tag -eq 'verdict') { $c.ForeColor = $p.Text; return }
    if ($c -is [System.Windows.Forms.TabControl]) {
        $c.BackColor = $p.Back
    } elseif ($c -is [System.Windows.Forms.TabPage]) {
        $c.UseVisualStyleBackColor = $false; $c.BackColor = $p.Back; $c.ForeColor = $p.Text
    } elseif ($c -is [System.Windows.Forms.Button]) {
        $c.UseVisualStyleBackColor = $false; $c.FlatStyle = 'Flat'
        $c.FlatAppearance.BorderColor = $p.BtnBorder; $c.FlatAppearance.BorderSize = 1
        $c.FlatAppearance.MouseOverBackColor = $p.BtnHover
        $c.BackColor = $p.Btn; $c.ForeColor = $p.Text
    } elseif ($c -is [System.Windows.Forms.ListView]) {
        $c.BackColor = $p.Surface; $c.ForeColor = $p.Text
    } elseif ($c -is [System.Windows.Forms.TextBoxBase]) {
        $c.BackColor = $p.Surface; $c.ForeColor = $p.Text
    } elseif ($c -is [System.Windows.Forms.NumericUpDown]) {
        $c.BackColor = $p.Surface; $c.ForeColor = $p.Text
    } elseif ($c -is [System.Windows.Forms.ComboBox]) {
        $c.FlatStyle = 'Flat'; $c.BackColor = $p.Surface; $c.ForeColor = $p.Text
    } elseif ($c -is [System.Windows.Forms.CheckBox]) {
        $c.ForeColor = $p.Text
    } elseif ($c -is [System.Windows.Forms.Label]) {
        $c.ForeColor = $p.Text
        if ($tag -eq 'muted') { $c.ForeColor = $p.Muted }
        if ($tag -eq 'info') { $c.BackColor = $p.Info }
    } elseif ($c -is [System.Windows.Forms.Panel]) {
        $c.BackColor = $p.Back
    }
    foreach ($ch in $c.Controls) { Apply-ThemeTo $ch }
}

# Barras de rolagem e cabecalhos escuros (so funcionam depois que a janela existe).
function Apply-NativeTheme($c) {
    try {
        # So barras de rolagem de listas e caixas de texto: e o minimo que escurece sem arriscar o desenho dos demais controles.
        if ($c.IsHandleCreated -and ($c -is [System.Windows.Forms.ListView] -or $c -is [System.Windows.Forms.TextBoxBase])) {
            $sub = $null
            if ($script:ThemeName -eq 'escuro') { $sub = 'DarkMode_Explorer' }
            [void][NetDoctorNative.Api]::SetWindowTheme($c.Handle, $sub, $null)
        }
    } catch { }
    foreach ($ch in $c.Controls) { Apply-NativeTheme $ch }
}

function Apply-Theme {
    $p = $script:Pal
    $script:form.SuspendLayout()
    $script:form.BackColor = $p.Back; $script:form.ForeColor = $p.Text
    $script:header.BackColor = $p.Header
    foreach ($c in $script:form.Controls) { Apply-ThemeTo $c }
    $script:form.ResumeLayout()
    # itens com cor propria (linhas de listas, veredito, grafico, diagnostico)
    Refresh-List
    Update-Verdict
    Fill-DnsList
    Fill-GameList
    Fill-DiskLists
    $script:histPanel.Invalidate()
    Render-UpdateNotes
    Update-VersionLabel
    Fill-WifiLists
    Show-WifiSummary
    Render-Faq
    $script:lblAssistBanner.BackColor = $p.Info; $script:lblRoute.BackColor = $p.Info
    if ($script:AssistColored.Count -gt 0) {
        $script:rtbAssist.Clear()
        foreach ($d in $script:AssistColored) { Add-RtbLine $script:rtbAssist $d.T $d.C }
    }
    if ($script:DiagColored.Count -gt 0) {
        $script:rtbDiag.Clear()
        foreach ($d in $script:DiagColored) { Add-RtbLine $script:rtbDiag $d.T $d.C }
    }
    $script:chart.Invalidate()
    $script:tabs.Invalidate()
    if ($script:form.IsHandleCreated) {
        try {
            $v = 0; if ($script:ThemeName -eq 'escuro') { $v = 1 }
            [void][NetDoctorNative.Api]::DwmSetWindowAttribute($script:form.Handle, 19, [ref]$v, 4)
            [void][NetDoctorNative.Api]::DwmSetWindowAttribute($script:form.Handle, 20, [ref]$v, 4)
        } catch { }
        foreach ($c in $script:form.Controls) { Apply-NativeTheme $c }
    }
}

function Set-Theme([string]$pref) {
    $script:Cfg.Tema = $pref
    Save-Config $script:Cfg
    Set-Pal (Resolve-ThemeName $pref)
    Apply-Theme
}

# ------------------------------------------------------------ hardware e saude dos discos (interface)
function Start-HwInfo {
    if ($script:HwInfoJob -and -not $script:HwInfoJob.Handle.IsCompleted) { return }
    if ($script:HwInfoJob) { Dispose-Bg $script:HwInfoJob }
    $script:txtHw.Text = 'Lendo o hardware...'
    $script:HwInfoJob = Start-Bg $script:HwInfoCode @{ Q = $script:BgQ }
}

function Start-HwLive {
    if ($script:HwLiveJob -and -not $script:HwLiveJob.Handle.IsCompleted -and $script:HwCtl -and $script:HwCtl.Run) { return }
    if ($script:HwLiveJob -and $script:HwLiveJob.Handle.IsCompleted) { Dispose-Bg $script:HwLiveJob }
    $script:HwCtl = [hashtable]::Synchronized(@{ Run = $true })
    $script:HwLiveJob = Start-Bg $script:HwLiveCode @{ Q = $script:BgQ; Ctl = $script:HwCtl }
}

function Stop-HwLive { if ($script:HwCtl) { $script:HwCtl.Run = $false } }

function Update-HwLiveText {
    $m = $script:HwLastLive
    $uso = @()
    if ($m) {
        if ($null -ne $m.CpuLoad) { $uso += ('CPU {0}%' -f $m.CpuLoad) }
        if ($null -ne $m.RamPct) { $uso += ('RAM {0}%' -f $m.RamPct) }
        if ($null -ne $m.GpuLoad) { $uso += ('GPU {0}%' -f $m.GpuLoad) }
    }
    $lines = @()
    if ($uso.Count -gt 0) { $lines += ('Uso agora: ' + ($uso -join '  |  ')) } else { $lines += 'Uso agora: medindo...' }
    $lines += (Format-HwStat 'Temperatura CPU/placa:' $script:HwStats.Cpu)
    $lines += (Format-HwStat 'Temperatura GPU:      ' $script:HwStats.Gpu)
    if ($script:HwStats.Cpu.N -eq 0 -and $script:HwStats.Gpu.N -eq 0 -and $script:HwLastLive) {
        $lines += 'O Windows não expõe sensores de temperatura sem driver. Abra o LibreHardwareMonitor (gratuito) e o NetDoctor passa a mostrar CPU e GPU; placas NVIDIA mostram a GPU sozinhas.'
    }
    $script:lblHwLive.Text = ($lines -join "`r`n")
}

function Copy-HwText {
    try {
        $t = $script:txtPc.Text + "`r`n`r`n" + $script:txtHw.Text + "`r`n`r`n" + $script:lblHwLive.Text
        [System.Windows.Forms.Clipboard]::SetText($t)
        Set-Status 'Informações do PC copiadas.'
    } catch { Set-Status 'Não foi possível copiar.' }
}

function Start-DiskInfo {
    if ($script:DiskJob -and -not $script:DiskJob.Handle.IsCompleted) { return }
    if ($script:DiskJob) { Dispose-Bg $script:DiskJob }
    Set-Status 'Lendo a saúde dos discos...'
    $script:DiskJob = Start-Bg $script:DiskCode @{ Q = $script:BgQ }
}

function Fill-DiskLists {
    $lv = $script:lvDisk
    $lv.BeginUpdate(); $lv.Items.Clear()
    foreach ($r in @($script:DiskRows)) {
        $it = New-Object System.Windows.Forms.ListViewItem([string]$r.Nome)
        foreach ($k in @('Tipo', 'Cap', 'Saude', 'Temp', 'Horas', 'Desgaste', 'Erros', 'Smart', 'Conc')) { [void]$it.SubItems.Add([string]$r[$k]) }
        $it.BackColor = (Get-RowColor ([string]$r.Nivel))
        [void]$lv.Items.Add($it)
    }
    $lv.EndUpdate()
    $lv2 = $script:lvVol
    $lv2.BeginUpdate(); $lv2.Items.Clear()
    foreach ($v in @($script:DiskVols)) {
        $it = New-Object System.Windows.Forms.ListViewItem([string]$v.Letra)
        foreach ($k in @('Nome', 'Sis', 'Tam', 'Livre', 'Usado')) { [void]$it.SubItems.Add([string]$v[$k]) }
        $it.BackColor = (Get-RowColor ([string]$v.Nivel))
        [void]$lv2.Items.Add($it)
    }
    $lv2.EndUpdate()
}

function Copy-DiskText {
    try {
        $o = @()
        foreach ($r in @($script:DiskRows)) { $o += ('{0} | {1} | {2} | {3} | temp {4} | {5} ligado | desgaste {6} | SMART {7} | {8}' -f $r.Nome, $r.Tipo, $r.Cap, $r.Saude, $r.Temp, $r.Horas, $r.Desgaste, $r.Smart, $r.Conc) }
        foreach ($v in @($script:DiskVols)) { $o += ('{0} {1} | {2} | {3} | livre {4} | {5} usado' -f $v.Letra, $v.Nome, $v.Sis, $v.Tam, $v.Livre, $v.Usado) }
        [System.Windows.Forms.Clipboard]::SetText(($o -join "`r`n"))
        Set-Status 'Saúde dos discos copiada.'
    } catch { Set-Status 'Não foi possível copiar.' }
}

function Start-SmartUi {
    if (-not (Confirm-Action ('Abrir os atributos SMART detalhados?' + "`r`n`r`n" + 'Funciona com discos SATA e pede permissão de administrador. É somente leitura; uma janela mostra a tabela.') 'NetDoctor - SMART')) { return }
    $r = Invoke-Elevated $script:SmartScript -NoWait -Visible
    if ($null -eq $r) { Set-Status 'Cancelado: a permissão de administrador não foi concedida.' } else { Set-Status 'Uma janela com os atributos SMART foi aberta.' }
}

# ------------------------------------------------------------ notas, bandeja, alertas, assistente, rota, historico, relatorio
function Show-Scores {
    $sc = $script:LastScores
    if (-not $sc) { return }
    $linhas = @()
    if ($sc.Texto) { $linhas += $sc.Texto } else { $linhas += 'Sem dados suficientes para as notas (ligue o teste de velocidade).' }
    $an = $script:LastAnatel
    if ($an -and @($an.Linhas).Count -gt 0) { $linhas += $an.Linhas[0] }
    $script:lblScores.Text = ($linhas -join "`r`n")
}

# ----- bandeja do sistema
function Show-MainWindow {
    try {
        $script:form.Show()
        $script:form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        $script:form.Activate()
    } catch { }
}

function Exit-App {
    $script:ExitRequested = $true
    $script:form.Close()
}

function Toggle-MonitorTray {
    if ($script:Running) { Stop-Monitor } else { Start-Monitor }
}

function Update-Tray {
    try {
        $texto = 'NetDoctor - parado'
        if ($script:Running) {
            $tot = 0
            foreach ($t in $script:Targets) { $tot += $t.Total }
            $texto = ('NetDoctor - monitorando ({0} testes)' -f $tot)
        }
        $ativo = $false
        foreach ($k in @($script:AlertState.Keys)) { if ($script:AlertState[$k].Ativo) { $ativo = $true } }
        if ($ativo) { $texto = 'NetDoctor - CONEXÃO COM PROBLEMA' }
        if ($texto.Length -gt 62) { $texto = $texto.Substring(0, 62) }
        $script:notify.Text = $texto
        if ($ativo -and $script:trayAlert) { $script:notify.Icon = $script:trayAlert }
        elseif ($script:trayNormal) { $script:notify.Icon = $script:trayNormal }
    } catch { }
}

function Show-MonitorAlert($a) {
    if ($a.Tipo -eq 'problema') {
        $txt = ('{0}: {1}% de problemas (falhas e picos) nos últimos {2} min.' -f $a.Nome, $a.Pct, $a.Janela)
        try { $script:notify.ShowBalloonTip(8000, 'NetDoctor - conexão com problema', $txt, [System.Windows.Forms.ToolTipIcon]::Warning) } catch { }
        try { [System.Media.SystemSounds]::Exclamation.Play() } catch { }
        Write-MonEvent $a.Nome 'problema' $txt
    } else {
        $txt = ('{0}: a conexão normalizou ({1}% de problemas na janela).' -f $a.Nome, $a.Pct)
        try { $script:notify.ShowBalloonTip(5000, 'NetDoctor - conexão normalizada', $txt, [System.Windows.Forms.ToolTipIcon]::Info) } catch { }
        Write-MonEvent $a.Nome 'recuperou' $txt
    }
    Set-Status $txt
}

function Check-Alerts {
    if (-not $script:Running -or -not $script:chkAlert.Checked) { return }
    foreach ($a in @(Get-MonitorAlerts ([double]$script:numAlert.Value) 3)) { Show-MonitorAlert $a }
}

function Get-StartupLinkPath { Join-Path ([Environment]::GetFolderPath('Startup')) 'NetDoctor.lnk' }

function Set-StartupShortcut([bool]$on) {
    $lnk = Get-StartupLinkPath
    if ($on) {
        $sh = New-Object -ComObject WScript.Shell
        $l = $sh.CreateShortcut($lnk)
        $l.TargetPath = (Join-Path $PSScriptRoot 'NetDoctor.bat')
        $l.WorkingDirectory = $PSScriptRoot
        $l.WindowStyle = 7
        $ico = Join-Path $PSScriptRoot 'NetDoctor.ico'
        if (Test-Path $ico) { $l.IconLocation = $ico }
        $l.Description = 'NetDoctor'
        $l.Save()
    } elseif (Test-Path $lnk) { Remove-Item -Path $lnk -Force }
}

# ----- assistente
function Start-Assist([string]$tipo) {
    if ($script:AssistJob -and -not $script:AssistJob.Handle.IsCompleted) { return }
    if ($script:AssistJob) { Dispose-Bg $script:AssistJob }
    [void](Resolve-AutoTargets)
    $tg = @()
    foreach ($t in $script:Targets) {
        if ($t.Role -eq 'destino' -or $t.Role -eq 'controle') { $tg += @{ Nome = [string]$t.Nome; Destino = [string]$t.Destino; Porta = [int]$t.Porta; Role = [string]$t.Role } }
    }
    $script:rtbAssist.Clear(); $script:AssistColored.Clear()
    foreach ($b in $script:btnAssist) { $b.Enabled = $false }
    $script:lblAssistBanner.BackColor = $script:Pal.Info
    $script:lblAssistBanner.Text = 'Testando... isso leva de 30 segundos a 2 minutos.'
    $script:AssistJob = Start-Bg $script:AssistCode @{ Q = $script:BgQ; Lib = $script:NetTestLib; Problema = $tipo; Alvos = $tg; PlanoMbps = (Convert-PlanToMbps ([string]$script:Cfg.Plano)); PingExterno = '1.1.1.1' }
}

# ----- rota por salto
function Start-Route {
    if ($script:RouteJob -and -not $script:RouteJob.Handle.IsCompleted -and $script:RouteCtl -and $script:RouteCtl.Run) { return }
    $dest = $script:txtRouteDest.Text.Trim()
    if ($dest -notmatch '^[A-Za-z0-9][A-Za-z0-9.\-]*$') { Show-Msg 'Informe um endereço válido (exemplo: 1.1.1.1 ou google.com).' 'Warning'; return }
    if ($script:RouteJob -and $script:RouteJob.Handle.IsCompleted) { Dispose-Bg $script:RouteJob }
    $script:RouteCtl = [hashtable]::Synchronized(@{ Run = $true })
    $script:lvRoute.Items.Clear()
    $script:lblRoute.Text = 'Descobrindo a rota...'
    $script:btnRouteStart.Enabled = $false; $script:btnRouteStop.Enabled = $true
    $script:RouteJob = Start-Bg $script:RouteCode @{ Q = $script:BgQ; Ctl = $script:RouteCtl; Destino = $dest; MaxSaltos = 20 }
}

function Stop-Route {
    if ($script:RouteCtl) { $script:RouteCtl.Run = $false }
    if ($script:btnRouteStart) { $script:btnRouteStart.Enabled = $true; $script:btnRouteStop.Enabled = $false }
}

function Show-RouteRows($rows) {
    $lv = $script:lvRoute
    $rows = @($rows)
    $concl = Get-RouteConclusion $rows
    $script:lblRoute.Text = $concl.Texto
    $script:lblRoute.BackColor = $script:Pal.Info
    if ($concl.Nivel -eq 'bad') { $script:lblRoute.BackColor = $script:Pal.RowBad }
    if ($lv.Items.Count -ne $rows.Count) {
        $lv.Items.Clear()
        foreach ($r in $rows) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$r.Ttl)
            for ($k = 0; $k -lt 9; $k++) { [void]$it.SubItems.Add('') }
            [void]$lv.Items.Add($it)
        }
    }
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]; $it = $lv.Items[$i]
        $addr = [string]$r.Addr; if (-not $addr) { $addr = '*' }
        $vals = @($addr, [string]$r.Nome, [string]$r.Sent, ('{0}%' -f $r.Pct), $(if ($null -ne $r.Last) { [string][math]::Round($r.Last, 1) } else { '-' }), $(if ($null -ne $r.Avg) { [string]$r.Avg } else { '-' }), $(if ($null -ne $r.Min) { [string]$r.Min } else { '-' }), $(if ($null -ne $r.Max) { [string]$r.Max } else { '-' }), [string]$r.Jit)
        for ($k = 0; $k -lt 9; $k++) { Set-SubText $it ($k + 1) $vals[$k] }
        $cor = $script:Pal.Surface
        if ($r.Pct -ge 3) { $cor = $script:Pal.RowWarn }
        if ($null -ne $concl.Ttl -and $r.Ttl -ge $concl.Ttl -and $r.Pct -ge 3) { $cor = $script:Pal.RowBad }
        if ($it.BackColor.ToArgb() -ne $cor.ToArgb()) { $it.BackColor = $cor }
    }
}

# ----- historico
function Fill-HistTargets {
    $atual = [string]$script:cmbHistAlvo.SelectedItem
    $script:cmbHistAlvo.Items.Clear()
    [void]$script:cmbHistAlvo.Items.Add('(todos)')
    foreach ($t in $script:Targets) { [void]$script:cmbHistAlvo.Items.Add([string]$t.Nome) }
    $idx = -1
    if ($atual) { $idx = $script:cmbHistAlvo.Items.IndexOf($atual) }
    if ($idx -lt 0) {
        for ($i = 0; $i -lt $script:Targets.Count; $i++) { if ($script:Targets[$i].Role -eq 'controle') { $idx = $i + 1; break } }
    }
    if ($idx -lt 0) { $idx = 0 }
    $script:cmbHistAlvo.SelectedIndex = $idx
}

function Start-HistLoad {
    if ($script:HistJob -and -not $script:HistJob.Handle.IsCompleted) { return }
    if ($script:HistJob) { Dispose-Bg $script:HistJob }
    try { Flush-HistBuckets } catch { }
    $dias = 7
    switch ([int]$script:cmbHistPer.SelectedIndex) { 0 { $dias = 1 } 1 { $dias = 7 } 2 { $dias = 30 } }
    $filtro = ''
    $sel = [string]$script:cmbHistAlvo.SelectedItem
    if ($sel -and $sel -ne '(todos)') { $filtro = $sel.Replace(',', ';') }
    $script:lblHist.Text = 'Lendo o histórico...'
    $script:HistJob = Start-Bg $script:HistCode @{ Q = $script:BgQ; Path = (Get-MonHistPath); Dias = $dias; Filtro = $filtro }
}

function Show-HistSummary {
    $m = $script:HistData
    if (-not $m) { return }
    if ($m.Msg) { $script:lblHist.Text = $m.Msg; return }
    $disp = 100.0
    if ($m.Total -gt 0) { $disp = 100.0 * (1 - $m.Falhas / $m.Total) }
    $prob = 0.0
    if ($m.Total -gt 0) { $prob = 100.0 * ($m.Falhas + $m.Picos) / $m.Total }
    $lat = '-'
    if ($m.OkN -gt 0) { $lat = ('{0} ms' -f [math]::Round($m.Soma / $m.OkN, 1)) }
    $pior = 'sem destaque'; $piorV = 0.0; $piorH = -1
    for ($h = 0; $h -lt 24; $h++) {
        $x = $m.Horas[$h]
        if ($x.T -ge 20) { $v = 100.0 * ($x.F + $x.P) / $x.T; if ($v -gt $piorV) { $piorV = $v; $piorH = $h } }
    }
    if ($piorH -ge 0 -and $piorV -gt 0) { $pior = ('{0:00}h às {1:00}h ({2}% de problemas)' -f $piorH, (($piorH + 1) % 24), [math]::Round($piorV, 1)) }
    $script:lblHist.Text = ('Amostras: {0}   |   Disponibilidade: {1}%   |   Problemas (falhas e picos): {2}%   |   Latência média: {3}' -f $m.Total, [math]::Round($disp, 2), [math]::Round($prob, 1), $lat) + "`r`n" + ('Blocos de 5 min sem nenhuma resposta: {0}   |   Pior horário do dia: {1}' -f $m.Quedas, $pior) + "`r`n" + 'Dados do monitor em blocos de 5 minutos. Deixe o Monitor rodando (de preferência na bandeja) para acumular dias de histórico.'
}

function Draw-Bars($g, $vals, $labels, [int]$x0, [int]$y0, [int]$w, [int]$h, [string]$titulo, [int]$passoRotulo) {
    $p = $script:Pal
    $fonte = New-Object System.Drawing.Font('Segoe UI', [single]8.5)
    $tb = New-Object System.Drawing.SolidBrush($p.Muted)
    $g.DrawString($titulo, $fonte, $tb, $x0, $y0 - 20)
    $n = $vals.Count
    if ($n -eq 0) { $fonte.Dispose(); $tb.Dispose(); return }
    $max = 5.0
    foreach ($v in $vals) { if ($v -gt $max) { $max = $v } }
    $gp = New-Object System.Drawing.Pen($p.Grid)
    $g.DrawLine($gp, $x0, $y0 + $h, $x0 + $w, $y0 + $h)
    $g.DrawLine($gp, $x0, $y0, $x0 + $w, $y0)
    $g.DrawString(('{0}%' -f [math]::Round($max, 0)), $fonte, $tb, [single]($x0 - 34), [single]($y0 - 7))
    $g.DrawString('0%', $fonte, $tb, [single]($x0 - 24), [single]($y0 + $h - 8))
    $largura = [math]::Max(3, [int](($w - 4) / $n))
    for ($i = 0; $i -lt $n; $i++) {
        $alt = [int][math]::Round(($h - 2) * $vals[$i] / $max, 0)
        $cor = $p.Line
        if ($vals[$i] -ge 5) { $cor = $p.Red } elseif ($vals[$i] -ge 1) { $cor = $p.Dash }
        $br = New-Object System.Drawing.SolidBrush($cor)
        $g.FillRectangle($br, $x0 + 2 + $i * $largura, $y0 + $h - $alt, [math]::Max(2, $largura - 2), $alt)
        $br.Dispose()
        if ($passoRotulo -gt 0 -and ($i % $passoRotulo) -eq 0) { $g.DrawString([string]$labels[$i], $fonte, $tb, [single]($x0 + $i * $largura), [single]($y0 + $h + 2)) }
    }
    $gp.Dispose(); $fonte.Dispose(); $tb.Dispose()
}

function Draw-Hist($g, [int]$w, [int]$h) {
    $g.Clear($script:Pal.Surface)
    $m = $script:HistData
    $fonte = New-Object System.Drawing.Font('Segoe UI', [single]9.5)
    $mb = New-Object System.Drawing.SolidBrush($script:Pal.Muted)
    if (-not $m -or $m.Total -le 0) {
        $g.DrawString('Sem dados ainda. Inicie o monitor e deixe rodando; o histórico se forma em blocos de 5 minutos.', $fonte, $mb, 14, 14)
        $fonte.Dispose(); $mb.Dispose(); return
    }
    $horas = @(); $rotH = @()
    for ($i = 0; $i -lt 24; $i++) {
        $x = $m.Horas[$i]; $v = 0.0
        if ($x.T -gt 0) { $v = 100.0 * ($x.F + $x.P) / $x.T }
        $horas += $v; $rotH += ('{0:00}h' -f $i)
    }
    $dias = @(); $rotD = @()
    foreach ($d in $m.Dias) {
        $v = 0.0
        if ($d.T -gt 0) { $v = 100.0 * ($d.F + $d.P) / $d.T }
        $dias += $v; $rotD += ([string]$d.D).Substring(5)
    }
    $meio = [int]($w / 2)
    $alt = [math]::Max(40, $h - 60)
    Draw-Bars $g $horas $rotH 44 30 ($meio - 70) $alt 'Problemas por hora do dia (%)' 3
    $passo = 1; if ($dias.Count -gt 10) { $passo = [int][math]::Ceiling($dias.Count / 8) }
    Draw-Bars $g $dias $rotD ($meio + 44) 30 ($w - $meio - 70) $alt 'Problemas por dia (%)' $passo
    $fonte.Dispose(); $mb.Dispose()
}

# ----- relatorio HTML
function Start-Report {
    if ($script:ReportJob -and -not $script:ReportJob.Handle.IsCompleted) { return }
    if ($script:ReportJob) { Dispose-Bg $script:ReportJob }
    try { Flush-HistBuckets } catch { }
    $al = @()
    foreach ($t in $script:Targets) {
        $mm = Get-Avg $t; $mtxt = '-'; if ($null -ne $mm) { $mtxt = [string]$mm }
        $al += @{ Nome = [string]$t.Nome; Destino = (Get-Endereco $t); Total = [int]$t.Total; Falhas = [int]$t.Falhas; Picos = [int]$t.Picos; Media = $mtxt; Pct = [double](Get-Pct $t) }
    }
    $pm = Convert-PlanToMbps ([string]$script:Cfg.Plano)
    $an = Get-AnatelSummary $pm
    $sc = ''
    if ($script:LastScores) { $sc = [string]$script:LastScores.Texto }
    $dados = @{
        DataHora = (Get-Date -Format 'dd/MM/yyyy HH:mm'); Provedor = [string]$script:txtProv.Text; Plano = [string]$script:txtPlano.Text
        Scores = $sc; Anatel = @($an.Linhas); Alvos = $al; Achados = @($script:DiagFindings.ToArray())
        Rede = [string]$script:txtPc.Text; Suporte = [string]$script:txtSupport.Text
    }
    $saida = Join-Path (Get-ReportDir) ('relatorio_conexao_{0}.html' -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
    Set-Status 'Gerando o relatório...'
    $script:ReportJob = Start-Bg $script:ReportCode @{ Q = $script:BgQ; Dados = $dados; Saida = $saida; HistPath = (Get-MonHistPath); SpeedPath = (Get-SpeedHistPath); EvPath = (Get-EventsPath) }
}

# ------------------------------------------------------------ atualizacoes (interface)
function Show-UpdatesTab { try { $script:tabs.SelectedTab = $script:pgUpd } catch { } }

function Update-VersionLabel {
    $p = $script:Pal
    $v = 'v' + $script:AppVersion
    $f = $script:lblVersion.Font
    if ($script:UpdChecking) { $script:lblVersion.Text = $v + '  ·  verificando atualizações...'; $script:lblVersion.ForeColor = $p.Muted }
    elseif ($script:UpdAvailable -and $script:UpdLatest) {
        $script:lblVersion.Text = ('{0}  ·  atualização disponível: {1}  (clique)' -f $v, $script:UpdLatest.Tag)
        $script:lblVersion.ForeColor = $p.Accent
    } else {
        $t = $v; if ($script:UpdOk) { $t += '  ·  atualizado' }
        $script:lblVersion.Text = $t; $script:lblVersion.ForeColor = $p.Muted
    }
}

function Render-UpdateNotes {
    $script:UpdLines.Clear()
    $add = { param($t, $c) [void]$script:UpdLines.Add(@{ T = $t; C = $c }) }
    & $add ('Versão instalada: v' + $script:AppVersion) 'Gray'
    if ($script:UpdAvailable -and $script:UpdLatest) { & $add ('Nova versão disponível: {0} ({1})' -f $script:UpdLatest.Tag, $script:UpdLatest.Data) 'Green' }
    elseif ($script:UpdOk -and @($script:UpdReleases).Count -gt 0) { & $add 'Você está na versão mais recente.' 'Green' }
    if ($script:UpdMsg) { & $add $script:UpdMsg 'Yellow' }
    $cur = ConvertTo-VersionObj $script:AppVersion
    foreach ($rl in @($script:UpdReleases)) {
        & $add '' 'Gray'
        $marca = ''
        if ($rl.Ver -and $cur -and $rl.Ver -gt $cur) { $marca = '  -  NOVA' }
        elseif ($rl.Ver -and $cur -and $rl.Ver -eq $cur) { $marca = '  -  instalada' }
        $titulo = ('=== {0}  ({1}){2} ===' -f $rl.Tag, $rl.Data, $marca)
        & $add $titulo 'Cyan'
        foreach ($l in @(Convert-NotesToLines $rl.Body)) { & $add $l.T $l.C }
    }
    $script:rtbUpd.Clear()
    foreach ($d in $script:UpdLines) { Add-RtbLine $script:rtbUpd $d.T $d.C }
    if ($script:rtbUpd.TextLength -gt 0) { $script:rtbUpd.SelectionStart = 0; $script:rtbUpd.ScrollToCaret() }
}

function Update-UpdateButtons {
    $pode = [bool]($script:UpdAvailable -and $script:UpdLatest)
    $script:btnUpdInstall.Enabled = $pode
    if ($script:UpdChecking) { $script:lblUpdStatus.Text = 'Verificando no GitHub...' }
    elseif ($pode) { $script:lblUpdStatus.Text = ('Atualização disponível: {0} (você tem v{1}). Clique em "Atualizar agora".' -f $script:UpdLatest.Tag, $script:AppVersion) }
    elseif ($script:UpdMsg) { $script:lblUpdStatus.Text = $script:UpdMsg }
    elseif ($script:UpdOk) { $script:lblUpdStatus.Text = ('Você está na versão mais recente (v{0}). Última verificação: {1}.' -f $script:AppVersion, $script:UpdLastCheck.ToString('HH:mm')) }
    else { $script:lblUpdStatus.Text = 'Ainda não verificado.' }
}

function Start-UpdateCheck([switch]$Manual) {
    if ($script:UpdCheckJob -and -not $script:UpdCheckJob.Handle.IsCompleted) { return }
    if ($script:UpdCheckJob) { Dispose-Bg $script:UpdCheckJob }
    $script:UpdManual = [bool]$Manual
    $script:UpdChecking = $true
    $script:UpdLastCheck = Get-Date
    Update-VersionLabel; Update-UpdateButtons
    $url = ('https://api.github.com/repos/{0}/{1}/releases?per_page=6' -f $script:RepoOwner, $script:RepoName)
    $script:UpdCheckJob = Start-Bg $script:UpdCheckCode @{ Q = $script:BgQ; Url = $url }
}

function Open-UpdatePage {
    $u = ('https://github.com/{0}/{1}/releases' -f $script:RepoOwner, $script:RepoName)
    if ($script:UpdLatest -and ([string]$script:UpdLatest.Url) -like 'https://github.com/*') { $u = [string]$script:UpdLatest.Url }
    try { Start-Process $u } catch { Set-Status 'Não foi possível abrir o navegador.' }
}

function Start-UpdateInstall {
    $rel = $script:UpdLatest
    if (-not $rel) { return }
    if (-not $rel.ZipUrl -or -not $rel.Sha) {
        $motivo = 'Esta versão não tem um arquivo .zip anexado.'
        if ($rel.ZipUrl) { $motivo = 'Esta versão não informa o código SHA256 do pacote, então não posso conferir a integridade.' }
        Show-Msg ($motivo + "`r`n`r`n" + 'Vou abrir a página da versão para você baixar manualmente.') 'Warning'
        Open-UpdatePage; return
    }
    $q = ('Atualizar para a versão {0}?' -f $rel.Tag) + "`r`n`r`n" + 'O NetDoctor baixa o pacote do GitHub, confere o SHA256 publicado, guarda um backup dos arquivos atuais e depois pede para reiniciar. Seus dados e configurações são mantidos.'
    if (-not (Confirm-Action $q 'NetDoctor - atualizar')) { return }
    $dest = Join-Path ([System.IO.Path]::GetTempPath()) 'NetDoctor-update.zip'
    try { if (Test-Path $dest) { Remove-Item $dest -Force } } catch { }
    $script:UpdExpectedSha = [string]$rel.Sha
    $script:btnUpdInstall.Enabled = $false
    $script:lblUpdStatus.Text = 'Baixando a atualização...'
    $script:UpdDlJob = Start-Bg $script:UpdDownloadCode @{ Q = $script:BgQ; ZipUrl = [string]$rel.ZipUrl; Dest = $dest }
}

function Finish-UpdateInstall($m) {
    if (-not $m.Ok) { $script:lblUpdStatus.Text = 'Falha no download: ' + $m.Msg; Update-UpdateButtons; return }
    if ($m.Sha -ne $script:UpdExpectedSha) {
        try { Remove-Item $m.Path -Force } catch { }
        $script:lblUpdStatus.Text = 'O arquivo baixado NÃO confere com o SHA256 publicado. A atualização foi cancelada.'
        Show-Msg 'O arquivo baixado não confere com o SHA256 publicado na versão. Por segurança, nada foi instalado.' 'Warning'
        Update-UpdateButtons; return
    }
    $script:lblUpdStatus.Text = 'Conferido. Instalando...'
    $r = Install-Update $m.Path
    try { Remove-Item $m.Path -Force } catch { }
    if (-not $r.Ok) {
        $script:lblUpdStatus.Text = 'A instalação falhou: ' + $r.Msg
        Show-Msg ('A instalação falhou.' + "`r`n`r`n" + $r.Msg) 'Warning'
        Update-UpdateButtons; return
    }
    $script:lblUpdStatus.Text = 'Atualização instalada. Reinicie o NetDoctor para usar a nova versão.'
    if (Confirm-Action ('Atualização instalada.' + "`r`n`r`n" + 'Um backup da versão anterior foi guardado em:' + "`r`n" + $r.Backup + "`r`n`r`n" + 'Reiniciar o NetDoctor agora?') 'NetDoctor - atualizado') {
        try { Start-Process -FilePath (Join-Path $PSScriptRoot 'NetDoctor.bat') -WorkingDirectory $PSScriptRoot } catch { }
        Exit-App
    }
}

# ------------------------------------------------------------ wi-fi, suporte e idioma (interface)
function Start-Wifi {
    if ($script:WifiJob -and -not $script:WifiJob.Handle.IsCompleted) { return }
    if ($script:WifiJob) { Dispose-Bg $script:WifiJob }
    $script:lblWifi.Text = 'Lendo o Wi-Fi...'
    $script:WifiJob = Start-Bg $script:WifiCode @{ Q = $script:BgQ }
}

function Fill-WifiLists {
    $m = $script:WifiData
    $lv = $script:lvWifi; $lc = $script:lvWifiCh
    $lv.BeginUpdate(); $lv.Items.Clear(); $lc.BeginUpdate(); $lc.Items.Clear()
    if ($m -and $m.Ok) {
        $nets = @($m.Nets | Sort-Object { -1 * [int]$_.Signal })
        foreach ($n in $nets) {
            $nome = [string]$n.Ssid; if (-not $nome) { $nome = '(oculta)' }
            $it = New-Object System.Windows.Forms.ListViewItem($nome)
            [void]$it.SubItems.Add(('{0}%' -f $n.Signal)); [void]$it.SubItems.Add([string]$n.Channel)
            [void]$it.SubItems.Add((Get-WifiBand $n.Channel)); [void]$it.SubItems.Add([string]$n.Radio)
            $minha = ''
            if ($m.Own -and $m.Own.Bssid -and [string]$n.Bssid -eq [string]$m.Own.Bssid) { $minha = '●'; $it.BackColor = $script:Pal.RowOk }
            [void]$it.SubItems.Add($minha)
            [void]$lv.Items.Add($it)
        }
        $an = Get-WifiAnalysis $m.Own $m.Nets
        foreach ($c in $an.Canais) {
            $it = New-Object System.Windows.Forms.ListViewItem([string]$c.Canal)
            [void]$it.SubItems.Add([string]$c.Faixa); [void]$it.SubItems.Add([string]$c.Redes)
            $mx = '-'; if ($c.Max -gt 0) { $mx = ('{0}%' -f $c.Max) }
            [void]$it.SubItems.Add($mx); [void]$it.SubItems.Add([string]$c.Nivel); [void]$it.SubItems.Add([string]$c.Obs)
            if ($c.Nivel -eq 'alta') { $it.BackColor = $script:Pal.RowBad } elseif ($c.Nivel -eq 'média') { $it.BackColor = $script:Pal.RowWarn }
            [void]$lc.Items.Add($it)
        }
    }
    $lv.EndUpdate(); $lc.EndUpdate()
}

function Show-WifiSummary {
    $m = $script:WifiData
    if (-not $m) { return }
    if (-not $m.Ok) { $script:lblWifi.Text = $m.Msg; $script:lblWifi.BackColor = $script:Pal.Info; return }
    $an = Get-WifiAnalysis $m.Own $m.Nets
    $linhas = @()
    $o = $m.Own
    if ($o -and $o.Conectado) {
        $rx = '-'; if ($null -ne $o.Rx) { $rx = ('{0} Mbps' -f $o.Rx) }
        $tx = '-'; if ($null -ne $o.Tx) { $tx = ('{0} Mbps' -f $o.Tx) }
        $linhas += ('Rede: {0}   |   canal {1} ({2})   |   {3}   |   segurança: {4}   |   recepção {5} / envio {6}' -f $o.Ssid, $o.Channel, (Get-WifiBand $o.Channel), $o.Radio, $o.Auth, $rx, $tx)
    }
    $linhas += $an.Linhas
    if ($m.Msg) { $linhas += $m.Msg }
    $script:lblWifi.Text = ($linhas -join "`r`n")
    $script:lblWifi.BackColor = (Get-RowColor $an.Nivel)
    if ($an.Nivel -eq 'ok') { $script:lblWifi.BackColor = $script:Pal.Info }
}

# ----- suporte
function Render-Faq {
    $script:rtbFaq.Clear()
    foreach ($l in @(Get-FaqLines $script:LangCode)) { Add-RtbLine $script:rtbFaq $l.T $l.C }
    if ($script:rtbFaq.TextLength -gt 0) { $script:rtbFaq.SelectionStart = 0; $script:rtbFaq.ScrollToCaret() }
}

function Update-SupportInfo {
    $txt = (T 'Precisa de ajuda? Veja as perguntas frequentes ou envie uma mensagem.')
    if ($script:SupportEmail) { $txt += "`r`n" + ((T 'E-mail de contato:') + ' ' + $script:SupportEmail) }
    else { $txt += "`r`n" + (T 'O e-mail de contato ainda não foi configurado pelo desenvolvedor.') }
    $script:lblSupportHead.Text = $txt
    $script:btnSupCopy.Enabled = [bool]$script:SupportEmail
    $script:btnSupWrite.Enabled = [bool]$script:SupportEmail
    $script:btnFbSend.Enabled = [bool]$script:FeedbackUrl
    if ($script:FeedbackUrl) { $script:lblFbStatus.Text = (T 'Escreva sua mensagem e clique em Enviar.') }
    else { $script:lblFbStatus.Text = (T 'O envio direto ainda não foi configurado. Use "Abrir no meu e-mail".') }
}

function Get-FeedbackType { @('sugestao', 'bug', 'duvida', 'elogio')[[math]::Max(0, [int]$script:cmbFbTipo.SelectedIndex)] }

function Start-FeedbackSend {
    $msg = $script:txtFbMsg.Text.Trim()
    if ($msg.Length -lt 10) { $script:lblFbStatus.Text = (T 'Escreva uma mensagem com pelo menos 10 caracteres.'); return }
    if ($msg.Length -gt 3000) { $msg = $msg.Substring(0, 3000) }
    $contato = $script:txtFbMail.Text.Trim()
    if ($contato -and $contato -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $script:lblFbStatus.Text = (T 'O e-mail informado não parece válido. Corrija ou deixe em branco.'); return }
    if (((Get-Date) - $script:FbLast).TotalSeconds -lt 60) { $script:lblFbStatus.Text = (T 'Aguarde um minuto para enviar outra mensagem.'); return }
    if ($script:FbJob -and -not $script:FbJob.Handle.IsCompleted) { return }
    if ($script:FbJob) { Dispose-Bg $script:FbJob }
    $tec = ''; if ($script:chkFbTec.Checked) { $tec = Get-TechInfoText }
    $payload = @{ tipo = (Get-FeedbackType); mensagem = $msg; contato = $contato; versao = $script:AppVersion; idioma = $script:LangCode; id = (Get-InstallId); tecnico = $tec }
    $json = $payload | ConvertTo-Json -Compress
    $script:FbLast = Get-Date
    $script:btnFbSend.Enabled = $false
    $script:lblFbStatus.Text = (T 'Enviando...')
    $script:FbJob = Start-Bg $script:FeedbackCode @{ Q = $script:BgQ; Url = $script:FeedbackUrl; Json = $json }
}

function Open-FeedbackMail {
    if (-not $script:SupportEmail) { Show-Msg 'O e-mail de contato ainda não foi configurado pelo desenvolvedor.'; return }
    $corpo = $script:txtFbMsg.Text
    if ($script:chkFbTec.Checked) { $corpo += "`r`n`r`n" + (Get-TechInfoText) }
    try { Start-Process (New-MailtoLink $script:SupportEmail ('[NetDoctor] ' + (Get-FeedbackType) + ' - v' + $script:AppVersion) $corpo) } catch { Set-Status 'Não foi possível abrir o programa de e-mail.' }
}

function Create-SupportPackage {
    $q = 'Criar o pacote de suporte?' + "`r`n`r`n" + 'Ele reúne em um zip: informações do programa e do Windows, o log de erros, a configuração e os históricos de velocidade e do monitor. Nome de usuário e nome do computador são removidos dos textos. Nada é enviado: você decide se e para quem mandar o arquivo.'
    if (-not (Confirm-Action $q 'NetDoctor - pacote de suporte')) { return }
    $r = New-SupportPackage
    if ($r.Ok) {
        Set-Status 'Pacote de suporte criado.'
        try { Start-Process explorer.exe ('/select,"' + $r.Path + '"') } catch { }
    } else { Set-Status 'Não foi possível criar o pacote de suporte.'; Show-Msg ('Não foi possível criar o pacote de suporte.' + "`r`n`r`n" + $r.Msg) 'Warning' }
}

# ----- idioma
function Set-Language([string]$pref) {
    $script:Cfg.Idioma = $pref
    try { Save-Config $script:Cfg } catch { }
    Apply-Language
}

function Apply-Language {
    $script:LangCode = Resolve-LangCode ([string]$script:Cfg.Idioma)
    foreach ($c in $script:form.Controls) { Translate-Control $c }
    try { Translate-Combo $script:cmbTheme 'tema' } catch { }
    try { $script:sub.Text = (T 'monitor, diagnóstico e ferramentas de DNS') } catch { }
    try { Render-Faq; Update-SupportInfo } catch { }
    try { $script:tabs.Invalidate() } catch { }
}

function Handle-Bg($m) {
    switch ($m.Kind) {
        'diag-line' { Add-RtbLine $script:rtbDiag $m.Text $m.Color; [void]$script:DiagLines.Add($m.Text); [void]$script:DiagColored.Add(@{ T = $m.Text; C = $m.Color }) }
        'diag-find' { [void]$script:DiagFindings.Add($m.Text) }
        'diag-meta' { $script:DiagMeta[$m.Key] = $m.Value }
        'diag-prog' { $script:lblDiag.Text = $m.Text }
        'diag-done' {
            $path = Join-Path (Get-ReportDir) ('relatorio_{0}.txt' -f (Get-Date -Format 'yyyy-MM-dd_HHmm'))
            try { [System.IO.File]::WriteAllLines($path, [string[]]$script:DiagLines.ToArray(), (New-Object System.Text.UTF8Encoding($true))) } catch { Log-Error $_ }
            $script:lblDiag.Text = 'Pronto. Relatório salvo em ' + $path
            $script:btnDiag.Enabled = $true
            try {
                $pm = Convert-PlanToMbps ([string]$script:Cfg.Plano)
                if ($script:DiagMeta.ContainsKey('Down') -and [double]$script:DiagMeta['Down'] -gt 0) { Add-SpeedHistory $script:DiagMeta $pm }
                $script:LastScores = Get-QualityScores $script:DiagMeta ([string]$script:Cfg.Plano)
                $script:LastAnatel = Get-AnatelSummary $pm
                Show-Scores
            } catch { Log-Error $_ }
        }
        'scan-prog' { $script:lblScan.Text = $m.Text }
        'scan-dev' {
            $it = New-Object System.Windows.Forms.ListViewItem($m.Ip)
            [void]$it.SubItems.Add($m.Mac); [void]$it.SubItems.Add($m.Nome); [void]$it.SubItems.Add($m.Nota)
            [void]$script:lvNet.Items.Add($it)
        }
        'scan-done' {
            $script:btnScan.Enabled = $true
            $script:lblScan.Text = ('{0} aparelho(s) encontrado(s). {1}' -f $m.Count, $m.Msg)
        }
        'net-info' {
            $i = $m.Info
            $antes = $script:DnsSig
            $script:LastInfo = $i; $script:LastInfoTime = Get-Date
            Apply-NetInfo $i
            Show-PcInfo $i
            Fill-Adapters $m.Adapters ([int]$i.IfIndex)
            $novo = ($i.Dns -join ',')
            $script:NetSig = Get-NetSigLite
            $script:DnsSig = $novo
            if ($m.Why -eq 'change') {
                if ($antes -and $antes -ne $novo) {
                    Notify-DnsChanged
                    $msg = ('O DNS mudou: {0} → {1}.' -f $antes, $(if ($novo) { $novo } else { '(nenhum)' }))
                } else { $msg = 'A rede mudou: roteador e DNS foram detectados de novo.' }
                if ($script:Running) { $msg += ' Pare e inicie o monitor para medir a nova rede.' }
                Set-Status $msg
            }
        }
        'dns-info' {
            $script:DnsCache = @{ IfIndex = [int]$m.IfIndex; Servers = @($m.Servers); V6 = @($m.V6); Modo = [string]$m.Modo }
            if ([int]$m.IfIndex -eq (Get-SelectedIfIndex)) { Set-DnsInfoText }
        }
        'wifi-info' { $script:WifiData = $m; Fill-WifiLists; Show-WifiSummary }
        'fb-done' {
            $script:btnFbSend.Enabled = [bool]$script:FeedbackUrl
            if ($m.Ok) { $script:txtFbMsg.Clear(); $script:lblFbStatus.Text = (T 'Mensagem enviada. Obrigado!') }
            else { $script:FbLast = [datetime]::MinValue; $script:lblFbStatus.Text = ((T 'Não foi possível enviar: ') + [string]$m.Msg + ' ' + (T 'Você pode usar "Abrir no meu e-mail".')) }
        }
        'upd-info' {
            $script:UpdChecking = $false
            $script:UpdReleases = @($m.Releases); $script:UpdMsg = [string]$m.Msg; $script:UpdOk = [bool]$m.Ok
            $script:UpdLatest = $null; $script:UpdAvailable = $false
            $cur = ConvertTo-VersionObj $script:AppVersion
            foreach ($rl in $script:UpdReleases) {
                $v = ConvertTo-VersionObj $rl.Tag
                if ($null -eq $v) { continue }
                $rl['Ver'] = $v
                if ($null -eq $script:UpdLatest -or $v -gt $script:UpdLatest.Ver) { $script:UpdLatest = $rl }
            }
            if ($script:UpdLatest -and $cur -and $script:UpdLatest.Ver -gt $cur) { $script:UpdAvailable = $true }
            if (-not $m.Ok) { $script:UpdLastCheck = (Get-Date).AddMinutes(-330) }
            Render-UpdateNotes; Update-VersionLabel; Update-UpdateButtons
            if ($script:UpdAvailable -and $script:UpdNotified -ne $script:UpdLatest.Tag) {
                $script:UpdNotified = $script:UpdLatest.Tag
                try { $script:notify.ShowBalloonTip(8000, 'NetDoctor - atualização disponível', ('A versão {0} está disponível. Abra a aba Atualizações.' -f $script:UpdLatest.Tag), [System.Windows.Forms.ToolTipIcon]::Info) } catch { }
            }
            if ($script:UpdManual) {
                if (-not $m.Ok) { Set-Status $m.Msg } elseif (-not $script:UpdAvailable) { Set-Status 'Você já está na versão mais recente.' }
            }
        }
        'upd-prog' { $script:lblUpdStatus.Text = ('Baixando a atualização... {0}% ({1} MB)' -f $m.Pct, [math]::Round($m.Bytes / 1MB, 1)) }
        'upd-downloaded' { Finish-UpdateInstall $m }
        'assist-line' { Add-RtbLine $script:rtbAssist $m.Text $m.Color; [void]$script:AssistColored.Add(@{ T = $m.Text; C = $m.Color }) }
        'assist-prog' { $script:lblAssistBanner.Text = $m.Text }
        'assist-done' {
            foreach ($b in $script:btnAssist) { $b.Enabled = $true }
            $txt = 'Sem problemas encontrados nesta rodada. Veja os detalhes abaixo.'
            $cor = Get-RowColor 'ok'
            if ($m.Nivel -eq 'warn') { $txt = 'Encontrei pontos de atenção. Veja o que fazer abaixo.'; $cor = Get-RowColor 'warn' }
            if ($m.Nivel -eq 'bad') { $txt = 'Encontrei um problema. Veja o que fazer abaixo.'; $cor = Get-RowColor 'bad' }
            $script:lblAssistBanner.Text = $txt; $script:lblAssistBanner.BackColor = $cor
        }
        'route-prog' { $script:lblRoute.Text = $m.Text }
        'route-hops' { if ($script:RouteCtl -and $script:RouteCtl.Run) { Show-RouteRows $m.Rows } }
        'route-stopped' { $script:btnRouteStart.Enabled = $true; $script:btnRouteStop.Enabled = $false }
        'hist-done' { $script:HistData = $m; Show-HistSummary; $script:histPanel.Invalidate() }
        'report-done' {
            if ($m.Ok) { Set-Status ('Relatório salvo em ' + $m.Path); try { Start-Process $m.Path } catch { } }
            else { Set-Status ('Não foi possível gerar o relatório: ' + $m.Msg) }
        }
        'hw-info' { $script:txtHw.Text = [string]$m.Text }
        'hw-live' {
            if ($script:HwCtl -and $script:HwCtl.Run) {
                $script:HwLastLive = $m
                Add-HwStat $script:HwStats.Cpu $m.Cpu $m.CpuSrc
                Add-HwStat $script:HwStats.Gpu $m.Gpu $m.GpuSrc
                Update-HwLiveText
            }
        }
        'disk-info' {
            $script:DiskRows = @($m.Rows); $script:DiskVols = @($m.Vols); $script:DiskSmart = [bool]$m.SmartAcesso
            Fill-DiskLists
            $n = 'Os dados vêm do próprio Windows (saúde, contadores de confiabilidade e SMART básico). "-" significa que o disco ou o driver não informa. Isto não substitui backup: um disco pode falhar sem avisar.'
            if (-not $script:DiskSmart) { $n += ' A previsão SMART ("sem acesso") precisa de administrador: use o botão SMART detalhado.' }
            $script:lblDisk.Text = $n
            Set-Status 'Saúde dos discos atualizada.'
        }
        'game-states' {
            foreach ($k in @($m.States.Keys)) { $script:GameStates[[string]$k] = [string]$m.States[$k] }
            $script:IsLaptop = [bool]$m.Laptop
            Fill-GameList
        }
        'dns-prog' { $script:lblDnsProg.Text = $m.Text }
        'dns-row' {
            if ($m.Idx -ge 0 -and $m.Idx -lt $script:DnsItems.Count) {
                $d = $script:DnsItems[$m.Idx]
                $d.Media = $m.Media; $d.Falhas = $m.Falhas; $d.Ping = $m.Ping; $d.Testado = $true
                Fill-DnsList
            }
        }
        'dns-done' {
            $ord = @($script:DnsItems | Sort-Object { if ($null -eq $_.Media) { 999999 } else { [double]$_.Media } }, { if ($null -eq $_.Ping) { 999999 } else { [double]$_.Ping } })
            $novo = New-Object System.Collections.ArrayList
            foreach ($x in $ord) { [void]$novo.Add($x) }
            $script:DnsItems = $novo
            Fill-DnsList
            $script:btnDnsTest.Enabled = $true
            $top = $ord | Where-Object { $null -ne $_.Media } | Select-Object -First 1
            if ($top) { $script:lblDnsProg.Text = ('Pronto. Mais rápido neste teste: {0} ({1} ms). Desempate pelo ping. Resultados variam com a hora e a sua rede.' -f $top.Nome, (Fmt $top.Media)) }
            else { $script:lblDnsProg.Text = 'Nenhum DNS respondeu. Confira se há internet (alguns provedores bloqueiam consultas DNS externas).' }
            if ($script:AutoApplyAfterTest) { $script:AutoApplyAfterTest = $false; Apply-DnsFastestNow }
        }
        'pub-done' {
            if ($m.Org) {
                $script:txtProv.Text = $m.Org
                Set-Status ('Provedor detectado: {0} (IP público {1}). Confira se está certo antes de gerar o texto.' -f $m.Org, $m.Ip)
            } else { Set-Status $m.Msg }
        }
        'snap-done' {
            $script:btnSnap.Enabled = $true
            Set-Status ('Configuração salva em ' + $m.Path + ' ' + $m.Msg)
            [void][System.Windows.Forms.MessageBox]::Show('Configuração salva em:' + "`r`n" + $m.Path, 'NetDoctor')
        }
    }
}

function Drain-All {
    $item = $null; $dirty = $false
    while ($script:Q.TryDequeue([ref]$item)) {
        if ($item.Idx -ge 0 -and $item.Idx -lt $script:Targets.Count) {
            [void](Apply-Sample $script:Targets[$item.Idx] $item)
            $dirty = $true
        }
    }
    if ($dirty) { Refresh-List; $script:chart.Invalidate(); Update-Verdict }
    $m = $null
    while ($script:BgQ.TryDequeue([ref]$m)) { Handle-Bg $m }
    if ($script:DnsInfoPending -and (-not $script:DnsInfoJob -or $script:DnsInfoJob.Handle.IsCompleted)) { $script:DnsInfoPending = $false; Update-DnsInfo }
    if ($script:GameDirty -and (-not $script:GameJob -or $script:GameJob.Handle.IsCompleted)) { $script:GameDirty = $false; Start-GameStates }
    $script:AlertTick++
    if ($script:AlertTick -ge 40) {
        $script:AlertTick = 0
        try { Check-Alerts; Update-Tray } catch { Log-Error $_ }
        try { if ($script:chkWifiAuto.Checked -and (Get-TabKey $script:tabs.SelectedTab) -eq 'Wi-Fi') { Start-Wifi } } catch { Log-Error $_ }
        try {
            if ([bool]$script:Cfg.AutoUpdate -and -not $script:UpdChecking -and (((Get-Date) - $script:UpdLastCheck).TotalHours -ge 6)) { Start-UpdateCheck }
        } catch { Log-Error $_ }
    }
    $script:NetTick++
    if ($script:NetTick -ge 16) { $script:NetTick = 0; Check-NetChange }
    for ($i = $script:Retiring.Count - 1; $i -ge 0; $i--) {
        if ($script:Retiring[$i].Handle.IsCompleted) { Dispose-Bg $script:Retiring[$i]; $script:Retiring.RemoveAt($i) }
    }
}

# ------------------------------------------------------------ montagem da janela
Set-Pal (Resolve-ThemeName ([string]$script:Cfg.Tema))
$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = 'NetDoctor'
$script:form.StartPosition = 'CenterScreen'
$script:form.ClientSize = New-Object System.Drawing.Size(1120, 720)
$script:form.MinimumSize = New-Object System.Drawing.Size(900, 620)
$script:form.Font = New-Object System.Drawing.Font('Segoe UI', [single]9.5)
$icoPath = Join-Path $PSScriptRoot 'NetDoctor.ico'
if (Test-Path $icoPath) { try { $script:form.Icon = New-Object System.Drawing.Icon($icoPath) } catch { Log-Error $_ } }

$root = New-Tlp 3
Add-Row $root 'abs' 56; Add-Row $root 'pct' 100; Add-Row $root 'abs' 26
$script:form.Controls.Add($root)

# cabecalho
$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Fill'; $header.Tag = 'keep'; $header.BackColor = [System.Drawing.Color]::FromArgb(30, 41, 59)
$script:header = $header
$title = New-Object System.Windows.Forms.Label
$title.Text = 'NetDoctor'; $title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', [single]16)
$title.AutoSize = $true; $title.Left = 14; $title.Top = 8
$sub = New-Object System.Windows.Forms.Label
$sub.Text = 'monitor, diagnóstico e ferramentas de DNS'; $sub.ForeColor = [System.Drawing.Color]::FromArgb(180, 190, 205)
$sub.AutoSize = $true; $sub.Left = 140; $sub.Top = 18
$script:lblChip = New-Object System.Windows.Forms.Label
$script:lblChip.Text = '○ parado'; $script:lblChip.ForeColor = [System.Drawing.Color]::White
$script:lblChip.AutoSize = $true; $script:lblChip.Anchor = 'Top,Right'; $script:lblChip.Left = 920; $script:lblChip.Top = 18
$script:sub = $sub
$header.Controls.Add($title); $header.Controls.Add($sub); $header.Controls.Add($script:lblChip)
$script:cmbTheme = New-Object System.Windows.Forms.ComboBox
$script:cmbTheme.DropDownStyle = 'DropDownList'; $script:cmbTheme.FlatStyle = 'Flat'; $script:cmbTheme.Width = 140; $script:cmbTheme.Top = 15
$script:cmbTheme.BackColor = [System.Drawing.Color]::FromArgb(45, 58, 78); $script:cmbTheme.ForeColor = [System.Drawing.Color]::White
[void]$script:cmbTheme.Items.Add('Tema: automático'); [void]$script:cmbTheme.Items.Add('Tema: claro'); [void]$script:cmbTheme.Items.Add('Tema: escuro')
$idxTema = 0; if ([string]$script:Cfg.Tema -eq 'claro') { $idxTema = 1 } elseif ([string]$script:Cfg.Tema -eq 'escuro') { $idxTema = 2 }
$script:cmbTheme.SelectedIndex = $idxTema
$script:cmbTheme.Left = 760
$script:cmbTheme.Add_SelectedIndexChanged({
    try { if ($script:Translating -or $script:cmbTheme.SelectedIndex -lt 0) { return }; Set-Theme (@('auto', 'claro', 'escuro')[$script:cmbTheme.SelectedIndex]) } catch { Log-Error $_ }
})
$header.Controls.Add($script:cmbTheme)
$script:cmbLang = New-Object System.Windows.Forms.ComboBox
$script:cmbLang.DropDownStyle = 'DropDownList'; $script:cmbLang.FlatStyle = 'Flat'; $script:cmbLang.Width = 110; $script:cmbLang.Top = 15
$script:cmbLang.BackColor = [System.Drawing.Color]::FromArgb(45, 58, 78); $script:cmbLang.ForeColor = [System.Drawing.Color]::White
foreach ($li in @('Auto', 'Português', 'English', 'Español')) { [void]$script:cmbLang.Items.Add($li) }
$idxLang = 0
switch ([string]$script:Cfg.Idioma) { 'pt' { $idxLang = 1 } 'en' { $idxLang = 2 } 'es' { $idxLang = 3 } }
$script:cmbLang.SelectedIndex = $idxLang
$script:cmbLang.Left = 640
$script:cmbLang.Add_SelectedIndexChanged({
    try { if ($script:Translating -or $script:cmbLang.SelectedIndex -lt 0) { return }; Set-Language (@('auto', 'pt', 'en', 'es')[$script:cmbLang.SelectedIndex]) } catch { Log-Error $_ }
})
$header.Controls.Add($script:cmbLang)
$header.Add_Resize({ try { $script:cmbTheme.Left = [math]::Max(320, $script:header.ClientSize.Width - $script:cmbTheme.Width - 150); $script:cmbLang.Left = $script:cmbTheme.Left - $script:cmbLang.Width - 10 } catch { } })
$root.Controls.Add($header, 0, 0)

$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Dock = 'Fill'; $script:lblStatus.TextAlign = 'MiddleLeft'; $script:lblStatus.Tag = 'muted'
$script:lblStatus.Text = 'Pronto. Na aba Monitor, clique em Iniciar.'
$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Dock = 'Fill'
$script:lblVersion = New-Object System.Windows.Forms.Label
$script:lblVersion.Dock = 'Right'; $script:lblVersion.Width = 380; $script:lblVersion.TextAlign = 'MiddleRight'
$script:lblVersion.Tag = 'muted'; $script:lblVersion.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:lblVersion.Add_Click({ Show-UpdatesTab })
[void]$pnlStatus.Controls.Add($script:lblStatus)
[void]$pnlStatus.Controls.Add($script:lblVersion)
$root.Controls.Add($pnlStatus, 0, 2)

$tabs = New-Object System.Windows.Forms.TabControl
$script:tabs = $tabs
$tabs.Dock = 'Fill'
$tabs.Appearance = 'FlatButtons'; $tabs.DrawMode = 'OwnerDrawFixed'; $tabs.SizeMode = 'Fixed'
$tabs.ItemSize = New-Object System.Drawing.Size(130, 30)
$tabs.Font = New-Object System.Drawing.Font('Segoe UI', [single]9)
$tabs.Add_DrawItem({
    param($sender, $e)
    try {
        $p = $script:Pal
        $sel = ($e.Index -eq $sender.SelectedIndex)
        $bg = $p.TabIdle; if ($sel) { $bg = $p.TabSel }
        $br = New-Object System.Drawing.SolidBrush($bg)
        $e.Graphics.FillRectangle($br, $e.Bounds); $br.Dispose()
        if ($sel) {
            $ac = New-Object System.Drawing.SolidBrush($p.Accent)
            $e.Graphics.FillRectangle($ac, $e.Bounds.X, ($e.Bounds.Bottom - 3), $e.Bounds.Width, 3); $ac.Dispose()
        }
        $flags = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, SingleLine, EndEllipsis'
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $sender.TabPages[$e.Index].Text, $sender.Font, $e.Bounds, $p.Text, $flags)
    } catch { }
})
$root.Controls.Add($tabs, 0, 1)

# ----- aba Monitor
$pgMon = New-Object System.Windows.Forms.TabPage('Monitor')
$tMon = New-Tlp 5
Add-Row $tMon 'abs' 44; Add-Row $tMon 'abs' 40; Add-Row $tMon 'pct' 40; Add-Row $tMon 'pct' 60; Add-Row $tMon 'abs' 76
$tb = New-Toolbar
$script:btnStart = New-Btn 'Iniciar' { Start-Monitor } 90
$script:btnStop = New-Btn 'Parar' { Stop-Monitor } 90
$script:btnStop.Enabled = $false
[void]$tb.Controls.Add($script:btnStart); [void]$tb.Controls.Add($script:btnStop)
[void]$tb.Controls.Add((New-Btn 'Zerar' { Reset-Monitor } 80))
[void]$tb.Controls.Add((New-Btn '+ Destino' { Add-TargetUi } 100))
[void]$tb.Controls.Add((New-Btn 'Remover' { Remove-TargetUi } 90))
[void]$tb.Controls.Add((New-Btn 'Pasta de logs' { Start-Process (Get-ReportDir) } 110))
[void]$tb.Controls.Add((New-Lbl 'Intervalo (s)' 82))
$script:numInt = New-Object System.Windows.Forms.NumericUpDown
$script:numInt.Minimum = 1; $script:numInt.Maximum = 10; $script:numInt.Value = [math]::Max(1, [math]::Min(10, [int]$script:Cfg.IntervalS)); $script:numInt.Width = 50
$script:numInt.Add_ValueChanged({ $script:Cfg.IntervalS = [int]$script:numInt.Value; Save-Config $script:Cfg })
[void]$tb.Controls.Add($script:numInt)
[void]$tb.Controls.Add((New-Lbl 'Pico a partir de (ms)' 130))
$script:numSpike = New-Object System.Windows.Forms.NumericUpDown
$script:numSpike.Minimum = 50; $script:numSpike.Maximum = 2000; $script:numSpike.Increment = 50
$script:numSpike.Value = [math]::Max(50, [math]::Min(2000, $script:SpikeMs)); $script:numSpike.Width = 65
$script:numSpike.Add_ValueChanged({ $script:SpikeMs = [int]$script:numSpike.Value; $script:Cfg.SpikeMs = $script:SpikeMs; Save-Config $script:Cfg })
[void]$tb.Controls.Add($script:numSpike)
$tMon.Controls.Add($tb, 0, 0)

# opcoes de monitoramento em segundo plano
$tbOp = New-Toolbar
$script:chkTray = New-Object System.Windows.Forms.CheckBox
$script:chkTray.Text = 'Minimizar para a bandeja'; $script:chkTray.AutoSize = $true; $script:chkTray.Checked = [bool]$script:Cfg.Bandeja
$script:chkTray.Margin = (New-Object System.Windows.Forms.Padding(8, 6, 3, 3))
$script:chkTray.Add_CheckedChanged({ try { $script:Cfg.Bandeja = [bool]$script:chkTray.Checked; Save-Config $script:Cfg } catch { Log-Error $_ } })
[void]$tbOp.Controls.Add($script:chkTray)
$script:chkAlert = New-Object System.Windows.Forms.CheckBox
$script:chkAlert.Text = 'Alertar (balão e som) quando houver problemas acima de'; $script:chkAlert.AutoSize = $true; $script:chkAlert.Checked = [bool]$script:Cfg.Alertas
$script:chkAlert.Margin = (New-Object System.Windows.Forms.Padding(14, 6, 3, 3))
$script:chkAlert.Add_CheckedChanged({ try { $script:Cfg.Alertas = [bool]$script:chkAlert.Checked; Save-Config $script:Cfg } catch { Log-Error $_ } })
[void]$tbOp.Controls.Add($script:chkAlert)
$script:numAlert = New-Object System.Windows.Forms.NumericUpDown
$script:numAlert.Minimum = 1; $script:numAlert.Maximum = 50; $script:numAlert.Width = 50
$script:numAlert.Value = [math]::Max(1, [math]::Min(50, [int]$script:Cfg.AlertaPct))
$script:numAlert.Add_ValueChanged({ try { $script:Cfg.AlertaPct = [int]$script:numAlert.Value; Save-Config $script:Cfg } catch { Log-Error $_ } })
[void]$tbOp.Controls.Add($script:numAlert)
[void]$tbOp.Controls.Add((New-Lbl '% em 3 min' 70))
$script:chkAutoMon = New-Object System.Windows.Forms.CheckBox
$script:chkAutoMon.Text = 'Monitorar ao abrir'; $script:chkAutoMon.AutoSize = $true; $script:chkAutoMon.Checked = [bool]$script:Cfg.AutoMonitor
$script:chkAutoMon.Margin = (New-Object System.Windows.Forms.Padding(14, 6, 3, 3))
$script:chkAutoMon.Add_CheckedChanged({ try { $script:Cfg.AutoMonitor = [bool]$script:chkAutoMon.Checked; Save-Config $script:Cfg } catch { Log-Error $_ } })
[void]$tbOp.Controls.Add($script:chkAutoMon)
$script:chkStartup = New-Object System.Windows.Forms.CheckBox
$script:chkStartup.Text = 'Iniciar com o Windows'; $script:chkStartup.AutoSize = $true
$script:chkStartup.Checked = (Test-Path (Get-StartupLinkPath))
$script:chkStartup.Margin = (New-Object System.Windows.Forms.Padding(14, 6, 3, 3))
$script:chkStartup.Add_CheckedChanged({ try { Set-StartupShortcut ([bool]$script:chkStartup.Checked) } catch { Log-Error $_; Set-Status 'Não foi possível alterar a inicialização com o Windows.' } })
[void]$tbOp.Controls.Add($script:chkStartup)
$tMon.Controls.Add($tbOp, 0, 1)

$script:lv = New-Object System.Windows.Forms.ListView
$script:lv.Dock = 'Fill'; $script:lv.View = 'Details'; $script:lv.FullRowSelect = $true
$script:lv.GridLines = $true; $script:lv.HideSelection = $false; $script:lv.MultiSelect = $false
foreach ($col in @(@('Destino', 150), @('Endereço', 170), @('Último', 75), @('Média', 80), @('Mín', 70), @('Máx', 80), @('Problemas', 110), @('Testes', 70))) {
    [void]$script:lv.Columns.Add($col[0], $col[1])
}
Set-DoubleBuffered $script:lv
$script:lv.Add_SelectedIndexChanged({
    if ($script:lv.SelectedIndices.Count -gt 0) { $script:Sel = $script:lv.SelectedIndices[0]; $script:chart.Invalidate() }
})
$tMon.Controls.Add($script:lv, 0, 2)

$script:chart = New-Object System.Windows.Forms.Panel
$script:chart.Dock = 'Fill'; $script:chart.Tag = 'surface'
Set-DoubleBuffered $script:chart
$script:chart.Add_Paint({
    param($s, $e)
    try { Draw-Chart $e.Graphics $s.ClientSize.Width $s.ClientSize.Height } catch { Log-Error $_ }
})
$script:chart.Add_Resize({ $script:chart.Invalidate() })
$tMon.Controls.Add($script:chart, 0, 3)

$script:lblVerdict = New-Object System.Windows.Forms.Label
$script:lblVerdict.Tag = 'verdict'; $script:lblVerdict.Dock = 'Fill'; $script:lblVerdict.Padding = (New-Object System.Windows.Forms.Padding(10, 6, 10, 6))
$script:lblVerdict.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$script:lblVerdict.BackColor = [System.Drawing.Color]::FromArgb(236, 240, 246)
$script:lblVerdict.Text = 'Clique em Iniciar para começar a medir.'
$tMon.Controls.Add($script:lblVerdict, 0, 4)
$pgMon.Controls.Add($tMon)
$tabs.TabPages.Add($pgMon)

# ----- aba Diagnostico
$pgDiag = New-Object System.Windows.Forms.TabPage('Diagnóstico')
$tDiag = New-Tlp 3
Add-Row $tDiag 'abs' 44; Add-Row $tDiag 'abs' 62; Add-Row $tDiag 'pct' 100
$tb2 = New-Toolbar
$script:btnDiag = New-Btn 'Executar diagnóstico' { Start-Diag } 170
$script:chkSpeed = New-Object System.Windows.Forms.CheckBox
$script:chkSpeed.Text = 'incluir teste de velocidade (usa ~300 MB)'; $script:chkSpeed.Checked = $true; $script:chkSpeed.AutoSize = $true
$script:chkSpeed.Margin = (New-Object System.Windows.Forms.Padding(8, 8, 3, 3))
$script:lblDiag = New-Lbl 'Leva uns 2 a 3 minutos.' 420
[void]$tb2.Controls.Add($script:btnDiag); [void]$tb2.Controls.Add($script:chkSpeed); [void]$tb2.Controls.Add($script:lblDiag)
$tDiag.Controls.Add($tb2, 0, 0)
$script:lblScores = New-Object System.Windows.Forms.Label
$script:lblScores.Dock = 'Fill'; $script:lblScores.Tag = 'info'; $script:lblScores.Padding = (New-Object System.Windows.Forms.Padding(8, 4, 8, 4))
$script:lblScores.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$script:lblScores.Text = 'As notas (bufferbloat, jogos, chamadas, streaming, navegação e velocidade contra o plano) aparecem aqui depois do diagnóstico com o teste de velocidade.'
$tDiag.Controls.Add($script:lblScores, 0, 1)
$script:rtbDiag = New-Object System.Windows.Forms.RichTextBox
$script:rtbDiag.Dock = 'Fill'; $script:rtbDiag.ReadOnly = $true; $script:rtbDiag.BackColor = [System.Drawing.Color]::White
$script:rtbDiag.Font = New-Object System.Drawing.Font('Consolas', [single]9.5)
$tDiag.Controls.Add($script:rtbDiag, 0, 2)
$pgDiag.Controls.Add($tDiag)
$tabs.TabPages.Add($pgDiag)

# ----- aba Rede
$pgNet = New-Object System.Windows.Forms.TabPage('Rede')
$tNet = New-Tlp 2
Add-Row $tNet 'abs' 44; Add-Row $tNet 'pct' 100
$tb3 = New-Toolbar
$script:btnScan = New-Btn 'Escanear a rede' { Start-Scan } 150
$script:lblScan = New-Lbl 'Mostra os aparelhos ligados na mesma rede (Wi-Fi e cabo).' 520
[void]$tb3.Controls.Add($script:btnScan); [void]$tb3.Controls.Add($script:lblScan)
$tNet.Controls.Add($tb3, 0, 0)
$script:lvNet = New-Object System.Windows.Forms.ListView
$script:lvNet.Dock = 'Fill'; $script:lvNet.View = 'Details'; $script:lvNet.FullRowSelect = $true; $script:lvNet.GridLines = $true
foreach ($col in @(@('Endereço IP', 140), @('MAC', 160), @('Nome', 300), @('Nota', 120))) { [void]$script:lvNet.Columns.Add($col[0], $col[1]) }
$tNet.Controls.Add($script:lvNet, 0, 1)
$pgNet.Controls.Add($tNet)
$tabs.TabPages.Add($pgNet)

# ----- aba Suporte
$pgSup = New-Object System.Windows.Forms.TabPage('Texto para o suporte')
$tSup = New-Tlp 2
Add-Row $tSup 'abs' 44; Add-Row $tSup 'pct' 100
$tb4 = New-Toolbar
[void]$tb4.Controls.Add((New-Lbl 'Provedor' 62))
$script:txtProv = New-Object System.Windows.Forms.TextBox
$script:txtProv.Width = 120; $script:txtProv.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3)); $script:txtProv.Text = [string]$script:Cfg.Provedor
[void]$tb4.Controls.Add($script:txtProv)
[void]$tb4.Controls.Add((New-Btn 'Detectar' { Start-Pub } 70))
[void]$tb4.Controls.Add((New-Lbl 'Plano' 42))
$script:txtPlano = New-Object System.Windows.Forms.TextBox
$script:txtPlano.Width = 90; $script:txtPlano.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3)); $script:txtPlano.Text = [string]$script:Cfg.Plano
[void]$tb4.Controls.Add($script:txtPlano)
$script:cmbKind = New-Object System.Windows.Forms.ComboBox
$script:cmbKind.DropDownStyle = 'DropDownList'; $script:cmbKind.Width = 190; $script:cmbKind.Margin = (New-Object System.Windows.Forms.Padding(8, 6, 3, 3))
[void]$script:cmbKind.Items.Add('Para a operadora de internet'); [void]$script:cmbKind.Items.Add('Para o servidor de jogo')
$script:cmbKind.SelectedIndex = 0
[void]$tb4.Controls.Add($script:cmbKind)
[void]$tb4.Controls.Add((New-Btn 'Gerar texto' { Gen-Support } 100))
[void]$tb4.Controls.Add((New-Btn 'Gerar relatório HTML' { Start-Report } 160))
[void]$tb4.Controls.Add((New-Btn 'Copiar' { if ($script:txtSupport.Text) { [System.Windows.Forms.Clipboard]::SetText($script:txtSupport.Text); Set-Status 'Texto copiado.' } } 80))
$tSup.Controls.Add($tb4, 0, 0)
$script:txtSupport = New-Object System.Windows.Forms.TextBox
$script:txtSupport.Dock = 'Fill'; $script:txtSupport.Multiline = $true; $script:txtSupport.ScrollBars = 'Vertical'
$script:txtSupport.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$script:txtSupport.Text = 'Rode o Monitor por alguns minutos (e, se quiser, o Diagnóstico) e clique em "Gerar texto". Ele monta a mensagem com os números reais, pronta para colar no chat ou e-mail do suporte.'
$tSup.Controls.Add($script:txtSupport, 0, 1)
$pgSup.Controls.Add($tSup)
$tabs.TabPages.Add($pgSup)

# ----- aba Este PC (rede + hardware)
$pgPc = New-Object System.Windows.Forms.TabPage('Este PC')
$tPc = New-Tlp 3
Add-Row $tPc 'abs' 44; Add-Row $tPc 'pct' 100; Add-Row $tPc 'abs' 96
$tb5 = New-Toolbar
$script:btnSnap = New-Btn 'Salvar configuração' { Start-Snap } 150
[void]$tb5.Controls.Add($script:btnSnap)
[void]$tb5.Controls.Add((New-Btn 'Atualizar' { Refresh-PcInfo; Start-HwInfo } 90))
[void]$tb5.Controls.Add((New-Btn 'Reparar rede' { Repair-NetUi } 120))
[void]$tb5.Controls.Add((New-Btn 'Painel do roteador' { if ($script:GwCache) { Start-Process ('http://' + $script:GwCache) } } 140))
[void]$tb5.Controls.Add((New-Btn 'Baixar Cloudflare WARP' { Start-Process 'https://one.one.one.one/' } 170))
[void]$tb5.Controls.Add((New-Btn 'Copiar informações' { Copy-HwText } 140))
$script:chkTemp = New-Object System.Windows.Forms.CheckBox
$script:chkTemp.Text = 'Medir temperaturas'; $script:chkTemp.AutoSize = $true; $script:chkTemp.Checked = $true
$script:chkTemp.Margin = (New-Object System.Windows.Forms.Padding(8, 8, 3, 3))
$script:chkTemp.Add_CheckedChanged({ try { if ($script:chkTemp.Checked) { Start-HwLive } else { Stop-HwLive } } catch { Log-Error $_ } })
[void]$tb5.Controls.Add($script:chkTemp)
$tPc.Controls.Add($tb5, 0, 0)

$script:txtPc = New-Object System.Windows.Forms.TextBox
$script:txtPc.Dock = 'Fill'; $script:txtPc.Multiline = $true; $script:txtPc.ReadOnly = $true; $script:txtPc.ScrollBars = 'Vertical'
$script:txtPc.Font = New-Object System.Drawing.Font('Consolas', [single]10)
$script:txtHw = New-Object System.Windows.Forms.TextBox
$script:txtHw.Dock = 'Fill'; $script:txtHw.Multiline = $true; $script:txtHw.ReadOnly = $true; $script:txtHw.ScrollBars = 'Vertical'
$script:txtHw.Font = New-Object System.Drawing.Font('Consolas', [single]10)
$script:txtHw.Text = 'Abra esta aba para ler o hardware.'
$mid = New-Object System.Windows.Forms.TableLayoutPanel
$mid.Dock = 'Fill'; $mid.ColumnCount = 2; $mid.RowCount = 1
[void]$mid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 47)))
[void]$mid.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 53)))
[void]$mid.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$mid.Controls.Add($script:txtPc, 0, 0); $mid.Controls.Add($script:txtHw, 1, 0)
$tPc.Controls.Add($mid, 0, 1)

$script:lblHwLive = New-Object System.Windows.Forms.Label
$script:lblHwLive.Dock = 'Fill'; $script:lblHwLive.Tag = 'info'; $script:lblHwLive.Padding = (New-Object System.Windows.Forms.Padding(8, 4, 8, 4))
$script:lblHwLive.Font = New-Object System.Drawing.Font('Consolas', [single]9.5)
$script:lblHwLive.Text = 'Temperaturas e uso aparecem aqui assim que a leitura começar.'
$tPc.Controls.Add($script:lblHwLive, 0, 2)
$pgPc.Controls.Add($tPc)
$tabs.TabPages.Add($pgPc)

# ----- aba Saúde dos discos
$pgDisk = New-Object System.Windows.Forms.TabPage('Saúde dos discos')
$tDisk = New-Tlp 4
Add-Row $tDisk 'abs' 44; Add-Row $tDisk 'pct' 55; Add-Row $tDisk 'pct' 45; Add-Row $tDisk 'abs' 64
$tbDk = New-Toolbar
[void]$tbDk.Controls.Add((New-Btn 'Atualizar' { Start-DiskInfo } 90))
[void]$tbDk.Controls.Add((New-Btn 'SMART detalhado (administrador)' { Start-SmartUi } 230))
[void]$tbDk.Controls.Add((New-Btn 'Copiar' { Copy-DiskText } 90))
$tDisk.Controls.Add($tbDk, 0, 0)
$script:lvDisk = New-Object System.Windows.Forms.ListView
$script:lvDisk.Dock = 'Fill'; $script:lvDisk.View = 'Details'; $script:lvDisk.FullRowSelect = $true; $script:lvDisk.GridLines = $true; $script:lvDisk.HideSelection = $false
foreach ($col in @(@('Disco', 210), @('Tipo', 100), @('Capacidade', 85), @('Saúde (Windows)', 110), @('Temp.', 60), @('Ligado', 80), @('Desgaste', 70), @('Erros L/E', 70), @('SMART', 105), @('Conclusão', 330))) { [void]$script:lvDisk.Columns.Add($col[0], $col[1]) }
Set-DoubleBuffered $script:lvDisk
$tDisk.Controls.Add($script:lvDisk, 0, 1)
$script:lvVol = New-Object System.Windows.Forms.ListView
$script:lvVol.Dock = 'Fill'; $script:lvVol.View = 'Details'; $script:lvVol.FullRowSelect = $true; $script:lvVol.GridLines = $true; $script:lvVol.HideSelection = $false
foreach ($col in @(@('Unidade', 80), @('Nome', 200), @('Sistema', 80), @('Tamanho', 100), @('Livre', 100), @('% usado', 80))) { [void]$script:lvVol.Columns.Add($col[0], $col[1]) }
Set-DoubleBuffered $script:lvVol
$tDisk.Controls.Add($script:lvVol, 0, 2)
$script:lblDisk = New-Object System.Windows.Forms.Label
$script:lblDisk.Dock = 'Fill'; $script:lblDisk.Tag = 'info'; $script:lblDisk.Padding = (New-Object System.Windows.Forms.Padding(8, 4, 8, 4))
$script:lblDisk.Text = 'Abra esta aba para ler a saúde dos discos.'
$tDisk.Controls.Add($script:lblDisk, 0, 3)
$pgDisk.Controls.Add($tDisk)
$tabs.TabPages.Add($pgDisk)

# ----- aba Ferramentas DNS
$pgDns = New-Object System.Windows.Forms.TabPage('Ferramentas DNS')
$tDns = New-Tlp 5
Add-Row $tDns 'abs' 44; Add-Row $tDns 'abs' 44; Add-Row $tDns 'abs' 26; Add-Row $tDns 'pct' 100; Add-Row $tDns 'abs' 56
$tbD1 = New-Toolbar
$script:btnDnsTest = New-Btn 'Testar DNS' { Start-DnsTest } 95
[void]$tbD1.Controls.Add($script:btnDnsTest)
[void]$tbD1.Controls.Add((New-Btn 'Aplicar selecionado' { Apply-DnsSelected } 140))
[void]$tbD1.Controls.Add((New-Btn 'Aplicar o mais rápido' { Apply-DnsFastest } 160))
[void]$tbD1.Controls.Add((New-Btn 'Automático (DHCP)' { Reset-DnsAuto } 130))
[void]$tbD1.Controls.Add((New-Btn 'Restaurar anterior' { Restore-DnsBackup } 125))
[void]$tbD1.Controls.Add((New-Btn 'Limpar cache' { Flush-DnsUi } 105))
$tDns.Controls.Add($tbD1, 0, 0)

$tbD2 = New-Toolbar
[void]$tbD2.Controls.Add((New-Lbl 'Adaptador' 68))
$script:cmbAd = New-Object System.Windows.Forms.ComboBox
$script:cmbAd.DropDownStyle = 'DropDownList'; $script:cmbAd.Width = 200; $script:cmbAd.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3))
$script:cmbAd.Add_SelectedIndexChanged({ try { if (-not $script:AdFilling) { Update-DnsInfo } } catch { Log-Error $_ } })
[void]$tbD2.Controls.Add($script:cmbAd)
[void]$tbD2.Controls.Add((New-Lbl 'DNS 1' 42))
$script:txtDns1 = New-Object System.Windows.Forms.TextBox
$script:txtDns1.Width = 105; $script:txtDns1.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3))
[void]$tbD2.Controls.Add($script:txtDns1)
[void]$tbD2.Controls.Add((New-Lbl 'DNS 2' 42))
$script:txtDns2 = New-Object System.Windows.Forms.TextBox
$script:txtDns2.Width = 105; $script:txtDns2.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3))
[void]$tbD2.Controls.Add($script:txtDns2)
[void]$tbD2.Controls.Add((New-Btn 'Aplicar manual' { Apply-DnsManual } 115))
$script:chkSom = New-Object System.Windows.Forms.CheckBox
$script:chkSom.Text = 'Som ao mudar o DNS'; $script:chkSom.AutoSize = $true
$script:chkSom.Margin = (New-Object System.Windows.Forms.Padding(8, 8, 3, 3))
$script:chkSom.Checked = ($script:Cfg.SomDns -ne $false)
$script:chkSom.Add_CheckedChanged({ try { $script:Cfg.SomDns = [bool]$script:chkSom.Checked; Save-Config $script:Cfg } catch { Log-Error $_ } })
[void]$tbD2.Controls.Add($script:chkSom)
$tDns.Controls.Add($tbD2, 0, 1)

$script:lblDnsProg = New-Lbl 'Clique em "Testar DNS" para comparar a velocidade de cada servidor.' 700
$script:lblDnsProg.Dock = 'Fill'; $script:lblDnsProg.Tag = 'muted'
$tDns.Controls.Add($script:lblDnsProg, 0, 2)

$script:lvDns = New-Object System.Windows.Forms.ListView
$script:lvDns.Dock = 'Fill'; $script:lvDns.View = 'Details'; $script:lvDns.FullRowSelect = $true; $script:lvDns.GridLines = $true
$script:lvDns.HideSelection = $false; $script:lvDns.MultiSelect = $false
foreach ($col in @(@('Servidor', 200), @('DNS 1', 120), @('DNS 2', 120), @('Resolução média', 115), @('Falhas', 70), @('Ping', 70), @('Observação', 230))) { [void]$script:lvDns.Columns.Add($col[0], $col[1]) }
Set-DoubleBuffered $script:lvDns
$script:lvDns.Add_DoubleClick({ try { Apply-DnsSelected } catch { Log-Error $_ } })
$tDns.Controls.Add($script:lvDns, 0, 3)

$script:lblDnsInfo = New-Object System.Windows.Forms.Label
$script:lblDnsInfo.Tag = 'info'; $script:lblDnsInfo.Dock = 'Fill'; $script:lblDnsInfo.Padding = (New-Object System.Windows.Forms.Padding(8, 4, 8, 4))
$script:lblDnsInfo.BackColor = [System.Drawing.Color]::FromArgb(236, 240, 246)
$tDns.Controls.Add($script:lblDnsInfo, 0, 4)
$pgDns.Controls.Add($tDns)
$tabs.TabPages.Add($pgDns)

# ----- aba Desempenho em jogos
$pgGame = New-Object System.Windows.Forms.TabPage('Desempenho em jogos')
$tGame = New-Tlp 4
Add-Row $tGame 'abs' 44; Add-Row $tGame 'abs' 44; Add-Row $tGame 'pct' 100; Add-Row $tGame 'abs' 84
$tbG1 = New-Toolbar
[void]$tbG1.Controls.Add((New-Btn 'Marcar recomendadas' { Mark-GameRec } 150))
[void]$tbG1.Controls.Add((New-Btn 'Desmarcar tudo' { Clear-GameMarks } 115))
[void]$tbG1.Controls.Add((New-Btn 'Aplicar selecionadas' { Apply-GamesUi } 150))
[void]$tbG1.Controls.Add((New-Btn 'Reverter selecionadas' { Revert-GamesUi $false } 160))
[void]$tbG1.Controls.Add((New-Btn 'Reverter tudo' { Revert-GamesUi $true } 110))
$tGame.Controls.Add($tbG1, 0, 0)
$tbG2 = New-Toolbar
[void]$tbG2.Controls.Add((New-Btn 'Ponto de restauração' { Create-RestoreUi } 150))
[void]$tbG2.Controls.Add((New-Btn 'Limpar temporários' { Start-GameToolUi 'temp' ('Limpar os arquivos temporários do usuário e do Windows?' + "`r`n`r`n" + 'Arquivos em uso são mantidos. Uma janela de administrador mostra o resultado.') } 140))
[void]$tbG2.Controls.Add((New-Btn 'Otimizar discos' { Start-GameToolUi 'disks' ('Otimizar os discos?' + "`r`n`r`n" + 'SSD: comando TRIM. HDD: desfragmentação (pode demorar). Discos de tipo desconhecido são ignorados.') } 125))
[void]$tbG2.Controls.Add((New-Btn 'Verificar sistema (SFC)' { Start-GameToolUi 'sfc' ('Verificar e reparar arquivos do Windows (sfc /scannow)?' + "`r`n`r`n" + 'Leva de 10 a 20 minutos. Uma janela de administrador mostra o progresso.') } 170))
[void]$tbG2.Controls.Add((New-Btn 'Atualizar estado' { Refresh-GameList } 125))
$tGame.Controls.Add($tbG2, 0, 1)

$script:lvGame = New-Object System.Windows.Forms.ListView
$script:lvGame.Dock = 'Fill'; $script:lvGame.View = 'Details'; $script:lvGame.FullRowSelect = $true; $script:lvGame.GridLines = $true
$script:lvGame.CheckBoxes = $true; $script:lvGame.HideSelection = $false; $script:lvGame.MultiSelect = $false
foreach ($col in @(@('Otimização', 360), @('Categoria', 95), @('Risco', 70), @('Admin', 60), @('Estado', 110))) { [void]$script:lvGame.Columns.Add($col[0], $col[1]) }
Set-DoubleBuffered $script:lvGame
$script:lvGame.Add_SelectedIndexChanged({
    try {
        if ($script:lvGame.SelectedItems.Count -gt 0) {
            $t = Get-TweakById ([string]$script:lvGame.SelectedItems[0].Tag)
            if ($t) { $script:lblGame.Text = $t.Desc }
        }
    } catch { Log-Error $_ }
})
$tGame.Controls.Add($script:lvGame, 0, 2)

$script:lblGame = New-Object System.Windows.Forms.Label
$script:lblGame.Tag = 'info'; $script:lblGame.Dock = 'Fill'; $script:lblGame.Padding = (New-Object System.Windows.Forms.Padding(8, 4, 8, 4))
$script:lblGame.BackColor = [System.Drawing.Color]::FromArgb(236, 240, 246)
$script:lblGame.Text = 'Clique em uma otimização para ver o que ela faz. As recomendadas são as de menor risco. Tudo pede confirmação, guarda o valor original e pode ser revertido. Baseado na documentação da Microsoft e no projeto winutil (Chris Titus Tech).'
$tGame.Controls.Add($script:lblGame, 0, 3)
$pgGame.Controls.Add($tGame)
$tabs.TabPages.Add($pgGame)

# ----- aba Assistente
$pgAss = New-Object System.Windows.Forms.TabPage('Assistente')
$tAss = New-Tlp 4
Add-Row $tAss 'abs' 40; Add-Row $tAss 'abs' 50; Add-Row $tAss 'abs' 46; Add-Row $tAss 'pct' 100
$lblAssT = New-Lbl 'Qual é o problema? Escolha e o NetDoctor roda só os testes que importam e explica em linguagem simples.' 900
$lblAssT.Dock = 'Fill'; $lblAssT.Font = New-Object System.Drawing.Font('Segoe UI', [single]10.5)
$tAss.Controls.Add($lblAssT, 0, 0)
$tbAs = New-Toolbar
$script:btnAssist = @()
foreach ($a in @(@('Lag / ping alto em jogo', 'lag'), @('Internet cai ou fica instável', 'queda'), @('Está lenta', 'lenta'), @('Wi-Fi ruim', 'wifi'))) {
    $b = New-Btn $a[0] ([scriptblock]::Create("Start-Assist '" + $a[1] + "'")) 210
    $script:btnAssist += $b
    [void]$tbAs.Controls.Add($b)
}
$tAss.Controls.Add($tbAs, 0, 1)
$script:lblAssistBanner = New-Object System.Windows.Forms.Label
$script:lblAssistBanner.Tag = 'verdict'; $script:lblAssistBanner.Dock = 'Fill'; $script:lblAssistBanner.Padding = (New-Object System.Windows.Forms.Padding(10, 8, 10, 6))
$script:lblAssistBanner.Font = New-Object System.Drawing.Font('Segoe UI', [single]10.5)
$script:lblAssistBanner.Text = 'Escolha um problema acima para começar.'
$script:lblAssistBanner.BackColor = $script:Pal.Info
$tAss.Controls.Add($script:lblAssistBanner, 0, 2)
$script:rtbAssist = New-Object System.Windows.Forms.RichTextBox
$script:rtbAssist.Dock = 'Fill'; $script:rtbAssist.ReadOnly = $true
$script:rtbAssist.Font = New-Object System.Drawing.Font('Consolas', [single]10)
$tAss.Controls.Add($script:rtbAssist, 0, 3)
$pgAss.Controls.Add($tAss)
$tabs.TabPages.Add($pgAss)

# ----- aba Rota
$pgRoute = New-Object System.Windows.Forms.TabPage('Rota')
$tRt = New-Tlp 3
Add-Row $tRt 'abs' 44; Add-Row $tRt 'pct' 100; Add-Row $tRt 'abs' 78
$tbRt = New-Toolbar
[void]$tbRt.Controls.Add((New-Lbl 'Destino' 56))
$script:txtRouteDest = New-Object System.Windows.Forms.TextBox
$script:txtRouteDest.Width = 170; $script:txtRouteDest.Text = '1.1.1.1'; $script:txtRouteDest.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3))
[void]$tbRt.Controls.Add($script:txtRouteDest)
$script:btnRouteStart = New-Btn 'Iniciar' { Start-Route } 90
$script:btnRouteStop = New-Btn 'Parar' { Stop-Route } 90
$script:btnRouteStop.Enabled = $false
[void]$tbRt.Controls.Add($script:btnRouteStart); [void]$tbRt.Controls.Add($script:btnRouteStop)
[void]$tbRt.Controls.Add((New-Lbl 'Mede cada salto do caminho sem parar e mostra onde a perda começa.' 520))
$tRt.Controls.Add($tbRt, 0, 0)
$script:lvRoute = New-Object System.Windows.Forms.ListView
$script:lvRoute.Dock = 'Fill'; $script:lvRoute.View = 'Details'; $script:lvRoute.FullRowSelect = $true; $script:lvRoute.GridLines = $true; $script:lvRoute.HideSelection = $false
foreach ($col in @(@('Salto', 50), @('Endereço', 130), @('Nome', 300), @('Enviados', 70), @('Perda', 65), @('Último', 65), @('Média', 65), @('Mín', 55), @('Máx', 60), @('Jitter', 60))) { [void]$script:lvRoute.Columns.Add($col[0], $col[1]) }
Set-DoubleBuffered $script:lvRoute
$tRt.Controls.Add($script:lvRoute, 0, 1)
$script:lblRoute = New-Object System.Windows.Forms.Label
$script:lblRoute.Tag = 'verdict'; $script:lblRoute.Dock = 'Fill'; $script:lblRoute.Padding = (New-Object System.Windows.Forms.Padding(10, 6, 10, 6))
$script:lblRoute.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$script:lblRoute.Text = 'Clique em Iniciar. Atenção: equipamentos do caminho podem limitar respostas e parecer que perdem; a conclusão só aponta perda que continua até o destino.'
$script:lblRoute.BackColor = $script:Pal.Info
$tRt.Controls.Add($script:lblRoute, 0, 2)
$pgRoute.Controls.Add($tRt)
$tabs.TabPages.Add($pgRoute)

# ----- aba Historico
$pgHist = New-Object System.Windows.Forms.TabPage('Histórico')
$tHi = New-Tlp 3
Add-Row $tHi 'abs' 44; Add-Row $tHi 'pct' 100; Add-Row $tHi 'abs' 86
$tbHi = New-Toolbar
[void]$tbHi.Controls.Add((New-Lbl 'Período' 56))
$script:cmbHistPer = New-Object System.Windows.Forms.ComboBox
$script:cmbHistPer.Name = 'histper'; $script:cmbHistPer.Tag = 'i18n'; $script:cmbHistPer.DropDownStyle = 'DropDownList'; $script:cmbHistPer.Width = 100; $script:cmbHistPer.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3))
[void]$script:cmbHistPer.Items.Add('Hoje'); [void]$script:cmbHistPer.Items.Add('7 dias'); [void]$script:cmbHistPer.Items.Add('30 dias')
$script:cmbHistPer.SelectedIndex = 1
[void]$tbHi.Controls.Add($script:cmbHistPer)
[void]$tbHi.Controls.Add((New-Lbl 'Destino' 56))
$script:cmbHistAlvo = New-Object System.Windows.Forms.ComboBox
$script:cmbHistAlvo.DropDownStyle = 'DropDownList'; $script:cmbHistAlvo.Width = 170; $script:cmbHistAlvo.Margin = (New-Object System.Windows.Forms.Padding(3, 6, 3, 3))
[void]$tbHi.Controls.Add($script:cmbHistAlvo)
[void]$tbHi.Controls.Add((New-Btn 'Atualizar' { Fill-HistTargets; Start-HistLoad } 90))
[void]$tbHi.Controls.Add((New-Btn 'Gerar relatório HTML' { Start-Report } 160))
[void]$tbHi.Controls.Add((New-Btn 'Pasta dos dados' { Start-Process (Get-AppDir) } 130))
$tHi.Controls.Add($tbHi, 0, 0)
$script:histPanel = New-Object System.Windows.Forms.Panel
$script:histPanel.Dock = 'Fill'; $script:histPanel.Tag = 'surface'
Set-DoubleBuffered $script:histPanel
$script:histPanel.Add_Paint({ param($s, $e) try { Draw-Hist $e.Graphics $s.ClientSize.Width $s.ClientSize.Height } catch { Log-Error $_ } })
$script:histPanel.Add_Resize({ $script:histPanel.Invalidate() })
$tHi.Controls.Add($script:histPanel, 0, 1)
$script:lblHist = New-Object System.Windows.Forms.Label
$script:lblHist.Tag = 'info'; $script:lblHist.Dock = 'Fill'; $script:lblHist.Padding = (New-Object System.Windows.Forms.Padding(8, 4, 8, 4))
$script:lblHist.Text = 'Abra esta aba para ver o histórico do monitor.'
$tHi.Controls.Add($script:lblHist, 0, 2)
$pgHist.Controls.Add($tHi)
$tabs.TabPages.Add($pgHist)

# ----- aba Atualizações
$pgUpd = New-Object System.Windows.Forms.TabPage('Atualizações')
$script:pgUpd = $pgUpd
$tUp = New-Tlp 3
Add-Row $tUp 'abs' 44; Add-Row $tUp 'abs' 40; Add-Row $tUp 'pct' 100
$tbUp = New-Toolbar
[void]$tbUp.Controls.Add((New-Btn 'Verificar agora' { Start-UpdateCheck -Manual } 130))
$script:btnUpdInstall = New-Btn 'Atualizar agora' { Start-UpdateInstall } 140
$script:btnUpdInstall.Enabled = $false
[void]$tbUp.Controls.Add($script:btnUpdInstall)
[void]$tbUp.Controls.Add((New-Btn 'Abrir página da versão' { Open-UpdatePage } 180))
$script:chkAutoUpd = New-Object System.Windows.Forms.CheckBox
$script:chkAutoUpd.Text = 'Verificar automaticamente (a cada 6 horas)'; $script:chkAutoUpd.AutoSize = $true; $script:chkAutoUpd.Checked = [bool]$script:Cfg.AutoUpdate
$script:chkAutoUpd.Margin = (New-Object System.Windows.Forms.Padding(14, 8, 3, 3))
$script:chkAutoUpd.Add_CheckedChanged({ try { $script:Cfg.AutoUpdate = [bool]$script:chkAutoUpd.Checked; Save-Config $script:Cfg } catch { Log-Error $_ } })
[void]$tbUp.Controls.Add($script:chkAutoUpd)
$tUp.Controls.Add($tbUp, 0, 0)
$script:lblUpdStatus = New-Object System.Windows.Forms.Label
$script:lblUpdStatus.Tag = 'info'; $script:lblUpdStatus.Dock = 'Fill'; $script:lblUpdStatus.Padding = (New-Object System.Windows.Forms.Padding(8, 8, 8, 4))
$script:lblUpdStatus.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$script:lblUpdStatus.Text = 'Ainda não verificado. A consulta usa a página de versões do projeto no GitHub (o GitHub vê o seu IP, como em qualquer site).'
$tUp.Controls.Add($script:lblUpdStatus, 0, 1)
$script:rtbUpd = New-Object System.Windows.Forms.RichTextBox
$script:rtbUpd.Dock = 'Fill'; $script:rtbUpd.ReadOnly = $true
$script:rtbUpd.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$tUp.Controls.Add($script:rtbUpd, 0, 2)
$pgUpd.Controls.Add($tUp)
$tabs.TabPages.Add($pgUpd)

# ----- aba Wi-Fi
$pgWifi = New-Object System.Windows.Forms.TabPage('Wi-Fi')
$tWf = New-Tlp 4
Add-Row $tWf 'abs' 44; Add-Row $tWf 'abs' 112; Add-Row $tWf 'pct' 55; Add-Row $tWf 'pct' 45
$tbWf = New-Toolbar
[void]$tbWf.Controls.Add((New-Btn 'Atualizar' { Start-Wifi } 100))
$script:chkWifiAuto = New-Object System.Windows.Forms.CheckBox
$script:chkWifiAuto.Text = 'Atualizar a cada 10 s'; $script:chkWifiAuto.AutoSize = $true
$script:chkWifiAuto.Margin = (New-Object System.Windows.Forms.Padding(14, 8, 3, 3))
[void]$tbWf.Controls.Add($script:chkWifiAuto)
$tWf.Controls.Add($tbWf, 0, 0)
$script:lblWifi = New-Object System.Windows.Forms.Label
$script:lblWifi.Tag = 'verdict'; $script:lblWifi.Dock = 'Fill'; $script:lblWifi.Padding = (New-Object System.Windows.Forms.Padding(10, 6, 10, 6))
$script:lblWifi.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$script:lblWifi.BackColor = $script:Pal.Info
$script:lblWifi.Text = 'Abra esta aba para analisar o Wi-Fi: sinal, canal e redes vizinhas.'
$tWf.Controls.Add($script:lblWifi, 0, 1)
$script:lvWifi = New-Object System.Windows.Forms.ListView
$script:lvWifi.Dock = 'Fill'; $script:lvWifi.View = 'Details'; $script:lvWifi.FullRowSelect = $true; $script:lvWifi.GridLines = $true; $script:lvWifi.HideSelection = $false
foreach ($col in @(@('Rede', 240), @('Sinal', 70), @('Canal', 70), @('Faixa', 110), @('Tipo', 130), @('Sua rede', 80))) { [void]$script:lvWifi.Columns.Add($col[0], $col[1]) }
Set-DoubleBuffered $script:lvWifi
$tWf.Controls.Add($script:lvWifi, 0, 2)
$script:lvWifiCh = New-Object System.Windows.Forms.ListView
$script:lvWifiCh.Dock = 'Fill'; $script:lvWifiCh.View = 'Details'; $script:lvWifiCh.FullRowSelect = $true; $script:lvWifiCh.GridLines = $true; $script:lvWifiCh.HideSelection = $false
foreach ($col in @(@('Canal', 70), @('Faixa', 120), @('Redes', 70), @('Sinal máx.', 90), @('Interferência', 120), @('Observação', 320))) { [void]$script:lvWifiCh.Columns.Add($col[0], $col[1]) }
Set-DoubleBuffered $script:lvWifiCh
$tWf.Controls.Add($script:lvWifiCh, 0, 3)
$pgWifi.Controls.Add($tWf)
$tabs.TabPages.Add($pgWifi)

# ----- aba Suporte
$pgSupp = New-Object System.Windows.Forms.TabPage('Suporte')
$tSp = New-Tlp 3
Add-Row $tSp 'abs' 74; Add-Row $tSp 'abs' 44; Add-Row $tSp 'pct' 100
$script:lblSupportHead = New-Object System.Windows.Forms.Label
$script:lblSupportHead.Tag = 'info'; $script:lblSupportHead.Dock = 'Fill'; $script:lblSupportHead.Padding = (New-Object System.Windows.Forms.Padding(10, 8, 10, 4))
$script:lblSupportHead.Font = New-Object System.Drawing.Font('Segoe UI', [single]10.5)
$tSp.Controls.Add($script:lblSupportHead, 0, 0)
$tbSp = New-Toolbar
$script:btnSupCopy = New-Btn 'Copiar e-mail' { if ($script:SupportEmail) { [System.Windows.Forms.Clipboard]::SetText($script:SupportEmail); Set-Status 'Texto copiado.' } } 130
$script:btnSupWrite = New-Btn 'Escrever e-mail' { if ($script:SupportEmail) { try { Start-Process ('mailto:' + $script:SupportEmail) } catch { } } } 140
[void]$tbSp.Controls.Add($script:btnSupCopy); [void]$tbSp.Controls.Add($script:btnSupWrite)
[void]$tbSp.Controls.Add((New-Btn 'Gerar pacote de suporte' { Create-SupportPackage } 190))
[void]$tbSp.Controls.Add((New-Btn 'Abrir página do projeto' { try { Start-Process ('https://github.com/{0}/{1}' -f $script:RepoOwner, $script:RepoName) } catch { } } 180))
$tSp.Controls.Add($tbSp, 0, 1)
$mid2 = New-Object System.Windows.Forms.TableLayoutPanel
$mid2.Dock = 'Fill'; $mid2.ColumnCount = 2; $mid2.RowCount = 1
[void]$mid2.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 55)))
[void]$mid2.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 45)))
[void]$mid2.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$script:rtbFaq = New-Object System.Windows.Forms.RichTextBox
$script:rtbFaq.Dock = 'Fill'; $script:rtbFaq.ReadOnly = $true; $script:rtbFaq.Font = New-Object System.Drawing.Font('Segoe UI', [single]10)
$mid2.Controls.Add($script:rtbFaq, 0, 0)
$fp = New-Tlp 9
Add-Row $fp 'abs' 24; Add-Row $fp 'abs' 32; Add-Row $fp 'abs' 24; Add-Row $fp 'pct' 100; Add-Row $fp 'abs' 24; Add-Row $fp 'abs' 32; Add-Row $fp 'abs' 46; Add-Row $fp 'abs' 44; Add-Row $fp 'abs' 56
$l1 = New-Lbl 'Tipo da mensagem' 200; $l1.Dock = 'Fill'; $l1.TextAlign = 'BottomLeft'
$fp.Controls.Add($l1, 0, 0)
$script:cmbFbTipo = New-Object System.Windows.Forms.ComboBox
$script:cmbFbTipo.Name = 'fbtipo'; $script:cmbFbTipo.Tag = 'i18n'; $script:cmbFbTipo.DropDownStyle = 'DropDownList'; $script:cmbFbTipo.Width = 260
foreach ($it in @('Sugestão', 'Problema (bug)', 'Dúvida', 'Elogio')) { [void]$script:cmbFbTipo.Items.Add($it) }
$script:cmbFbTipo.SelectedIndex = 0
$fp.Controls.Add($script:cmbFbTipo, 0, 1)
$l2 = New-Lbl 'Sua mensagem' 200; $l2.Dock = 'Fill'; $l2.TextAlign = 'BottomLeft'
$fp.Controls.Add($l2, 0, 2)
$script:txtFbMsg = New-Object System.Windows.Forms.TextBox
$script:txtFbMsg.Multiline = $true; $script:txtFbMsg.ScrollBars = 'Vertical'; $script:txtFbMsg.Dock = 'Fill'; $script:txtFbMsg.MaxLength = 3000
$fp.Controls.Add($script:txtFbMsg, 0, 3)
$l3 = New-Lbl 'Seu e-mail (opcional, só se quiser resposta)' 360; $l3.Dock = 'Fill'; $l3.TextAlign = 'BottomLeft'
$fp.Controls.Add($l3, 0, 4)
$script:txtFbMail = New-Object System.Windows.Forms.TextBox
$script:txtFbMail.Dock = 'Top'; $script:txtFbMail.MaxLength = 120
$fp.Controls.Add($script:txtFbMail, 0, 5)
$script:chkFbTec = New-Object System.Windows.Forms.CheckBox
$script:chkFbTec.Text = 'Incluir informações técnicas (versão do programa e do Windows, tipo de conexão)'; $script:chkFbTec.AutoSize = $false; $script:chkFbTec.Dock = 'Fill'; $script:chkFbTec.Checked = $true
$fp.Controls.Add($script:chkFbTec, 0, 6)
$tbFb = New-Toolbar
$script:btnFbSend = New-Btn 'Enviar' { Start-FeedbackSend } 110
[void]$tbFb.Controls.Add($script:btnFbSend)
[void]$tbFb.Controls.Add((New-Btn 'Abrir no meu e-mail' { Open-FeedbackMail } 180))
$fp.Controls.Add($tbFb, 0, 7)
$script:lblFbStatus = New-Object System.Windows.Forms.Label
$script:lblFbStatus.Tag = 'muted'; $script:lblFbStatus.Dock = 'Fill'; $script:lblFbStatus.Padding = (New-Object System.Windows.Forms.Padding(4, 4, 4, 0))
$fp.Controls.Add($script:lblFbStatus, 0, 8)
$mid2.Controls.Add($fp, 1, 0)
$tSp.Controls.Add($mid2, 0, 2)
$pgSupp.Controls.Add($tSp)
$tabs.TabPages.Add($pgSupp)

# ordem final e abas em duas linhas
$ordem = @('Assistente', 'Monitor', 'Diagnóstico', 'Rota', 'Histórico', 'Rede', 'Wi-Fi', 'Texto para o suporte', 'Este PC', 'Saúde dos discos', 'Ferramentas DNS', 'Desempenho em jogos', 'Atualizações', 'Suporte')
$todas = @(); foreach ($pg in $tabs.TabPages) { $todas += $pg }
$tabs.TabPages.Clear()
foreach ($nm in $ordem) { foreach ($pg in $todas) { if ($pg.Text -eq $nm) { [void]$tabs.TabPages.Add($pg) } } }
foreach ($pg in $todas) { if ($tabs.TabPages.IndexOf($pg) -lt 0) { [void]$tabs.TabPages.Add($pg) } }
$tabs.Multiline = $true
$tabs.ItemSize = New-Object System.Drawing.Size(122, 28)

# ----- bandeja do sistema
$script:notify = New-Object System.Windows.Forms.NotifyIcon
$icoPath = Join-Path $PSScriptRoot 'NetDoctor.ico'
try {
    if (Test-Path $icoPath) {
        # usa o quadro do .ico do tamanho exato da bandeja (16 px em 100% de escala) em vez de reduzir o de 32 px
        $tam = [System.Windows.Forms.SystemInformation]::SmallIconSize
        $script:trayNormal = New-Object System.Drawing.Icon($icoPath, $tam)
        $bmp = New-Object System.Drawing.Bitmap($tam.Width, $tam.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gx = [System.Drawing.Graphics]::FromImage($bmp)
        $gx.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gx.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gx.DrawIcon($script:trayNormal, (New-Object System.Drawing.Rectangle(0, 0, $tam.Width, $tam.Height)))
        $dp = [int][math]::Max(5, [math]::Round($tam.Width * 0.5))
        $px = $tam.Width - $dp - 1; $py = $tam.Height - $dp - 1
        $gx.FillEllipse([System.Drawing.Brushes]::White, ($px - 1), ($py - 1), ($dp + 2), ($dp + 2))
        $gx.FillEllipse([System.Drawing.Brushes]::Red, $px, $py, $dp, $dp)
        $gx.Dispose()
        $hic = $bmp.GetHicon()
        $script:trayAlert = [System.Drawing.Icon]([System.Drawing.Icon]::FromHandle($hic)).Clone()
        [void][NetDoctorNative.Api]::DestroyIcon($hic)
        $bmp.Dispose()
        $script:notify.Icon = $script:trayNormal
    } else { $script:notify.Icon = [System.Drawing.SystemIcons]::Application }
} catch { $script:notify.Icon = [System.Drawing.SystemIcons]::Application }
$script:notify.Text = 'NetDoctor'
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Abrir NetDoctor', $null, { Show-MainWindow })
[void]$menu.Items.Add('Iniciar / parar o monitor', $null, { Toggle-MonitorTray })
[void]$menu.Items.Add('Sair', $null, { Exit-App })
$script:notify.ContextMenuStrip = $menu
$script:notify.Add_DoubleClick({ Show-MainWindow })
$script:notify.Visible = $true
$script:form.Add_Resize({
    try { if ($script:form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized -and $script:chkTray.Checked) { $script:form.Hide() } } catch { }
})

$tabs.Add_SelectedIndexChanged({
    param($sender, $e)
    try {
        $nome = Get-TabKey $sender.SelectedTab
        if ($nome -eq 'Desempenho em jogos' -and -not $script:GamesLoaded) { $script:GamesLoaded = $true; Refresh-GameList }
        if ($nome -eq 'Este PC' -and -not $script:HwLoaded) {
            $script:HwLoaded = $true
            Start-HwInfo
            if ($script:chkTemp.Checked) { Start-HwLive }
        }
        if ($nome -eq 'Saúde dos discos' -and -not $script:DiskLoaded) { $script:DiskLoaded = $true; Start-DiskInfo }
        if ($nome -eq 'Wi-Fi' -and -not $script:WifiLoaded) { $script:WifiLoaded = $true; Start-Wifi }
        if ($nome -eq 'Suporte') { Update-SupportInfo }
        if ($nome -eq 'Atualizações' -and -not $script:UpdOk -and -not $script:UpdChecking) { Start-UpdateCheck -Manual }
        if ($nome -eq 'Histórico' -and -not $script:HistLoaded) { $script:HistLoaded = $true; Fill-HistTargets; Start-HistLoad }
    } catch { Log-Error $_ }
})

# ------------------------------------------------------------ eventos e partida
Apply-Language
Apply-Theme
$script:timer = New-Object System.Windows.Forms.Timer
$script:timer.Interval = 250
$script:timer.Add_Tick({ try { Drain-All } catch { Log-Error $_ } })

$script:form.Add_Shown({
    try {
        Rebuild-List
        if ($script:lv.Items.Count -gt 0) {
            $first = 0
            for ($i = 0; $i -lt $script:Targets.Count; $i++) { if ($script:Targets[$i].Role -eq 'destino') { $first = $i; break } }
            $script:lv.Items[$first].Selected = $true
        }
        Set-Cue $script:txtProv 'sua operadora'
        Set-Cue $script:txtPlano 'ex.: 500 Mega'
        Set-Cue $script:txtDns1 'ex.: 1.1.1.1'
        Set-Cue $script:txtDns2 'opcional'
        $script:NetSig = Get-NetSigLite
        [void](Start-NetInfoAsync 'start')
        foreach ($p in $script:DnsProviders) { [void]$script:DnsItems.Add([pscustomobject]@{ Nome = $p.Nome; Dns1 = $p.Dns1; Dns2 = $p.Dns2; Nota = $p.Nota; Media = $null; Falhas = 0; Ping = $null; Testado = $false; Filtra = [bool]$p.Filtra }) }
        Fill-DnsList
        Update-Verdict
        $script:cmbTheme.Left = [math]::Max(320, $script:header.ClientSize.Width - $script:cmbTheme.Width - 150); $script:cmbLang.Left = $script:cmbTheme.Left - $script:cmbLang.Width - 10
        Apply-Theme
        $script:timer.Start()
        if ([bool]$script:Cfg.AutoMonitor) {
            Start-Monitor
            if ([bool]$script:Cfg.Bandeja) { $script:form.WindowState = [System.Windows.Forms.FormWindowState]::Minimized }
        }
    } catch { Log-Error $_ }
})
$script:form.Add_FormClosing({ try { Stop-HwLive; Stop-Route; Stop-Monitor; Flush-HistBuckets; Sync-Cfg; $script:notify.Visible = $false; $script:notify.Dispose() } catch { } })
$script:form.Add_FormClosed({ [Environment]::Exit(0) })

try {
    [System.Windows.Forms.Application]::Run($script:form)
} catch {
    Log-Error $_
    [void][System.Windows.Forms.MessageBox]::Show(('Erro: ' + $_.Exception.Message + "`r`nDetalhes em: " + (Join-Path (Get-AppDir) 'erro.log')), 'NetDoctor')
}
