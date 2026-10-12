# Plano — Transferência de Arquivos (Mobile / Flutter + Android)

> Plano do lado **Mobile**. O lado desktop está em `Iriseus/plano.md`. A seção de protocolo é **idêntica** nos dois arquivos: qualquer mudança precisa ser feita nos dois.

Objetivo: transferir qualquer tipo de arquivo, em qualquer direção (celular ⇄ PC), por WiFi ou USB.

**Decisões fechadas**
- Pasta de destino: `Download/Iriseus` (via MediaStore)
- Ofertas do PC pareado são **aceitas automaticamente**.
- **Sem retomada**: se a conexão cair, a transferência falha, o temporário é apagado e o usuário reenvia.

---

## 1. Protocolo (compartilhado)

```
           Controle (JSON)  ── WebSocket :45678 (já existe)
[Mobile] ◄──────────────────────────────────────────────► [Desktop]
           Dados (binário)  ── TCP :45680 (novo, criptografado)
```

- O desktop é **sempre servidor** no 45680 e o mobile **sempre cliente**, nos dois sentidos. No USB o mobile conecta em `127.0.0.1:45680` (o desktop faz o `adb reverse`).
- Chave de arquivos: `crypto_kdf_derive_from_key(subkey_id=1, ctx="irisfile", key=segredo_ECDH_do_pareamento)`.
- Cifra: `crypto_secretstream_xchacha20poly1305` (libsodium). Integridade final por SHA-256 do arquivo.

### 1.1 Mensagens WS

| `type` | Direção | Campos |
|---|---|---|
| `file_offer` | remetente → destinatário | `transferId` (uuid v4), `name`, `size` (uint64), `mime`, `sha256` (hex) |
| `file_accept` | destinatário → remetente | `transferId` |
| `file_reject` | destinatário → remetente | `transferId`, `reason` (`not_paired`, `no_space`, `busy`) |
| `file_ready` | desktop → mobile | `transferId`, `port`, `token` (32 bytes, base64) |
| `file_complete` | destinatário → remetente | `transferId`, `ok` (bool), `error?` |
| `file_cancel` | qualquer um | `transferId` |

### 1.2 Canal de dados (TCP 45680)

```
Handshake (mobile → desktop):
  [16 bytes transferId (uuid binário)][32 bytes token][1 byte dir: 0 = mobile envia, 1 = desktop envia]

Quem envia os dados:
  [24 bytes header secretstream]
  [4 bytes BE: N][N bytes chunk cifrado]  (plaintext ≤ 256 KiB, +17 bytes de tag)
  ...  (último chunk com TAG_FINAL)
```

### 1.3 Fluxos
- **Celular → PC**: `file_offer` (M) → `file_accept` (D, automático) → `file_ready` (D) → M conecta e envia → D confere o hash → `file_complete` (D).
- **PC → Celular**: `file_offer` (D) → `file_accept` (M, automático) → `file_ready` (D) → M conecta (dir=1) e recebe → M confere o hash → `file_complete` (M).
- Qualquer erro, queda ou timeout de 30 s sem dados → `file_cancel`/falha, e o temporário é apagado.

---

## 2. Tarefas — Mobile

### Marco 1 — Celular → PC sem criptografia
- [x] **M1.1** Dependências: `file_picker`, `crypto` (SHA-256), `uuid`.
- [x] **M1.2** `lib/models/file_transfer.dart`: `FileTransfer` (id, nome, tamanho, mime, direção, estado, bytes) com `fromJson`/`toJson`.
- [x] **M1.3** Em [`ws_client.dart`](file:///c:/Users/Plusb/StudioProjects/Iriseus/lib/core/ws_client.dart): `sendFileOffer`, `sendFileAccept`, `sendFileReject`, `sendFileCancel`, `sendFileComplete`.
- [x] **M1.4** `lib/core/file_transfer_client.dart`: `Socket.connect(host, 45680)` (`127.0.0.1` no modo USB) e envio do handshake.
- [x] **M1.5** Envio: `File.openRead` em chunks de 256 KiB, com framing e backpressure (`await socket.flush()`).
- [x] **M1.6** `lib/core/file_transfer_manager.dart`: escuta `file_*` em `ws.messages`, calcula o SHA-256, manda a oferta, espera `file_ready`, dispara o client e aguarda `file_complete`. Expõe `Stream<List<FileTransfer>>`.

### Marco 2 — Criptografia
- [ ] **M2.1** Dependência `sodium_libs` (secretstream compatível com libsodium).
- [ ] **M2.2** `deriveFileKey()` em [`pairing_manager.dart`](file:///c:/Users/Plusb/StudioProjects/Iriseus/lib/core/pairing_manager.dart) (KDF da seção 1).
- [ ] **M2.3** Aplicar `secretstream push` no envio.
- [ ] **M2.4** Mover a cripto e o hash para um `Isolate`, para não travar a UI.
- [ ] **M2.5** Testar com o mesmo vetor fixo do desktop.

### Marco 3 — PC → Celular
- [ ] **M3.1** Manager: ao receber `file_offer`, checar espaço livre e mandar `file_accept` automaticamente (ou `file_reject{no_space}`).
- [ ] **M3.2** Client modo recebimento (dir=1): parser de framing com buffer, `secretstream pull`, gravação em arquivo temporário no cache e SHA-256 incremental.
- [ ] **M3.3** `MethodChannel` Kotlin `saveToDownloads(path, name, mime)`: `MediaStore.Downloads` com `RELATIVE_PATH = Download/Iriseus` (API 29+). Para API ≤ 28, `WRITE_EXTERNAL_STORAGE`.
- [ ] **M3.4** Após salvar: apagar o temporário e mandar `file_complete`.

### Marco 4 — UI e integração Android
- [ ] **M4.1** Botão **"Enviar arquivo"** na [`home_screen.dart`](file:///c:/Users/Plusb/StudioProjects/Iriseus/lib/ui/home_screen.dart) (habilitado quando conectado, aceita vários arquivos).
- [ ] **M4.2** `lib/ui/transfers_screen.dart`: lista com progresso, velocidade, cancelar e "abrir" (recebidos).
- [ ] **M4.3** Snackbar/notificação de arquivo recebido ou erro.
- [ ] **M4.4** **Compartilhar → Iriseus**: `intent-filter` `ACTION_SEND` / `ACTION_SEND_MULTIPLE` com `*/*` no `AndroidManifest.xml` + `receive_sharing_intent`.
- [ ] **M4.5** Leitura por content URI (`ContentResolver.openInputStream`) via MethodChannel, para arquivos compartilhados/grandes sem copiar para o cache.
- [ ] **M4.6** Foreground service tipo `dataSync` (estender o `CameraForegroundService` ou criar um novo) com notificação de progresso + `WifiLock`, para a transferência sobreviver em segundo plano.

### Marco 5 — Casos de borda
- [ ] **M5.1** Cancelamento, queda do WS/socket ou timeout → fechar o socket, apagar o temporário e mostrar erro.
- [ ] **M5.2** Sanitizar o nome recebido (`/`, `..`, caracteres de controle).
- [ ] **M5.3** Modo USB nos dois sentidos.
- [ ] **M5.4** Transferir com a câmera ativa → o vídeo não pode degradar.

---

## 3. Testes de aceitação (mobile)
- [ ] Arquivos de 0 B, 1 B, 1 MB e > 4 GB.
- [ ] Tipos variados (`.apk`, `.zip`, `.mp4`, `.pdf`). Nomes com acentos e emoji.
- [ ] O hash confere nos dois sentidos. Recebidos aparecem em `Download/Iriseus` no app Arquivos.
- [ ] Compartilhar da Galeria → chega no PC.
- [ ] App em segundo plano durante a transferência → conclui.
- [ ] Cancelar ou derrubar o WiFi no meio → nenhum arquivo órfão e erro claro.
