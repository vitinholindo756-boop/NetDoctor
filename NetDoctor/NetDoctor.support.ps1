# NetDoctor - suporte: perguntas frequentes, formulario de sugestoes (Google Apps Script), pacote de suporte.
# O e-mail do dono NAO fica no programa: o formulario envia para um script do Google que repassa para o Gmail do dono.
# Configure em NetDoctor.contato.ps1.

$script:FaqData = @{
    pt = @(
        @{ P = 'O NetDoctor muda algo no meu PC?'; R = 'Monitor, Diagnóstico, Rota, Histórico, Wi-Fi, discos e hardware só leem informações. Só mudam algo: Ferramentas DNS (troca de DNS), Desempenho em jogos, Reparar rede e Iniciar com o Windows. Todos pedem confirmação e, quando possível, guardam backup para voltar atrás.' },
        @{ P = 'O que o programa envia pela internet?'; R = 'Nada além do que você usa: o teste de velocidade fala com a Cloudflare; "Detectar" consulta o ipinfo.io; a aba Atualizações consulta o GitHub; o formulário desta aba envia só o que você escrever. O monitor faz pings e conexões TCP aos destinos que você escolheu. Seus históricos ficam no seu PC, em %APPDATA%\NetDoctor.' },
        @{ P = 'Por que a temperatura aparece como indisponível?'; R = 'O Windows não expõe sensores de CPU/GPU sem driver. Abra o LibreHardwareMonitor (gratuito) ou use uma placa NVIDIA e o NetDoctor passa a mostrar os valores.' },
        @{ P = 'O antivírus reclamou do NetDoctor.'; R = 'O programa é um conjunto de scripts do PowerShell sem assinatura digital. Ferramentas que consultam a rede, trocam DNS e se atualizam às vezes são marcadas por engano. Baixe só da página oficial do projeto, confira o SHA256 da versão e, se quiser, envie o arquivo ao VirusTotal.' },
        @{ P = 'Como desfaço uma otimização ou troca de DNS?'; R = 'Desempenho em jogos > Reverter. Ferramentas DNS > Restaurar anterior ou Automático (DHCP). O ponto de restauração do Windows também serve.' },
        @{ P = 'Como comparo com o plano da operadora?'; R = 'Informe o plano em Texto para o suporte, rode o Diagnóstico com o teste de velocidade várias vezes, em dias e horários diferentes, e veja a média do mês. As metas da Anatel citadas são só indicativo.' },
        @{ P = 'O problema acontece só às vezes. E agora?'; R = 'Deixe o Monitor ligado (de preferência na bandeja, com alertas) e veja a aba Histórico; depois gere o relatório HTML para enviar à operadora.' },
        @{ P = 'O que é o pacote de suporte?'; R = 'Um arquivo zip com versão, erros e históricos (sem o seu nome de usuário) para você enviar quando algo der errado. Revise o conteúdo antes de enviar.' }
    )
    en = @(
        @{ P = 'Does NetDoctor change anything on my PC?'; R = 'Monitor, Diagnostics, Route, History, Wi-Fi, disks and hardware only read information. Only these change something: DNS tools (switching DNS), Gaming performance, Repair network and Start with Windows. All ask for confirmation and, when possible, keep a backup so you can undo.' },
        @{ P = 'What does the program send over the internet?'; R = 'Nothing beyond what you use: the speed test talks to Cloudflare; "Detect" queries ipinfo.io; the Updates tab queries GitHub; the form on this tab sends only what you write. The monitor pings and opens TCP connections to the targets you chose. Your histories stay on your PC, in %APPDATA%\NetDoctor.' },
        @{ P = 'Why is the temperature shown as unavailable?'; R = 'Windows does not expose CPU/GPU sensors without a driver. Open LibreHardwareMonitor (free) or use an NVIDIA card and NetDoctor will show the values.' },
        @{ P = 'My antivirus flagged NetDoctor.'; R = 'The program is a set of unsigned PowerShell scripts. Tools that query the network, change DNS and update themselves are sometimes flagged by mistake. Download only from the official project page, check the release SHA256 and, if you like, upload the file to VirusTotal.' },
        @{ P = 'How do I undo an optimization or a DNS change?'; R = 'Gaming performance > Revert. DNS tools > Restore previous or Automatic (DHCP). A Windows restore point also works.' },
        @{ P = 'How do I compare with my ISP plan?'; R = 'Enter your plan on the Support text tab, run Diagnostics with the speed test several times on different days and hours, and check the monthly average. The regulator targets mentioned are only an indication.' },
        @{ P = 'The problem only happens sometimes. Now what?'; R = 'Leave the Monitor running (preferably in the tray, with alerts) and check the History tab; then create the HTML report to send to your ISP.' },
        @{ P = 'What is the support package?'; R = 'A zip file with version, errors and histories (without your user name) to send when something goes wrong. Review the contents before sending.' }
    )
    es = @(
        @{ P = '¿NetDoctor cambia algo en mi PC?'; R = 'Monitor, Diagnóstico, Ruta, Historial, Wi-Fi, discos y hardware solo leen información. Solo cambian algo: Herramientas DNS (cambio de DNS), Rendimiento en juegos, Reparar red e Iniciar con Windows. Todos piden confirmación y, cuando es posible, guardan una copia para deshacer.' },
        @{ P = '¿Qué envía el programa por internet?'; R = 'Nada más que lo que usted utiliza: la prueba de velocidad habla con Cloudflare; "Detectar" consulta ipinfo.io; la pestaña Actualizaciones consulta GitHub; el formulario de esta pestaña envía solo lo que usted escriba. El monitor hace pings y conexiones TCP a los destinos que eligió. Sus historiales quedan en su PC, en %APPDATA%\NetDoctor.' },
        @{ P = '¿Por qué la temperatura aparece como no disponible?'; R = 'Windows no expone sensores de CPU/GPU sin un controlador. Abra LibreHardwareMonitor (gratuito) o use una tarjeta NVIDIA y NetDoctor mostrará los valores.' },
        @{ P = 'El antivirus marcó NetDoctor.'; R = 'El programa es un conjunto de scripts de PowerShell sin firma digital. Las herramientas que consultan la red, cambian el DNS y se actualizan a veces se marcan por error. Descargue solo de la página oficial del proyecto, compruebe el SHA256 de la versión y, si quiere, suba el archivo a VirusTotal.' },
        @{ P = '¿Cómo deshago una optimización o un cambio de DNS?'; R = 'Rendimiento en juegos > Revertir. Herramientas DNS > Restaurar anterior o Automático (DHCP). El punto de restauración de Windows también sirve.' },
        @{ P = '¿Cómo comparo con el plan de mi operador?'; R = 'Indique su plan en Texto para soporte, ejecute el Diagnóstico con la prueba de velocidad varias veces en días y horas distintos y vea el promedio del mes. Las metas del regulador mencionadas son solo una referencia.' },
        @{ P = 'El problema ocurre solo a veces. ¿Y ahora?'; R = 'Deje el Monitor encendido (de preferencia en la bandeja, con alertas) y revise la pestaña Historial; luego genere el informe HTML para enviarlo a su operador.' },
        @{ P = '¿Qué es el paquete de soporte?'; R = 'Un archivo zip con versión, errores e historiales (sin su nombre de usuario) para enviar cuando algo falle. Revise el contenido antes de enviarlo.' }
    )
}

function Get-InstallId {
    if (-not $script:Cfg.InstallId) {
        $script:Cfg | Add-Member -NotePropertyName InstallId -NotePropertyValue ([guid]::NewGuid().ToString('N')) -Force
        Save-Config $script:Cfg
    }
    [string]$script:Cfg.InstallId
}

# Informacoes tecnicas opcionais (sem IP, sem nome do PC, sem nome de usuario).
function Get-TechInfoText {
    $l = @()
    $l += ('Programa: v' + $script:AppVersion)
    try {
        $v = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $l += ('Windows: {0} (build {1}, versão {2})' -f $v.ProductName, $v.CurrentBuildNumber, $v.DisplayVersion)
    } catch { $l += 'Windows: não identificado' }
    $l += ('PowerShell: ' + $PSVersionTable.PSVersion.ToString())
    $l += ('Idioma do Windows: ' + (Get-Culture).Name)
    $con = 'cabo ou outro'; if ($script:IsWifi) { $con = 'Wi-Fi' }
    $l += ('Conexão: ' + $con)
    $l -join "`r`n"
}

# Envio do formulario (segundo plano). Nao usa credenciais: o Apps Script ja esta autorizado pelo dono.
$script:FeedbackCode = {
    $ErrorActionPreference = 'Stop'
    $fila = $Q
    $r = @{ Kind = 'fb-done'; Ok = $false; Msg = '' }
    try {
        Add-Type -AssemblyName System.Net.Http
        $hc = New-Object System.Net.Http.HttpClient
        $hc.Timeout = [TimeSpan]::FromSeconds(30)
        $conteudo = New-Object System.Net.Http.StringContent($Json, [System.Text.Encoding]::UTF8, 'text/plain')
        $resp = $hc.PostAsync($Url, $conteudo).Result
        $corpo = $resp.Content.ReadAsStringAsync().Result
        $hc.Dispose()
        $obj = $null
        try { $obj = $corpo | ConvertFrom-Json } catch { }
        if ($obj -and $obj.ok) { $r.Ok = $true }
        elseif ($obj -and $obj.msg) { $r.Msg = [string]$obj.msg }
        else { $r.Msg = 'Resposta inesperada do servidor (código ' + [int]$resp.StatusCode + ').' }
    } catch { $r.Msg = $_.Exception.Message }
    $fila.Enqueue($r)
}

function Get-FaqLines([string]$lang) {
    if (-not $script:FaqData.ContainsKey($lang)) { $lang = 'pt' }
    $out = @()
    foreach ($i in $script:FaqData[$lang]) {
        $out += @{ T = [string]$i.P; C = 'Cyan' }
        $out += @{ T = [string]$i.R; C = 'Gray' }
        $out += @{ T = ''; C = 'Gray' }
    }
    $out
}

# Link mailto: com assunto e corpo (limitado para nao estourar o tamanho de endereco do Windows).
function New-MailtoLink([string]$para, [string]$assunto, [string]$corpo) {
    if ($corpo.Length -gt 1500) { $corpo = $corpo.Substring(0, 1500) }
    'mailto:' + $para + '?subject=' + [uri]::EscapeDataString($assunto) + '&body=' + [uri]::EscapeDataString($corpo)
}

# Pacote de suporte: zip com informacoes, erros e historicos (sem nome de usuario nem nome do PC).
function New-SupportPackage {
    $res = @{ Ok = $false; Path = ''; Msg = '' }
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('NetDoctor-suporte-' + $stamp)
    try {
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $dados = Get-AppDir
        $usuario = [string]$env:USERNAME; $pc = [string]$env:COMPUTERNAME
        $limpa = {
            param($t)
            $x = [string]$t
            if ($usuario) { $x = $x -replace [regex]::Escape($usuario), '<usuario>' }
            if ($pc) { $x = $x -replace [regex]::Escape($pc), '<pc>' }
            $x
        }
        $utf = New-Object System.Text.UTF8Encoding($true)
        $info = @()
        $info += 'Pacote de suporte do NetDoctor'
        $info += ('Gerado em: ' + (Get-Date -Format 'dd/MM/yyyy HH:mm'))
        $info += ''
        $info += (Get-TechInfoText)
        $info += ('Administrador: ' + [string](Test-IsAdmin))
        $info += ('Tema: ' + [string]$script:Cfg.Tema + '   Idioma: ' + [string]$script:Cfg.Idioma)
        if ($script:LastScores -and $script:LastScores.Texto) { $info += ''; $info += ('Última nota do diagnóstico: ' + $script:LastScores.Texto) }
        $info += ''
        $info += 'Conteúdo deste pacote:'
        $info += '  info.txt (este arquivo), erro.log (últimas 300 linhas), config.json (sem identificador da instalação),'
        $info += '  historico-monitor.csv, historico-velocidade.csv e eventos.csv (se existirem).'
        $info += 'Removido: nome de usuário do Windows e nome do computador nos textos. Revise antes de enviar.'
        [System.IO.File]::WriteAllText((Join-Path $tmp 'info.txt'), (& $limpa ($info -join "`r`n")), $utf)

        $log = Join-Path $dados 'erro.log'
        if (Test-Path $log) { [System.IO.File]::WriteAllText((Join-Path $tmp 'erro.log'), (& $limpa ((Get-Content -Path $log -Tail 300 -ErrorAction SilentlyContinue) -join "`r`n")), $utf) }
        $cfgPath = Join-Path $dados 'config.json'
        if (Test-Path $cfgPath) {
            $c = Get-Content -Path $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($c.PSObject.Properties['InstallId']) { $c.PSObject.Properties.Remove('InstallId') }
            [System.IO.File]::WriteAllText((Join-Path $tmp 'config.json'), (& $limpa ($c | ConvertTo-Json -Depth 5)), $utf)
        }
        foreach ($nome in @('historico-monitor.csv', 'historico-velocidade.csv', 'eventos.csv')) {
            $o = Join-Path $dados $nome
            if (Test-Path $o) { Copy-Item -Path $o -Destination (Join-Path $tmp $nome) -Force }
        }
        $dir = Get-ReportDir
        $zip = Join-Path $dir ('NetDoctor-suporte-' + $stamp + '.zip')
        if (Test-Path $zip) { Remove-Item $zip -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tmp, $zip)
        $res.Ok = $true; $res.Path = $zip
    } catch { $res.Msg = $_.Exception.Message }
    finally { try { Remove-Item -Path $tmp -Recurse -Force } catch { } }
    $res
}
