# Script de servidor (Server Script tipo "API" o método whitelisted en tu app).
# Crea un DocType simple "Auditoria Code" con campos: app (Data), ruta (Small Text),
# fecha (Datetime), hallazgos (Int), informe (Long Text) y pega esto como API Script
# llamado "auditar_app". Requiere que el LangGraph server del auditor esté arriba.
#
# El botón en el frontend (client script de "Auditoria Code" o una página):
#   frappe.call({ method: "auditar_app", args: { app_path: rutas.auditor } ... })
# ver README para el snippet JS.

import json

import frappe
import requests

LANGGRAPH_URL = frappe.conf.get("auditor_url", "http://127.0.0.1:2024")
# Permitidor de rutas auditables (evita que el button lea cualquier path del server)
BASE_APPS = frappe.conf.get("auditor_base", "../apps")


@frappe.whitelist()
def auditar_app(app: str) -> dict:
    frappe.has_permission("Auditoria Code", "create", throw=True)

    if app != frappe.scrub(app) or app not in _apps_del_bench():
        frappe.throw("App no permitida para auditoría")
    ruta = frappe.utils.get_bench_path() + "/apps/" + app

    r = requests.post(
        f"{LANGGRAPH_URL}/runs/wait",
        json={"assistant_id": "auditor_frappe", "input": {"app_path": ruta}},
        timeout=300,
    )
    r.raise_for_status()
    estado = r.json()

    doc = frappe.new_doc("Auditoria Code")
    doc.app = app
    doc.ruta = ruta
    doc.fecha = frappe.utils.now()
    doc.hallazgos = len(estado.get("hallazgos") or [])
    doc.informe = estado.get("informe") or ""
    doc.save()
    return {"name": doc.name, "hallazgos": doc.hallazgos}


def _apps_del_bench() -> list:
    import os

    base = frappe.utils.get_bench_path() + "/apps"
    return [d for d in os.listdir(base) if os.path.isdir(os.path.join(base, d))]
