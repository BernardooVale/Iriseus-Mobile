import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/file_transfer_manager.dart';
import '../models/file_transfer.dart';

class TransfersScreen extends StatelessWidget {
  final FileTransferManager manager;
  final String pcIp;

  const TransfersScreen({
    super.key,
    required this.manager,
    required this.pcIp,
  });

  Future<void> _pickAndSendFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    for (final picked in result.files) {
      if (picked.path != null) {
        final file = File(picked.path!);
        manager.sendFile(file: file, host: pcIp);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transferências de Arquivos'),
      ),
      body: StreamBuilder<List<FileTransfer>>(
        stream: manager.transfersStream,
        initialData: manager.transfers,
        builder: (context, snapshot) {
          final transfers = snapshot.data ?? [];

          if (transfers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.drive_folder_upload_outlined,
                    size: 64,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nenhuma transferência ainda',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _pickAndSendFile(context),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Selecionar arquivos para enviar'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: transfers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final t = transfers[index];
              return _TransferCard(
                transfer: t,
                formatBytes: _formatBytes,
                onCancel: () => manager.cancelTransfer(t.id),
              );
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(
            onPressed: () => _pickAndSendFile(context),
            icon: const Icon(Icons.upload_file),
            label: const Text('Enviar novo arquivo'),
          ),
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final FileTransfer transfer;
  final String Function(int) formatBytes;
  final VoidCallback onCancel;

  const _TransferCard({
    required this.transfer,
    required this.formatBytes,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusIcon = switch (transfer.status) {
      TransferStatus.completed =>
        const Icon(Icons.check_circle, color: Colors.green),
      TransferStatus.failed =>
        const Icon(Icons.error, color: Colors.red),
      TransferStatus.cancelled =>
        const Icon(Icons.cancel, color: Colors.grey),
      TransferStatus.transferring =>
        const Icon(Icons.sync, color: Colors.blue),
      TransferStatus.pending =>
        const Icon(Icons.hourglass_empty, color: Colors.orange),
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                statusIcon,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    transfer.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (transfer.status == TransferStatus.transferring ||
                    transfer.status == TransferStatus.pending)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: onCancel,
                    tooltip: 'Cancelar',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (transfer.status == TransferStatus.transferring) ...[
              LinearProgressIndicator(value: transfer.progress),
              const SizedBox(height: 6),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatBytes(transfer.bytesTransferred)} / ${formatBytes(transfer.size)}',
                  style: theme.textTheme.bodySmall,
                ),
                Text(
                  switch (transfer.status) {
                    TransferStatus.completed => 'Concluído',
                    TransferStatus.failed => transfer.error ?? 'Falhou',
                    TransferStatus.cancelled => 'Cancelado',
                    TransferStatus.transferring =>
                      '${(transfer.progress * 100).toInt()}%',
                    TransferStatus.pending => 'Aguardando PC...',
                  },
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: transfer.status == TransferStatus.failed
                        ? Colors.red
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
