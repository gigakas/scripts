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

## Topología de VMs/LXC (infraestructura real, no `kind`)

El host real es un Proxmox que corre **anidado dentro de una VM de VMware**,
con 16 vCPU / 32 GB RAM / 400 GB libres disponibles en total para *todo* lo
de este ejercicio (incluyendo `local.devops`, que también vive ahí). En vez
de simular el cluster de Kubernetes dentro de una sola VM con `kind` (nodos
como contenedores), armamos un cluster real con `kubeadm` repartido en
varias VMs — es la diferencia entre simular un cluster y operar uno de
verdad (red entre nodos real, bootstrap con tokens de join, etcd, CNI).

**Convención de nombres:** cada servidor tiene un dominio `local.<nombre>`
para identificarlo rápido (mismo patrón que ya usa `local.devops`).

**Mapa de IPs (`/etc/hosts`) — ya creadas:**

| Dominio | IP | Tipo |
|---|---|---|
| `local.devops` | 192.168.171.100 | VM *(sin responder — revisar)* |
| `local.k8s-cp` | 192.168.171.101 | VM |
| `local.k8s-worker1` | 192.168.171.102 | VM |
| `local.k8s-worker2` | 192.168.171.103 | VM |
| `local.k8s-ci-runner` | 192.168.171.104 | VM |
| `local.monitoring` | 192.168.171.105 | LXC |
| `local.registry` | 192.168.171.106 | LXC |

**VM vs LXC:** un nodo necesita ser **VM** (kernel propio) si corre
containers anidados — kubelet+containerd (para correr pods) o Docker (para
`docker build`) necesitan crear namespaces/cgroups y cargar módulos de
kernel (`br_netfilter`, `overlay`) que un LXC no privilegiado no permite.
Si el componente es un binario nativo sin Docker de por medio (Prometheus,
Grafana, Loki, o el registry simple), **LXC alcanza y es más liviano**.

**Specs — tabla rápida:**

| Dominio | Tipo | vCPU | RAM | Disco | Rol (corto) |
|---|---|---|---|---|---|
| `local.devops` *(ya existe, bajar a 2 vCPU)* | VM | 2 | 4 GB | 40 GB | Bastion / control node |
| `local.k8s-cp` | VM | 2 | 4 GB | 40 GB | Control plane (kubeadm) |
| `local.k8s-worker1` | VM | 2 | 6 GB | 50 GB | Nodo worker |
| `local.k8s-worker2` | VM | 2 | 6 GB | 50 GB | Nodo worker |
| `local.k8s-ci-runner` | VM | 2 | 3 GB | 40 GB | CI/CD (runner GitHub Actions) |
| `local.monitoring` | **LXC** | 2 | 3 GB | 40 GB | Observabilidad (Prometheus/Grafana/Loki) |
| `local.registry` *(opcional)* | **LXC** | 1 | 2 GB | 60 GB | Registry privado |
| **Total (sin `registry`)** | | **12** | **26 GB** | **300 GB** | deja 4 vCPU / 6 GB / 100 GB libres |
| **Total (con `registry`)** | | **13** | **28 GB** | **360 GB** | deja 3 vCPU / 4 GB / 40 GB libres |

**Detalle de cada nodo:**

- **`local.devops`** — bastion/control node. Acá viven `kubectl`, `helm`,
  `k9s`, `trivy`, `k6`, `argocd` y `velero` (los clientes ya instalados en
  `system/00-08`). No corre workloads ni es parte del cluster — es desde
  donde lo operás. Tenía 8 vCPU asignados; bajarlo a 2 libera cores para el
  resto sin perder nada (es solo un cliente CLI). 40 GB de disco alcanza de
  sobra: son binarios livianos + el repo `frappe_docker` clonado + las
  imágenes del demo de la Fase 1 (unos 3-4 GB). `kind` queda instalado pero
  sin uso en este plan.
- **`local.k8s-cp`** *(VM)* — control plane de `kubeadm init`: etcd,
  kube-apiserver, scheduler, controller-manager. 2 vCPU/4 GB es el mínimo
  recomendado por kubeadm. Por defecto no agenda pods de la app (taint
  `NoSchedule`).
- **`local.k8s-worker1` / `local.k8s-worker2`** *(VM)* — corren los pods de
  Frappe, ArgoCD y KEDA. Con 2 workers ya se puede demostrar HPA/KEDA
  moviendo y escalando pods entre nodos.
- **`local.k8s-ci-runner`** *(VM)* — runner self-hosted de GitHub Actions
  (`docker build` + push de imágenes). El disco extra es para la cache de
  capas de Docker/buildx.
- **`local.monitoring`** *(LXC)* — Prometheus + Grafana + Loki,
  **desacoplado** del cluster de la app. Son binarios Go nativos (systemd,
  sin Docker), por eso LXC no privilegiado alcanza sin ningún truco.
- **`local.registry`** *(LXC, opcional)* — el binario simple `registry`
  (lo que corre adentro de la imagen `registry:2`) también es nativo, sin
  Docker — anda bien en LXC. Si en cambio preferís Harbor (multi-contenedor,
  instala vía Docker Compose), necesita el mismo nesting que Docker: mejor
  VM. GHCR (gratis) cubre lo mismo sin necesitar esta VM/LXC en absoluto.

**Docker vs containerd — dónde va cada uno** (punto comun de confusion):
Docker (el Engine completo) **no va en los nodos del cluster**. Desde
Kubernetes 1.24 se saco el `dockershim`, asi que `kubelet` habla directo con
**containerd** (se instala junto con `kubeadm` en la Fase 4, no es un paso
aparte). Docker solo hace falta donde alguien corre `docker build` o
`docker compose up` a mano:

| Nodo | ¿Docker? | ¿containerd? |
|---|---|---|
| `local.k8s-cp` / `local.k8s-worker*` | No | Si (via kubeadm) |
| `local.k8s-ci-runner` | Si (`docker build` + push) | No |
| `local.devops` | Si, solo para el demo de Frappe de la Fase 1 | No |
| `local.monitoring` / `local.registry` | No (binarios nativos) | No |

**Prerrequisitos de `kubeadm`** a tener en cuenta al crear `local.k8s-cp` y
los `local.k8s-worker*` (esto es contenido de la Fase 4, no hace falta
resolverlo ahora): swap desactivado, hostname y
`/sys/class/dmi/id/product_uuid` únicos por VM (cuidado si cloneas una VM de
otra sin regenerar esto), módulos de kernel `br_netfilter` + `overlay`
cargados, y elegir un CNI (Calico o Flannel) antes del primer `kubeadm init`.

---

## Herramientas a instalar (por categoría)

Asumiendo Ubuntu/Debian (igual que `system/00-install-docker.sh` de este repo).
Instalá esto de forma incremental, fase por fase — no hace falta todo el
día 1.

### Base (Fase 0-1)

| Herramienta | Para qué | Instalación |
|---|---|---|
| Docker + Compose | Contenerizar y correr Frappe en dev | `sudo bash system/00-install-docker.sh` (ya en este repo) |
| `git` / `gh` | Versionado, PRs, Actions | Ya los tenés |

### Kubernetes (Fase 4 en adelante — cluster real con kubeadm)

Ya instalados y probados en `local.devops` via `system/00-08-install-*.sh`
(ver tabla de scripts en el `README.md` raíz del repo):

| Herramienta | Para qué |
|---|---|
| `kubectl` | CLI de Kubernetes — corre desde `local.devops`, apunta al cluster remoto |
| `helm` | Gestor de paquetes de k8s (charts) |
| `k9s` | TUI para navegar el cluster sin pelear con `kubectl get` todo el tiempo |
| `kind` | Instalado pero **sin uso** en el plan actual (multi-VM con kubeadm en vez de nodos-como-contenedores) — queda como alternativa liviana si en algún momento faltan recursos para las VMs dedicadas |

Falta instalar en `k8s-cp`/`k8s-worker-*` (no en `local.devops`): `kubeadm`,
`kubelet`, `kubectl` (version-matched) y el runtime de contenedores
(`containerd`) — eso es contenido de la Fase 4 en sí, no de esta lista de
herramientas base.

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

Cloná el repo oficial `frappe/frappe_docker` y levantá un sitio con `pwd.yml`
(el demo descartable de un solo archivo). Objetivo: tener ERPNext
funcionando localmente y entender qué hace cada contenedor antes de
complicarlo con Kubernetes.

**Importante:** `pwd.yml` es explícitamente un demo "solo para evaluación
corta" — **no soporta apps custom**. Si tu plan incluye una app propia (ver
Fase 2), esta fase es solo para el smoke test inicial con Frappe/ERPNext
vanilla; el setup real con tu app va en la Fase 2.

**Criterio de éxito:** entrás al sitio por navegador, creás un usuario, y
podés ver en `docker compose ps` los 7+ contenedores corriendo sanos.

### Fase 2 — Entender la imagen (con tus 10 apps custom de Azure Repos)

Tu caso concreto: 10 apps ya existentes en repos privados de Azure DevOps
(no hay que crearlas, solo integrarlas al build).

1. **`apps.json`** en la raíz de `frappe_docker`, una entrada por app. Las
   10 viven en la misma organización/proyecto de Azure DevOps, así que un
   solo PAT alcanza para todas — solo cambia el nombre del repo (`_git/<repo>`)
   en cada URL:
   ```json
   [
     { "url": "https://github.com/frappe/erpnext", "branch": "version-16" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app1", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app2", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app3", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app4", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app5", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app6", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app7", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app8", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app9", "branch": "main" },
     { "url": "https://${AZURE_PAT}@dev.azure.com/TU_ORG/TU_PROYECTO/_git/app10", "branch": "main" }
   ]
   ```
   Reemplazá `TU_ORG`/`TU_PROYECTO` y los 10 nombres de repo por los reales
   (y el `branch` de cada una, si no todas usan `main`).

2. **Nunca commitees `apps.json` con el PAT real adentro.** Guardá un
   `apps.json.template` en git con el placeholder `${AZURE_PAT}` literal, y
   generá el `apps.json` real (con el token ya sustituido) recién antes del
   build, en un paso descartable:
   ```bash
   envsubst < apps.json.template > apps.json   # sustituye ${AZURE_PAT} por la variable de entorno
   ```
   Agregá `apps.json` (sin `.template`) a `.gitignore`. El PAT en sí vive
   como secret de GitHub Actions (Fase 3) o como variable de entorno local,
   nunca en el repo.

3. **Buildeá la imagen custom** (requiere Docker Engine v23+; usa BuildKit
   secrets para que ni el `apps.json` ni el PAT queden en las capas o en
   `docker image history`):
   ```bash
   docker build --no-cache \
     --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
     --build-arg=FRAPPE_BRANCH=version-16 \
     --secret=id=apps_json,src=apps.json \
     --tag=custom:16 \
     --file=images/layered/Containerfile .
   ```
   Con 10 apps el build tarda bastante más — para reconstruir rápido en
   iteraciones futuras usá `CACHE_BUST` (ver Fase 3) en vez de `--no-cache`
   cada vez; solo la primera build de referencia se hace con `--no-cache`.

4. **Desplegá con el compose completo** (no `pwd.yml`): `compose.yaml` +
   overrides, con `CUSTOM_IMAGE=custom` / `CUSTOM_TAG=16` /
   `PULL_POLICY=missing` en el `.env` para que use tu imagen local.

**Criterio de éxito:** el sitio corre con las 10 apps custom instaladas y
visibles en el Desk de Frappe, `apps.json` (con el PAT real) nunca aparece
en `git log` ni en `docker image history`, y podés explicar qué hace cada
stage del `Containerfile`.

### Fase 3 — CI con GitHub Actions

Armá un workflow que en cada push:
1. Corra lint (`ruff`/`flake8`) y tests (`bench run-tests`).
2. Genere `apps.json` desde `apps.json.template` sustituyendo `${AZURE_PAT}`
   por un **GitHub Actions secret** (`Settings > Secrets > Actions`) — nunca
   hardcodeado en el workflow ni en el repo.
3. Construya la imagen (sin `--no-cache`; usá `CACHE_BUST=$GITHUB_SHA` para
   invalidar el cache solo cuando cambia el commit, no en cada run — con 10
   apps esto es la diferencia entre un build de minutos y uno de segundos).
4. La escanee con `trivy` (fallar el build si hay CVEs críticos).
5. La suba a GHCR con el tag del commit SHA.

**Criterio de éxito:** un push con un test roto falla el pipeline antes de
llegar a construir o subir nada, y podés confirmar en los logs del build
que las capas de las 9 apps que no cambiaron se reusaron de cache (solo se
reconstruyó la que modificaste).

### Fase 4 — "Producción" real con Kubernetes (kubeadm multi-VM)

Con la topología de VMs de más arriba: bootstrapeá el cluster con
`kubeadm init` en `k8s-cp`, uní `k8s-worker-1`/`k8s-worker-2` con
`kubeadm join`, instalá un CNI (Calico o Flannel) y `ingress-nginx`. Todo
esto se opera desde `local.devops` con el `kubectl`/`helm` ya instalados
ahí (no en los nodos del cluster). Desplegá Frappe con su Helm chart
oficial (o escribí los manifests vos: `Deployment` para `web` y `worker`
con `replicas: 2+`, el `scheduler` con `replicas: 1` fijo, MariaDB y Redis
vía los charts de Bitnami).

**Criterio de éxito:** matás un pod de `web` a mano (`kubectl delete pod`)
y el sitio sigue respondiendo porque hay más de una réplica — y además
podés ver en qué nodo (`k8s-worker-1` o `-2`) quedó reprogramado.

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
