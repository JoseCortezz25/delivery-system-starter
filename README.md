# Decodex

**Decodex es la codificación de una marca en código.** Es una metodología para
generar piezas de publicidad a escala, de forma **agéntica**: se toma el design system de una marca
(paleta, tipografía, logo, tono, plantillas) y se convierte en prompts y tokens estandarizados, para
que una IA pueda generar las piezas gráficas (HTML → PNG/JPEG) sin diagramar cada una a mano.

> Este repo es la **estructura estándar** (propuesta) que cualquier proyecto de marca en Decodex debería
> adoptar — todavía en construcción y sujeta a ajustes.

## La idea central

El diseño de una marca se documenta una sola vez, en un formato que tanto un humano como una IA
pueden leer sin ambigüedad. A partir de esa especificación, un motor genera cualquier cantidad de
piezas — distintos tamaños, canales, variantes de copy — sin que nadie tenga que diagramarlas una
por una a mano.

## Cómo funciona, en 3 niveles

1. **Foundations** — lo que nunca cambia de una pieza a otra: paleta, tipografía, logo, tono, límites
   legales. Se resuelve una sola vez, al principio de cada marca.
2. **Frameworks** — cada estructura visual reutilizable (ej. "producto + logo + texto abajo") se
   documenta en detalle: qué elementos tiene, cómo se comporta el texto largo, las medidas exactas de
   cada tamaño que cubre. Un framework, un documento.
3. **Engine** — el motor que lee esos documentos y genera las piezas reales. Se construye después de
   que foundations y frameworks ya están documentados, nunca antes.

## El flujo completo

![Flujo de Decodex: setup → construir el conocimiento → ejecución](./decodex-flow.svg)

## Qué hay en este proyecto

| Carpeta        | Qué guarda                                                                     |
| -------------- | ------------------------------------------------------------------------------ |
| `foundations/` | Base local heredada (paleta, tipografía, logo, tono, legal): se sincroniza una vez a Decodex y queda bloqueada |
| `frameworks/`  | Documentos de framework heredados: se sincronizan una vez a Decodex y quedan bloqueados |
| `library/`     | Los insumos crudos de la marca: logos, fotos, videos, íconos, sonidos, fuentes |
| `content/`     | Las piezas ya generadas, organizadas por proyecto/campaña                      |
| `references/`  | Miniaturas/montajes de frameworks ya aprobados, para consulta visual rápida    |
| `engine/`      | El motor que genera las piezas                                                 |

## Cómo se opera esto

Este proyecto está pensado para trabajarse junto a un agente de IA que sigue las instrucciones de
`CLAUDE.md` y las reglas de `RULES.md`. Un humano aporta el criterio de marca (brandbook,
aprobaciones, copy); la IA tokeniza, documenta cada framework, y genera las piezas — siempre
preguntando antes de inventar un valor, y pidiendo aprobación antes de escalar a más variantes o
tamaños. El detalle completo de cómo opera la IA vive en `.claude/knowledge/`.

Decodex es la fuente de verdad de la marca. Si un proyecto todavía tiene contenido en
`foundations/` o `frameworks/`, la skill `decodex-sync` lo pasa a Decodex una sola vez y luego
bloquea ambas carpetas con `.decodex-sync.json` (ver `RULES.md`). Solo el usuario puede
desbloquearlas, borrando ese archivo.

## Instalación

El arnés se instala siempre desde una **release** publicada en GitHub, nunca desde `main`. Hay dos
rutas:

- **Con el plugin de Claude Code** (`/decodex:new`): crea el proyecto de marca a partir de la última
  release. Ver el README del plugin.
- **Sin plugin**, con `install-harness.sh` (el repo es público, no requiere autenticación):

```bash
# Proyecto nuevo (la carpeta debe estar vacía o no existir)
curl -fsSL https://github.com/JoseCortezz25/delivery-system-starter/releases/latest/download/install-harness.sh \
  | bash -s -- --mode install --dir ./mi-marca

# Actualizar el arnés de un proyecto existente (no toca los datos de la marca)
curl -fsSL https://github.com/JoseCortezz25/delivery-system-starter/releases/latest/download/install-harness.sh \
  | bash -s -- --mode update --dir .
```

Opciones: `--version <tag>` fija una release concreta (por defecto, la más reciente) y `--dry-run`
muestra qué cambiaría sin escribir nada. La actualización la corre la persona en su terminal, no la
IA: los hooks del arnés bloquean que la IA modifique `.claude/`, `CLAUDE.md` y `RULES.md`.

### Dependencias

| Dependencia | Para qué | Instalación (macOS) |
| --- | --- | --- |
| Claude Code | Operar el proyecto | — |
| `curl`, `tar` | Descargar e instalar el arnés | Vienen con el sistema |
| `jq` | **Obligatorio**: sin él, los hooks de protección bloquean todas las ediciones y comandos | `brew install jq` |
| Node.js (`npx`) | Servidores MCP de Playwright y Chrome DevTools | `brew install node` |
| Google Chrome | Abrir piezas y páginas de carga | — |
| Python 3.9+ con `.venv` | Exportar piezas a imagen | Ver abajo |
| Cuenta de Decodex | Conexión `decodex-brand` (login OAuth en el primer uso). Rol Codifier para configurar la marca, Maker para producir | Pedirla al equipo Decodex |

Entorno de Python, una vez por proyecto desde su raíz:

```bash
python3 -m venv .venv
.venv/bin/pip install playwright Pillow
.venv/bin/python -m playwright install chromium
```

Al abrir Claude Code dentro del proyecto, aprueba los servidores MCP del proyecto y autentícate en
`decodex-brand` con `/mcp`.

### Publicar una versión (mantenedores)

El comando de una línea descarga el instalador desde la última release
(`releases/latest/download/install-harness.sh`), así que nunca hay que editar su versión. A cambio,
**cada release debe llevar `install-harness.sh` adjunto como archivo**.

1. Publica una pre-release, adjuntando el instalador. Los instaladores la ignoran por defecto:
   ```bash
   gh release create vX.Y.Z-rc.N install-harness.sh --target main --prerelease --title "vX.Y.Z-rc.N"
   ```
2. Pruébala desde cero (script y plugin). Como `latest` no apunta a una pre-release, usa la URL del tag:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/JoseCortezz25/delivery-system-starter/vX.Y.Z-rc.N/install-harness.sh \
     | bash -s -- --mode install --dir ./prueba --version vX.Y.Z-rc.N
   ```
3. Publica la release final marcada como *Latest*, también con el instalador adjunto:
   ```bash
   gh release create vX.Y.Z install-harness.sh --target main --latest --title "vX.Y.Z"
   ```
