enum TransferDirection {
  mobileUploadToPc,
  desktopDownloadToMobile,
}

enum TransferStatus {
  pending,
  transferring,
  completed,
  failed,
  cancelled,
}

class FileTransfer {
  final String id;
  final String name;
  final int size;
  final String mime;
  final String sha256;
  final String? localPath;
  final TransferDirection direction;
  TransferStatus status;
  int bytesTransferred;
  String? error;

  FileTransfer({
    required this.id,
    required this.name,
    required this.size,
    required this.mime,
    required this.sha256,
    this.localPath,
    required this.direction,
    this.status = TransferStatus.pending,
    this.bytesTransferred = 0,
    this.error,
  });

  double get progress => size > 0 ? (bytesTransferred / size).clamp(0.0, 1.0) : 0.0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        'mime': mime,
        'sha256': sha256,
        'direction': direction.index,
        'status': status.index,
        'bytesTransferred': bytesTransferred,
        'error': error,
      };

  factory FileTransfer.fromJson(Map<String, dynamic> json) => FileTransfer(
        id: json['id'] as String,
        name: json['name'] as String,
        size: json['size'] as int,
        mime: json['mime'] as String? ?? 'application/octet-stream',
        sha256: json['sha256'] as String? ?? '',
        direction: TransferDirection.values[json['direction'] as int? ?? 0],
        status: TransferStatus.values[json['status'] as int? ?? 0],
        bytesTransferred: json['bytesTransferred'] as int? ?? 0,
        error: json['error'] as String?,
      );
}
