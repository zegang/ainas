# AI-NAS: Intelligent Storage Management

[![GitHub release](https://img.shields.io/github/v/release/zegang/ainas)](https://github.com/zegang/ainas/releases)
[![GitHub stars](https://img.shields.io/github/stars/zegang/ainas?style=social)](https://github.com/zegang/ainas)
[![Python](https://img.shields.io/badge/python-3.10+-3776AB?logo=python)](https://python.org)
[![Flutter](https://img.shields.io/badge/flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart SDK](https://img.shields.io/badge/dart-%3E%3D3.0-blue)](https://dart.dev)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20android-3ddc84?logo=linux)](https://flutter.dev)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](https://github.com/zegang/ainas/pulls)
[![Website](https://img.shields.io/badge/website-github.io-8ab4f8)](https://zegang.github.io/ainas)

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

![Search Images By AI Auto-Generated Tags](./docs/images/searchbyimagetags.gif)

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