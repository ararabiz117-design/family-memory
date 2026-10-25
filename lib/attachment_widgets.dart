import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'attachment_image_processor.dart';
import 'attachment_models.dart';
import 'repository.dart';
import 'glass_ui.dart';

class AttachmentSection extends StatefulWidget {
  const AttachmentSection({
    super.key,
    required this.repository,
    required this.targetType,
    required this.targetId,
  });

  final FamilyRepository repository;
  final AttachmentTargetType targetType;
  final String targetId;

  @override
  State<AttachmentSection> createState() => _AttachmentSectionState();
}

class _AttachmentSectionState extends State<AttachmentSection> {
  bool busy = false;

  Future<void> _pickAndUpload() async {
    final selected = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (selected == null || !mounted) return;
    setState(() => busy = true);
    try {
      final bytes = await selected.readAsBytes();
      await widget.repository.addImageAttachment(
        targetType: widget.targetType,
        targetId: widget.targetId,
        sourceBytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('位置情報などを除去して写真を追加しました。')));
    } on AttachmentImageException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写真を追加できませんでした。通信状態を確認してください。')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _delete(FamilyAttachment attachment) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('写真を削除しますか？'),
            content: const Text('家族の画面から非表示になります。安全な保管期間の後、画像本体も削除されます。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('削除する'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.repository.softDeleteAttachment(attachment);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('写真を削除できませんでした。最新状態で再試行してください。')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachments = widget.repository.attachmentsFor(
      widget.targetType,
      widget.targetId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
          child: Text(
            '写真（家族限定）',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        if (attachments.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.repository.isDemo ? '写真は家族限定版で利用できます。' : '写真はまだありません。',
              ),
            ),
          ),
        for (final attachment in attachments)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PrivateAttachmentCard(
              key: ValueKey(attachment.id),
              repository: widget.repository,
              attachment: attachment,
              canDelete: !widget.repository.viewerMode && !busy,
              onDelete: () => _delete(attachment),
            ),
          ),
        const SizedBox(height: 10),
        if (!widget.repository.viewerMode)
          OutlinedButton.icon(
            onPressed: widget.repository.isDemo || busy ? null : _pickAndUpload,
            icon: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: Text(busy ? '安全処理して追加中…' : 'JPG・PNG写真を追加'),
          ),
        if (!widget.repository.isDemo)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '5MiB・4096px以下。長辺1600px・適正画質へ自動調整し、位置情報などを除去してから保存します。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _PrivateAttachmentCard extends StatefulWidget {
  const _PrivateAttachmentCard({
    super.key,
    required this.repository,
    required this.attachment,
    required this.canDelete,
    required this.onDelete,
  });

  final FamilyRepository repository;
  final FamilyAttachment attachment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  State<_PrivateAttachmentCard> createState() => _PrivateAttachmentCardState();
}

class _PrivateAttachmentCardState extends State<_PrivateAttachmentCard> {
  late Future<String> signedUrl = _loadUrl();

  Future<String> _loadUrl() =>
      widget.repository.createAttachmentSignedUrl(widget.attachment.id);

  @override
  void didUpdateWidget(covariant _PrivateAttachmentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.id != widget.attachment.id ||
        oldWidget.attachment.version != widget.attachment.version) {
      signedUrl = _loadUrl();
    }
  }

  void _retry() => setState(() => signedUrl = _loadUrl());

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 10,
          child: FutureBuilder<String>(
            future: signedUrl,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return Image.network(
                  snapshot.data!,
                  fit: BoxFit.cover,
                  semanticLabel: widget.attachment.caption.isEmpty
                      ? '家族限定の添付写真'
                      : widget.attachment.caption,
                  errorBuilder: (_, _, _) => _ImageLoadError(onRetry: _retry),
                );
              }
              if (snapshot.hasError) return _ImageLoadError(onRetry: _retry);
              return const GlassSkeleton(height: double.infinity);
            },
          ),
        ),
        if (widget.attachment.caption.isNotEmpty || widget.canDelete)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.attachment.caption.isEmpty
                        ? '${widget.attachment.width}×${widget.attachment.height}px'
                        : widget.attachment.caption,
                  ),
                ),
                if (widget.canDelete)
                  IconButton(
                    tooltip: '写真を削除',
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ImageLoadError extends StatelessWidget {
  const _ImageLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('写真を再読み込み'),
    ),
  );
}
