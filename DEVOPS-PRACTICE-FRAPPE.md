# Ejercicio práctico: DevOps completo con Frappe Framework

Ejercicio de práctica personal para recorrer el ciclo completo de DevOps
(build → test → deploy → operar → observar → escalar → mejorar) usando una
app real de gran escala como sujeto: **Frappe Framework** (el framework
detrás de ERPNext).

No es un tutorial paso a paso con copiar/pegar garantizado — es una guía de
fases con las herramientas y el objetivo de cada una. Cada fase asume que
resolviste la anterior y podés investigar los detalles de configuración
sobre la marcha (así se practica de verdad).

---

## Por qué Frappe y no un "hello world"

Frappe/ERPNext no es una app de un solo proceso — es un sistema multi-servicio
real, del mismo tipo que vas a encontrar en un trabajo de DevOps profesional:

| Servicio | Rol | Por qué es interesante para practicar |
|---|---|---|
| `web` (gunicorn, Python) | Sirve la app y la API | Stateless, fácil de escalar horizontalmente |
| `worker` (background jobs) | Procesa colas via Redis Queue (RQ) | Escalar según profundidad de cola, no CPU — el caso de uso ideal para **KEDA** |
| `scheduler` | Tareas cron-like internas | Debe correr como réplica única (no se puede escalar sin coordinación) |
| `socketio` (Node.js) | WebSockets en tiempo real | El clásico problema de escalar estado/sesiones |
| `nginx` | Reverse proxy / estáticos | Ingress y TLS |
| `mariadb` | Base de datos | Backups, PVs, StatefulSets |
| `redis-cache` / `redis-queue` | Cache y broker de colas | Dependencias con estado que todo lo demás necesita sano |

Tiene además un repo oficial ya pensado para Docker (`frappe_docker`) y un
Helm chart oficial — así que no partís de cero armando Dockerfiles, podés
enfocarte en la parte de DevOps en sí.

---

## Herramientas a instalar (por categoría)

Asumiendo Ubuntu/Debian (igual que `system/install-docker.sh` de este repo).
Instalá esto de forma incremental, fase por fase — no hace falta todo el
día 1.

### Base (Fase 0-1)

| Herramienta | Para qué | Instalación |
|---|---|---|
| Docker + Compose | Contenerizar y correr Frappe en dev | `sudo bash system/install-docker.sh` (ya en este repo) |
| `git` / `gh` | Versionado, PRs, Actions | Ya los tenés |

### Kubernetes local (Fase 4 en adelante — "simular producción")

| Herramienta | Para qué | Instalación |
|---|---|---|
| `kind` | Cluster de Kubernetes local en Docker (simula un cluster real) | `curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x kind && sudo mv kind /usr/local/bin/` |
| `kubectl` | CLI de Kubernetes | `curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install -m 0755 kubectl /usr/local/bin/kubectl` |
| `helm` | Gestor de paquetes de k8s (charts) | `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash` |
| `k9s` | TUI para navegar el cluster sin pelear con `kubectl get` todo el tiempo | `sudo snap install k9s` (o binario desde sus releases de GitHub) |

### CI/CD (Fase 3 y 5)

| Herramienta | Para qué |
|---|---|
| GitHub Actions | CI: lint, test, build de imagen, push a registry, scan de seguridad |
| GHCR (`ghcr.io`) | Registry de imágenes (gratis, integrado a tu cuenta de GitHub) |
| ArgoCD | CD por GitOps: el cluster se sincroniza solo con lo que hay en un repo git |

### Observabilidad (Fase 6)

| Herramienta | Para qué | Instalación |
|---|---|---|
| kube-prometheus-stack | Métricas (Prometheus) + dashboards (Grafana) + alertas (Alertmanager), todo en un Helm chart | `helm install monitoring prometheus-community/kube-prometheus-stack` |
| Loki + Promtail | Logs centralizados de todos los pods, sin pelear con `kubectl logs` por pod | Helm chart `grafana/loki-stack` |

### Escalabilidad (Fase 7)

| Herramienta | Para qué |
|---|---|
| HPA (nativo de k8s) | Auto-escala pods por CPU/memoria |
| **KEDA** | Auto-escala por métricas custom — en Frappe, por **longitud de la cola de Redis**, que es la señal real de carga de los workers, no la CPU |
| `k6` o `Locust` | Generar carga contra `web` para forzar el auto-escalado y medir el comportamiento |

### Seguridad (Fase 8)

| Herramienta | Para qué |
|---|---|
| `trivy` | Escanear la imagen construida en busca de CVEs antes de subirla al registry |
| `kube-linter` o `checkov` | Detectar malas prácticas en los manifests de k8s (privilegios excesivos, sin límites de recursos, etc.) |
| Sealed Secrets (o Vault) | Poder versionar secretos cifrados en git sin exponer las credenciales reales |

### Backup / DR (Fase 9)

| Herramienta | Para qué |
|---|---|
| Velero | Backup/restore de namespaces completos + volúmenes persistentes (la base de datos de Frappe vive ahí) |

### Entrega progresiva (Fase 10)

| Herramienta | Para qué |
|---|---|
| Argo Rollouts | Canary / blue-green deploys reales, no solo `kubectl apply` directo a 100% del tráfico |

---

## Fases del ejercicio

### Fase 1 — Baseline en Docker Compose

Cloná el repo oficial `frappe/frappe_docker` y levantá un sitio con su
`docker-compose` de ejemplo (Compose ya lo conocés por el stack de `ai/` de
este mismo repo). Objetivo: tener ERPNext funcionando localmente y entender
qué hace cada contenedor antes de complicarlo con Kubernetes.

**Criterio de éxito:** entrás al sitio por navegador, creás un usuario, y
podés ver en `docker compose ps` los 7+ contenedores corriendo sanos.

### Fase 2 — Entender la imagen

Mirá el `Dockerfile` que usa `frappe_docker` (multi-stage: build de assets
con Node, instalación de la app Python vía `bench`). Modificá algo trivial
del código de una app de Frappe custom y reconstruí la imagen a mano.

**Criterio de éxito:** podés explicar qué hace cada stage del Dockerfile y
por qué está separado así (cache de capas, tamaño final de imagen).

### Fase 3 — CI con GitHub Actions

Armá un workflow que en cada push:
1. Corra lint (`ruff`/`flake8`) y tests (`bench run-tests`).
2. Construya la imagen.
3. La escanee con `trivy` (fallar el build si hay CVEs críticos).
4. La suba a GHCR con el tag del commit SHA.

**Criterio de éxito:** un push con un test roto falla el pipeline antes de
llegar a construir o subir nada.

### Fase 4 — "Producción" simulada con Kubernetes

Levantá un cluster local con `kind` y desplegá Frappe con su Helm chart
oficial (o escribí los manifests vos: `Deployment` para `web` y `worker`
con `replicas: 2+`, el `scheduler` con `replicas: 1` fijo, MariaDB y Redis
vía los charts de Bitnami, `Ingress` con `ingress-nginx`).

**Criterio de éxito:** matás un pod de `web` a mano (`kubectl delete pod`)
y el sitio sigue respondiendo porque hay más de una réplica.

### Fase 5 — CD por GitOps con ArgoCD

Instalá ArgoCD en el mismo cluster. Apuntalo a una carpeta de tu repo con
los manifests/values de Helm. Cambiá un valor (ej. el tag de la imagen o el
número de réplicas), hacé `git push`, y mirá cómo ArgoCD lo aplica solo sin
que corras `kubectl apply`.

**Criterio de éxito:** el estado del cluster siempre coincide con lo que
dice el repo git — si alguien cambia algo a mano con `kubectl edit`, ArgoCD
lo revierte solo (esa es la garantía de GitOps).

### Fase 6 — Observabilidad

Instalá `kube-prometheus-stack` y `loki-stack`. Armá un dashboard de Grafana
que muestre: requests/seg de `web`, profundidad de la cola de Redis, uso de
CPU/memoria de los `worker`. Configurá una alerta simple (ej. "más de 100
jobs pendientes en cola por más de 2 minutos").

**Criterio de éxito:** podés responder "¿qué está pasando ahora mismo?" del
sistema completo mirando un solo dashboard, sin entrar a ningún pod.

### Fase 7 — Escalabilidad real

Configurá KEDA para escalar los `worker` según la longitud de la cola de
Redis (no CPU). Generá carga con `k6` disparando tareas pesadas (ej. generar
reportes) y mirá en Grafana cómo KEDA agrega pods de `worker` a medida que
crece la cola, y los quita cuando baja.

**Criterio de éxito:** podés mostrar el gráfico de "cola sube → pods de
worker suben → cola baja → pods bajan" — esa curva es la prueba de que el
auto-escalado funciona de verdad y no es cosmético.

### Fase 8 — Seguridad

Escaneá la imagen final con `trivy` y arreglá al menos una vulnerabilidad
real que encuentre. Migrá las credenciales de MariaDB/Redis de `Secret`
plano a Sealed Secrets, de forma que puedas commitear el secreto cifrado al
repo sin exponer la contraseña real.

**Criterio de éxito:** tu repo de manifests no tiene ni un solo secreto en
texto plano, pero el cluster igual arranca sano.

### Fase 9 — Backup y Disaster Recovery

Con Velero, hacé un backup del namespace completo (incluyendo el volumen de
MariaDB). Borrá el namespace entero a propósito. Restaurá desde el backup.

**Criterio de éxito:** después de restaurar, el usuario que creaste en la
Fase 1 sigue existiendo — probaste que el backup realmente contiene datos
recuperables, no solo la definición de los recursos.

### Fase 10 — Mejora continua / entrega progresiva

Con Argo Rollouts, convertí el deploy de `web` en un canary: la nueva
versión recibe el 10% del tráfico, se observa por unos minutos con las
métricas de la Fase 6, y si no hay errores se promueve al 100% de forma
automática o manual.

**Criterio de éxito:** podés desplegar una versión con un bug intencional,
verla fallar solo en el 10% del tráfico canario, y hacer rollback sin que el
90% restante de usuarios haya notado nada.

---

## Checklist final

- [ ] App corriendo en Compose (dev) y en Kubernetes local (prod simulada)
- [ ] Pipeline de CI que testea, escanea y construye antes de publicar
- [ ] Deploy por GitOps, no por `kubectl apply` manual
- [ ] Dashboard de observabilidad de todo el sistema en un solo lugar
- [ ] Auto-escalado demostrado con una métrica de negocio (cola), no solo CPU
- [ ] Cero secretos en texto plano en el repo de manifests
- [ ] Backup/restore probado de punta a punta (no solo "corrí el comando")
- [ ] Un deploy canario con rollback demostrado

Si completás las 10 fases con sus criterios de éxito, recorriste el mismo
ciclo que se espera de un rol de DevOps/Platform Engineer en una empresa que
opera a escala — la diferencia con un entorno real es solo el tamaño del
cluster y que nadie más depende de que no la rompas.

---

## Referencias

- Frappe Docker (oficial): https://github.com/frappe/frappe_docker
- Frappe Helm chart (oficial): https://github.com/frappe/helm
- Kubernetes: https://kubernetes.io
- Helm: https://helm.sh
- ArgoCD: https://argo-cd.readthedocs.io
- KEDA: https://keda.sh
- k6: https://k6.io
- Trivy: https://trivy.dev
- Velero: https://velero.io
- Argo Rollouts: https://argoproj.github.io/rollouts
