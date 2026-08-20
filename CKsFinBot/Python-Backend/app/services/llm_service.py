import math
import asyncio
from langchain_groq import ChatGroq
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_pinecone import PineconeVectorStore
from langchain_core.prompts import PromptTemplate
from langchain_core.runnables import RunnableParallel, RunnablePassthrough
from langchain_core.output_parsers import StrOutputParser
from operator import itemgetter

from app.core.config import settings
from app.prompts import (
    SMART_CHAT_PROMPT_TEMPLATE,
    DOCUMENT_ANALYSIS_PROMPT_TEMPLATE,
    ANALYTICAL_INSIGHTS_PROMPT_TEMPLATE,
    GENERAL_CONVERSATION_PROMPT_TEMPLATE
)


# Global singleton - loaded once at startup
_embeddings = None

def get_embeddings():
    global _embeddings
    if _embeddings is None:
        from langchain_huggingface import HuggingFaceEmbeddings
        _embeddings = HuggingFaceEmbeddings(
            model_name='sentence-transformers/all-MiniLM-L6-v2',
            model_kwargs={'device': 'cpu'},
            encode_kwargs={'normalize_embeddings': True}
        )
    return _embeddings


from .pinecone_service import get_pinecone_client

def format_docs(docs: list) -> str:
    """Helper function to format retrieved documents into a single string."""
    if not docs:
        return "No relevant documents found."
    return "\n---\n".join([doc.page_content for doc in docs])

def format_chat_history(chat_history: list) -> str:
    """Formats chat history into a readable string."""
    if not chat_history:
        return "No previous conversation."
    return "\n".join([f"{msg.get('role', 'unknown').capitalize()}: {msg.get('content', '')}" for msg in chat_history])

async def retrieve_from_multiple_namespaces(embeddings, question: str, namespaces: list):
    """
    Dynamically determines search 'k' by using the existing get_pinecone_client() helper
    to get namespace stats, then runs retrievals concurrently.
    Returns empty list if no namespaces exist or retrieval fails.
    """
    if not namespaces:
        print("⚠️  No namespaces provided for retrieval.")
        return []

    namespace_stats = {}
    print("📊 Skipping Pinecone stats fetch - using fixed k=10 for all retrievals.")

    tasks = []
    for ns in namespaces:
        try:
            dynamic_k = 10
            print(f"🔍 Retrieving from '{ns}' with fixed k={dynamic_k}")

            vectorstore = PineconeVectorStore(
                index_name="cksfinbot", 
                embedding=embeddings, 
                namespace=ns
            )
            retriever = vectorstore.as_retriever(
                search_kwargs={"k": dynamic_k}
            )
            
            tasks.append(retriever.ainvoke(question))
            
        except Exception as e:
            print(f"⚠️  Warning: Could not create retriever for namespace {ns}. Skipping. Error: {e}")

    if not tasks:
        print("⚠️  No valid retrieval tasks could be created. Returning empty results.")
        return []
        
    all_docs_nested = await asyncio.gather(*tasks, return_exceptions=True)
    
    # Filter out any exceptions that occurred during retrieval
    combined_docs = []
    for result in all_docs_nested:
        if isinstance(result, Exception):
            print(f"⚠️  Retrieval error: {result}")
        else:
            combined_docs.extend(result)
    
    print(f"✅ Retrieved a total of {len(combined_docs)} documents from {len(namespaces)} namespaces.")
    
    return combined_docs

async def smart_chat_pipeline(llm, embeddings, question: str, chat_history: str, namespaces: list):
    """
    The RAG pipeline for the multi-modal Smart Chat feature, built with LCEL.
    Always sends query to LLM even if no documents are found, allowing the prompt
    to handle general queries and missing context scenarios.
    """
    print("🚀 Executing Smart Chat Pipeline with LCEL")
    
    # Try to retrieve documents, but don't block if none exist
    relevant_docs = []
    if namespaces:
        relevant_docs = await retrieve_from_multiple_namespaces(embeddings, question, namespaces)
    else:
        print("⚠️  No namespaces provided. Proceeding with empty context.")
    
    # Format context (will be empty string or "No relevant documents found" if no docs)
    context = format_docs(relevant_docs) if relevant_docs else "No financial documents have been uploaded yet."

    # Create prompt template
    prompt = PromptTemplate.from_template(SMART_CHAT_PROMPT_TEMPLATE)

    # Build the LCEL RAG Chain - ALWAYS executes, even with empty context
    rag_chain = (
        {
            "context": lambda _: context,
            "question": itemgetter("question"),
            "chat_history": itemgetter("chat_history"),
        }
        | prompt
        | llm
        | StrOutputParser()
    )
    
    # Invoke the chain with the required inputs
    print("📤 Sending query to Groq...")
    response = await rag_chain.ainvoke({"question": question, "chat_history": chat_history})
    print("✅ Response received from Groq")
    return response

async def document_analysis_pipeline(llm, embeddings, question: str, chat_history: str, namespaces: list):
    """Document Analysis Pipeline - Currently under development."""
    print("🚀 Executing Document Analysis Pipeline")
    
    # Similar structure - always send to LLM
    relevant_docs = []
    if namespaces:
        relevant_docs = await retrieve_from_multiple_namespaces(embeddings, question, namespaces)
    
    context = format_docs(relevant_docs) if relevant_docs else "No financial documents have been uploaded yet."
    
    prompt = PromptTemplate.from_template(DOCUMENT_ANALYSIS_PROMPT_TEMPLATE)
    
    chain = (
        {
            "context": lambda _: context,
            "question": itemgetter("question"),
            "chat_history": itemgetter("chat_history"),
        }
        | prompt
        | llm
        | StrOutputParser()
    )
    
    return await chain.ainvoke({"question": question, "chat_history": chat_history})

async def analytical_insights_pipeline(llm, embeddings, question: str, chat_history: str, namespaces: list):
    """Analytical Insights Pipeline - Currently under development."""
    print("🚀 Executing Analytical Insights Pipeline")
    
    # Similar structure - always send to LLM
    relevant_docs = []
    if namespaces:
        relevant_docs = await retrieve_from_multiple_namespaces(embeddings, question, namespaces)
    
    context = format_docs(relevant_docs) if relevant_docs else "No financial documents have been uploaded yet."
    
    prompt = PromptTemplate.from_template(ANALYTICAL_INSIGHTS_PROMPT_TEMPLATE)
    
    chain = (
        {
            "context": lambda _: context,
            "question": itemgetter("question"),
            "chat_history": itemgetter("chat_history"),
        }
        | prompt
        | llm
        | StrOutputParser()
    )
    
    return await chain.ainvoke({"question": question, "chat_history": chat_history})

async def general_conversation_pipeline(llm, question: str, chat_history: str):
    """A simple conversational chain without document retrieval, built with LCEL."""
    print("🚀 Executing General Conversation Pipeline with LCEL")
    
    prompt = PromptTemplate.from_template(GENERAL_CONVERSATION_PROMPT_TEMPLATE)
    
    conversation_chain = prompt | llm | StrOutputParser()
    
    return await conversation_chain.ainvoke({"question": question, "chat_history": chat_history})


async def get_answer_from_rag(question: str, chat_history: list, pinecone_namespaces: list, feature_mode: str) -> str:
    """
    Initializes models and routes the request to the correct RAG pipeline.
    Always sends queries to LLM regardless of namespace/document availability.
    """
    print(f"🎯 Router: Processing query with feature_mode='{feature_mode}'")
    
    # Initialize models once per request
    llm = ChatGroq(
        model="llama-3.3-70b-specdec", 
        temperature=0, 
        api_key=settings.GROQ_API_KEY 
    )
    embeddings = get_embeddings()
    print("✅ Models initialized.")
    
    # Format chat history once
    formatted_history = format_chat_history(chat_history)

    # Router logic to select and execute the correct pipeline
    if feature_mode == "Smart_Chat":
        return await smart_chat_pipeline(llm, embeddings, question, formatted_history, pinecone_namespaces)
    
    elif feature_mode == "Document_Analysis":
        return await document_analysis_pipeline(llm, embeddings, question, formatted_history, pinecone_namespaces)
        
    elif feature_mode == "Analytical_Insights":
        return await analytical_insights_pipeline(llm, embeddings, question, formatted_history, pinecone_namespaces)
        
    elif feature_mode == "General_Conversation":
        return await general_conversation_pipeline(llm, question, formatted_history)
        
    else:  # Fallback to the default Smart Chat mode
        print(f"⚠️  Unknown feature mode '{feature_mode}', defaulting to Smart_Chat.")
        return await smart_chat_pipeline(llm, embeddings, question, formatted_history, pinecone_namespaces)