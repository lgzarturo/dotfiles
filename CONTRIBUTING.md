# Guía de contribución

¡Gracias por tu interés en mejorar este proyecto! Esta guía explica cómo
contribuir de forma efectiva.

---

## Tabla de contenidos

- [Código de conducta](#código-de-conducta)
- [¿Cómo puedo contribuir?](#cómo-puedo-contribuir)
- [Entorno de desarrollo](#entorno-de-desarrollo)
- [Flujo de trabajo](#flujo-de-trabajo)
- [Convención de commits](#convención-de-commits)
- [Nomenclatura de ramas](#nomenclatura-de-ramas)
- [Proceso de Pull Request](#proceso-de-pull-request)
- [Estándares de código](#estándares-de-código)
- [Reportar vulnerabilidades](#reportar-vulnerabilidades)

---

## Código de conducta

Este proyecto se rige por el [Código de conducta](CODE_OF_CONDUCT.md). Al
participar, aceptas cumplir sus términos.

---

## ¿Cómo puedo contribuir?

### Reportar un bug

1. Busca en los [issues existentes](../../issues) para evitar duplicados.
2. Si no existe, abre un [nuevo bug report](../../issues/new?template=bug_report.md).
3. Incluye: SO, versión, pasos para reproducir, salida del script y resultado esperado.

### Proponer una mejora

1. Busca en los issues si ya fue sugerida.
2. Abre un [feature request](../../issues/new?template=feature_request.md).
3. Explica el problema que resuelve y los casos de uso.

### Enviar código

Para correcciones pequeñas (typos, un liner), puedes abrir un PR directamente.  
Para cambios mayores, abre primero un issue para discutir el enfoque.

---

## Entorno de desarrollo

### Requisitos

| Herramienta | Versión mínima | Notas |
|-------------|----------------|-------|
| bash        | 4.0            | macOS usa zsh por defecto — instala bash vía Homebrew |
| shellcheck  | 0.9            | Linter para scripts bash/sh |
| PowerShell  | 7.0            | Solo para cambios en `setup.ps1` |

### Configuración inicial

```bash
git clone https://github.com/<tu-usuario>/dotfiles.git
cd dotfiles

# Verificar que el entorno es correcto
bash --version
shellcheck --version
```

### Ejecutar en dry-run (sin cambios reales)

```bash
# Linux / macOS / WSL
bash setup.sh --dry-run

# Windows
.\setup.ps1 -DryRun
```

### Lint de scripts

```bash
# Revisar un script individual
shellcheck lib/agent-tools.sh

# Revisar todos los scripts bash
shellcheck setup.sh lib/*.sh
```

---

## Flujo de trabajo

```
main
 └── feature/nombre-descriptivo   ← tu rama
      └── (commits)
           └── Pull Request → main
```

1. Haz un fork del repositorio.
2. Crea una rama a partir de `main` (ver nomenclatura más abajo).
3. Aplica tus cambios siguiendo los estándares de código.
4. Ejecuta el script en `--dry-run` para verificar que no hay errores de sintaxis.
5. Ejecuta `shellcheck` sobre los archivos modificados.
6. Abre un Pull Request hacia `main`.

---

## Convención de commits

Este proyecto usa [Conventional Commits](https://www.conventionalcommits.org/)
**en español**.

### Formato

```
<tipo>(<scope>): <descripción corta>

- <detalle 1>
- <detalle 2>
```

### Tipos válidos

| Tipo       | Cuándo usarlo |
|------------|---------------|
| `feat`     | Nueva funcionalidad |
| `fix`      | Corrección de bug |
| `docs`     | Cambios en documentación |
| `style`    | Formato, espacios (sin cambio de lógica) |
| `refactor` | Reestructuración sin cambio de comportamiento |
| `test`     | Adición o corrección de tests |
| `chore`    | Tareas de mantenimiento (deps, CI) |
| `perf`     | Mejoras de rendimiento |
| `ci`       | Cambios en pipelines de CI/CD |

### Reglas

- Idioma: **español neutro** siempre.
- Encabezado: máximo **69 caracteres**, sin punto final.
- Cuerpo: viñetas concisas, una idea por línea.
- Sin gerundios (`"agregando"`, `"corrigiendo"`).
- Usar infinitivo o imperativo (`"agregar"`, `"corregir"`, `"actualizar"`).

### Ejemplos

```
fix(setup.sh): corregir nombre de paquete xz en Ubuntu

- El paquete correcto en APT es xz-utils, no xz
- La rama Fedora/RHEL ya usaba el nombre correcto

feat(agent-tools): actualizar npm y node antes de instalar paquetes

- Agregar _update_node_npm() que ejecuta npm install -g npm@latest
- Incluir mise upgrade node como best-effort antes de Claude Code
```

---

## Nomenclatura de ramas

```
feat/descripcion-corta          ← nueva funcionalidad
fix/descripcion-del-bug         ← corrección de bug
docs/lo-que-se-documenta        ← solo documentación
chore/tarea-de-mantenimiento    ← deps, lint, refactor menor
```

Usa kebab-case y máximo 50 caracteres después del prefijo.

---

## Proceso de Pull Request

1. **Título**: sigue el mismo formato que los commits (`tipo(scope): descripción`).
2. **Descripción**: completa el template — no lo borres.
3. **Scope**: un PR por tema. Si tocas `setup.sh` y `lib/agent-tools.sh` porque
   están relacionados, está bien. Si son temas distintos, abre dos PRs.
4. **Dry-run**: confirma que `--dry-run` pasa sin errores en Linux y/o Windows.
5. **Shellcheck**: sin warnings en los archivos modificados.
6. **CHANGELOG**: actualiza `[Unreleased]` con una entrada en la sección
   correspondiente (`Added`, `Fixed`, `Changed`, etc.).

El mantenedor revisará el PR en un plazo razonable. Si no hay respuesta en
14 días, puedes hacer un comentario de seguimiento.

---

## Estándares de código

### Bash

- Siempre incluir `#!/usr/bin/env bash` como shebang.
- Los scripts de lib deben ser sourceados, no ejecutados directamente.
- Usar las funciones de `lib/logger.sh`: `log_info`, `log_warn`, `log_error`,
  `log_success`, `log_debug`.
- Respetar la variable `DOTFILES_DRY_RUN`: verificar antes de cualquier
  operación con efecto secundario.
- Manejar errores con `|| log_warn "mensaje"` o `|| true` según corresponda.
- Variables locales dentro de funciones: usar `local`.
- No usar `echo` para log — siempre usar las funciones de `logger.sh`.

### PowerShell

- Usar `#Requires -Version 7` cuando sea posible.
- Respetar la variable `$DryRun` con el mismo patrón que el bash.
- Usar `Write-Log` o la función equivalente del script, no `Write-Host` directo.
- Manejo de errores: `try/catch` para operaciones críticas.

### Documentación

- Los archivos en `docs/` están en español.
- `CHANGELOG.md` sigue el formato [Keep a Changelog](https://keepachangelog.com/es/).
- Los comentarios en código pueden estar en español o inglés, pero sé consistente
  dentro del mismo archivo.

---

## Reportar vulnerabilidades

No abras un issue público para vulnerabilidades de seguridad.  
Consulta [SECURITY.md](SECURITY.md) para el proceso de divulgación responsable.

---

## Licencia

Al contribuir, aceptas que tu código se publique bajo la
[Licencia MIT](LICENSE) del proyecto.
