# Configuración Local de Git (`skip-worktree`)

Cuando utilizas este repositorio de *dotfiles*, el archivo `config/git/.gitconfig` es el archivo principal de configuración de Git que se enlaza simbólicamente (mediante stow) a tu directorio `~/.gitconfig`.

Debido a que este archivo está bajo control de versiones, cualquier cambio que hagas en él (como modificar `user.name` o `user.email` para usar tus credenciales personales en tu máquina local) aparecerá como modificado al ejecutar `git status` dentro del repositorio de dotfiles.

Para solucionar esto y mantener tus datos personales en el archivo sin que Git los rastree ni los incluya en los próximos commits, puedes utilizar la bandera `--skip-worktree` del índice de Git.

## Cómo ignorar los cambios locales

1. Edita el archivo `config/git/.gitconfig` con tus datos personales:
   ```ini
   [user]
       name = Tu Nombre Real
       email = tu_correo@ejemplo.com
   ```

2. Ejecuta el siguiente comando dentro de la carpeta `~/.dotfiles`:
   ```bash
   git update-index --skip-worktree config/git/.gitconfig
   ```

A partir de este momento, Git ignorará todas las modificaciones locales que hagas en ese archivo y al ejecutar `git status` te mostrará el árbol de trabajo limpio. Tus credenciales funcionarán perfectamente en la máquina.

## Cómo restaurar el seguimiento del archivo

Si en el futuro se actualiza el formato del `gitconfig` en el repositorio principal o si deseas enviar cambios a ese archivo, necesitas decirle a Git que vuelva a rastrearlo:

1. Ejecuta el siguiente comando dentro de la carpeta `~/.dotfiles`:
   ```bash
   git update-index --no-skip-worktree config/git/.gitconfig
   ```

2. Ahora Git volverá a marcar el archivo como modificado (debido a los cambios locales). Puedes hacer el `commit` de las modificaciones nuevas, o si prefieres descartar tus datos locales, ejecutar `git restore config/git/.gitconfig` para devolverlo al estado original del repositorio.
