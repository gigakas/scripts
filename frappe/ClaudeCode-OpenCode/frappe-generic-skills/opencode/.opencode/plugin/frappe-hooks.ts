// Plugin de opencode con los "hooks" del proyecto Frappe:
// - registra cada cambio hecho por IA en changelog.md (raíz del proyecto)
// - formatea con ruff los .py editados (convención Frappe v15)
// - avisa cuando cambia el JSON de un DocType (hace falta bench migrate)
import type { Plugin } from "@opencode-ai/plugin"
import { appendFileSync, existsSync, writeFileSync } from "node:fs"
import { join, relative } from "node:path"

export const FrappeHooks: Plugin = async ({ $, directory }) => {
  const changelog = join(directory ?? process.cwd(), "changelog.md")

  return {
    "tool.execute.after": async (input, output) => {
      if (input.tool !== "edit" && input.tool !== "write") return
      const file: string | undefined =
        (output as any)?.args?.filePath ?? (output as any)?.args?.file_path
      if (!file) return

      // changelog automático (excluye el propio changelog para no auto-loguearse)
      if (!file.endsWith("changelog.md")) {
        if (!existsSync(changelog)) {
          writeFileSync(
            changelog,
            "# Changelog\n\nRegistro de cambios realizados por IA en este proyecto.\n" +
              "Las líneas con hora las genera un plugin automático; los resúmenes por tarea los añade el agente.\n\n",
          )
        }
        const ts = new Date().toISOString().slice(0, 16).replace("T", " ")
        const rel = relative(directory ?? process.cwd(), file)
        appendFileSync(changelog, `- ${ts} · ${input.tool} · \`${rel}\`\n`)
      }

      if (file.endsWith(".py")) {
        await $`ruff format ${file}`.nothrow().quiet()
      }

      if (file.includes("/doctype/") && file.endsWith(".json")) {
        ;(output as any).metadata = {
          ...(output as any).metadata,
          reminder:
            "Esquema de DocType modificado: ejecuta `bench --site <site> migrate && bench --site <site> clear-cache`",
        }
      }
    },
  }
}
