# Hermes aislado para OpenCode

Esta configuracion ejecuta Hermes Agent en un contenedor desechable y conserva
solamente su estado en `data/` y los archivos de trabajo en `workspace/`.
OpenCode puede delegar tareas mediante el subagente `hermes` o la herramienta
del mismo nombre.

## Limites aplicados

- Sin acceso al socket de Docker, al directorio personal ni al proyecto desde
  el que se ejecute OpenCode.
- Solo `data/` y `workspace/` se montan con escritura.
- Proceso de agente no-root y arbol de instalacion `/opt/hermes` inmutable por
  los permisos de la imagen oficial. Todas las capabilities se eliminan salvo
  las requeridas por su arranque no-root.
- Limites de 2 CPU, 4 GiB de RAM y 256 procesos.
- No se publica ningun puerto.

Hermes mantiene salida a Internet para consultar al proveedor LLM. Docker por
si solo no restringe la salida a dominios concretos ni impide alcanzar todos
los servicios de la LAN; para ese nivel de aislamiento se necesita un proxy de
egress o reglas de firewall adicionales.

## Preparacion

Define el UID/GID del usuario del host y valida la configuracion:

```bash
cp .env.example .env
sed -i "s/^HERMES_UID=.*/HERMES_UID=$(id -u)/; s/^HERMES_GID=.*/HERMES_GID=$(id -g)/" .env
docker compose config --quiet
```

Ejecuta una vez el asistente de Hermes. Las credenciales se guardan en
`data/.env`, no en la configuracion de OpenCode:

```bash
docker compose run --rm hermes setup
```

Prueba una consulta aislada:

```bash
docker compose run --rm hermes chat -q "Resume los archivos de /workspace"
```

## Uso desde OpenCode

Abre OpenCode desde este directorio para que descubra `.opencode/`:

```bash
opencode /home/gnino/Documents/Hermes
```

Luego selecciona o menciona el subagente `hermes`, o pide al agente principal
que use la herramienta `hermes`. Reinicia OpenCode si ya estaba abierto cuando
se crearon estos archivos.

Los proyectos que Hermes deba modificar deben copiarse o clonarse dentro de
`workspace/`. No montes `/var/run/docker.sock`: equivaldria practicamente a
darle control total sobre el host.
