# Iriseus Mobile

App Android do Iriseus — captura câmera e envia stream H264 para o app
Windows via WiFi ou USB, aparecendo como webcam virtual no PC.

Repositório do app Windows: https://github.com/BernardooVale/Iriseus

---

## Problema original

Necessidade de usar o celular como webcam em entrevistas técnicas em
empresas grandes, que exigem câmera ligada durante provas online.
O PC não possui câmera integrada.

---

## Estado atual

- WebSocket client — canal de controle com o app Windows
- Pareamento via QR Code + PIN (ECDH X25519 + TOFU)
- Descoberta de dispositivos via mDNS (`_iriseus._tcp.local`)
- Pipeline de câmera: CameraX → MediaCodec H264 → socket TCP
- Modo USB — detecção automática via `127.0.0.1`
- Reconexão automática sem novo pareamento

---

## Arquitetura

```
[CameraX — captura frames]
↓
[MediaCodec — encode H264 Baseline 1280x720 30fps]
↓
[Socket TCP porta 45679 — framing 4 bytes big-endian]
↓ WiFi ou USB via ADB reverse
[App Windows — decodifica e envia para Softcam]
```

**Protocolo de framing do stream:**
```
[4 bytes big-endian: tamanho N][N bytes: NALU H264]
[4 bytes big-endian: tamanho M][M bytes: NALU H264]
```

**Portas:**
- `45678` — WebSocket de controle
- `45679` — stream H264 TCP
- `5353` — mDNS (multicast)

---

## Stack

| Componente | Tecnologia |
|---|---|
| Framework | Flutter 3.x (Android) |
| WebSocket | `web_socket_channel` |
| mDNS | `multicast_dns` |
| QR Code scanner | `mobile_scanner` |
| Criptografia | `cryptography` (X25519 ECDH) |
| Persistência | `shared_preferences` |
| Permissões | `permission_handler` |
| Câmera + encode | CameraX + MediaCodec (Kotlin nativo) |

---

## Estrutura

```
iriseus/
├── android/app/src/main/kotlin/com/example/iriseus/
│ ├── MainActivity.kt ← channels Flutter ↔ Kotlin
│ ├── CameraStreamer.kt ← CameraX + MediaCodec + socket TCP
│ ├── CameraStreamView.kt ← PlatformView com PreviewView
│ └── CameraStreamViewFactory.kt
├── lib/
│ ├── main.dart
│ ├── core/
│ │ ├── ws_client.dart ← WebSocket de controle
│ │ ├── mdns_discovery.dart ← descoberta de dispositivos
│ │ ├── pairing_manager.dart ← ECDH + TOFU + persistência
│ │ └── stream_controller.dart
│ ├── ui/
│ │ ├── home_screen.dart ← lista dispositivos + botões USB/parear
│ │ ├── pairing_screen.dart ← scanner QR + entrada PIN
│ │ └── camera_screen.dart ← preview + controles de stream
│ └── models/
│ ├── device.dart
│ └── pairing_info.dart
└── docs/
├── flutter_architecture.md
└── background_streaming.md ← débito técnico
```

---

## Pré-requisitos

- Flutter 3.19+
- Android SDK 24+ (Android 7.0)
- App Windows rodando na mesma rede

---

## Build

```bash
flutter pub get
flutter run
```

Para modo USB, configurar ADB reverse no PC antes de iniciar o app:

```
adb reverse tcp:45678 tcp:45678
adb reverse tcp:45679 tcp:45679
```

O app Windows faz isso automaticamente ao detectar o celular via USB.

---

## Primeiro uso

### Via QR Code
1. Abrir app Windows → menu systray → "Parear dispositivo"
2. No celular: "Parear novo dispositivo" → escanear QR

### Via PIN
1. App Windows exibe PIN na tela de pareamento
2. No celular: descobrir PC via mDNS → digitar PIN

### Via USB
1. Conectar celular via USB com depuração USB habilitada
2. App Windows configura ADB reverse automaticamente
3. No celular: botão "Conectar via USB"

---

## Limitações conhecidas

- mDNS pode não funcionar se PC estiver em Ethernet e celular em WiFi
  (roteadores domésticos bloqueiam multicast entre interfaces) —
  usar conexão por IP manual ou USB como alternativa
- Streaming em background não suportado — câmera pausa se app for
  minimizado (ver `docs/background_streaming.md`)
- Conversão YUV→NV21 sem stride — pode gerar preview distorcido em
  alguns devices; ajuste stride-aware planejado

---

## Ordem de desenvolvimento

1. ✅ WebSocket client — controle
2. ✅ Pareamento QR + PIN — ECDH X25519 + TOFU
3. ✅ Descoberta mDNS
4. ✅ Pipeline de câmera — CameraX + MediaCodec + socket TCP
5. ✅ Modo USB — detecção automática
6. ✅ Reconexão automática
7. 🔲 Foreground Service — streaming em background
8. 🔲 Stride-aware YUV→NV21
9. 🔲 Transferência de arquivos
10. 🔲 iOS