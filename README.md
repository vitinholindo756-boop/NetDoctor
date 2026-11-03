# NetDoctor

Monitor e diagnóstico de internet para Windows, com ferramentas de DNS, Wi-Fi, saúde dos discos e ajustes para jogos. Feito em PowerShell: não precisa instalar nada.

## O que ele faz

- **Assistente:** você escolhe o problema (lag em jogo, internet que cai, lentidão, Wi-Fi ruim) e ele roda só os testes que importam e explica o resultado em linguagem simples.
- **Monitor:** mede ping e conexões aos seus destinos o tempo todo, com gráfico, alertas (balão e som) e opção de ficar na bandeja do sistema.
- **Diagnóstico:** latência, perda, jitter, teste de velocidade com notas de bufferbloat e de uso (jogos, chamadas, streaming), e comparação com o plano contratado.
- **Rota:** mede cada salto do caminho sem parar e indica onde a perda começa.
- **Histórico e relatório:** disponibilidade, problemas por hora do dia e relatório HTML para enviar à operadora.
- **Wi-Fi:** sinal, canal, redes vizinhas e sugestão de canal melhor.
- **Ferramentas DNS:** compara a velocidade de vários servidores DNS e troca o DNS, com backup para voltar atrás.
- **Desempenho em jogos:** ajustes reversíveis do Windows, com ponto de restauração.
- **Este PC e Saúde dos discos:** hardware, temperaturas (quando o Windows permite) e saúde de HDD/SSD.
- Tema claro/escuro, e interface em português, inglês e espanhol.

## Como usar

1. Baixe o `NetDoctor.zip` na página de [Releases](https://github.com/vitinholindo756-boop/NetDoctor/releases).
2. Extraia a pasta inteira (não rode de dentro do zip).
3. Dê dois cliques em `NetDoctor.bat`.

Se não abrir, use o `NetDoctor-diagnostico.bat`: ele mostra o console com os erros.

**Requisitos:** Windows 10 ou 11 e PowerShell 5.1 (já vem no Windows).

## Segurança e privacidade

- **O que muda no seu PC:** só as abas Ferramentas DNS e Desempenho em jogos, o botão Reparar rede e a opção Iniciar com o Windows. Todos pedem confirmação e, quando possível, guardam backup.
- **O que sai pela internet:** apenas o que você usa. O teste de velocidade fala com a Cloudflare, "Detectar" consulta o ipinfo.io, a aba Atualizações consulta o GitHub, e o formulário da aba Suporte envia só o que você escrever. Seus históricos ficam no seu PC, em `%APPDATA%\NetDoctor`.
- **Antivírus:** o programa é um conjunto de scripts sem assinatura digital. Ferramentas que consultam a rede, trocam DNS e se atualizam às vezes são marcadas por engano. Baixe só desta página e confira o SHA256 que aparece nas notas de cada versão. (Em casos de Desconfiança do .Zip, jogue o arquivo do nosso Projeto Oficial no site VirusTotal https://www.virustotal.com/gui/home/upload, para meios de desencargo e informações)

## Atualizações

A aba **Atualizações** mostra o que mudou em cada versão e instala a nova depois de conferir o SHA256, guardando um backup dos arquivos antigos.

## Suporte

Use a aba **Suporte** do programa (perguntas frequentes, formulário e pacote de suporte) ou abra uma [issue](https://github.com/vitinholindo756-boop/NetDoctor/issues).

## Limitações conhecidas

- Temperatura de CPU/GPU só aparece com o LibreHardwareMonitor aberto, com placa NVIDIA ou quando o Windows expõe a zona térmica.
- A análise de Wi-Fi lê o `netsh` (português, inglês e espanhol); no Windows 11 recente, listar redes vizinhas exige a Localização ligada.
- A tradução cobre a interface; resultados do diagnóstico e o relatório HTML ficam em português.
- As metas da Anatel mostradas são só um indicativo, não a medição oficial.
<img width="1919" height="1039" alt="Screenshot_1" src="https://github.com/user-attachments/assets/fd6fe7e3-9b90-4455-a434-b765297c375f" />
<img width="1919" height="1039" alt="Screenshot_2" src="https://github.com/user-attachments/assets/858b367c-18b7-4d8f-b1d1-f9777173e4ba" />
<img width="1919" height="1039" alt="Screenshot_15" src="https://github.com/user-attachments/assets/28f3136f-1336-4e67-8586-3ff5ed139f5b" />
