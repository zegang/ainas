# AI-NAS: Intelligent Storage Management

AI-NAS is a smart Network Attached Storage (NAS) management solution that integrates a powerful AI Assistant to simplify data management, system monitoring, and file operations through natural language.

## 🚀 Features

- **Conversational AI Assistant**: Manage your NAS using natural language commands.
- **Real-time Streaming**: Instant feedback for AI responses using server-sent events or streaming repositories.
- **Context-Aware File Operations**: Attach files directly from your NAS to the AI chat for analysis, summarization, or searching.
- **Quick Action Chips**: One-tap shortcuts for common tasks:
  - **Storage Health**: "How much storage is left?"
  - **Deep Search**: "Find all PDF files in /Home"
  - **System Optimization**: "Run a performance check"
- **Versatile AI Assistant**:
  - **Explain images**
  - **Lables on images**
  - ...
- **RAG with elasticsearch**: Exact retrieval and semantic similarity retrieval.
- **Cross-Platform GUI**: Responsive frontend built with Flutter.

## Demo Records

![Search Images By AI Auto-Generated Tags](./doc/images/searchbyimagetags.gif)

## Quantization Models

- Quant models with llama.cpp to run on resource constrained devices.


## 🏗️ Project Structure

- **`/frontend`**: The Flutter-based client application.
- **`/vendor`**: Custom Flutter toolchain and engine configurations.

## 🛠️ Tech Stack

- **Frontend**: Flutter / Dart
- **State Management**: standard `StatefulWidget` patterns (extensible to Riverpod/Bloc).
- **Communication**: REST API with real-time stream support.
- **Localization**: Official Flutter i18n support (ARB files).

## 🚦 Getting Started

1.  **Prerequisites**: Ensure you have the Flutter SDK installed.
2.  **Installation**:
    ```bash
    bash bootstrap.sh --setup
    ```
3.  **Run Backend**:
    ```bash
    bash bootstrap.sh --backend
    ```
4. **Run Frontend**:
    ```bash
    bash bootstrap.sh --frontend
    ```