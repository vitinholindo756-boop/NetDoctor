# NetDoctor - tarefas de fundo (diagnostico, varredura da rede, snapshot).
# Cada bloco roda num runspace proprio e fala com a janela pela fila $Q.

$script:DiagCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    Add-Type -AssemblyName System.Net.Http
    . ([scriptblock]::Create($Lib))

    function Emit([string]$t, [string]$c = 'Gray') { $Q.Enqueue(@{ Kind = 'diag-line'; Text = $t; Color = $c }) }
    function Achado([string]$t) { [void]$script:achados.Add($t); $Q.Enqueue(@{ Kind = 'diag-find'; Text = $t }) }
    function Meta([string]$k, $v) { $Q.Enqueue(@{ Kind = 'diag-meta'; Key = $k; Value = $v }) }
    function Prog([string]$t) { $Q.Enqueue(@{ Kind = 'diag-prog'; Text = $t }) }
    function Head([string]$t) { Emit ''; Emit ('=== ' + $t + ' ===') 'Cyan' }

    function Linha([string]$rot, $r) {
        if ($null -eq $r.Media) { Emit ('{0,-24} SEM RESPOSTA ({1} de {2} perdidos)' -f $rot, $r.Perdidos, $r.Enviados) 'Red' }
        else { Emit ('{0,-24} perda {1}% | mín {2} ms | média {3} ms | máx {4} ms' -f $rot, (Fmt $r.Pct), (Fmt $r.Min 0), (Fmt $r.Media), (Fmt $r.Max 0)) }
    }

    try {
        $script:achados = New-Object 'System.Collections.Generic.List[string]'
        Emit ('Data/hora: ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')) 'DarkGray'

        # ---------- adaptador
        $rota = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if (-not $rota) { Emit 'Sem conexão de rede ativa (nenhuma rota padrão). Verifique o cabo.' 'Red'; throw 'sem rede' }
        $gw = [string]$rota.NextHop
        $ad = Get-NetAdapter -InterfaceIndex $rota.InterfaceIndex
        Head 'Adaptador de rede ativo'
        Emit ('Nome:               ' + $ad.Name)
        Emit ('Descrição:          ' + $ad.InterfaceDescription)
        Emit ('Velocidade do link: ' + $ad.LinkSpeed)
        Emit ('Roteador (gateway): ' + $gw)
        if ($ad.Speed -and $ad.Speed -lt 1000000000) {
            Emit 'ATENÇÃO: o link negociou menos de 1 Gbps. Isso limita planos acima de 100 Mbps (cabo, conector ou placa antiga).' 'Yellow'
            Achado ('Link de rede abaixo de 1 Gbps (' + $ad.LinkSpeed + '): pode limitar a velocidade. Teste outro cabo.')
        }
        $pm = Get-NetAdapterPowerManagement -Name $ad.Name
        if ($pm -and [string]$pm.AllowComputerToTurnOffDevice -eq 'Enabled') {
            Emit 'ATENÇÃO: o Windows pode desligar esta placa de rede para economizar energia (pode causar quedas e picos).' 'Yellow'
            Achado 'A economia de energia da placa de rede está ligada: se houver quedas, desmarque "Permitir que o computador desligue este dispositivo" nas propriedades do adaptador (Gerenciador de Dispositivos > Gerenciamento de Energia).'
        }
        $st = Get-NetAdapterStatistics -Name $ad.Name
        if ($st) {
            $erros = [int64]$st.ReceivedPacketErrors + [int64]$st.OutboundPacketErrors
            $desc = [int64]$st.ReceivedDiscardedPackets + [int64]$st.OutboundDiscardedPackets
            Emit ('Erros de pacote desde que o PC ligou: {0} | descartados: {1}' -f $erros, $desc)
            if ($erros -gt 0) { Achado ('A placa de rede registrou {0} erros de pacote: suspeite de cabo, conector ou placa.' -f $erros) }
        }

        # ---------- ping local e externo
        Prog 'Medindo até o roteador...'
        Head 'Latência até o roteador (30 testes)'
        $rg = PingN $gw 30 150
        Linha ('Roteador ' + $gw) $rg
        if ($rg.Pct -gt 0) { Achado ('Perda de pacotes até o próprio roteador ({0}%): problema local (cabo, placa ou roteador).' -f (Fmt $rg.Pct)) }
        elseif ($rg.Max -gt 30) { Achado ('Picos de até {0} ms até o roteador: problema local intermitente.' -f $rg.Max) }

        Prog 'Medindo até a internet...'
        Head 'Latência até a internet (30 testes)'
        $re = PingN $PingExterno 30 150
        Linha ('Internet ' + $PingExterno) $re
        Meta 'Jitter' $re.Jitter; Meta 'Loss' $re.Pct; Meta 'LossLocal' $rg.Pct; Meta 'Idle' $re.Media
        if ($re.Pct -gt 0) { Achado ('Perda de pacotes até a internet ({0}%): problema entre o roteador e a operadora.' -f (Fmt $re.Pct)) }

        # ---------- DNS
        Prog 'Medindo DNS...'
        Head 'DNS configurado'
        $dnsLista = @(Get-DnsClientServerAddress -InterfaceIndex $rota.InterfaceIndex -AddressFamily IPv4 | ForEach-Object { $_.ServerAddresses } | Where-Object { $_ })
        foreach ($d in $dnsLista) {
            $tempos = foreach ($nome in 'google.com', 'cloudflare.com', 'youtube.com', 'wikipedia.org', 'microsoft.com') {
                (Measure-Command { Resolve-DnsName $nome -Server $d -Type A -DnsOnly }).TotalMilliseconds
            }
            $media = ($tempos | Measure-Object -Average).Average
            Emit ('DNS {0,-16} resolução média: {1} ms' -f $d, (Fmt $media))
        }

        # ---------- destinos (TCP)
        Head 'Comparação de destinos (conexão TCP, 40 testes cada)'
        $res = @{}
        foreach ($a in $Targets) {
            if ($a.Role -ne 'controle' -and $a.Role -ne 'destino') { continue }
            if ([int]$a.Porta -le 0) { continue }
            Prog ('Medindo ' + $a.Nome + '...')
            $r = TcpN $a.Destino ([int]$a.Porta) 40 300
            $pct = [math]::Round(($r.Perdidos + $r.Picos) / $r.Enviados * 100, 1)
            $res[$a.Nome] = @{ Pct = $pct; Role = $a.Role }
            if ($null -eq $r.Media) { Emit ('{0,-12} {1}:{2}  SEM RESPOSTA' -f $a.Nome, $a.Destino, $a.Porta) 'Red' }
            else { Emit ('{0,-12} {1}:{2}  problemas {3}% (falhas {4}, picos {5}) | média {6} ms | máx {7} ms' -f $a.Nome, $a.Destino, $a.Porta, (Fmt $pct), $r.Perdidos, $r.Picos, (Fmt $r.Media), (Fmt $r.Max 0)) }
        }
        $ctlPct = 0.0
        foreach ($k in $res.Keys) { if ($res[$k].Role -eq 'controle') { $ctlPct = $res[$k].Pct } }
        foreach ($k in $res.Keys) {
            if ($res[$k].Role -eq 'destino' -and $res[$k].Pct -ge ($ctlPct + 3)) {
                Achado ('Perda concentrada em {0} ({1}%) com o controle limpo ({2}%): indício de rota ruim até esse destino ou problema nele, não da sua linha.' -f $k, (Fmt $res[$k].Pct), (Fmt $ctlPct))
            }
        }

        # ---------- velocidade
        if ($DoSpeed) {
            Head 'Velocidade e atraso sob carga (Cloudflare)'
            Prog 'Medindo atraso parado...'
            $base = PingN $PingExterno 15 150
            Linha 'Ping parado' $base
            Prog 'Download (2 rodadas, 4 conexões)...'
            $mbd = 15
            if ($PlanoMbps) { $mbd = [math]::Max(5, [math]::Min(30, [int]([double]$PlanoMbps * 0.1875))) }
            $down = Carga 'down' ('https://speed.cloudflare.com/__down?bytes=' + ($mbd * 1000000)) 2 $mbd
            Emit ('Download: melhor {0} Mbps (4 conexões; rodadas: {1}) - valores aproximados' -f (Fmt $down.Melhor), $down.Rodadas)
            Linha 'Ping durante download' $down.Ping
            Prog 'Upload (2 rodadas, 3 conexões)...'
            $up = Carga 'up' 'https://speed.cloudflare.com/__up' 2 8
            Emit ('Upload:   melhor {0} Mbps (3 conexões; rodadas: {1}) - valores aproximados' -f (Fmt $up.Melhor), $up.Rodadas)
            Linha 'Ping durante upload' $up.Ping
            Meta 'Down' $down.Melhor; Meta 'Up' $up.Melhor; Meta 'Idle' $base.Media
            Meta 'LoadDown' $down.Ping.Media; Meta 'LoadUp' $up.Ping.Media
            foreach ($par in @(@('download', $down.Ping), @('upload', $up.Ping))) {
                $m = $par[1].Media
                if ($null -ne $m -and $null -ne $base.Media -and ($m - $base.Media) -gt 100) {
                    Achado ('O atraso sobe {0} ms durante o {1}: fila no roteador ou na operadora (bufferbloat).' -f [math]::Round($m - $base.Media), $par[0])
                }
            }
        }

        # ---------- rota
        Prog 'Rastreando rota (uns 30 segundos)...'
        Head 'Rota até 8.8.8.8 (tracert)'
        $tr = tracert -d -h 14 -w 1000 8.8.8.8
        foreach ($l in $tr) { if ($l -and $l.Trim()) { Emit ([string]$l) } }

        # ---------- conclusao
        Head 'O que isso indica'
        if ($script:achados.Count -eq 0) {
            Emit 'Nada de errado nesta rodada. Perdas raras podem não aparecer em poucos minutos: use a aba Monitor por 10 a 15 minutos, de preferência jogando.' 'Green'
        } else {
            foreach ($x in $script:achados) { Emit ('- ' + $x) 'Yellow' }
            Emit 'São indícios, não prova: confirme repetindo o teste e comparando com o controle.' 'DarkGray'
        }
    } catch {
        Emit ('Erro durante o diagnóstico: ' + $_.Exception.Message) 'Red'
    }
    $Q.Enqueue(@{ Kind = 'diag-done' })
}

$script:ScanCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        if (-not $r) { $Q.Enqueue(@{ Kind = 'scan-done'; Count = 0; Msg = 'Sem rede ativa.' }); return }
        $gw = [string]$r.NextHop
        $ip = Get-NetIPAddress -InterfaceIndex $r.InterfaceIndex -AddressFamily IPv4 | Select-Object -First 1
        $base = (($ip.IPAddress -split '\.')[0..2]) -join '.'
        $Q.Enqueue(@{ Kind = 'scan-prog'; Text = ('Varrendo {0}.1 a {0}.254...' -f $base) })
        $tarefas = 1..254 | ForEach-Object {
            $pp = New-Object System.Net.NetworkInformation.Ping
            $pp.SendPingAsync(('{0}.{1}' -f $base, $_), 800)
        }
        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($tarefas), 8000) } catch { }
        $viz = @(Get-NetNeighbor -AddressFamily IPv4 -InterfaceIndex $r.InterfaceIndex | Where-Object {
            $_.State -ne 'Unreachable' -and $_.State -ne 'Incomplete' -and $_.LinkLayerAddress -and
            $_.IPAddress -like ($base + '.*') -and $_.IPAddress -notlike '*.255' -and $_.LinkLayerAddress -ne 'FF-FF-FF-FF-FF-FF'
        } | Sort-Object { [int](($_.IPAddress -split '\.')[3]) })
        $nomes = @{}
        foreach ($v in $viz) { $nomes[$v.IPAddress] = [System.Net.Dns]::GetHostEntryAsync($v.IPAddress) }
        try { [void][System.Threading.Tasks.Task]::WaitAll([System.Threading.Tasks.Task[]]@($nomes.Values), 3000) } catch { }
        foreach ($v in $viz) {
            $nota = ''
            if ($v.IPAddress -eq $gw) { $nota = 'roteador' }
            if ($v.IPAddress -eq $ip.IPAddress) { $nota = 'este PC' }
            $nome = ''
            $tk = $nomes[$v.IPAddress]
            if ($tk -and $tk.IsCompleted -and -not $tk.IsFaulted) { $nome = [string]$tk.Result.HostName }
            $Q.Enqueue(@{ Kind = 'scan-dev'; Ip = [string]$v.IPAddress; Mac = [string]$v.LinkLayerAddress; Nome = $nome; Nota = $nota })
        }
        $Q.Enqueue(@{ Kind = 'scan-done'; Count = $viz.Count; Msg = '' })
    } catch {
        $Q.Enqueue(@{ Kind = 'scan-done'; Count = 0; Msg = ('Erro: ' + $_.Exception.Message) })
    }
}

$script:SnapCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    try {
        function Sec([string]$t) { Add-Content -Path $OutFile -Value ("`r`n=== " + $t + ' ===') -Encoding UTF8 }
        Set-Content -Path $OutFile -Value ('Configuração de rede deste PC - ' + (Get-Date -Format 'dd/MM/yyyy HH:mm:ss')) -Encoding UTF8
        $r = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        Sec 'ipconfig /all'; Add-Content -Path $OutFile -Value (ipconfig /all | Out-String) -Encoding UTF8
        Sec 'Tabela de rotas'; Add-Content -Path $OutFile -Value (route print | Out-String) -Encoding UTF8
        Sec 'Adaptadores'
        Add-Content -Path $OutFile -Value (Get-NetAdapter | Format-List Name, InterfaceDescription, Status, LinkSpeed, MediaType, DriverVersion, DriverDate, MacAddress | Out-String) -Encoding UTF8
        if ($r) {
            $ad = Get-NetAdapter -InterfaceIndex $r.InterfaceIndex
            Sec ('Opções avançadas do adaptador ativo (' + $ad.Name + ')')
            Add-Content -Path $OutFile -Value (Get-NetAdapterAdvancedProperty -Name $ad.Name | Format-Table DisplayName, DisplayValue -AutoSize | Out-String) -Encoding UTF8
        }
        Sec 'TCP global'; Add-Content -Path $OutFile -Value (netsh int tcp show global | Out-String) -Encoding UTF8
        Sec 'DNS configurado'
        Add-Content -Path $OutFile -Value (Get-DnsClientServerAddress | Format-Table InterfaceAlias, AddressFamily, ServerAddresses -AutoSize | Out-String) -Encoding UTF8
        $Q.Enqueue(@{ Kind = 'snap-done'; Path = $OutFile; Msg = '' })
    } catch {
        $Q.Enqueue(@{ Kind = 'snap-done'; Path = $OutFile; Msg = ('Erro: ' + $_.Exception.Message) })
    }
}

# Mede a velocidade de resposta de servidores DNS (consulta UDP direta, com tempo limite).
$script:DnsTestCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    function Query-Dns([string]$server, [string]$name, [int]$timeoutMs) {
        $id = Get-Random -Maximum 65535
        $bytes = New-Object 'System.Collections.Generic.List[byte]'
        $bytes.Add([byte]($id -shr 8)); $bytes.Add([byte]($id -band 255))
        $bytes.AddRange([byte[]](1, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        foreach ($lbl in $name.Split('.')) {
            $b = [System.Text.Encoding]::ASCII.GetBytes($lbl)
            $bytes.Add([byte]$b.Length); $bytes.AddRange($b)
        }
        $bytes.Add(0)
        $bytes.AddRange([byte[]](0, 1, 0, 1))
        $udp = New-Object System.Net.Sockets.UdpClient
        try {
            $udp.Client.ReceiveTimeout = $timeoutMs
            $udp.Connect($server, 53)
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            [void]$udp.Send($bytes.ToArray(), $bytes.Count)
            $ep = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
            $r = $udp.Receive([ref]$ep)
            $sw.Stop()
            $rcode = $r[3] -band 15
            $respostas = ($r[6] * 256) + $r[7]
            if ($r.Length -ge 12 -and $r[0] -eq $bytes[0] -and $r[1] -eq $bytes[1] -and $rcode -eq 0 -and $respostas -gt 0) { return $sw.Elapsed.TotalMilliseconds }
            return -1.0
        } catch { return -1.0 } finally { $udp.Close() }
    }
    try {
        $dominios = 'google.com', 'youtube.com', 'wikipedia.org', 'microsoft.com', 'amazon.com'
        $ping = New-Object System.Net.NetworkInformation.Ping
        for ($i = 0; $i -lt $Items.Count; $i++) {
            $srv = [string]$Items[$i].Dns
            $Q.Enqueue(@{ Kind = 'dns-prog'; Text = ('Testando {0} ({1} de {2})...' -f $srv, ($i + 1), $Items.Count) })
            $tempos = New-Object 'System.Collections.Generic.List[double]'
            $falhas = 0; $seguidas = 0
            foreach ($d in $dominios) {
                $a = Query-Dns $srv $d 1500          # aquece o cache do servidor
                if ($a -lt 0) {
                    $falhas++; $seguidas++
                    if ($seguidas -ge 2) { $falhas = $dominios.Count; $tempos.Clear(); break }
                    continue
                }
                $seguidas = 0
                $t = Query-Dns $srv $d 1500          # medida valida
                if ($t -ge 0) { $tempos.Add($t) } else { $falhas++ }
            }
            $media = $null
            if ($tempos.Count -gt 0) { $media = [math]::Round(($tempos | Measure-Object -Average).Average, 1) }
            $pg = $null
            try { $r = $ping.Send($srv, 1500); if ($r.Status -eq 'Success') { $pg = [double]$r.RoundtripTime } } catch { }
            $Q.Enqueue(@{ Kind = 'dns-row'; Idx = $i; Media = $media; Falhas = $falhas; Ping = $pg })
        }
    } catch { }
    $Q.Enqueue(@{ Kind = 'dns-done' })
}

# Descobre IP publico e provedor (so quando o usuario clica; consulta ipinfo.io).
$script:PubCode = {
    $ErrorActionPreference = 'Stop'
    try {
        $r = Invoke-RestMethod -Uri 'https://ipinfo.io/json' -TimeoutSec 8
        $org = ([string]$r.org) -replace '^AS\d+\s*', ''
        $Q.Enqueue(@{ Kind = 'pub-done'; Ip = [string]$r.ip; Org = $org; Msg = '' })
    } catch {
        $Q.Enqueue(@{ Kind = 'pub-done'; Ip = ''; Org = ''; Msg = 'Não foi possível consultar (sem internet?).' })
    }
}
