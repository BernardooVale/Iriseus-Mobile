import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../models/file_transfer.dart';
import 'ws_client.dart';
import 'file_transfer_client.dart';

class FileTransferManager {
  final WsClient _ws;
  final _uuid = const Uuid();

  final List<FileTransfer> _transfers = [];
  final _transfersController = StreamController<List<FileTransfer>>.broadcast();

  Stream<List<FileTransfer>> get transfersStream => _transfersController.stream;
  List<FileTransfer> get transfers => List.unmodifiable(_transfers);

  StreamSubscription? _wsSubscription;

  FileTransferManager(this._ws) {
    _initWsListener();
  }

  void _initWsListener() {
    _wsSubscription = _ws.messages.listen((msg) {
      final type = msg['type'] as String?;
      if (type == null) return;

      if (type == 'file_offer') {
        _handleIncomingFileOffer(msg);
      } else if (type == 'file_complete') {
        _handleFileComplete(msg);
      } else if (type == 'file_reject') {
        _handleFileReject(msg);
      } else if (type == 'file_cancel') {
        _handleFileCancel(msg);
      }
    });
  }

  void dispose() {
    _wsSubscription?.cancel();
    _transfersController.close();
  }

  void _notify() {
    if (!_transfersController.isClosed) {
      _transfersController.add(List.unmodifiable(_transfers));
    }
  }

  /// Calcula o SHA-256 de um arquivo local
  static Future<String> computeSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Inicia envio de arquivo para o PC conectado
  Future<void> sendFile({
    required File file,
    required String host,
    int? customPort,
  }) async {
    final size = await file.length();
    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'arquivo_${DateTime.now().millisecondsSinceEpoch}';

    // 1. Gera ID e calcula SHA-256
    final transferId = _uuid.v4();
    final hash = await computeSha256(file);

    final transfer = FileTransfer(
      id: transferId,
      name: name,
      size: size,
      mime: 'application/octet-stream',
      sha256: hash,
      localPath: file.path,
      direction: TransferDirection.mobileUploadToPc,
      status: TransferStatus.pending,
    );

    _transfers.insert(0, transfer);
    _notify();

    try {
      // 2. Envia file_offer pelo WebSocket
      _ws.sendFileOffer(
        transferId: transferId,
        name: name,
        size: size,
        mime: transfer.mime,
        sha256: hash,
      );

      // 3. Aguarda resposta file_ready (ou accept seguido de ready)
      // O desktop atual envia file_accept e em seguida file_ready com port e token
      final readyMsg = await _ws.messages
          .firstWhere((m) =>
              m['type'] == 'file_ready' && m['transferId'] == transferId)
          .timeout(const Duration(seconds: 15));

      final port = (readyMsg['port'] as int?) ?? customPort ?? 45680;
      final token = readyMsg['token'] as String;

      transfer.status = TransferStatus.transferring;
      _notify();

      // 4. Conecta no TCP e transmite os bytes
      await FileTransferClient.sendFile(
        host: host,
        port: port,
        transferId: transferId,
        tokenBase64: token,
        file: file,
        onProgress: (bytes, total) {
          transfer.bytesTransferred = bytes;
          _notify();
        },
        isCancelled: () => transfer.status == TransferStatus.cancelled,
      );

      // 5. Aguarda confirmação final file_complete do desktop
      final completeMsg = await _ws.messages
          .firstWhere((m) =>
              m['type'] == 'file_complete' && m['transferId'] == transferId)
          .timeout(const Duration(seconds: 15));

      final ok = completeMsg['ok'] as bool? ?? false;
      if (ok) {
        transfer.status = TransferStatus.completed;
      } else {
        transfer.status = TransferStatus.failed;
        transfer.error = completeMsg['error'] as String? ?? 'Erro no servidor';
      }
    } catch (e) {
      if (transfer.status != TransferStatus.cancelled) {
        transfer.status = TransferStatus.failed;
        transfer.error = e.toString();
      }
    } finally {
      _notify();
    }
  }

  void cancelTransfer(String transferId) {
    final idx = _transfers.indexWhere((t) => t.id == transferId);
    if (idx != -1) {
      _transfers[idx].status = TransferStatus.cancelled;
      _ws.sendFileCancel(transferId);
      _notify();
    }
  }

  void _handleFileComplete(Map<String, dynamic> msg) {
    final transferId = msg['transferId'] as String?;
    final ok = msg['ok'] as bool? ?? false;
    final error = msg['error'] as String?;

    final idx = _transfers.indexWhere((t) => t.id == transferId);
    if (idx != -1) {
      _transfers[idx].status = ok ? TransferStatus.completed : TransferStatus.failed;
      if (error != null) _transfers[idx].error = error;
      _notify();
    }
  }

  void _handleFileReject(Map<String, dynamic> msg) {
    final transferId = msg['transferId'] as String?;
    final reason = msg['reason'] as String? ?? 'Recusado';

    final idx = _transfers.indexWhere((t) => t.id == transferId);
    if (idx != -1) {
      _transfers[idx].status = TransferStatus.failed;
      _transfers[idx].error = 'Transferência recusada: $reason';
      _notify();
    }
  }

  void _handleFileCancel(Map<String, dynamic> msg) {
    final transferId = msg['transferId'] as String?;
    final idx = _transfers.indexWhere((t) => t.id == transferId);
    if (idx != -1) {
      _transfers[idx].status = TransferStatus.cancelled;
      _notify();
    }
  }

  Future<void> _handleIncomingFileOffer(Map<String, dynamic> msg) async {
    final transferId = msg['transferId'] as String?;
    final name = msg['name'] as String? ?? 'arquivo';
    final size = msg['size'] as int? ?? 0;
    final mime = msg['mime'] as String? ?? 'application/octet-stream';
    final sha256Expected = msg['sha256'] as String? ?? '';

    if (transferId == null) return;

    final transfer = FileTransfer(
      id: transferId,
      name: name,
      size: size,
      mime: mime,
      sha256: sha256Expected,
      direction: TransferDirection.desktopDownloadToMobile,
      status: TransferStatus.pending,
    );

    _transfers.insert(0, transfer);
    _notify();

    try {
      // 1. Aceita oferta automaticamente
      _ws.sendFileAccept(transferId);

      // 2. Aguarda file_ready com porta e token do Desktop
      final readyMsg = await _ws.messages
          .firstWhere((m) =>
              m['type'] == 'file_ready' && m['transferId'] == transferId)
          .timeout(const Duration(seconds: 15));

      final port = readyMsg['port'] as int? ?? 45680;
      final token = readyMsg['token'] as String;

      // 3. Cria arquivo temporário/Download
      final downloadDir = Directory('/storage/emulated/0/Download/Iriseus');
      if (!await downloadDir.exists()) {
        try {
          await downloadDir.create(recursive: true);
        } catch (_) {}
      }

      final targetPath = (await downloadDir.exists())
          ? '${downloadDir.path}/$name'
          : '${Directory.systemTemp.path}/$name';

      final targetFile = File('$targetPath.part');
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      transfer.status = TransferStatus.transferring;
      _notify();

      // 4. Recebe chunks via TCP
      await FileTransferClient.receiveFile(
        host: '127.0.0.1',
        port: port,
        transferId: transferId,
        tokenBase64: token,
        targetFile: targetFile,
        expectedSize: size,
        onProgress: (bytes, total) {
          transfer.bytesTransferred = bytes;
          _notify();
        },
        isCancelled: () => transfer.status == TransferStatus.cancelled,
      );

      // 5. Valida SHA-256
      final computedHash = await computeSha256(targetFile);
      if (sha256Expected.isNotEmpty && computedHash != sha256Expected) {
        throw Exception('Hash SHA-256 inválido');
      }

      // Renomeia .part para nome final (resolvendo duplicatas)
      var finalFile = File(targetPath);
      int counter = 1;
      while (await finalFile.exists()) {
        final dotIdx = name.lastIndexOf('.');
        if (dotIdx != -1) {
          final base = name.substring(0, dotIdx);
          final ext = name.substring(dotIdx);
          finalFile = File('${finalFile.parent.path}/$base ($counter)$ext');
        } else {
          finalFile = File('${finalFile.parent.path}/$name ($counter)');
        }
        counter++;
      }

      await targetFile.rename(finalFile.path);

      transfer.status = TransferStatus.completed;
      _ws.sendFileComplete(transferId, true);
    } catch (e) {
      if (transfer.status != TransferStatus.cancelled) {
        transfer.status = TransferStatus.failed;
        transfer.error = e.toString();
        _ws.sendFileComplete(transferId, false, e.toString());
      }
    } finally {
      _notify();
    }
  }
}
