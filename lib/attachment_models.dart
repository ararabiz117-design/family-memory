enum AttachmentTargetType {
  person('people'),
  place('places'),
  event('events');

  const AttachmentTargetType(this.storageSegment);

  final String storageSegment;
}

class FamilyAttachment {
  const FamilyAttachment({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.storagePath,
    required this.mimeType,
    required this.byteSize,
    required this.width,
    required this.height,
    required this.sha256,
    required this.version,
    this.caption = '',
  });

  final String id;
  final AttachmentTargetType targetType;
  final String targetId;
  final String storagePath;
  final String mimeType;
  final int byteSize;
  final int width;
  final int height;
  final String sha256;
  final int version;
  final String caption;
}
