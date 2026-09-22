import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

import '../../models/od_request.dart';
import '../../services/api_client.dart';
import '../../services/od_service.dart';
import '../../services/upload_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/file_viewer.dart';

/// Attach a certificate, a prize photo, or supporting documents to an
/// approved OD.
class AttachmentsSheet extends StatefulWidget {
  const AttachmentsSheet({super.key, required this.request});

  final ODRequest request;

  @override
  State<AttachmentsSheet> createState() => _AttachmentsSheetState();
}

class _AttachmentsSheetState extends State<AttachmentsSheet> {
  final _od = ODService();
  late List<ODFile> _files;
  String? _busyKind;
  String? _error;

  @override
  void initState() {
    super.initState();
    _files = List.of(widget.request.files);
  }

  Future<void> _add(String kind) async {
    final source = await _chooseSource(kind);
    if (source == null) return;

    setState(() {
      _busyKind = kind;
      _error = null;
    });
    try {
      ODFile? file;
      if (source == _Source.document) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
        );
        final path = picked?.files.single.path;
        if (path == null) {
          setState(() => _busyKind = null);
          return;
        }
        final name = picked!.files.single.name;
        file = await UploadService.uploadFile(
          requestId: widget.request.id,
          kind: kind,
          file: File(path),
          mimeType: _mimeFor(name),
          fileName: name,
        );
      } else {
        file = await UploadService.pickAndUploadImage(
          requestId: widget.request.id,
          kind: kind,
          source: source == _Source.camera ? ImageSource.camera : ImageSource.gallery,
        );
      }

      if (file != null && mounted) {
        setState(() => _files = [..._files, file!]);
        await _od.refresh();
        if (mounted) showToast(context, 'Uploaded.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busyKind = null);
    }
  }

  Future<_Source?> _chooseSource(String kind) => showModalBottomSheet<_Source>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Add ${_label(kind).toLowerCase()}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, _Source.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(ctx, _Source.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Choose a PDF or image file'),
                onTap: () => Navigator.pop(ctx, _Source.document),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

  Future<void> _remove(ODFile file) async {
    final ok = await confirm(
      context,
      title: 'Remove this file?',
      message: '${file.fileName} will be deleted permanently.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    try {
      await UploadService.delete(file.id);
      if (mounted) {
        setState(() => _files = _files.where((f) => f.id != file.id).toList());
        await _od.refresh();
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message, error: true);
    }
  }

  static String _label(String kind) => switch (kind) {
        'CERTIFICATE' => 'Certificate',
        'WINNING_PHOTO' => 'Winning photo',
        'EVENT_PHOTO' => 'Event photo',
        _ => 'Supporting document',
      };

  static String _mimeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    // A prize photo only makes sense for a win.
    final kinds = [
      'CERTIFICATE',
      if (widget.request.won) 'WINNING_PHOTO',
      'EVENT_PHOTO',
      'SUPPORTING_DOCUMENT',
    ];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Attachments',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(
                        widget.request.eventName,
                        style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              children: [
                if (_error != null) ErrorBanner(message: _error!),

                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.muted),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'Photos are compressed on your phone before upload. '
                          'JPEG, PNG, WebP or PDF, up to 10 MB.',
                          style: TextStyle(fontSize: 11.5, color: AppTheme.muted, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                for (final kind in kinds) ...[
                  _KindSection(
                    label: _label(kind),
                    files: _files.where((f) => f.kind == kind).toList(),
                    busy: _busyKind == kind,
                    onAdd: () => _add(kind),
                    onOpen: (f) => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => FileViewer(file: f)),
                    ),
                    onRemove: _remove,
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _Source { camera, gallery, document }

class _KindSection extends StatelessWidget {
  const _KindSection({
    required this.label,
    required this.files,
    required this.busy,
    required this.onAdd,
    required this.onOpen,
    required this.onRemove,
  });

  final String label;
  final List<ODFile> files;
  final bool busy;
  final VoidCallback onAdd;
  final void Function(ODFile) onOpen;
  final void Function(ODFile) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
          ],
        ),
        if (files.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'None attached',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          )
        else
          for (final f in files)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                dense: true,
                leading: Icon(
                  f.isImage ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
                  size: 20,
                  color: AppTheme.primary,
                ),
                title: Text(
                  f.fileName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(f.sizeLabel, style: const TextStyle(fontSize: 11.5)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined, size: 19),
                      onPressed: () => onOpen(f),
                      tooltip: 'View',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                      color: AppTheme.danger,
                      onPressed: () => onRemove(f),
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
