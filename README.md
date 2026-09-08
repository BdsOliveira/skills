# skills

Coleção de skills para agentes de IA (Claude Code, Cursor, etc.), versionada e
instalável em qualquer máquina via [`npx skills`](https://github.com/vercel-labs/skills).

## Skills disponíveis

| Skill | O que faz |
| --- | --- |
| [`webp-optimizer`](./webp-optimizer) | Converte imagens (`.png`/`.jpg`/`.jpeg`/`.tiff`) para **WebP** (ou AVIF) e reduz o peso das páginas em ~70–98%. Recebe um arquivo, uma lista ou uma pasta inteira. |
| [`laravel-project-setup`](./laravel-project-setup) | Aplica o toolchain padrão em um projeto Laravel (Larastan nível 10, Pint, Debugbar, Boost, Sail, Pest, scripts `stan`/`pint`/`coverage`/`quality`, pt_BR opcional). Cria o projeto do zero se precisar. |

---

## Instalar em outro computador / para outra pessoa

Qualquer pessoa com **Node.js** instalado usa o CLI `skills` — não precisa clonar
o repositório nem copiar arquivos na mão. O comando busca este repositório no
GitHub e instala a skill na pasta do agente.

### Instalação global (vale para todos os projetos da máquina)

```bash
npx skills add BdsOliveira/skills --skill webp-optimizer --global
```

### Instalação por projeto (fica só no projeto atual)

Rode dentro da pasta do projeto — a skill vai para `.claude/skills/` daquele
projeto e pode ser commitada junto do repositório para o time inteiro usar:

```bash
cd /caminho/do/seu/projeto
npx skills add BdsOliveira/skills --skill webp-optimizer
```

> **`--skill webp-optimizer`** escolhe qual skill instalar. Este repositório pode
> ter várias; sem o flag, o CLI lista todas para você escolher. Para instalar
> todas de uma vez: `--skill '*'`.

Outros comandos úteis:

```bash
npx skills add BdsOliveira/skills --list      # lista as skills do repo sem instalar
npx skills list --global                      # mostra o que já está instalado
npx skills update webp-optimizer              # atualiza para a última versão
npx skills remove webp-optimizer              # remove
```

---

## `laravel-project-setup`

Cada passo do setup é um arquivo separado em `modules/` e cada arquivo de
configuração é um arquivo separado em `assets/` — a ideia é dar pra **acrescentar
ou tirar coisa sem reescrever script nenhum**.

```bash
npx skills add BdsOliveira/skills --skill laravel-project-setup --global
```

Uso direto, sem agente:

```bash
laravel-project-setup/setup.sh --list                 # mostra os passos existentes
laravel-project-setup/setup.sh                        # configura o projeto da pasta atual
laravel-project-setup/setup.sh --new minha-app        # cria um Laravel novo e já configura
laravel-project-setup/setup.sh --with ptbr            # inclui traduções pt_BR
laravel-project-setup/setup.sh --with pest-drift     # converte os testes PHPUnit para Pest
laravel-project-setup/setup.sh --without boost        # pula um passo
laravel-project-setup/setup.sh --only phpstan,pint    # roda só esses
laravel-project-setup/setup.sh --dry-run              # mostra tudo sem escrever nada
```

Detecta o Laravel Sail sozinho e pode ser rodado de novo com segurança: config
que já existe e está diferente vira `.bak` antes de ser trocada, e os scripts do
`composer.json` são mesclados (os do projeto não se perdem).

### Como mudar o setup

| Quero… | Mexo em… |
| --- | --- |
| Trocar nível do PHPStan, regra do Pint, threshold de coverage | o arquivo correspondente em `assets/` |
| Adicionar/remover um pacote de dev | `assets/dev-packages.txt`, uma linha por pacote |
| Trocar os containers do Sail | `assets/sail-services.txt`, um serviço por linha |
| Adicionar um passo novo | copiar `modules/TEMPLATE.sh.example` para `modules/NN-nome.sh` |
| Remover um passo | apagar o arquivo, ou pôr `# default: off` no header dele |
| Fazer um passo virar pergunta por projeto | pôr uma linha `# ask:` no header (é assim que o `ptbr` funciona) |

Requisitos: PHP e Composer. O passo `--new` usa o instalador `laravel` quando
existe e cai para `composer create-project` quando não.

---

## Requisitos de execução da `webp-optimizer`

A skill converte imagens usando **uma** destas ferramentas (ela detecta sozinha):

- **sharp** (preferido) — instalado sob demanda com `npm install --no-save sharp`
  e removido depois, sem sujar o `package.json`. Basta ter Node/npm no projeto.
- **cwebp** (libwebp) ou **ImageMagick** — usados como fallback quando não há Node.
  Instale com `sudo apt install webp` (Ubuntu/WSL) ou `brew install webp` (macOS).

Nenhuma instalação prévia obrigatória: em qualquer projeto com Node ela funciona
de imediato.

## Como usar depois de instalada

Abra o agente (ex.: Claude Code) no seu projeto e peça em linguagem natural —
a skill dispara sozinha ao detectar a intenção:

- "otimiza essas imagens pra web: ./public/hero.png"
- "converte a pasta assets/fotos pra webp, tá muito pesada"
- "minhas imagens estão derrubando o Lighthouse, deixa elas mais leves"

Ou chame o script diretamente (sem agente):

```bash
# converte um arquivo, uma lista ou uma pasta; mantém os originais
node webp-optimizer/scripts/to-webp.mjs ./public/img -q 82

# redimensiona para no máx. 1080px de largura e converte
node webp-optimizer/scripts/to-webp.mjs ./hero.png --resize 1080
```

Flags: `-q/--quality` (padrão 82), `--resize <px>`, `--recursive`, `--avif`,
`--delete` (apaga os originais — cuidado, sem volta se não estiver no git).

---

## Desenvolvimento

O código-fonte de cada skill vive neste repositório. Para editar e testar a
skill localmente sem reinstalar toda hora, aponte a pasta de skills do agente
para cá com um symlink:

```bash
ln -s "$(pwd)/webp-optimizer" ~/.claude/skills/webp-optimizer
```

Assim, editar `webp-optimizer/` aqui reflete direto no agente.
