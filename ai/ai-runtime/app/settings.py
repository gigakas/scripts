from pydantic_settings import BaseSettings, SettingsConfigDict


class AppSettings(BaseSettings):
	chatbot_ai_host: str = "127.0.0.1"
	chatbot_ai_port: int = 8001
	chatbot_ai_provider: str = "ollama"
	chatbot_ai_bearer_token: str = ""
	ollama_base_url: str = "http://127.0.0.1:11434"
	vllm_base_url: str = "http://127.0.0.1:8000/v1"
	embedding_provider: str = "ollama"
	request_timeout: int = 90
	embedding_model: str = "nomic-embed-text"
	chroma_persist_dir: str = "/opt/chatbot-ai-runtime/data/chroma"

	model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = AppSettings()
