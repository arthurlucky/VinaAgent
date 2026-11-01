# 📱 Vina Agent

> **Executive Multi-Provider & 100% Offline AI Agent Workstation for Android & Mobile**  
> *Bridge the gap between Cloud Frontier LLMs, Local On-Device GGUF Inference, Unlimited AI Image Synthesis, Model Context Protocol (MCP), Sandboxed File Management with ZIP tools, and Self-Evolving Memory.*

[![Flutter](https://img.shields.io/badge/Flutter-3.29+-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Offline GGUF](https://img.shields.io/badge/Engine-Offline%20GGUF%20Native-FF6F00?style=for-the-badge)](https://github.com/ggerganov/llama.cpp)
[![MCP](https://img.shields.io/badge/Protocol-MCP%20Enabled-00F0FF?style=for-the-badge)](https://modelcontextprotocol.io)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

---

## 📁 Repository Structure

```
VinaAgent/
├── android/                    # Native Android configurations, ProGuard rules, & NDK bridges
├── lib/
│   ├── app/                    # Theme, Glass Tokens, & Router configuration
│   ├── core/                   # Drift SQLite Database, DAOs, Models, Storage Sandbox & Services
│   │   ├── db/                 # Drift tables & queries
│   │   ├── models/             # Provider-agnostic chat models, attachments & metrics
│   │   └── storage/            # Private App Sandbox boundary & Secure Key Store
│   ├── shared/                 # Glassmorphic UI components, code blocks & custom icons
│   └── features/
│       ├── agent/              # ReAct Agent Engine, Workdir Controller & Built-in Tools
│       ├── chat/               # Chat UI shell, input bar, message bubbles & attachments
│       ├── conversations/      # History drawer & thread management
│       ├── files/              # Sandboxed File Manager (Create, Move, ZIP Compress/Extract/Preview)
│       ├── local_models/       # Native GGUF inference runtime, model downloader & presets
│       ├── mcp/                # MCP protocol client (Streamable HTTP & SSE) & marketplace
│       ├── providers/          # Multi-provider gateways (OpenAI, Claude, Gemini, DeepSeek, Ollama)
│       ├── settings/           # Local models, MCP, Storage, API keys, & Hermes memory UI
│       └── telegram/           # Telegram Bot autonomous background relay service
└── test/                       # Unit and widget test suite
```

---

## 🌟 Key Features & Highlights

- ⚡ **100% Offline On-Device Native GGUF Inference**: Run state-of-the-art quantized SLMs locally on your phone using ARM NEON multi-threaded CPU acceleration. Zero cloud dependency, zero data leaving your device.
- 📎 **AI File Attachments & Auto-Attach**: The agent can explicitly send files or auto-attach newly generated files (`write_file`, `compress_to_zip`) straight into the chat bubble with interactive previews (code, markdown, images) and 1-tap File Manager navigation.
- 📁 **Full Sandboxed File Manager**: Seamless mobile file operations directly in the app sandbox (`root/`):
  - **Create Files & Folders**: Create new files with initial contents or folders on the fly.
  - **ZIP Archives**: Compress any file/folder to `.zip`, preview ZIP archive contents without extracting, and safely extract archives with zip-slip traversal protection.
  - **File Operations**: Move, rename, delete, preview files, and copy sandbox paths.
- 🏛️ **Agent Workspace (`/workdir`)**: Complete sandbox directory isolation anchored at `root/` (`<app documents>/VinaAgent`). Easily switch agent workspaces via `/workdir <folder>` or reset with `/workdir default`.
- 🔥 **Dedicated Uncensored & Standard SLM Suite**: Curated 1-tap presets including **SmolLM2 135M/360M Heretic**, **Llama 3.2 1B Abliterated**, **Qwen 2.5 0.5B**, **DeepSeek R1 Distill 1.5B**, and **Llama 3.2 3B**.
- ⚡ **Real-Time Token Generation Speed (`⚡ X.X tok/s`)**: Live generation throughput metric displayed dynamically in the bottom-right corner of the AI response container.
- 🎨 **Unlimited AI Image Generation Engine**: Create infinite images from natural language (`/image <prompt>`) with custom aspect ratios (`1:1`, `16:9`, `9:16`, `4:3`, `3:4`), interactive zoom/pan viewer, and 1-tap gallery downloads.
- 📥 **In-App Model Downloading with Live Notification Progress**: Download model weights straight from HuggingFace to your phone's storage with background Android notifications and 1-tap **"Load into RAM"**.
- 📐 **Adaptive Auto-Fitting Chat Layout**: User message bubbles automatically shrink-wrap to their content length (e.g., single-word prompts fit tightly without stretching).
- 🤖 **Autonomous ReAct Agent Engine**: Multi-step tool execution with step-by-step reasoning logs, real-time status chips, and configurable confirmation safety gates.
- 🔌 **Model Context Protocol (MCP) Marketplace**: Native Streamable HTTP & SSE transport support with 11+ built-in servers (Brave Search, GitHub, Puppeteer, PostgreSQL, Memory Graph, Hardware Specs, etc.).
- 🌌 **Hermes Self-Evolving Memory System**: Persistent `USER.md`, `MEMORY.md`, and `SOUL.md` files that autonomously learn your personality, preferences, and context across sessions.
- 🤖 **Telegram Autonomous Remote Relay**: Turn your phone into a 24/7 background AI assistant that receives prompts and replies over Telegram.
- 🎨 **Cyberpunk Glassmorphism UI**: Isolated backdrop blur, dark/light themes, syntax-highlighted code blocks, and haptic feedback.

---

## 🏗 Architecture Overview

```mermaid
graph TD
    A[Flutter Glassmorphism UI] --> B[Riverpod State Controllers]
    B --> C[Chat & Agent Coordinator]
    
    C --> D[Local AI Engine]
    C --> E[Cloud Multi-Provider Gateway]
    C --> F[ReAct Agent Engine]
    C --> G[Hermes Memory Core]
    C --> H[Neural Image Synthesizer]
    C --> I[Sandboxed File Manager & Workdir]

    D --> D1[Native llama.cpp ARM NEON Bridge]
    D --> D2[Offline GGUF Weight Store]
    D --> D3[Background Download Manager]

    E --> E1[OpenAI / Claude / Gemini / DeepSeek / Ollama / OpenRouter]

    F --> F1[Built-In Mobile Tools & Attachments]
    F --> F2[MCP Server Transport HTTP / SSE]

    G --> G1[USER.md / MEMORY.md / SOUL.md]
    
    H --> H1[Turbo Diffusion Engine & Local Caching]

    I --> I1[AppSandbox /root & ZIP Engine]
```

---

## 🧠 Curated Local Model Suite

| Model Name | Parameters | Quantization | RAM Footprint | Category | Key Capability |
| :--- | :---: | :---: | :---: | :---: | :--- |
| **SmolLM2-135M-Instruct-heretic** | 135M | `Q4_K_M` | ~150 MB | 🔥 Uncensored | Ultra-compact, near-zero RAM footprint, zero alignment refusals |
| **SmolLM2-360M-Instruct-Heretic** | 360M | `Q4_K_M` | ~350 MB | 🔥 Uncensored | Balanced reasoning & instruction-following without guardrails |
| **Llama-3.2-1B-Abliterated** | 1.2B | `Q4_K_M` | ~950 MB | 🔥 Uncensored | Unrestricted creative writing, coding, and general assistance |
| **Qwen2.5-0.5B-Instruct** | 0.5B | `Q4_K_M` | ~450 MB | 💬 Standard | Multilingual instruction following & fast summaries |
| **Llama-3.2-1B-Instruct** | 1.2B | `Q4_K_M` | ~950 MB | 💬 Standard | Official Meta 1B model, high quality formatting & reasoning |
| **DeepSeek-R1-Distill-Qwen-1.5B** | 1.5B | `Q4_K_M` | ~1.3 GB | 💬 Standard | Distilled reasoning model with chain-of-thought output |
| **Llama-3.2-3B-Instruct** | 3.2B | `Q4_K_M` | ~2.1 GB | 💬 Standard | Comprehensive complex multi-step reasoning & coding |
| **SD-Turbo-Image-Gen** | Diffusion | `FP16` | ~1.8 GB | 🎨 Image Gen | Fast single-step local image generation |

---

## 🎨 Image Generation Commands

Generate images directly in any conversation using natural language:

```bash
# Square (1:1)
/image cyberpunk neon samurai meditating in rain

# Widescreen (16:9)
/image futuristic electric sports car speeding through tokyo 16:9

# Mobile Wallpaper (9:16)
/image breathtaking bioluminescent alien forest at night 9:16

# Natural Language Phrases
draw a cute fluffy orange cat wearing an astronaut helmet
generate an image of a medieval library filled with glowing crystals
```

---

## 🚀 Getting Started & Build Instructions

### Prerequisites
- **Flutter SDK**: `>= 3.29.0`
- **Dart SDK**: `>= 3.12.0`
- **Android SDK & NDK**: Installed with compileSdk 37, minSdk 26
- **Physical Android Device** (connected via USB/ADB) or Emulator

### 1. Clone & Setup Dependencies
```bash
git clone https://github.com/arthurlucky/VinaAgent.git
cd VinaAgent
flutter pub get
```

### 2. Verify Code & Run Tests
```bash
# Static analysis (0 warnings / errors)
flutter analyze

# Unit & widget test suite
flutter test
```

### 3. Run in Debug Mode on Device
```bash
flutter run -d <device_id>
```

### 4. Build Final Production Release APK
```bash
flutter build apk --release
```
The optimized release APK will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 🔒 Security & Sandboxing

- **App Sandbox Isolation**: All agent file reads, writes, and commands are strictly confined to the application sandbox (`<app documents>/VinaAgent`). Direct writes to external storage (`/sdcard`, `/storage/emulated/0`) are blocked.
- **Human-in-the-Loop Safeguards**: Irreversible operations (`delete_file`, `overwrite_file`) require explicit confirmation depending on your chosen policy (`Destructive Only`, `Always Ask`, or `Autonomous`).
- **Hardware AES-256 Storage**: All cloud API keys and bot tokens are encrypted in hardware-backed platform storage via `flutter_secure_storage`.
- **R8 / ProGuard Safety**: Native JNI symbol preservation guarantees native model execution in release builds without runtime reflection crashes.

---

## 📄 License

Vina Agent is open-source software licensed under the **[MIT License](LICENSE)**.
