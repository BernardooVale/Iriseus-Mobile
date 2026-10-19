# Plano — Espelhamento de Tela do Celular (`plano_espelho.md`)

> Planejamento técnico e divisão de tarefas para permitir a transmissão da tela do celular no lugar da imagem da câmera, alternando por um botão ao lado do de inverter câmera e prevenindo loops de gravação recursiva (*efeito espelho infinito*).

**Legenda de status:**
- `[ ]` Tarefa aberta
- `[x]` Tarefa concluída

---

## 1. Visão Geral e Arquitetura

Atualmente, o pipeline de vídeo captura frames da câmera via **CameraX** (`ImageAnalysis` em YUV_420_888), codifica em **H.264** via `MediaCodec` e transmite pacotes NALU pelo socket TCP na porta `45679` para o PC (`StreamReceiver` → `VideoDecoder` → `VirtualCamera` / Softcam).

Para transmitir a tela do celular:
1. **Captura nativa via `MediaProjection` + `VirtualDisplay`**: no Android, utilizamos a API `MediaProjection` conectada diretamente a uma `Surface` de entrada do `MediaCodec` (`COLOR_FormatSurface`), sem passar buffers YUV pela CPU.
2. **Reuso do canal TCP (`45679`)**: a troca entre **Câmera ⇄ Tela** ocorre no mesmo socket TCP já ativo, reiniciando apenas o `MediaCodec` para emitir novos cabeçalhos `SPS/PPS` + `IDR` na transição sem derrubar o socket.
3. **Estabilidade de Resolução no PC (Pillarbox/Letterbox `1920x1080`)**: como a tela do celular geralmente está na vertical (ex.: `1080x2400`) e programas como Discord/Meet/OBS travam se a `VirtualCamera` (DirectShow) mudar de dimensões após aberta, o frame final enviado ao Softcam mantém o canvas fixo de `1920x1080` com barras pretas laterais (*pillarbox*) quando em retrato e preenchimento total quando em paisagem.

---

## 2. Estratégia Anti-Loop ("Não gravar a tela sendo gravada")

O loop recursivo (*hall of mirrors*) acontece quando a superfície que está sendo capturada exibe o próprio retorno da gravação. Para eliminar esse risco:

1. **Sem preview de tela no app Mobile**: diferentemente da câmera (que usa `PreviewView`), o `VirtualDisplay` do `MediaProjection` escreve **exclusivamente** na `Surface` do `MediaCodec`. Nenhum widget no Flutter renderiza os frames capturados da tela.
2. **Substituição do `PlatformView` no modo Tela**: enquanto o modo de compartilhamento de tela estiver ativo na `CameraScreen`, o `PlatformViewLink` do preview da câmera é desmontado/ocultado e substituído por um painel estático escuro informando *"Transmitindo a tela do celular — você pode minimizar o app"*.
3. **Minimização automática (`moveTaskToBack`)**: assim que o usuário concede a permissão de captura de tela, o app minimiza-se automaticamente para a tela inicial do Android, evitando gravar a própria interface de controle.

---

## 3. Tarefas Implementadas (Base Existente)

- [x] **B1.1** Pipeline TCP de vídeo H.264 na porta `45679` com framing `[4 bytes tamanho BE][NALU]` (`CameraStreamer.kt` e `StreamReceiver.cpp`).
- [x] **B1.2** Decodificação H.264 via FFmpeg (`VideoDecoder.cpp`) e envio para webcam virtual DirectShow (`VirtualCamera.cpp` / `softcam.dll`).
- [x] **B1.3** Serviço em primeiro plano (`CameraForegroundService.kt`) mantendo `WakeLock` e transmissão ativa com o app em background.
- [x] **B1.4** UI de transmissão no Flutter (`camera_screen.dart`) com indicador de status e botão de inverter câmera (`Icons.cameraswitch`).
- [x] **B1.5** Canal de controle WebSocket na porta `45678` e suporte a `adb reverse` via USB (`AdbManager.cpp`).

---

## 4. Tarefas — Mobile (`Iriseus-Mobile`)

### Marco 1 — Permissões e Configuração do `ForegroundService` (Android 10 a 14+)
- [x] **M1.1** Adicionar a permissão `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />` no `android/app/src/main/AndroidManifest.xml`.
- [x] **M1.2** Atualizar o `<service android:name=".CameraForegroundService">` no `AndroidManifest.xml` para declarar `android:foregroundServiceType="camera|mediaProjection"`.
- [x] **M1.3** Em `CameraForegroundService.kt`, criar suporte para alternar o tipo do `startForeground()` entre `FOREGROUND_SERVICE_TYPE_CAMERA` e `FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION` (obrigatório no Android 14 / API 34 antes de chamar `getMediaProjection`).
- [x] **M1.4** Atualizar o texto da notificação persistente quando em modo tela (*"Transmitindo a tela para o PC"*).

### Marco 2 — Solicitação de Permissão `MediaProjection` na `MainActivity`
- [x] **M2.1** Adicionar métodos `startScreenShare` e `stopScreenShare` no `MethodChannel("com.example.iriseus/camera")` em `MainActivity.kt`.
- [x] **M2.2** Implementar a chamada de `MediaProjectionManager.createScreenCaptureIntent()` com `startActivityForResult` e tratar o retorno em `onActivityResult`.
- [x] **M2.3** Se o usuário recusar a permissão (`resultCode != RESULT_OK`), retornar `false` para o Flutter e manter a câmera ativa sem interromper a conexão TCP.
- [x] **M2.4** Se o usuário aceitar (`RESULT_OK`), repassar `resultCode` e `data` (`Intent`) para o `CameraForegroundService` via `ACTION_START_SCREEN_SHARE`.

### Marco 3 — Captura da Tela e Codificação H.264 (`CameraStreamer.kt`)
- [x] **M3.1** Criar o modo de captura de tela em `CameraStreamer.kt` (compartilhando o mesmo `outputStream`/socket TCP) para alternar entre CameraX e `MediaProjection` sem desconectar do PC.
- [x] **M3.2** Ao entrar no modo tela: fazer `cameraProvider?.unbindAll()` para desligar a câmera física e economizar bateria/aquecimento.
- [x] **M3.3** Calcular a resolução do `VirtualDisplay` com base nas métricas da tela real do aparelho, limitando o maior lado a `1920` (ou `1280`) e arredondando largura e altura para múltiplos pares/16 compatíveis com o `MediaCodec`.
- [x] **M3.4** Configurar o `MediaCodec` (`video/avc`) com `COLOR_FormatSurface` e `KEY_REPEAT_PREVIOUS_FRAME_AFTER` (`100_000L` µs) para manter o envio de frames mesmo quando a tela estiver parada.
- [x] **M3.5** Registrar `MediaProjection.Callback` **antes** de criar o `VirtualDisplay` (requisito obrigatório do Android 14+) para detectar encerramento externo da gravação pelo sistema.
- [x] **M3.6** Criar a `inputSurface = encoder.createInputSurface()` e instanciar o `VirtualDisplay` com `DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR`, drenando os NALUs pelo `drainEncoderLoop()` existente.
- [x] **M3.7** Implementar a volta para a câmera (`stopScreenShare`): liberar `VirtualDisplay`, parar `MediaProjection`, recriar o encoder em `COLOR_FormatYUV420SemiPlanar` e religar `bindUseCases()` do CameraX.
- [x] **M3.8** Emitir eventos de mudança de modo (`mode: "camera" | "screen"`) pelo `EventChannel("com.example.iriseus/camera_events")` para sincronizar o estado da UI caso a gravação de tela seja encerrada pela barra do sistema Android.

### Marco 4 — Interface do Usuário e Prevenção de Loop (`camera_screen.dart` e `stream_controller.dart`)
- [x] **M4.1** Em `lib/core/stream_controller.dart`, adicionar estado do modo de transmissão (`StreamMode.camera` vs `StreamMode.screen`) e os métodos `startScreenShare()` / `stopScreenShare()`.
- [x] **M4.2** Em `lib/ui/camera_screen.dart`, adicionar o botão de compartilhar tela (`Icons.screen_share_outlined` / `Icons.stop_screen_share_outlined`) ao lado esquerdo do botão de inverter câmera (`Icons.cameraswitch`) na barra superior.
- [x] **M4.3** Desabilitar ou ocultar o botão de inverter câmera (`Icons.cameraswitch`) enquanto o modo de compartilhamento de tela estiver ativo.
- [x] **M4.4** **Prevenção de Loop na UI**: quando `_mode == StreamMode.screen`, remover o `PlatformViewLink` da árvore de widgets e exibir uma tela estática escura com ícone e instrução (*"Transmitindo a tela do celular"*), garantindo que nenhum frame capturado seja desenhado na própria tela.
- [x] **M4.5** **Prevenção de Loop no Android**: minimizar o app automaticamente (`moveTaskToBack(true)`) após o início da captura de tela durante o espelhamento.

---

## 5. Tarefas — Desktop (`Iriseus` Windows)

### Marco 5 — Adaptação de Proporção (Retrato/Paisagem) e Controle no PC
- [x] **D5.1** Em `VideoDecoder.cpp` / `StreamReceiver.cpp`, garantir que mudanças dinâmicas de resolução e orientação vindas do H.264 (ex.: câmera `1920x1080` → tela em retrato `1080x2400` → tela em paisagem `2400x1080`) sejam convertidas via `sws_scale` mantendo o aspect ratio com *pillarbox/letterbox* dentro de um frame fixo `1920x1080`, evitando fechar/reabrir a `VirtualCamera` durante chamadas ativas.
- [x] **D5.2** Adicionar mensagens WebSocket `start_screen` e `stop_screen` em `MessageDispatcher.h`, `WsServer.h/.cpp` e `ws_client.dart` para atualizar o tooltip do ícone de bandeja (`TrayIcon`) no Windows indicando se está recebendo câmera ou tela.

---

## 6. Guia de Testes de Aceitação

- [ ] **T1** Clicar no botão de transmitir tela ao lado do de inverter câmera abre o diálogo nativo de permissão do Android.
- [ ] **T2** Negar a permissão mantém a transmissão da câmera funcionando normalmente sem cair a conexão.
- [ ] **T3** Aceitar a permissão desliga a câmera, oculta o preview local (evitando o loop de gravar a própria tela) e passa a exibir a tela do celular no PC.
- [ ] **T4** Rotacionar o celular (retrato ⇄ paisagem) ajusta a imagem no PC sem travar o decodificador nem derrubar a webcam virtual nos apps consumidores.
- [ ] **T5** Deixar a tela do celular parada (sem tocar em nada) mantém a imagem estável no PC (graças ao `KEY_REPEAT_PREVIOUS_FRAME_AFTER`).
- [ ] **T6** Clicar novamente no botão de tela (ou parar pela notificação do sistema Android) retorna suavemente para a transmissão da câmera.
