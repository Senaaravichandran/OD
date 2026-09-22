import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/od_request.dart';
import '../../services/api_client.dart';
import '../../services/upload_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Views one attached certificate or photo.
///
/// The URL is fetched fresh each time and lasts five minutes. Nothing is
/// stored, so access never outlives the viewer's permission to look - which is
/// checked by the server against the OD the file belongs to.
class FileViewer extends StatefulWidget {
  const FileViewer({super.key, required this.file});

  final ODFile file;

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  String? _url;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await UploadService.viewUrl(widget.file.id);
      if (mounted) {
        setState(() {
          _url = url;
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _openExternally() async {
    final url = _url;
    if (url == null) return;
    // A PDF is handed to whatever the phone uses for PDFs; embedding a viewer
    // would mean shipping one, for a file most people open once.
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      await OpenFilex.open(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.file;

    return Scaffold(
      backgroundColor: f.isImage ? Colors.black : AppTheme.surface,
      appBar: AppBar(
        backgroundColor: f.isImage ? Colors.black : Colors.white,
        foregroundColor: f.isImage ? Colors.white : AppTheme.ink,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.kindLabel,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(
              f.fileName,
              style: TextStyle(
                fontSize: 11.5,
                color: f.isImage ? Colors.white70 : AppTheme.muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          if (_url != null)
            IconButton(
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: _openExternally,
              tooltip: 'Open outside the app',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ErrorBanner(message: _error!, onRetry: _load),
                      ],
                    ),
                  ),
                )
              : f.isImage
                  ? InteractiveViewer(
                      maxScale: 5,
                      child: Center(
                        child: Image.network(
                          _url!,
                          fit: BoxFit.contain,
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : const Center(child: CircularProgressIndicator()),
                          errorBuilder: (_, __, ___) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.broken_image_outlined,
                                      size: 48, color: Colors.white54),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Could not load the image.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: _load,
                                    child: const Text('Try again'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.picture_as_pdf_rounded,
                                size: 64, color: AppTheme.danger),
                            const SizedBox(height: 16),
                            Text(
                              f.fileName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(f.sizeLabel,
                                style: const TextStyle(
                                    fontSize: 12.5, color: AppTheme.muted)),
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              onPressed: _openExternally,
                              icon: const Icon(Icons.open_in_new_rounded, size: 18),
                              label: const Text('Open PDF'),
                            ),
                          ],
                        ),
                      ),
                    ),
    );
  }
}
