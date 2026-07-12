# Como remover o fundo de uma imagem (logo, ícone, etc.)

Guia para reproduzir a remoção de fundo que foi feita na `img/logo-verde.jpeg`.
Esta técnica funciona **muito bem quando o fundo é de uma cor sólida** (branco, por
exemplo) e o conteúdo tem cor bem diferente do fundo — caso típico de logos.

O resultado é um **PNG com transparência**, sem perda de qualidade e com as bordas
suavizadas (antialiasing preservado).

---

## O que essa técnica faz

Ela não usa "inteligência artificial". Ela faz uma **remoção por cor** (color key):

1. Lê cada pixel da imagem.
2. Calcula o quão "próximo do branco" aquele pixel está (distância de cor).
3. Pixels **quase brancos** viram totalmente transparentes.
4. Pixels **bem diferentes do branco** (o texto, os desenhos) ficam totalmente opacos.
5. Pixels **na borda** (meio-termo) ganham transparência parcial → borda suave, sem
   serrilhado.

> ⚠️ **Quando NÃO usar:** se o fundo tiver várias cores, textura, foto, ou se o
> conteúdo tiver a mesma cor do fundo. Nesses casos precisa de uma ferramenta de IA
> (ex.: `rembg`) ou edição manual.

---

## Pré-requisitos

- **Node.js** instalado (já temos: `node -v`).
- A biblioteca **sharp** (instalada no passo abaixo).

Não precisa de Python, ImageMagick nem Photoshop.

---

## Passo a passo

### 1. Instalar a dependência (só na primeira vez)

Rode dentro da pasta do projeto:

```bash
npm install sharp
```

> Se preferir não sujar o projeto, crie uma pasta temporária e rode o `npm install`
> lá dentro. Foi o que fizemos no processo original.

### 2. Criar o script `remover-fundo.js`

```js
const sharp = require("sharp");

// >>> AJUSTE AQUI <<<
const ENTRADA = "img/logo-verde.jpeg"; // imagem original
const SAIDA    = "img/logo-verde.png";  // resultado (sempre .png para ter transparência)

// Feather (suavização de borda). Distância de cor em relação ao branco:
//  - abaixo de T0  => vira transparente (fundo)
//  - acima  de T1  => fica opaco (conteúdo)
//  - entre os dois => transparência parcial (borda suave)
const T0 = 40;
const T1 = 100;

(async () => {
  const img = sharp(ENTRADA).ensureAlpha();
  const { data, info } = await img.raw().toBuffer({ resolveWithObject: true });
  const { width, height, channels } = info; // channels = 4 (RGBA)

  for (let i = 0; i < data.length; i += channels) {
    const r = data[i], g = data[i + 1], b = data[i + 2];
    // distância do branco puro (255,255,255)
    const d = Math.sqrt((255 - r) ** 2 + (255 - g) ** 2 + (255 - b) ** 2);

    let a;
    if (d <= T0) a = 0;            // fundo -> transparente
    else if (d >= T1) a = 255;     // conteúdo -> opaco
    else a = Math.round(((d - T0) / (T1 - T0)) * 255); // borda

    data[i + 3] = a; // sobrescreve o canal alpha
  }

  await sharp(data, { raw: { width, height, channels } })
    .png({ compressionLevel: 9 })
    .toFile(SAIDA);

  console.log("Pronto:", SAIDA, `${width}x${height}`);
})().catch((e) => { console.error(e); process.exit(1); });
```

### 3. Rodar

```bash
node remover-fundo.js
```

Gera o arquivo definido em `SAIDA` (ex.: `img/logo-verde.png`).

### 4. Conferir o resultado

O fundo transparente é difícil de ver num visualizador transparente. Para conferir,
coloque a imagem sobre um fundo colorido:

```js
// conferir.js
const sharp = require("sharp");
const ARQ = "img/logo-verde.png";

sharp({ create: { width: 879, height: 176, channels: 4, background: "#3a6351" } })
  .composite([{ input: ARQ }])
  .png()
  .toFile("conferir.png")
  .then(() => console.log("veja conferir.png"));
```

Ajuste `width`/`height` para o tamanho da sua imagem e `background` para uma cor que
contraste. Abra `conferir.png` e verifique se as bordas ficaram limpas.

### 5. Usar no site

Aponte o `<img>` para o novo `.png`:

```html
<img src="img/logo-verde.png" alt="...">
```

---

## Ajustes finos

| Situação | O que fazer |
|---|---|
| Sobrou "fantasma" branco em volta do conteúdo | Aumente `T0` (ex.: 50–60) |
| Comeu parte do conteúdo claro (some detalhe) | Diminua `T0`/`T1` |
| Borda serrilhada / dura | Aumente a distância entre `T0` e `T1` |
| Borda muito "desbotada" | Diminua a distância entre `T0` e `T1` |
| Fundo é preto, não branco | Troque `(255 - r)` por `r` (distância do preto) nas 3 linhas do cálculo de `d` |
| Fundo é outra cor (ex.: verde) | Troque `255,255,255` pelos valores RGB da cor do fundo |

---

## Resumo rápido (TL;DR)

```bash
npm install sharp
# ajuste ENTRADA/SAIDA no script e rode:
node remover-fundo.js
```

Fundo sólido → PNG transparente, sem perder qualidade.
