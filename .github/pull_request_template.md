# Pull Request

## Tipo de cambio

<!-- Marca el tipo que corresponde -->

- [ ] `fix` — corrección de bug
- [ ] `feat` — nueva funcionalidad
- [ ] `docs` — solo documentación
- [ ] `refactor` — reestructuración sin cambio de comportamiento
- [ ] `chore` — mantenimiento (deps, CI, lint)
- [ ] `perf` — mejora de rendimiento

## Descripción

<!-- ¿Qué cambia y por qué? -->

## Issue relacionado

<!-- Si resuelve un issue: "Closes #123" -->
<!-- Si es referencia: "Ref #123" -->

Closes #

## Checklist

### Obligatorio

- [ ] El título del PR sigue el formato `tipo(scope): descripción corta` en español
- [ ] Los commits siguen la [convención del proyecto](../CONTRIBUTING.md#convención-de-commits)
- [ ] `CHANGELOG.md` actualizado bajo `[Unreleased]`

### Bash / Shell (si aplica)

- [ ] `shellcheck` sin warnings en los archivos modificados
- [ ] Verificado con `bash setup.sh --dry-run` en Linux o WSL2
- [ ] Las funciones nuevas usan `log_info`/`log_warn`/`log_error` de `lib/logger.sh`
- [ ] Las operaciones con efecto secundario respetan `$DOTFILES_DRY_RUN`
- [ ] Variables locales declaradas con `local` dentro de funciones

### PowerShell (si aplica)

- [ ] Verificado con `.\setup.ps1 -DryRun` en Windows 11
- [ ] Las operaciones con efecto secundario respetan `$DryRun`

### Documentación

- [ ] Documentación actualizada si el comportamiento visible cambió
- [ ] Comentarios en código explicativos donde sea necesario

## Plataformas probadas

<!-- Marca las que hayas podido verificar -->

- [ ] Linux (Ubuntu / Debian)
- [ ] Linux (Fedora / RHEL)
- [ ] Linux (Arch / Manjaro)
- [ ] macOS
- [ ] Windows 11 (native PowerShell)
- [ ] WSL2

## Salida del dry-run

<!-- Pega la salida relevante de `--dry-run` / `-DryRun` si aplica -->

```
(salida aquí)
```

## Contexto adicional

<!-- Capturas de pantalla, notas de implementación, decisiones de diseño, etc. -->
