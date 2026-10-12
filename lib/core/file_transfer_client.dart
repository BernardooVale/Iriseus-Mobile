import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class FileTransferClient {
  static const int chunkPlaintextSize = 256 * 1024; // 256 KiB

  /// Converte string UUID (com ou sem hífens) em 16 bytes binários
  static Uint8List uuidToBytes(String uuidStr) {
    final clean = uuidStr.replaceAll('-', '');
    if (clean.length != 32) {
      // Fallback: preenche com UTF-8 truncado/padded
      final bytes = Uint8List(16);
      final raw = utf8.encode(clean);
      for (int i = 0; i < 16 && i < raw.length; i++) {
        bytes[i] = raw[i];
      }
      return bytes;
    }
    final bytes = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Converte token em Base64 para 32 bytes binários
  static Uint8List tokenToBytes(String tokenBase64) {
    // libsodium urlsafe no padding ou standard
    String normalized = tokenBase64.replaceAll('-', '+').replaceAll('_', '/');
    while (normalized.length % 4 != 0) {
      normalized += '=';
    }
    final decoded = base64Decode(normalized);
    if (decoded.length == 32) return Uint8List.fromList(decoded);
    final buf = Uint8List(32);
    for (int i = 0; i < 32 && i < decoded.length; i++) {
      buf[i] = decoded[i];
    }
    return buf;
  }

  /// Envia um arquivo local para o Desktop (direção 0: MobileUploadToPc)
  static Future<void> sendFile({
    required String host,
    required int port,
    required String transferId,
    required String tokenBase64,
    required File file,
    required void Function(int bytesSent, int totalBytes) onProgress,
    bool Function()? isCancelled,
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));

      // 1. Handshake (49 bytes):
      // [16 bytes transferId] + [32 bytes token] + [1 byte direction (0)]
      final handshake = BytesBuilder(copy: false);
      handshake.add(uuidToBytes(transferId));
      handshake.add(tokenToBytes(tokenBase64));
      handshake.addByte(0); // 0 = MobileUploadToPc

      socket.add(handshake.takeBytes());
      await socket.flush();

      final totalSize = await file.length();
      int bytesSent = 0;

      // 2. Transmissão em chunks com framing [4 bytes BE: N][N bytes]
      final fileStream = file.openRead();
      final chunkBuilder = BytesBuilder();

      await for (final data in fileStream) {
        if (isCancelled != null && isCancelled()) {
          throw Exception('Transferência cancelada');
        }

        chunkBuilder.add(data);

        while (chunkBuilder.length >= chunkPlaintextSize) {
          final chunk = Uint8List.fromList(chunkBuilder.takeBytes());
          final toSend = chunk.sublist(0, chunkPlaintextSize);
          final remaining = chunk.sublist(chunkPlaintextSize);
          chunkBuilder.add(remaining);

          final frame = _buildFrame(toSend);
          socket.add(frame);
          await socket.flush();

          bytesSent += toSend.length;
          onProgress(bytesSent, totalSize);
        }
      }

      // Resto final (se houver)
      if (chunkBuilder.length > 0) {
        final remaining = chunkBuilder.takeBytes();
        final frame = _buildFrame(remaining);
        socket.add(frame);
        await socket.flush();

        bytesSent += remaining.length;
        onProgress(bytesSent, totalSize);
      }
    } finally {
      try {
        await socket?.close();
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Recebe um arquivo do Desktop (direção 1: DesktopDownloadToMobile)
  static Future<void> receiveFile({
    required String host,
    required int port,
    required String transferId,
    required String tokenBase64,
    required File targetFile,
    required int expectedSize,
    required void Function(int bytesReceived, int totalBytes) onProgress,
    bool Function()? isCancelled,
  }) async {
    Socket? socket;
    IOSink? sink;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));

      // Handshake: [16 bytes transferId] + [32 bytes token] + [1 byte direction (1)]
      final handshake = BytesBuilder(copy: false);
      handshake.add(uuidToBytes(transferId));
      handshake.add(tokenToBytes(tokenBase64));
      handshake.addByte(1); // 1 = DesktopDownloadToMobile

      socket.add(handshake.takeBytes());
      await socket.flush();

      sink = targetFile.openWrite();
      int totalReceived = 0;

      final buffer = BytesBuilder();

      await for (final data in socket) {
        if (isCancelled != null && isCancelled()) {
          throw Exception('Transferência cancelada');
        }

        buffer.add(data);

        while (buffer.length >= 4) {
          final currentBytes = buffer.toBytes();
          final chunkSize = (currentBytes[0] << 24) |
                            (currentBytes[1] << 16) |
                            (currentBytes[2] << 8) |
                            currentBytes[3];

          if (chunkSize <= 0 || chunkSize > 1024 * 1024) {
            throw Exception('Chunk size inválido recebido: $chunkSize');
          }

          if (buffer.length < 4 + chunkSize) {
            // Aguarda mais dados para completar o frame
            break;
          }

          final chunk = currentBytes.sublist(4, 4 + chunkSize);
          sink.add(chunk);

          // Remove o frame processado do buffer
          final remaining = currentBytes.sublist(4 + chunkSize);
          buffer.clear();
          buffer.add(remaining);

          totalReceived += chunk.length;
          onProgress(totalReceived, expectedSize);
        }

        if (totalReceived >= expectedSize) {
          break;
        }
      }

      await sink.flush();
    } finally {
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await socket?.close();
        socket?.destroy();
      } catch (_) {}
    }
  }

  static Uint8List _buildFrame(List<int> payload) {
    final len = payload.length;
    final header = Uint8List(4);
    header[0] = (len >> 24) & 0xFF;
    header[1] = (len >> 16) & 0xFF;
    header[2] = (len >> 8) & 0xFF;
    header[3] = len & 0xFF;

    final bb = BytesBuilder(copy: false);
    bb.add(header);
    bb.add(payload);
    return bb.takeBytes();
  }
}
