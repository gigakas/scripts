#!/usr/bin/env python3
"""Register running AI Runtime providers in an OpenCode configuration."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
import urllib.request
from datetime import datetime
from pathlib import Path


def strip_jsonc(source: str) -> str:
    """Remove JSON comments and trailing commas without changing strings."""
    uncommented: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        char = source[index]
        next_char = source[index + 1] if index + 1 < len(source) else ""

        if in_string:
            uncommented.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue

        if char == '"':
            in_string = True
            uncommented.append(char)
            index += 1
        elif char == "/" and next_char == "/":
            index += 2
            while index < len(source) and source[index] not in "\r\n":
                index += 1
        elif char == "/" and next_char == "*":
            index += 2
            while index + 1 < len(source) and source[index : index + 2] != "*/":
                index += 1
            index += 2
        else:
            uncommented.append(char)
            index += 1

    source = "".join(uncommented)
    result: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(source):
        char = source[index]
        if in_string:
            result.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            result.append(char)
        elif char == ",":
            lookahead = index + 1
            while lookahead < len(source) and source[lookahead].isspace():
                lookahead += 1
            if lookahead < len(source) and source[lookahead] in "}]":
                index += 1
                continue
            result.append(char)
        else:
            result.append(char)
        index += 1

    return "".join(result)


def read_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def fetch_models(base_url: str, token: str) -> list[str]:
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}/models",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
    return [item["id"] for item in payload.get("data", []) if item.get("id")]


def parse_provider(value: str) -> tuple[str, str, str]:
    name, separator, urls = value.partition("=")
    public_url, discovery_separator, discovery_url = urls.partition("|")
    if not separator or not name or not public_url:
        raise argparse.ArgumentTypeError("provider must use NAME=PUBLIC_URL[|DISCOVERY_URL]")
    if not discovery_separator:
        discovery_url = public_url
    return name, public_url.rstrip("/"), discovery_url.rstrip("/")


def message(language: str, spanish: str, english: str) -> str:
    return spanish if language == "es" else english


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--env-file", required=True, type=Path)
    parser.add_argument("--provider", action="append", default=[], type=parse_provider)
    parser.add_argument("--language", choices=("es", "en"), default="en")
    args = parser.parse_args()

    env_values = read_env(args.env_file)
    token = env_values.get("CHATBOT_AI_BEARER_TOKEN", "")
    if not token:
        raise SystemExit(
            message(
                args.language,
                f"No se encontró CHATBOT_AI_BEARER_TOKEN en {args.env_file}",
                f"CHATBOT_AI_BEARER_TOKEN was not found in {args.env_file}",
            )
        )

    config_path = args.config.expanduser().resolve()
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config: dict = {}

    if config_path.exists():
        try:
            config = json.loads(strip_jsonc(config_path.read_text(encoding="utf-8")))
        except (json.JSONDecodeError, OSError) as error:
            raise SystemExit(
                message(
                    args.language,
                    f"No se pudo leer {config_path}: {error}",
                    f"Could not read {config_path}: {error}",
                )
            ) from error
        backup = config_path.with_name(
            f"{config_path.name}.backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        )
        shutil.copy2(config_path, backup)
        print(message(args.language, f"Copia de seguridad: {backup}", f"Backup: {backup}"))

    token_path = config_path.parent / "chatbot-ai-token"
    token_path.write_text(f"{token}\n", encoding="utf-8")
    token_path.chmod(0o600)

    config.setdefault("$schema", "https://opencode.ai/config.json")
    providers = config.setdefault("provider", {})
    if not isinstance(providers, dict):
        raise SystemExit(message(args.language, "El campo provider no es un objeto.", "The provider field is not an object."))
    embedding_model = env_values.get("EMBEDDING_MODEL", "")
    configured_models = 0
    configured_providers: list[str] = []

    for provider_name, base_url, discovery_url in args.provider:
        try:
            model_ids = fetch_models(discovery_url, token)
        except Exception as error:
            print(
                message(
                    args.language,
                    f"Aviso: no se pudo consultar {provider_name} ({base_url}): {error}",
                    f"Warning: could not query {provider_name} ({base_url}): {error}",
                )
            )
            continue

        if provider_name == "internal-ollama" and embedding_model:
            embedding_name = embedding_model.split(":", 1)[0]
            model_ids = [model for model in model_ids if model.split(":", 1)[0] != embedding_name]

        provider = providers.setdefault(provider_name, {})
        if not isinstance(provider, dict):
            provider = {}
            providers[provider_name] = provider
        provider["npm"] = "@ai-sdk/openai-compatible"
        provider["name"] = "Internal AI - Ollama" if provider_name == "internal-ollama" else "Internal AI - vLLM"
        options = provider.setdefault("options", {})
        if not isinstance(options, dict):
            options = {}
            provider["options"] = options
        options["baseURL"] = base_url
        options["apiKey"] = f"{{file:{token_path}}}"
        models = provider.setdefault("models", {})
        if not isinstance(models, dict):
            models = {}
            provider["models"] = models
        for model_id in model_ids:
            model = models.setdefault(model_id, {})
            if not isinstance(model, dict):
                model = {}
                models[model_id] = model
            model.setdefault("limit", {"context": 12288, "output": 2048})
            configured_models += 1
        configured_providers.append(provider_name)

        print(
            message(
                args.language,
                f"{provider_name}: {len(model_ids)} modelo(s) agregado(s)",
                f"{provider_name}: {len(model_ids)} model(s) added",
            )
        )

    if configured_models == 0:
        raise SystemExit(message(args.language, "No se detectaron modelos activos.", "No active models were detected."))

    enabled_providers = config.get("enabled_providers")
    if isinstance(enabled_providers, list):
        for provider_name in configured_providers:
            if provider_name not in enabled_providers:
                enabled_providers.append(provider_name)
    disabled_providers = config.get("disabled_providers")
    if isinstance(disabled_providers, list):
        config["disabled_providers"] = [
            provider_name for provider_name in disabled_providers if provider_name not in configured_providers
        ]

    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{config_path.name}.", dir=config_path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
            json.dump(config, temporary_file, indent=2, ensure_ascii=False)
            temporary_file.write("\n")
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, config_path)
    finally:
        if os.path.exists(temporary_name):
            os.unlink(temporary_name)

    print(message(args.language, f"Configuración actualizada: {config_path}", f"Configuration updated: {config_path}"))
    print(message(args.language, "Reinicia OpenCode para aplicar los cambios.", "Restart OpenCode to apply the changes."))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
