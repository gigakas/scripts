# 1. Hace que el Dock lateral SOLO muestre las apps de tu workspace actual
gsettings set org.gnome.shell.extensions.dash-to-dock isolate-workspaces true

# 2. Hace que al pulsar Alt + Tab SOLO veas las ventanas de tu workspace actual
gsettings set org.gnome.shell.app-switcher current-workspace-only true

# 3. Cambia la acción del clic en el dock para que no te fuerce a saltar de escritorio
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize-or-previews'
