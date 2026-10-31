# NetDoctor - ferramentas de DNS e reparo de rede (nativas, sem programas de terceiros).
# Carregado por NetDoctor.ps1. Alterar o DNS exige permissao de administrador (o Windows pede na hora).

$script:DnsProviders = @(
    [pscustomobject]@{ Nome = 'US - Google Public DNS'; Dns1 = '8.8.8.8'; Dns2 = '8.8.4.4'; Nota = 'estável e muito usado'; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - OpenDNS'; Dns1 = '208.67.222.222'; Dns2 = '208.67.220.220'; Nota = 'Cisco'; Filtra = $false },
    [pscustomobject]@{ Nome = 'RU - Yandex'; Dns1 = '77.88.8.1'; Dns2 = '77.88.8.8'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'Cloudflare'; Dns1 = '1.1.1.1'; Dns2 = '1.0.0.1'; Nota = 'rápido e focado em privacidade'; Filtra = $false },
    [pscustomobject]@{ Nome = 'Cloudflare (bloqueia malware)'; Dns1 = '1.1.1.2'; Dns2 = '1.0.0.2'; Nota = 'bloqueia sites maliciosos'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - Norton ConnectSafe'; Dns1 = '199.85.126.10'; Dns2 = '199.85.127.10'; Nota = 'serviço antigo, pode não responder mais'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - Level 3 - A'; Dns1 = '209.244.0.3'; Dns2 = '209.244.0.4'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Level 3 - B'; Dns1 = '4.2.2.1'; Dns2 = '4.2.2.2'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Level 3 - C'; Dns1 = '4.2.2.3'; Dns2 = '4.2.2.4'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Level 3 - D'; Dns1 = '4.2.2.5'; Dns2 = '4.2.2.6'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Comodo Secure'; Dns1 = '8.26.56.26'; Dns2 = '8.20.247.20'; Nota = 'filtro de segurança'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - Dyn'; Dns1 = '216.146.35.35'; Dns2 = '216.146.36.36'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Norton DNS'; Dns1 = '198.153.192.1'; Dns2 = '198.153.194.1'; Nota = 'filtra sites'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - Comodo'; Dns1 = '156.154.70.22'; Dns2 = '156.154.71.22'; Nota = 'filtra sites'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - VeriSign Public DNS'; Dns1 = '64.6.64.6'; Dns2 = '64.6.65.6'; Nota = 'sem redirecionar erros'; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Qwest'; Dns1 = '205.171.3.65'; Dns2 = '205.171.2.65'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'RU - Safe DNS'; Dns1 = '195.46.39.39'; Dns2 = '195.46.39.40'; Nota = 'filtra sites'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - UltraDNS'; Dns1 = '204.69.234.1'; Dns2 = '204.74.101.1'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'GB - Zen Internet'; Dns1 = '212.23.8.1'; Dns2 = '212.23.3.1'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'GB - Orange DNS'; Dns1 = '195.92.195.94'; Dns2 = '195.92.195.95'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Hurricane Electric'; Dns1 = '74.82.42.42'; Dns2 = ''; Nota = 'só um endereço'; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Neustar 1'; Dns1 = '156.154.70.1'; Dns2 = '156.154.71.1'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - Neustar 2'; Dns1 = '156.154.70.5'; Dns2 = '156.154.71.5'; Nota = 'filtra sites'; Filtra = $true },
    [pscustomobject]@{ Nome = 'RU - AdGuard'; Dns1 = '94.140.14.14'; Dns2 = '94.140.15.15'; Nota = 'bloqueia anúncios e rastreadores'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - Quad9 Security'; Dns1 = '9.9.9.9'; Dns2 = '149.112.112.112'; Nota = 'bloqueia sites maliciosos'; Filtra = $true },
    [pscustomobject]@{ Nome = 'US - Quad9 No Security'; Dns1 = '9.9.9.10'; Dns2 = '149.112.112.112'; Nota = 'sem bloqueio'; Filtra = $false },
    [pscustomobject]@{ Nome = 'US - NextDNS'; Dns1 = '45.90.28.230'; Dns2 = '45.90.30.230'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'DE - DNS4EU'; Dns1 = '86.54.11.100'; Dns2 = '86.54.11.200'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'DNSPorta Online Telecom'; Dns1 = '191.7.213.230'; Dns2 = '191.7.213.231'; Nota = ''; Filtra = $false },
    [pscustomobject]@{ Nome = 'CleanBrowsing (família)'; Dns1 = '185.228.168.168'; Dns2 = '185.228.169.168'; Nota = 'filtro de conteúdo adulto'; Filtra = $true }
)

function Test-IPv4([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    if ($s -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    $a = $null
    if (-not [System.Net.IPAddress]::TryParse($s, [ref]$a)) { return $false }
    if ($s -eq '0.0.0.0' -or $s -eq '255.255.255.255') { return $false }
    $true
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { $false }
}

# Roda um comando PowerShell com privilegios de administrador (aparece o aviso do Windows).
# Retorna o codigo de saida, ou $null se o usuario recusou a permissao.
function Invoke-Elevated([string]$Script, [switch]$NoWait, [switch]$Visible) {
    $enc = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($Script))
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-EncodedCommand', $enc)
    if ($Visible) { $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc) }
    try {
        if ($NoWait) {
            if (Test-IsAdmin) { [void](Start-Process -FilePath 'powershell.exe' -ArgumentList $args2) }
            else { [void](Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -Verb RunAs) }
            return 0
        }
        if (Test-IsAdmin) { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -PassThru -Wait }
        else { $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -Verb RunAs -PassThru -Wait }
        return [int]$p.ExitCode
    } catch { return $null }
}

# Funcoes de leitura de DNS: definidas uma vez, executadas aqui e nos runspaces de fundo.
$script:DnsLib = @'
# 'automatico' (DHCP), 'manual' ou 'desconhecido'
function Get-DnsMode([int]$IfIndex) {
    try {
        $ad = Get-NetAdapter -InterfaceIndex $IfIndex -ErrorAction Stop
        $key = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\' + $ad.InterfaceGuid
        $ns = (Get-ItemProperty -Path $key -Name NameServer -ErrorAction Stop).NameServer
        if ([string]::IsNullOrWhiteSpace([string]$ns)) { return 'automatico' }
        return 'manual'
    } catch { return 'desconhecido' }
}
function Get-DnsServers([int]$IfIndex) {
    @(Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
}
# DNS IPv6 configurado (o Windows pode preferir este ao IPv4 escolhido). Ignora o endereco padrao antigo fec0:.
function Get-DnsServers6([int]$IfIndex) {
    @(Get-DnsClientServerAddress -InterfaceIndex $IfIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ -and $_ -notlike 'fec0:*' })
}
'@
. ([scriptblock]::Create($script:DnsLib))

# Le DNS do adaptador em segundo plano (evita travar a janela).
$script:DnsInfoCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    . ([scriptblock]::Create($Lib))
    $srv = @(Get-DnsServers $IfIndex)
    $v6 = @(Get-DnsServers6 $IfIndex)
    $modo = Get-DnsMode $IfIndex
    $Q.Enqueue(@{ Kind = 'dns-info'; IfIndex = $IfIndex; Servers = $srv; V6 = $v6; Modo = $modo })
}



function Save-DnsBackup([int]$IfIndex) {
    try {
        $ad = Get-NetAdapter -InterfaceIndex $IfIndex -ErrorAction Stop
        $o = [pscustomobject]@{
            Guid    = [string]$ad.InterfaceGuid
            Nome    = [string]$ad.Name
            Modo    = (Get-DnsMode $IfIndex)
            Servers = @(Get-DnsServers $IfIndex)
            Data    = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
        $o | ConvertTo-Json | Set-Content -Path (Join-Path (Get-AppDir) 'dns-backup.json') -Encoding UTF8
    } catch { Log-Error $_ }
}

function Read-DnsBackup {
    $p = Join-Path (Get-AppDir) 'dns-backup.json'
    if (-not (Test-Path $p)) { return $null }
    try { Get-Content -Path $p -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $null }
}

# Troca o DNS do adaptador (ou volta ao automatico com -Reset). Retorna @{ Ok; Msg }.
function Invoke-DnsChange([int]$IfIndex, [string[]]$Servers, [bool]$Reset) {
    if ($IfIndex -le 0) { return @{ Ok = $false; Msg = 'Nenhum adaptador selecionado.' } }
    if ($Reset) {
        $cmd = ('Set-DnsClientServerAddress -InterfaceIndex {0} -ResetServerAddresses' -f $IfIndex)
    } else {
        if (-not $Servers -or $Servers.Count -eq 0) { return @{ Ok = $false; Msg = 'Nenhum DNS informado.' } }
        foreach ($s in $Servers) {
            if (-not (Test-IPv4 $s)) { return @{ Ok = $false; Msg = ('Endereço DNS inválido: ' + $s) } }
        }
        $lista = ($Servers | ForEach-Object { "'" + $_ + "'" }) -join ','
        $cmd = ('Set-DnsClientServerAddress -InterfaceIndex {0} -ServerAddresses @({1})' -f $IfIndex, $lista)
    }
    $script2 = '$ErrorActionPreference = ''Stop''; try { ' + $cmd + '; Clear-DnsClientCache -ErrorAction SilentlyContinue; exit 0 } catch { exit 1 }'
    $code = Invoke-Elevated $script2
    if ($null -eq $code) { return @{ Ok = $false; Msg = 'Cancelado: a permissão de administrador não foi concedida.' } }
    if ($code -ne 0) { return @{ Ok = $false; Msg = 'O Windows recusou a alteração do DNS.' } }
    @{ Ok = $true; Msg = '' }
}

function Invoke-FlushDns {
    $code = Invoke-Elevated 'try { Clear-DnsClientCache -ErrorAction Stop; exit 0 } catch { exit 1 }'
    if ($null -eq $code) { return @{ Ok = $false; Msg = 'Cancelado: a permissão de administrador não foi concedida.' } }
    if ($code -ne 0) { return @{ Ok = $false; Msg = 'Não foi possível limpar o cache.' } }
    @{ Ok = $true; Msg = '' }
}

# ------------------------------------------------------------ toque ao mudar o DNS
$script:SoundPlayer = $null

function Get-DnsSoundPath {
    foreach ($p in @((Join-Path $PSScriptRoot 'Sounds\applepay.mp3'), (Join-Path $PSScriptRoot 'applepay.mp3'))) {
        if (Test-Path $p) { return $p }
    }
    $null
}

function Play-DnsSound {
    $p = Get-DnsSoundPath
    if ($p) {
        try {
            if (-not $script:SoundPlayer) {
                Add-Type -AssemblyName PresentationCore
                $script:SoundPlayer = New-Object System.Windows.Media.MediaPlayer
            }
            $script:SoundPlayer.Stop()
            $script:SoundPlayer.Open((New-Object System.Uri($p)))
            $script:SoundPlayer.Play()
            return
        } catch { Log-Error $_ }
    }
    try { [System.Media.SystemSounds]::Asterisk.Play() } catch { }
}

# Reparo de rede: limpa caches e renova o IP. -Winsock tambem redefine Winsock e TCP/IP (exige reiniciar o PC).
function Invoke-NetRepair([bool]$Winsock) {
    $cmd = 'ipconfig /flushdns | Out-Null; netsh interface ip delete arpcache | Out-Null; ipconfig /release | Out-Null; ipconfig /renew | Out-Null; exit 0'
    if ($Winsock) { $cmd = 'netsh winsock reset | Out-Null; netsh int ip reset | Out-Null; ' + $cmd }
    $code = Invoke-Elevated $cmd -NoWait
    if ($null -eq $code) { return @{ Ok = $false; Msg = 'Cancelado: a permissão de administrador não foi concedida.' } }
    @{ Ok = $true; Msg = '' }
}
