# Scribe - Audio Transcription

A cross-platform desktop application for high-performance, offline audio transcription.

## 🏗️ Architecture

```
┌─────────────────┐          ┌─────────────────┐
│  Flutter UI     │  <gRPC>  │  Python Engine  │
│  (Frontend)     │◄────────►│  (Backend)      │
└─────────────────┘          └─────────────────┘
        │                            │
        ▼                            ▼
  Local SQLite DB              Whisper Models
```

- **Frontend**: Flutter desktop application for the user interface
- **Backend**: Python server with faster-whisper transcription engine
- **Communication**: gRPC for efficient, type-safe communication
- **Storage**: SQLite for job management and settings
- **Models**: Local Whisper model cache for offline operation

## 📋 Prerequisites

### macOS

- Python 3.10+ with pip
- FFmpeg (`brew install ffmpeg`)
- Protocol Buffers compiler (`brew install protobuf`)
- Dart protoc plugin (`dart pub global activate protoc_plugin`)
- Flutter SDK 3.22+ with desktop support
- Xcode Command Line Tools

### Windows

- Python 3.10+ with pip
- FFmpeg (download from ffmpeg.org)
- Protocol Buffers compiler (download from GitHub releases)
- Dart protoc plugin (`dart pub global activate protoc_plugin`)
- Flutter SDK 3.22+ with desktop support
- Visual Studio 2022 with C++ desktop development

### Linux

- Python 3.10+ with pip
- FFmpeg (`sudo apt install ffmpeg`)
- Protocol Buffers compiler (`sudo apt install protobuf-compiler`)
- Dart protoc plugin (`dart pub global activate protoc_plugin`)
- Flutter SDK 3.22+ with desktop support
- Build essentials (`sudo apt install build-essential`)

## 🚀 Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/munalgar/scribe.git
cd scribe
```

### 2. Set up the Python backend

```bash
# Create virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r backend/requirements.txt

# Generate gRPC code
bash scripts/gen_proto.sh  # On Windows: powershell scripts/gen_proto.ps1
```

### 3. Set up the Flutter frontend

```bash
# Navigate to Flutter app
cd frontend/flutter/scribe_app

# Get dependencies
flutter pub get
```

### 4. Run the application

**Terminal 1 - Start the backend:**

```bash
bash scripts/dev_backend.sh  # On Windows: powershell scripts/dev_backend.ps1
```

**Terminal 2 - Start the frontend:**

```bash
bash scripts/dev_frontend.sh macos  # Or: windows, linux
```

## 🎙️ Usage

1. **Start the backend server** - This runs the transcription engine
2. **Launch the Flutter app** - This provides the user interface
3. **Connect** - Click the Connect button to establish connection with the backend
4. **Select audio file** - Choose an audio file to transcribe
5. **View results** - See real-time transcription progress and results

## 🚀 GPU Acceleration

### NVIDIA GPUs (CUDA)

- Install CUDA Toolkit 11.8 or 12.x
- Install cuDNN 8.x
- The backend will automatically detect and use CUDA

### Apple Silicon (Metal)

- Works automatically on M1/M2/M3 Macs
- No additional setup required

### AMD GPUs (ROCm)

- Linux only: Install ROCm toolkit
- Set environment variable: `export HSA_OVERRIDE_GFX_VERSION=10.3.0`

### Windows (DirectML)

- Supports AMD, Intel, and NVIDIA GPUs
- Install DirectML runtime (comes with Windows 10 1903+)

## 📦 Model Management

Whisper models are downloaded automatically on first use:

- **tiny** (~39 MB) - Fastest, lower accuracy
- **base** (~74 MB) - Good balance
- **small** (~244 MB) - Better accuracy
- **medium** (~769 MB) - High accuracy
- **large-v3** (~1.5 GB) - Best accuracy

Models are cached in `shared/models/` for offline use.

## 🏗️ Building for Distribution

### Backend (Python to executable)

```bash
bash scripts/build_backend_nuitka.sh
```

### Frontend (Flutter)

```bash
cd frontend/flutter/scribe_app

# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
```

## 🔧 Troubleshooting

### Backend won't start

- Check Python version: `python3 --version` (needs 3.10+)
- Verify virtual environment is activated
- Check port 50051 is not in use

### Frontend connection issues

- Ensure backend is running first
- Check firewall isn't blocking localhost:50051
- Verify gRPC code generation completed successfully

### GPU not detected

- Check CUDA installation: `nvidia-smi`
- Verify PyTorch CUDA support: `python -c "import torch; print(torch.cuda.is_available())"`
- Try CPU mode by setting compute_type to "int8"

### Model download fails

- Check disk space (need 2-3 GB free)
- Verify internet connection for initial download
- Try smaller model first (tiny or base)

## Testing

### Backend Tests

Basic sanity checks for backend components:

```bash
python3 tests/test_backend.py
python3 tests/test_server.py
```

### Frontend Tests

Run Flutter widget tests:

```bash
cd frontend/flutter/scribe_app
flutter test
```

## Contributing

We welcome contributions! Please see CONTRIBUTING.md for guidelines.

## 📄 License

This project is licensed under the MIT License - see LICENSE file for details.

## 🙏 Acknowledgments

- [OpenAI Whisper](https://github.com/openai/whisper) for the transcription models
- [faster-whisper](https://github.com/SYSTRAN/faster-whisper) for optimized inference
- [Flutter](https://flutter.dev) for cross-platform UI
- [gRPC](https://grpc.io) for efficient communication

---

Built with ❤️ for privacy and performance
