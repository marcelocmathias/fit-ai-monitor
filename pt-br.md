---
title: Fit AI Monitor — guia de instalação
lang: pt-BR
---

[English](./) · **Português (Brasil)**

# Fit AI Monitor — guia de instalação

Grave seus treinos de academia no Galaxy Watch, veja no Samsung Health e
converse com o Claude sobre as cargas que você levantou.

- **Relógio** — toque em *Próximo* a cada troca de exercício. Ele grava o tempo
  e a frequência cardíaca de cada bloco, e funciona com o celular no armário.
- **Celular** — recebe cada sessão, grava no Health Connect (para o Samsung
  Health mostrar) e no **seu próprio** banco de dados Supabase.
- **Claude** — você conta o que foi cada bloco ("supino 4×8 com 60 kg…") e
  depois pergunta "quanto peguei no leg press da última vez?".

Seus dados ficam num projeto Supabase gratuito que é **seu**. Ninguém mais —
nem quem compartilhou o app com você — consegue ver.

A configuração leva uns **30 minutos**, uma vez só.

---

## O que você precisa

| | |
|---|---|
| Celular | Android 14 ou mais novo (Samsung recomendado) |
| Relógio | Galaxy Watch4 ou mais novo, atualizado (Wear OS 5) |
| Apps no celular | **Samsung Health** e **Health Connect** (já vem no Android 14+) |
| Contas | Conta gratuita no [Supabase](https://supabase.com) · conta no [Claude](https://claude.ai) com conectores e skills |
| Para instalar no relógio | Um computador com as platform-tools do Android, **ou** um app de instalação no celular (passo 4) |

## Downloads

| Arquivo | O que é |
|---|---|
| [fit-ai-monitor-phone.apk](downloads/fit-ai-monitor-phone.apk) | App do celular |
| [fit-ai-monitor-watch.apk](downloads/fit-ai-monitor-watch.apk) | App do relógio |
| [setup.sql](https://github.com/marcelocmathias/fit-ai-monitor/blob/main/setup.sql) | Criação do banco de dados (passo 1) |
| [fit-ai-monitor-skill.zip](downloads/fit-ai-monitor-skill.zip) | Skill do Claude (passo 6) |

---

## 1. Crie seu banco de dados (Supabase)

1. Entre em [supabase.com](https://supabase.com) → **New project**.
   - Name: o que quiser, por exemplo `fitaimonitor`
   - Region: a mais próxima — no Brasil, **South America (São Paulo)**
   - Database password: clique em *Generate* e guarde no seu gerenciador de
     senhas (você quase nunca vai precisar)
   - Plan: **Free**
2. Espere o projeto terminar de iniciar (~2 minutos).
3. Abra **SQL Editor** → **New query**. Abra o
   [setup.sql](https://github.com/marcelocmathias/fit-ai-monitor/blob/main/setup.sql),
   clique no botão **Copy raw file**, cole tudo no editor e clique em **Run**.
   Deve aparecer *Success. No rows returned*.
4. Confira — rode numa nova query:

   ```sql
   select count(*) from workout_types;   -- deve dar 5
   ```

## 2. Crie seu login e tranque a porta

O app do celular entra com **um** usuário: você. Depois você desliga os
cadastros, para ninguém mais conseguir criar conta no seu projeto.

1. **Authentication → Users → Add user → Create new user**. Seu e-mail e uma
   senha forte. Marque **Auto Confirm User**.
2. **Authentication → Sign In / Providers** → **desligue** *Allow new users to
   sign up* → Save.

## 3. Copie dois valores para o celular

Abra **Project Settings → API Keys** (ou o botão **Connect** no topo).

| Valor | Formato |
|---|---|
| **Project URL** | `https://abcdefgh.supabase.co` |
| **Publishable key** | `sb_publishable_...` (crie uma se a lista estiver vazia) |

Nunca use a chave **secret** no app. Mande os dois valores para o celular (por
exemplo, por e-mail para você mesmo) — você vai colar no passo 5.

**Opcional, recomendado:** projetos gratuitos pausam depois de uma semana sem
uso. Para evitar: **Database → Extensions** → ative `pg_cron` e rode no SQL Editor:

```sql
select cron.schedule('keepalive', '0 6 * * 1', $$ select 1 $$);
```

## 4. Instale os apps

### Celular

1. No celular, abra o [link do APK do celular](downloads/fit-ai-monitor-phone.apk).
2. Permita que o navegador *instale apps desconhecidos* quando pedir.
3. Se o Play Protect avisar que o app é desconhecido → **Mais detalhes →
   Instalar mesmo assim**.

### Relógio

O relógio não tem navegador, então o APK é enviado a partir de um computador ou
do celular.

**Primeiro, no relógio:** Configurações → Sobre o relógio → Software → toque 5
vezes em *Versão do software* (modo desenvolvedor). Depois Configurações →
**Opções do desenvolvedor** → ative **Depuração ADB** e **Depuração sem fio**.
Deixe o relógio na mesma rede Wi-Fi do computador/celular.

**Opção A — pelo computador** (Windows/Mac/Linux, com as
[platform-tools](https://developer.android.com/tools/releases/platform-tools)):

1. No relógio, em *Depuração sem fio*, toque em **Parear novo dispositivo**.
   Anote o IP, a porta e o código de 6 dígitos.
2. No computador:

   ```
   adb pair 192.168.1.50:41234       (digite o código quando pedir)
   adb connect 192.168.1.50:5555     (IP e porta da tela principal de Depuração sem fio)
   adb install fit-ai-monitor-watch.apk
   ```

**Opção B — pelo celular, sem computador:** instale um app de instalação para
Wear OS na Play Store (por exemplo *Wear Installer 2* ou *Bugjaeger*) e siga os
passos de pareamento dele com o APK do relógio que você baixou.

Depois de instalado, **desligue a Depuração ADB** no relógio (economiza bateria).

## 5. Configure o app do celular

Abra o **Fit AI Monitor** no celular → aba **Configurações**.

1. **Supabase** → cole a **URL do projeto** e a **Chave publicável** → *Salvar
   projeto*. Depois entre com o e-mail e a senha do passo 2.
2. **Health Connect** → *Conceder permissões* → permita tudo que aparecer.
3. **Idioma** — Sistema, PT-PT, PT-BR ou English.

### Samsung Health

O Samsung Health lê seus treinos do Health Connect:

1. Samsung Health → **⋮ → Configurações → Health Connect** → abra as permissões
   e permita que o Samsung Health **leia Exercício, Frequência cardíaca e
   Calorias queimadas**. (Leitura e gravação são chaves separadas.)
2. Samsung Health → Configurações → **Consentimentos** (ou *Permissões de
   dados*) → permita o processamento de dados de saúde, se estiver desligado.

Os treinos aparecem no Samsung Health como **"Máquinas de musculação"**
(*Weight machines*), com a curva de frequência cardíaca e as calorias. Eles
aparecem um pouco depois de o celular recebê-los.

### Relógio

Abra o Fit AI Monitor no relógio e aceite todas as permissões (frequência
cardíaca, atividade física, localização, notificações). A localização só serve
para sugerir em qual academia você está.

## 6. Conecte o Claude

1. claude.ai → **Configurações → Conectores** → adicione o **Supabase** →
   autorize com a sua conta do Supabase.
2. claude.ai → **Configurações → Recursos (Capabilities) → Skills** → **Upload
   skill** → escolha o
   [fit-ai-monitor-skill.zip](downloads/fit-ai-monitor-skill.zip)
   e confira se está ativado.
3. Abra uma conversa nova e diga:

   > Me ajuda a configurar o Fit AI Monitor. Minhas academias são …

   O Claude confere o banco e cadastra suas academias. Para cada uma, passe o
   nome e um **link do Google Maps** (ou as coordenadas: toque e segure no
   prédio no Google Maps). Você também pode dizer sua idade ou sua frequência
   cardíaca máxima para ajustar as zonas.
4. Abra o app do celular e **puxe para baixo a lista de Treinos** — isso envia
   as academias para o relógio. Abra de novo o app no relógio: suas academias
   aparecem em *Qual academia?*.

## 7. No dia a dia

1. **Na academia:** abra o app no relógio (ou o bloco/tile) → escolha a
   academia → escolha o treino → **toque em Próximo a cada troca de
   exercício**. Concluir → Salvar.
2. **Depois:** a sessão chega sozinha no celular quando os dois estiverem
   perto. Conte ao Claude o que você fez:

   > Hoje: supino reto 4 séries, 60 kg × 10, 8, 8, 6. Depois supino inclinado com halter 22 kg cada…

3. **Mais tarde:** pergunte o que quiser — *"quanto peguei no leg press da
   última vez?"*, *"como evoluiu meu agachamento este mês?"*.

O relógio segue o ciclo **Peito → Costas → Pernas → Braços**, mais **Core**
fora do ciclo, e já sugere o próximo. Se a sua divisão é outra, escolha o mais
parecido — o que vale é o que você conta ao Claude.

---

## Problemas comuns

| Problema | Solução |
|---|---|
| Sessão no relógio mas não no celular | Deixe os dois perto, Bluetooth ligado; abra o app do celular e puxe a lista para baixo. |
| Não chegou ao Supabase | Em Configurações → Supabase deve aparecer *conectado*. A aba **Registros** mostra cada etapa. |
| Não aparece no Samsung Health | Confira as permissões de leitura do Samsung Health no Health Connect; depois, no app do celular, Configurações → *Enviar o que falta*. |
| Minha academia não aparece no relógio | Ela precisa de coordenadas. Peça ao Claude para conferir, puxe a lista no celular e reabra o app do relógio. *Outra* está sempre disponível. |
| O app do relógio não instala: "assinaturas diferentes" | Desinstale o app antigo do relógio antes. Os apps do celular e do relógio precisam ser da mesma versão. |
| Login recusado | Confira se o projeto mostrado em Configurações → Supabase é o seu e se o usuário existe em Authentication → Users. *Usar outro projeto* permite digitar URL e chave de novo. |

## Privacidade

- Tudo fica no **seu** projeto Supabase e nos seus aparelhos.
- A chave publicável sozinha não abre nada: toda tabela exige o usuário
  conectado, e os cadastros estão desligados.
- O Claude só vê seus dados nas conversas em que você usa o conector do Supabase.
