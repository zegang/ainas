import logging
import json
import re
import uuid

import asyncio # Import asyncio for cancellation event
from langchain_core.messages import SystemMessage, AIMessage, AIMessageChunk, BaseMessage, ToolMessage, HumanMessage
from langgraph.graph import StateGraph, START, END
from langgraph.prebuilt import ToolNode, tools_condition
from backend.services.monitoring.prometheus import TrackNodeTime, AI_AGENT_ITERATIONS_PER_REQUEST, AI_TOOL_CALL_TOTAL, AI_TOOL_DURATION

def _get_system_message(tools: list) -> SystemMessage:
    """Constructs the primary system instructions for the NAS AI Assistant."""
    tool_desc = "\n".join([f"- {t.name}: {t.description}" for t in tools])
    return SystemMessage(content=(
        f"You are a NAS AI Assistant. You have access to the following tools:\n{tool_desc}\n\n"
        "STRICT RULES:\n"
        "1. Filenames in [Attached files] are wrapped in quotes. Use the EXACT filename string for tool arguments.\n"
        "2. To call a tool, you MUST use: <tool_call>{\"name\": \"tool_name\", \"args\": {...}}</tool_call>\n"
        "3. For images (PNG, JPG, JPEG, WEBP, etc.), you MUST use the 'explain_image' tool to see or analyze the content.\n"
        "4. For documents (PDF, DOCX, TXT, MD, etc.), you MUST use the 'query_documents' tool to search and retrieve text content.\n"
        "4. Once a tool provides the requested info, STOP and provide the final answer.\n"
        "5. DO NOT perform extra unrequested actions or call unrelated tools.\n"
        "6. If the ACTUAL CONTENT or ANSWER is already in chat history, do NOT call tools again.\n"
        "7. A filename in '[Attached files]' is just a pointer. It is NOT the content itself. You MUST query the tool to read it.\n"
        "8. CRITICAL: ALWAYS respond in the SAME LANGUAGE as the user's message. If the user writes in Chinese, respond entirely in Chinese. If they write in English, respond in English. Detect the language from the user's input and match it exactly."
    ))

def _parse_manual_tool_calls(response_message: AIMessage, history: list) -> None:
    """
    Parses raw <tool_call> tags from message content if structured tool_calls are missing.
    Updates the message object in-place.
    """
    logger = logging.getLogger(__name__)
    if not response_message.content or "<tool_call>" not in response_message.content:
        return

    logger.info("Structured tool_calls missing. Attempting manual parse from content tags.")
    tool_call_regex = r"<tool_call>\s*(.*?)(?:\s*</tool_call>|$)"
    matches = re.findall(tool_call_regex, response_message.content, re.DOTALL)
    
    manual_calls = []
    for m in matches:
        try:
            cleaned_json = m.strip()
            # Remove unbalanced trailing braces
            while cleaned_json.count('{') < cleaned_json.count('}') and cleaned_json.endswith('}'):
                cleaned_json = cleaned_json[:-1].strip()
            
            data = json.loads(cleaned_json)
            t_name = data.get("name")
            t_args = data.get("arguments", data.get("args", {}))
            
            if not t_name:
                continue

            # Redundancy check
            if any(isinstance(msg, AIMessage) and hasattr(msg, 'tool_calls') and 
                   any(tc['name'] == t_name and tc['args'] == t_args for tc in msg.tool_calls) 
                   for msg in history):
                logger.warning("Agent attempted redundant tool call for '%s'. Ignoring.", t_name)
                continue

            manual_calls.append({
                "name": t_name,
                "args": t_args,
                "id": f"call_{uuid.uuid4().hex[:12]}",
                "type": "tool_call"
            })
        except Exception as e:
            logger.warning("Manual tool call parsing failed: %s", e)
    
    if manual_calls:
        if not hasattr(response_message, "tool_calls") or response_message.tool_calls is None:
            response_message.tool_calls = []
        response_message.tool_calls.extend(manual_calls)
        response_message.content = re.sub(r"<tool_call>.*?(?:</tool_call>|$)", "", response_message.content, flags=re.DOTALL).strip()
        logger.info("Recovered %d tool calls from tags.", len(manual_calls))

async def _auto_query_documents(messages: list, filenames: list[str], tools: list) -> str | None:
    """Pre-queries the document index for attached files and injects content into the message context.
    Returns the document content string if found, or None."""
    logger = logging.getLogger(__name__)
    docs = [f for f in filenames if f.lower().endswith(('.pdf', '.docx', '.txt', '.md', '.log'))]
    if not docs:
        return None

    logger.info("Auto-querying documents: %s", ', '.join(docs))
    query_doc_tool = next((t for t in tools if t.name == "query_documents"), None)
    if not query_doc_tool:
        return None

    user_text = messages[-1].content if messages else ""
    doc_content = await query_doc_tool.ainvoke({"query": user_text})
    if doc_content and "Error" not in doc_content:
        logger.info("Auto-query returned content, injecting as context.")
        messages.insert(-1 if messages else 0, HumanMessage(
            content=f"[Document content from {', '.join(docs)}]:\n{doc_content}"
        ))
        return doc_content
    return None

def create_nas_agent(chat_feature, tools):

    async def call_agent(state: dict):
        logger = logging.getLogger(__name__)
        with TrackNodeTime("agent"):
            llm = chat_feature.llm
            if llm is None:
                raise RuntimeError("Chat model is not set. Please configure a chat model first.")
            llm_with_tools = llm.bind_tools(tools)
            logger.info("--- Entering Node: 'agent' ---")
            
            if state.get('cancellation_event') and state['cancellation_event'].is_set():
                raise asyncio.CancelledError("Agent processing cancelled.")

            messages = state.get('messages', [])
            iterations = state.get('iterations', 0) + 1
            
            if iterations > 8:
                logger.warning("Agent reached maximum iterations (8). Terminating loop.")
                return {"messages": [AIMessage(content="I've reached my maximum reasoning steps for this request. Please try being more specific.")]}
            
            # logic: First enter vs Re-entry
            has_system_msg = any(isinstance(m, SystemMessage) for m in messages)
            if not has_system_msg:
                logger.info("First entry: Preparing SystemMessage.")
                
                images = [f for f in state.get('filenames', []) if f.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'))]
                
                # Nudge the agent if image files are attached
                if images:
                    logger.info("Images attached. Adding tool instruction nudges.")
                    nudges = [f"Use 'explain_image' to analyze visual content of: {', '.join(images)}."]
                    messages[-1].content += f"\n\n{' '.join(nudges)}"

                messages = [_get_system_message(tools)] + messages
            else:
                logger.info("Re-entry: SystemMessage already present in history.")

            # Prepare LLM Input
            llm_input = messages
            last_msg = messages[-1] if messages else None
            
            # Parse and deal with tool responds: provide a nudge if we just received data
            if isinstance(last_msg, ToolMessage):
                logger.debug("Parsing tool response: Providing completion nudge to LLM.")
                llm_input = messages + [HumanMessage(content="[INSTRUCTION] You have received the tool data. Do not call any more tools. Summarize the information and provide your final response to the user now.")]
            
            full_response = None
            async for chunk in llm_with_tools.astream(llm_input):
                if state.get('cancellation_event') and state['cancellation_event'].is_set():
                    raise asyncio.CancelledError("Agent LLM stream cancelled.")
                
                if isinstance(chunk, BaseMessage):
                    if full_response is None:
                        full_response = chunk
                    else:
                        full_response += chunk
            
            response = full_response or AIMessage(content="")
        
        # Handle potential manual tool calls in content
        if not (hasattr(response, "tool_calls") and response.tool_calls):
            _parse_manual_tool_calls(response, messages)

        if hasattr(response, "tool_calls") and response.tool_calls:
            for tool_call in response.tool_calls:
                logger.info("Agent requesting tool: %s with args: %s", tool_call['name'], tool_call['args'])
                AI_TOOL_CALL_TOTAL.labels(tool_name=tool_call['name']).inc()
        else:
            logger.info("Agent final response: %s", response.content)
            AI_AGENT_ITERATIONS_PER_REQUEST.observe(iterations)
            
        return {
            "messages": messages + [response],
            "iterations": iterations
        }

    async def call_tools_node(state: dict):
        logger = logging.getLogger(__name__)
        with TrackNodeTime("tools"):
            logger.info("--- Entering Node: 'tools' ---")
            
            if state.get('cancellation_event') and state['cancellation_event'].is_set():
                raise asyncio.CancelledError("Tools processing cancelled.")

            tool_node = ToolNode(tools)
            result = await tool_node.ainvoke(state)
            
            if state.get('cancellation_event') and state['cancellation_event'].is_set():
                raise asyncio.CancelledError("Tools processing cancelled.")

            logger.info("Tools result: %s", result)
            return result

    # LangGraph's StateGraph can work with a simple dict for state.
    # We'll pass the cancellation_event in this dict.
    workflow = StateGraph(dict) 
    workflow.add_node("agent", call_agent)
    workflow.add_node("tools", call_tools_node)
    workflow.add_edge(START, "agent")
    workflow.add_conditional_edges("agent", tools_condition)
    workflow.add_edge("tools", "agent")
    return workflow.compile()