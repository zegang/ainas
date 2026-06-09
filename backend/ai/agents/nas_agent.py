import logging
import json
import re
import uuid

from langchain_core.messages import SystemMessage
from langgraph.graph import StateGraph, START, MessagesState
from langgraph.prebuilt import ToolNode, tools_condition

logger = logging.getLogger(__name__)

def create_nas_agent(llm, tools):
    llm_with_tools = llm.bind_tools(tools)

    def call_agent(state: MessagesState):
        logger.info("--- Entering Node: 'agent' ---")
        sys_msg = SystemMessage(content=(
            "You are the AI-NAS Assistant. You manage files and images on the user's storage.\n"
            "STRICT RULES:\n"
            "1. Filenames in [NAS CONTEXT] are wrapped in quotes (e.g., \"file with spaces.png\"). "
            "When calling tools, use the EXACT content inside those quotes. "
            "Do not truncate, modify, or summarize the filename or path.\n"
            "2. If multiple files are provided, ensure you use the one the user is explicitly asking about."
            "\n3. To call a tool, use the following format: <tool_call>{\"name\": \"tool_name\", \"arguments\": {\"arg\": \"val\"}}</tool_call>"
        ))
        responds = llm_with_tools.invoke([sys_msg] + state['messages'])
        
        # Fallback mechanism: Manually parse tool calls from content if structured tool_calls are missing
        if not (hasattr(responds, "tool_calls") and responds.tool_calls) and responds.content and "<tool_call>" in responds.content:
            logger.info("Structured tool_calls missing. Attempting manual parse from content tags.")
            # Regex to capture JSON content inside <tool_call> tags
            tool_call_regex = r"<tool_call>\s*(.*?)\s*</tool_call>"
            matches = re.findall(tool_call_regex, responds.content, re.DOTALL)
            
            manual_calls = []
            for m in matches:
                try:
                    # Clean common artifacts (extra braces, triple braces, etc.)
                    cleaned_json = m.strip()
                    # Iteratively remove unbalanced trailing braces instead of all of them
                    while cleaned_json.count('{') < cleaned_json.count('}') and cleaned_json.endswith('}'):
                        cleaned_json = cleaned_json[:-1].strip()
                    
                    data = json.loads(cleaned_json)
                    manual_calls.append({
                        "name": data.get("name"),
                        "args": data.get("arguments", data.get("args", {})),
                        "id": f"call_{uuid.uuid4().hex[:12]}", # Required for ToolNode execution
                        "type": "tool_call"
                    })
                except Exception as e:
                    logger.warning("Manual tool call parsing failed for: %s. Error: %s", m, e)
            
            if manual_calls:
                responds.tool_calls = manual_calls
                logger.info("Successfully recovered %d tool calls from content tags.", len(manual_calls))

        if hasattr(responds, "tool_calls") and responds.tool_calls:
            for tool_call in responds.tool_calls:
                logger.info("Agent requesting tool: %s with args: %s", tool_call['name'], tool_call['args'])
        else:
            logger.info("Agent final response: %s", responds.content)
            
        return {"messages": [responds]}

    def call_tools_node(state: MessagesState):
        logger.info("--- Entering Node: 'tools' ---")
        return ToolNode(tools).invoke(state)

    workflow = StateGraph(MessagesState)
    workflow.add_node("agent", call_agent)
    workflow.add_node("tools", call_tools_node)
    workflow.add_edge(START, "agent")
    workflow.add_conditional_edges("agent", tools_condition)
    workflow.add_edge("tools", "agent")
    return workflow.compile()