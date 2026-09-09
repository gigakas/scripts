from pydantic_settings import BaseSettings, SettingsConfigDict


class AppSettings(BaseSettings):
	chatbot_ai_host: str = "127.0.0.1"
	chatbot_ai_port: int = 8001
	chatbot_ai_provider: str = "ollama"
	chatbot_ai_bearer_token: str = ""
	ollama_base_url: str = "http://127.0.0.1:11434"
	vllm_base_url: str = "http://127.0.0.1:8000/v1"
	vllm_extra_base_urls: str = ""
	embedding_provider: str = "ollama"
	ollama_default_num_ctx: int = 8192
	request_timeout: int = 90
	embedding_model: str = "nomic-embed-text"
	chroma_persist_dir: str = "/opt/chatbot-ai-runtime/data/chroma"
	cors_allow_origins: str = "null,http://local.helpdesk:8000,https://local.helpdesk:8000"

	model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = AppSettings()
