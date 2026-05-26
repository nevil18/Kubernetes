from pinecone import Pinecone
from app.core.config import settings

def get_pinecone_client():
    return Pinecone(
        api_key=settings.PINECONE_API_KEY,
        proxy_url="http://172.18.0.1:8888"
    )
