# NetDoctor - hardware do PC (estilo CPU-Z / GPU-Z, usando os dados que o proprio Windows expoe)
# e saude dos discos. Tudo somente leitura. As leituras lentas rodam em segundo plano.
#
# Limites honestos: CPU-Z e GPU-Z usam drivers proprios para ler sensores e SPD; aqui usamos WMI/CIM.
# Temperaturas: o Windows nao expoe sensores de CPU/GPU sem driver. O NetDoctor le (nesta ordem)
# LibreHardwareMonitor/OpenHardwareMonitor se estiverem abertos, nvidia-smi (placas NVIDIA) e a zona
# termica ACPI (nem sempre representa a CPU).

# ------------------------------------------------------------ informacoes estaticas
$script:HwInfoCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    $fila = $Q
    $L = New-Object System.Collections.ArrayList
    function Add-L([string]$t) { [void]$L.Add($t) }
    function Gb($b) { if ($b) { [math]::Round([double]$b / 1GB, 1) } else { 0 } }
    function Clean([string]$s) { if ($s) { ($s -replace '\s+', ' ').Trim() } else { '' } }
    function Mem-Type($m) {
        $t = [int]$m.SMBIOSMemoryType
        switch ($t) {
            20 { return 'DDR' } 21 { return 'DDR2' } 24 { return 'DDR3' } 26 { return 'DDR4' }
            30 { return 'LPDDR4' } 34 { return 'DDR5' } 35 { return 'LPDDR5' }
            default { if ($t -gt 0) { return ('tipo ' + $t) } else { return 'RAM' } }
        }
    }

    Add-L '== PROCESSADOR =='
    foreach ($c in @(Get-CimInstance Win32_Processor)) {
        Add-L ('Modelo:            ' + (Clean $c.Name))
        Add-L ('Fabricante:        ' + (Clean $c.Manufacturer))
        Add-L ('Núcleos / threads: {0} / {1}' -f $c.NumberOfCores, $c.NumberOfLogicalProcessors)
        Add-L ('Clock (máx./atual): {0} MHz / {1} MHz' -f $c.MaxClockSpeed, $c.CurrentClockSpeed)
        Add-L ('Cache L2 / L3:     {0} KB / {1} KB' -f $c.L2CacheSize, $c.L3CacheSize)
        Add-L ('Soquete:           ' + (Clean $c.SocketDesignation))
    }

    $bb = Get-CimInstance Win32_BaseBoard | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS | Select-Object -First 1
    $cs = Get-CimInstance Win32_ComputerSystem | Select-Object -First 1
    Add-L ''
    Add-L '== PLACA-MÃE =='
    Add-L ('Fabricante:        ' + (Clean $bb.Manufacturer))
    Add-L ('Modelo:            ' + (Clean $bb.Product))
    if ($cs) { Add-L ('Computador:        ' + (Clean ([string]$cs.Manufacturer + ' ' + [string]$cs.Model))) }
    $dt = '-'
    if ($bios.ReleaseDate) { try { $dt = ([datetime]$bios.ReleaseDate).ToString('dd/MM/yyyy') } catch { } }
    Add-L ('BIOS:              {0}  ({1})' -f (Clean $bios.SMBIOSBIOSVersion), $dt)

    Add-L ''
    Add-L '== MEMÓRIA =='
    $mods = @(Get-CimInstance Win32_PhysicalMemory)
    $arr = Get-CimInstance Win32_PhysicalMemoryArray | Select-Object -First 1
    if ($cs) { Add-L ('Total instalado:    {0} GB  ({1} de {2} slots)' -f (Gb $cs.TotalPhysicalMemory), $mods.Count, $arr.MemoryDevices) }
    foreach ($m in $mods) {
        $vel = $m.ConfiguredClockSpeed; if (-not $vel) { $vel = $m.Speed }
        $nome = (Clean ([string]$m.Manufacturer + ' ' + [string]$m.PartNumber))
        Add-L ('  {0}: {1} GB {2} {3} MHz  {4}' -f (Clean $m.DeviceLocator), (Gb $m.Capacity), (Mem-Type $m), $vel, $nome)
    }

    Add-L ''
    Add-L '== PLACA DE VÍDEO =='
    $vram = @{}
    $cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    foreach ($k in @(Get-ChildItem $cls)) {
        if ($k.PSChildName -notmatch '^\d{4}$') { continue }
        $p = Get-ItemProperty $k.PSPath
        $dn = [string]$p.DriverDesc
        $qw = $p.'HardwareInformation.qwMemorySize'
        if ($dn -and $qw) {
            try { if ($qw -is [byte[]]) { $vram[$dn] = [BitConverter]::ToUInt64($qw, 0) } else { $vram[$dn] = [uint64]$qw } } catch { }
        }
    }
    foreach ($g in @(Get-CimInstance Win32_VideoController)) {
        $mem = $g.AdapterRAM
        if ($vram.ContainsKey([string]$g.Name)) { $mem = $vram[[string]$g.Name] }
        Add-L ('Modelo:            ' + (Clean $g.Name))
        $memTxt = '-'; if ($mem) { $memTxt = ('{0} GB' -f (Gb $mem)) }
        Add-L ('Memória de vídeo:  ' + $memTxt)
        $dd = '-'; if ($g.DriverDate) { try { $dd = ([datetime]$g.DriverDate).ToString('dd/MM/yyyy') } catch { } }
        Add-L ('Driver:            {0}  ({1})' -f $g.DriverVersion, $dd)
        if ($g.CurrentHorizontalResolution) { Add-L ('Resolução:         {0}x{1} @ {2} Hz' -f $g.CurrentHorizontalResolution, $g.CurrentVerticalResolution, $g.CurrentRefreshRate) }
    }

    $os = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
    Add-L ''
    Add-L '== SISTEMA =='
    Add-L ('Windows:           {0}  (build {1}, {2})' -f (Clean $os.Caption), $os.BuildNumber, $os.OSArchitecture)
    if ($os.LastBootUpTime) {
        $up = (Get-Date) - [datetime]$os.LastBootUpTime
        Add-L ('Ligado há:         {0} d {1} h {2} min' -f $up.Days, $up.Hours, $up.Minutes)
    }
    $fila.Enqueue(@{ Kind = 'hw-info'; Text = ($L -join "`r`n") })
}

# ------------------------------------------------------------ leitura ao vivo (carga e temperaturas)
$script:HwLiveCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    $nv = $null
    foreach ($cand in @('nvidia-smi.exe', (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'), (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'))) {
        $cmd = Get-Command $cand -ErrorAction SilentlyContinue
        if ($cmd) { $nv = $cmd.Source; break }
    }
    $ns = $null; $volta = 0
    while ($Ctl.Run) {
        if ($volta % 12 -eq 0) {
            $ns = $null
            foreach ($n in @('root/LibreHardwareMonitor', 'root/OpenHardwareMonitor')) {
                $t = Get-CimInstance -Namespace $n -ClassName Hardware -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($t) { $ns = $n; break }
            }
        }
        $volta++
        $r = @{ Kind = 'hw-live'; Cpu = $null; CpuSrc = ''; Gpu = $null; GpuSrc = ''; CpuLoad = $null; RamPct = $null; GpuLoad = $null }

        $lp = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
        if ($lp.Count -gt 0 -and $null -ne $lp.Average) { $r.CpuLoad = [math]::Round([double]$lp.Average, 0) }
        $os = Get-CimInstance Win32_OperatingSystem | Select-Object -First 1
        if ($os -and $os.TotalVisibleMemorySize) { $r.RamPct = [math]::Round(100 * (1 - ([double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize)), 0) }

        if ($ns) {
            $sens = @(Get-CimInstance -Namespace $ns -ClassName Sensor -Filter "SensorType='Temperature'")
            $cpuS = @($sens | Where-Object { $_.Identifier -match '^/(intelcpu|amdcpu|cpu)/' })
            $gpuS = @($sens | Where-Object { $_.Identifier -match '^/(gpu|nvidiagpu|atigpu)' })
            $pk = $cpuS | Where-Object { $_.Name -match 'Package|Tctl|Tdie' } | Select-Object -First 1
            if ($pk) { $r.Cpu = [double]$pk.Value }
            elseif ($cpuS.Count -gt 0) { $r.Cpu = [math]::Round([double](($cpuS | Measure-Object -Property Value -Average).Average), 1) }
            if ($null -ne $r.Cpu) { $r.CpuSrc = 'LibreHardwareMonitor' }
            $gc = $gpuS | Where-Object { $_.Name -match 'Core' } | Select-Object -First 1
            if (-not $gc) { $gc = $gpuS | Select-Object -First 1 }
            if ($gc) { $r.Gpu = [double]$gc.Value; $r.GpuSrc = 'LibreHardwareMonitor' }
        }
        if ($nv) {
            $o = & $nv --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
            if ($o -match '^\s*(\d+)\s*,\s*(\d+)') {
                if ($null -eq $r.Gpu) { $r.Gpu = [double]$Matches[1]; $r.GpuSrc = 'nvidia-smi' }
                $r.GpuLoad = [double]$Matches[2]
            }
        }
        if ($null -eq $r.Cpu) {
            $z = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation | ForEach-Object { [double]$_.Temperature - 273.15 } | Where-Object { $_ -gt 0 -and $_ -lt 120 })
            if ($z.Count -gt 0) { $r.Cpu = [math]::Round([double](($z | Measure-Object -Maximum).Maximum), 1); $r.CpuSrc = 'zona térmica ACPI (pode não ser a CPU)' }
        }
        $Q.Enqueue($r)
        for ($i = 0; $i -lt 50 -and $Ctl.Run; $i++) { Start-Sleep -Milliseconds 100 }
    }
}

# ------------------------------------------------------------ estatisticas (atual / media / min / max)
function New-HwStat { @{ N = 0; Sum = 0.0; Min = $null; Max = $null; Last = $null; Src = '' } }

function Add-HwStat($st, $v, [string]$src) {
    if ($null -eq $v) { return }
    $d = [double]$v
    $st.N = [int]$st.N + 1; $st.Sum = [double]$st.Sum + $d; $st.Last = $d
    if ($null -eq $st.Min -or $d -lt $st.Min) { $st.Min = $d }
    if ($null -eq $st.Max -or $d -gt $st.Max) { $st.Max = $d }
    if ($src) { $st.Src = $src }
}

function Format-HwStat([string]$rotulo, $st) {
    if ($st.N -eq 0) { return ($rotulo + ' indisponível') }
    $avg = [double]$st.Sum / [double]$st.N
    ('{0} atual {1} °C | média {2} °C | mín {3} | máx {4}  ({5} leituras; {6})' -f $rotulo, ([math]::Round($st.Last, 1)), ([math]::Round($avg, 1)), ([math]::Round($st.Min, 1)), ([math]::Round($st.Max, 1)), $st.N, $st.Src)
}

# ------------------------------------------------------------ saude dos discos
$script:DiskCode = {
    $ErrorActionPreference = 'SilentlyContinue'
    function Fmt-Cap($b) {
        if (-not $b) { return '-' }
        if ($b -ge 1TB) { return ('{0:N2} TB' -f ($b / 1TB)) }
        ('{0:N0} GB' -f ($b / 1GB))
    }
    $rows = New-Object System.Collections.ArrayList
    $dds = @(Get-CimInstance Win32_DiskDrive)
    $pf = @(Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus)
    foreach ($pd in @(Get-PhysicalDisk)) {
        $rel = $pd | Get-StorageReliabilityCounter
        $dd = $dds | Where-Object { [string]$_.Index -eq [string]$pd.DeviceId } | Select-Object -First 1
        $pred = 'sem acesso'
        if ($dd -and $pf.Count -gt 0) {
            $m = $pf | Where-Object { $_.InstanceName -like ([string]$dd.PNPDeviceID + '*') } | Select-Object -First 1
            if ($m) { if ($m.PredictFailure) { $pred = 'FALHA PREVISTA' } else { $pred = 'OK' } }
        }
        $bus = [string]$pd.BusType; $mt = [string]$pd.MediaType
        if ($bus -eq 'NVMe') { $tipo = 'NVMe SSD' }
        elseif (-not $mt -or $mt -eq 'Unspecified') { $tipo = $bus }
        else { $tipo = ($mt + ' (' + $bus + ')') }
        $hs = [string]$pd.HealthStatus
        $saude = $hs
        if ($hs -eq 'Healthy') { $saude = 'Saudável' } elseif ($hs -eq 'Warning') { $saude = 'Atenção' } elseif ($hs -eq 'Unhealthy') { $saude = 'Com problema' }
        $temp = $null; if ($rel -and $rel.Temperature) { $temp = [int]$rel.Temperature }
        $wear = $null; if ($rel -and $null -ne $rel.Wear) { $wear = [int]$rel.Wear }
        $hours = $null; if ($rel -and $rel.PowerOnHours) { $hours = [int]$rel.PowerOnHours }
        $erros = '-'; if ($rel -and ($null -ne $rel.ReadErrorsTotal -or $null -ne $rel.WriteErrorsTotal)) { $erros = ('{0}/{1}' -f [int64]$rel.ReadErrorsTotal, [int64]$rel.WriteErrorsTotal) }

        $nivel = 'ok'; $msgs = @()
        if ($hs -eq 'Warning') { $nivel = 'warn'; $msgs += 'o Windows reporta atenção' }
        if ($hs -eq 'Unhealthy') { $nivel = 'bad'; $msgs += 'o Windows reporta problema: faça backup' }
        if ($pred -eq 'FALHA PREVISTA') { $nivel = 'bad'; $msgs += 'SMART prevê falha: faça backup agora' }
        if ($null -ne $wear) {
            if ($wear -ge 90) { $nivel = 'bad'; $msgs += ('desgaste de {0}%' -f $wear) }
            elseif ($wear -ge 70) { if ($nivel -eq 'ok') { $nivel = 'warn' }; $msgs += ('desgaste de {0}%' -f $wear) }
        }
        if ($null -ne $temp -and $temp -ge 65) { if ($nivel -eq 'ok') { $nivel = 'warn' }; $msgs += ('temperatura alta ({0} °C)' -f $temp) }
        if ($nivel -eq 'ok') { $conc = 'Sem sinais de problema nos dados disponíveis' } else { $conc = ($msgs -join '; ') }
        $nome = [string]$pd.FriendlyName
        $rows.Add(@{
            Nome = $nome; Tipo = $tipo; Cap = (Fmt-Cap $pd.Size); Saude = $saude
            Temp = $(if ($null -ne $temp) { ('{0} °C' -f $temp) } else { '-' })
            Horas = $(if ($null -ne $hours) { ('{0} h' -f $hours) } else { '-' })
            Desgaste = $(if ($null -ne $wear) { ('{0}%' -f $wear) } else { '-' })
            Erros = $erros; Smart = $pred; Conc = $conc; Nivel = $nivel
        }) | Out-Null
    }
    $vols = New-Object System.Collections.ArrayList
    foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $usado = '-'; $nv = 'ok'
        if ($v.Size) {
            $p = [math]::Round(100 * (1 - ([double]$v.FreeSpace / [double]$v.Size)), 0)
            $usado = ('{0}%' -f $p)
            if ($p -ge 95) { $nv = 'bad' } elseif ($p -ge 85) { $nv = 'warn' }
        }
        $vols.Add(@{ Letra = [string]$v.DeviceID; Nome = [string]$v.VolumeName; Sis = [string]$v.FileSystem; Tam = (Fmt-Cap $v.Size); Livre = (Fmt-Cap $v.FreeSpace); Usado = $usado; Nivel = $nv }) | Out-Null
    }
    $Q.Enqueue(@{ Kind = 'disk-info'; Rows = $rows.ToArray(); Vols = $vols.ToArray(); SmartAcesso = ($pf.Count -gt 0) })
}

# Atributos SMART brutos (SATA), como o CrystalDiskInfo. Precisa de administrador; abre uma janela propria.
$script:SmartScript = @'
$ErrorActionPreference = 'SilentlyContinue'
$nomes = @{ 1='Taxa de erros de leitura'; 3='Tempo de rotação'; 4='Ciclos de partida/parada'; 5='Setores realocados'; 7='Erros de posicionamento'; 9='Horas ligado'; 10='Falhas de rotação'; 12='Ciclos de energia'; 177='Desgaste (wear leveling)'; 179='Blocos reserva usados'; 181='Falhas de programação'; 182='Falhas de apagamento'; 183='Erros SATA'; 184='Erro ponta a ponta'; 187='Erros incorrigíveis'; 188='Comandos expirados'; 190='Temperatura (fluxo de ar)'; 191='Choques'; 192='Desligamentos bruscos'; 193='Ciclos de cabeça'; 194='Temperatura'; 195='Erros ECC corrigidos'; 196='Eventos de realocação'; 197='Setores pendentes'; 198='Setores incorrigíveis'; 199='Erros de CRC (cabo)'; 200='Erros de gravação'; 202='Vida restante'; 231='Vida restante do SSD'; 233='Desgaste da mídia'; 241='Total gravado (LBA)'; 242='Total lido (LBA)' }
$atencao = @(5, 187, 188, 197, 198, 196)
Write-Host 'NetDoctor - atributos SMART (somente leitura)' -ForegroundColor Cyan
$dados = @(Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictData)
$lim = @(Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictThresholds)
if ($dados.Count -eq 0) { Write-Host 'Nenhum disco SATA com SMART exposto ao Windows (discos NVMe e alguns USB não aparecem aqui).' -ForegroundColor Yellow }
foreach ($d in $dados) {
    Write-Host ''
    Write-Host ('Disco: ' + $d.InstanceName) -ForegroundColor Green
    $t = $lim | Where-Object { $_.InstanceName -eq $d.InstanceName } | Select-Object -First 1
    $v = $d.VendorSpecific; $tv = $t.VendorSpecific
    '{0,-4} {1,-30} {2,6} {3,6} {4,6} {5,16}  {6}' -f 'ID', 'Atributo', 'Atual', 'Pior', 'Limite', 'Bruto', 'Avaliação' | Write-Host
    for ($i = 2; $i -lt 362; $i += 12) {
        $id = [int]$v[$i]
        if ($id -eq 0) { continue }
        $cur = [int]$v[$i + 3]; $pior = [int]$v[$i + 4]
        $raw = [uint64]0
        for ($k = 5; $k -ge 0; $k--) { $raw = $raw * 256 + [uint64]$v[$i + 5 + $k] }
        $th = 0; if ($tv) { $th = [int]$tv[$i + 1] }
        $nome = $nomes[$id]; if (-not $nome) { $nome = 'Atributo ' + $id }
        $av = 'ok'; $cor = 'Gray'
        if ($th -gt 0 -and $cur -le $th) { $av = 'FALHA (abaixo do limite)'; $cor = 'Red' }
        elseif ($atencao -contains $id -and $raw -gt 0) { $av = 'ATENÇÃO (valor bruto maior que zero)'; $cor = 'Yellow' }
        elseif ($id -eq 199 -and $raw -gt 0) { $av = 'verifique o cabo SATA'; $cor = 'Yellow' }
        ('{0,-4} {1,-30} {2,6} {3,6} {4,6} {5,16}  {6}' -f $id, $nome, $cur, $pior, $th, $raw, $av) | Write-Host -ForegroundColor $cor
    }
}
Write-Host ''
Read-Host 'Pressione Enter para fechar'
'@
