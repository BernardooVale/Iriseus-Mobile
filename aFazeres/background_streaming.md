# Background Streaming — Débito Técnico

## Estado atual

CameraX roda no lifecycle da Activity. App minimizado ou tela desligada
pausa a câmera e interrompe o stream.

## O que precisa mudar

- `CameraStreamer.kt` → mover lógica para `CameraStreamService.kt`
  (Android Foreground Service)
- `MainActivity.kt` → comunicação via bindService em vez de instância direta
- `stream_controller.dart` → MethodChannel passa a controlar o Service
- `AndroidManifest.xml` → adicionar permissões e declaração do Service

## Permissões necessárias

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CAMERA" />
```

## Restrições Android

- Foreground Service com câmera exige notificação persistente visível
- Android 14+ exige declarar `foregroundServiceType="camera"` no manifest
- Não é possível acessar câmera em background puro (sem foreground service)

## Impacto estimado

~3-4h. Sem quebra de protocolo WebSocket/TCP — só reorganização do lado
Android.