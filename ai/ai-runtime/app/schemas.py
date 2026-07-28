from pydantic import BaseModel, Field


class MessageSchema(BaseModel):
	role: str
	content: str


class AnalyzeRequest(BaseModel):
	model: str
	messages: list[MessageSchema]
	options: dict = Field(default_factory=dict)
	response_format: str | None = None


class AnalyzeResponse(BaseModel):
	result: str
	prompt_tokens: int = 0
	completion_tokens: int = 0
	usage: dict = Field(default_factory=dict)
	provider: str = "ollama"
	model: str = ""
	latency_ms: int = 0
	status: str = "success"


class RagDocumentInput(BaseModel):
	id: str
	text: str
	metadata: dict = Field(default_factory=dict)


class RagUpsertRequest(BaseModel):
	collection_name: str
	documents: list[RagDocumentInput]
	embedding_model: str | None = None


class RagUpsertResponse(BaseModel):
	collection_name: str
	inserted: int = 0
	total_documents: int = 0
	embedding_model: str = ""
	status: str = "success"


class RagQueryRequest(BaseModel):
	collection_name: str
	query: str
	limit: int = 5
	where: dict = Field(default_factory=dict)
	embedding_model: str | None = None


class RagMatch(BaseModel):
	id: str
	document: str = ""
	metadata: dict = Field(default_factory=dict)
	distance: float | None = None


class RagQueryResponse(BaseModel):
	collection_name: str
	query: str
	matches: list[RagMatch] = Field(default_factory=list)
	embedding_model: str = ""
	status: str = "success"
