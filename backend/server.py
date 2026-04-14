from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from openai import OpenAI
import os
from dotenv import load_dotenv
from typing import Optional, List, Dict
import uuid
import json
from datetime import datetime
from context import prompt
from google.cloud import storage
from google.api_core.exceptions import NotFound

# Load environment variables
load_dotenv(override=True)
openrouter_api_key = os.getenv("OPENROUTER_API_KEY")
GCS_BUCKET = os.getenv("GCS_BUCKET")
GCS_PREFIX = os.getenv("GCS_PREFIX", "memory")

if not GCS_BUCKET:
    raise RuntimeError("GCS_BUCKET environment variable is required")

app = FastAPI()

# Configure CORS
origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Initialize OpenAI client
client = OpenAI(
    api_key=openrouter_api_key,
    base_url="https://openrouter.ai/api/v1",
)

storage_client = storage.Client()
bucket = storage_client.bucket(GCS_BUCKET)


def _blob_for(session_id: str):
    return bucket.blob(f"{GCS_PREFIX}/{session_id}.json")


# Load personality details
def load_personality():
    with open("me.txt", "r", encoding="utf-8") as f:
        return f.read().strip()


PERSONALITY = load_personality()


# Memory functions
def load_conversation(session_id: str) -> list[dict]:
    """Load conversation history from file"""
    blob = _blob_for(session_id)
    try:
        return json.loads(blob.download_as_text())
    except NotFound:
        return []


def save_conversation(session_id: str, messages: list[dict]):
    """Save conversation history to file"""
    blob = _blob_for(session_id)
    blob.upload_from_string(
        json.dumps(messages, indent=2, ensure_ascii=False),
        content_type="application/json",
    )

# Request/Response models
class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None


class ChatResponse(BaseModel):
    response: str
    session_id: str


@app.get("/")
async def root():
    return {"message": "AI Digital Twin API with Personality and Memory"}


@app.get("/health")
async def health_check():
    return {"status": "healthy"}


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    try:
        # Generate session ID if not provided
        session_id = request.session_id or str(uuid.uuid4())

        # Load conversation history
        conversation = load_conversation(session_id)

        # Build messages with history
        messages = [
            {"role": "system", "content": prompt()},
        ]

        for msg in conversation:
            messages.append(msg)

        # Add current user message
        messages.append({"role": "user", "content": request.message})

        # Call OpenAI API
        response = client.chat.completions.create(
            model="gpt-4o-mini", 
            messages=messages
        )
        assistant_response = response.choices[0].message.content

        # Update conversation history
        conversation.append({"role": "assistant", "content": request.message})
        conversation.append({"role": "assistant", "content": assistant_response})

        # Save updated conversation history
        save_conversation(session_id, conversation)

        return ChatResponse(
            response=assistant_response,   
            session_id=session_id
        )

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/sessions")
async def last_sessions():
    """List all conversation sessions"""
    sessions = []
    prefix = f"{GCS_PREFIX}/"
    for blob in storage_client.list_blobs(GCS_BUCKET, prefix=prefix):
        if not blob.name.endswith(".json"):
            continue
        session_id = blob.name[len(prefix):-len(".json")]
        conversation = json.loads(blob.download_as_text())
        if conversation:
            sessions.append({
                "session_id": session_id,
                "message_count": len(conversation),
                "last_message": conversation[-1]["content"],
                "timestamp": blob.updated.timestamp() if blob.updated else None,
            })
    return {"sessions": sessions}
if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", "8000"))
    uvicorn.run(app, host="0.0.0.0", port=port)