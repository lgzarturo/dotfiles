# Inventario de scripts y criterios de integración

Se revisó el contenido de `/home/algforge/Scripts` el 2026-09-14 antes de
integrar nuevos comandos. Este documento evita que dos scripts realicen la
misma operación con comportamientos distintos y deja claro qué sigue siendo
específico de una máquina.

| Origen | Destino o decisión | Motivo |
|---|---|---|
| `fedora-maintenance/` | `bin/fedora-maintenance` + `config/fedora-maintenance.conf` | Integrado: CLI interactiva, configuración segura, preflight, snapshots Btrfs, RPM/Flatpak/firmware, limpieza, reinicio, reporte, progreso, `--dry-run`, timer y logs. |
| `gen-apikey.sh`, `gen-password.sh` | `bin/gen-apikey`, `bin/gen-password` | Ya integrados en versiones más completas y documentadas. |
| `gwt*.sh`, `ai-agent.sh` | `bin/gwt*`, `bin/ai-agent` | Ya integrados; no se duplican comandos. |
| `png_to_webp.sh`, `optimizador_imagenes.sh` | `bin/png2webp`, `bin/img-optimize`, `bin/img-batch-webp` | Ya integrados con CLI reutilizable. |
| `install_fonts.sh`, `bootstrap.sh`, `dev-env.sh` | `scripts/setup/` y `setup.sh` | Cubiertos por el flujo multi-plataforma e idempotente del repositorio. |
| `audit.sh`, `optimize.sh`, `system-tune.sh`, `apply-clean-updates-and-tuning.sh` | `scripts/maintenance/system-audit.sh`, `system-optimize.sh`, bibliotecas `lib/*-tune.sh` | Se conserva una sola ruta de tuning; los originales mezclan hardware concreto y escrituras globales. |
| `dell-kbd-backlight.sh`, `fix-howdy-lockscreen.sh`, `switch-dm.sh` | `scripts/hardware/`, `scripts/desktop/` | Ya integrados como scripts específicos, con ayuda y modos de estado/reversión cuando aplica. |
| `01`–`04-fedora-*.sh` | `setup.sh`, `scripts/setup/git-tools.sh` | Son instaladores lineales antiguos; no se integran para evitar duplicar repositorios, descargas y cambios en `~/.zshrc`. |
| `cosmic-*.sh`, `install-cosmic-desktop.sh` | Pendientes de una revisión dedicada | Son cambios de escritorio y display manager de alto impacto; requieren perfil de hardware/DE antes de automatizarlos. |
| `spotify-a-mp3.sh`, `ptw_blog.sh`, `validate_domain.sh` | Se mantienen fuera del setup | Requieren datos externos específicos (playlist, blog o dominio/IP). No deben ejecutarse durante bootstrap. |

## Cobertura de `fedora-maintenance`

La integración conserva las responsabilidades de todos los módulos del proyecto
original, corrigiendo los puntos que podían bloquear o dañar una transacción
offline:

| Módulo original | Implementación en el framework |
|---|---|
| `cli.sh`, `ui.sh` | Flags completos, menú `gum` con fallback Bash y aliases seguros. |
| `config.sh` | Parser sin `source`/`eval`, tres niveles de configuración y precedencia CLI. |
| `validator.sh` | Validación Fedora, rechazo de Atomic, batería y red con timeout visible. |
| `snapshot.sh` | Snapshot de solo lectura antes de cualquier cambio RPM/firmware sobre Btrfs. |
| `dnf.sh` | DNF4/DNF5, modo online/offline y progreso nativo visible; no existe preconsulta silenciosa. |
| `flatpak.sh`, `fwupd.sh` | Ámbitos system/user y protección de batería para firmware. |
| `cleanup.sh` | Caché, autoremove, runtimes Flatpak y retención de logs configurables. La limpieza ocurre antes de preparar paquetes offline. |
| `reboot.sh` | `needs-restarting`, aviso explícito y reinicio automático solo por opt-in. |
| `systemd.sh` | Estado, logs, instalación idempotente y timer conservador sin firmware/reinicio. |
| `report.sh`, `logger.sh` | Resumen de duración/resultado, archivo de log y journal mediante stdout/stderr. |

`fm-status` usa `dnf --cacheonly` y `STATUS_TIMEOUT`; por tanto nunca inicia una
actualización de metadatos oculta. `fm-menu` muestra el modo online/offline y la
configuración efectiva antes de pedir confirmación.

## Criterio para nuevos scripts

Un script entra en `bin/` si es una utilidad diaria sin configuración personal;
entra en `scripts/maintenance/`, `hardware/` o `desktop/` si modifica el
sistema. Debe incluir `--help`, un modo de consulta o `--dry-run` cuando sea
posible, confirmación antes de cambios, operaciones repetibles y no asumir una
ruta personal. Los scripts con credenciales, dominios, dispositivos concretos
o descargas multimedia permanecen fuera del flujo automático hasta que tengan
una configuración explícita y segura.
