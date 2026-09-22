import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/od_request.dart';
import '../../services/report_export.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/file_viewer.dart';

/// One OD, in full: who filed it, what the event was, what came of it, who was
/// on the team and what each of them did, with the photographs.
///
/// Reached by tapping a row in Reports. The same record can be exported on its
/// own from here, which is what someone wants when they need to send one
/// student's achievement rather than a department listing.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.request});

  final ODRequest request;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  bool _exporting = false;

  Future<void> _export(String format) async {
    setState(() => _exporting = true);
    try {
      final records = await ReportExport.gather([widget.request]);
      final title = '${widget.request.studentName} - ${widget.request.eventName}';
      final File file = switch (format) {
        'pdf' => await ReportExport.toPdf(records: records, title: title),
        'excel' => await ReportExport.toExcel(records: records, title: title),
        _ => await ReportExport.toWord(records: records, title: title),
      };
      if (!mounted) return;
      setState(() => _exporting = false);
      await showExportResult(context, file, 1);
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        showToast(context, 'Export failed: $e', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final images = r.files.where((f) => f.isImage).toList();
    final documents = r.files.where((f) => !f.isImage).toList();

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            ExportMenu(onSelected: _export, label: 'Export as'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // -- who ------------------------------------------------------------
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.studentName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${r.registerNumber} · Year ${r.year} · Section ${r.section}',
                    style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
                  ),
                  const SizedBox(height: 12),
                  StatusBadge(
                    label: r.hasResult ? r.resultDisplay : 'Result not submitted',
                    color: r.won ? AppTheme.accent : AppTheme.primary,
                    icon: r.won
                        ? Icons.emoji_events_rounded
                        : Icons.workspace_premium_outlined,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // -- the event -------------------------------------------------------
          const SectionHeader(title: 'Event'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                children: [
                  DetailRow(label: 'Event', value: r.eventName),
                  DetailRow(label: 'Type', value: r.eventType),
                  DetailRow(
                    label: r.spansDays ? 'Dates' : 'Date',
                    value: r.spansDays
                        ? '${fmtDate(r.eventDate)} - ${fmtDate(r.eventEndDate)}'
                        : '${fmtDate(r.eventDate)} · ${r.eventDay}',
                  ),
                  DetailRow(
                    label: 'Duration',
                    value: r.dayCount == 1 ? '1 day' : '${r.dayCount} days',
                  ),
                  DetailRow(
                    label: 'Participation',
                    value: r.isTeam ? 'Team of ${r.teamMembers.length}' : 'Individual',
                  ),
                  DetailRow(label: 'Reference', value: r.referenceNo),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          const SectionHeader(title: 'Description'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                r.description,
                style: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // -- the result ------------------------------------------------------
          if (r.hasResult) ...[
            const SectionHeader(title: 'Result'),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  children: [
                    DetailRow(label: 'Outcome', value: r.resultDisplay),
                    DetailRow(
                      label: 'Project',
                      value: r.resultProjectName ?? r.eventName,
                    ),
                    if (r.resultPrize != null && r.resultPrize!.isNotEmpty)
                      DetailRow(label: 'Prize', value: r.resultPrize!),
                    if (r.resultPrizeDetails != null &&
                        r.resultPrizeDetails!.isNotEmpty)
                      DetailRow(label: 'Prize details', value: r.resultPrizeDetails!),
                    if (r.resultDescription != null &&
                        r.resultDescription!.isNotEmpty)
                      DetailRow(label: 'Details', value: r.resultDescription!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // -- who did what ----------------------------------------------------
          if (r.isTeam) ...[
            const SectionHeader(title: 'Team and contribution'),
            if (r.team.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    r.teamMembers.join(', '),
                    style: const TextStyle(fontSize: 13.5, height: 1.5),
                  ),
                ),
              )
            else
              for (final m in r.team)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.person_outline_rounded,
                                size: 17, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m.name,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (m.registerNumber != null &&
                                m.registerNumber!.isNotEmpty)
                              Text(
                                m.registerNumber!,
                                style: const TextStyle(
                                    fontSize: 11.5, color: AppTheme.muted),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          m.hasContribution
                              ? m.contribution!
                              : 'Contribution not recorded yet.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: m.hasContribution
                                ? AppTheme.ink
                                : AppTheme.muted,
                            fontStyle: m.hasContribution
                                ? FontStyle.normal
                                : FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 14),
          ],

          // -- the photographs -------------------------------------------------
          if (images.isNotEmpty) ...[
            SectionHeader(
              title: 'Photographs',
              trailing: Text(
                '${images.length}',
                style: const TextStyle(fontSize: 12.5, color: AppTheme.muted),
              ),
            ),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => _PhotoTile(file: images[i]),
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (documents.isNotEmpty) ...[
            const SectionHeader(title: 'Documents'),
            for (final f in documents)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.picture_as_pdf_outlined,
                      size: 20, color: AppTheme.primary),
                  title: Text(f.kindLabel,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${f.fileName} · ${f.sizeLabel}',
                      style: const TextStyle(fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FileViewer(file: f)),
                  ),
                ),
              ),
          ],

          if (r.files.isEmpty)
            const EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'No attachments',
              message: 'Nothing has been attached to this OD yet.',
            ),
        ],
      ),
    );
  }
}

/// A photograph in the strip. Tapping opens the full viewer, which fetches its
/// own signed URL - nothing here holds a lasting link to the file.
class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.file});

  final ODFile file;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => FileViewer(file: file)),
      ),
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              switch (file.kind) {
                'WINNING_PHOTO' => Icons.emoji_events_outlined,
                'CERTIFICATE' => Icons.workspace_premium_outlined,
                _ => Icons.photo_outlined,
              },
              size: 30,
              color: AppTheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              file.kindLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              file.sizeLabel,
              style: const TextStyle(fontSize: 10.5, color: AppTheme.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "Export as" menu, shared by the reports list and this screen so both
/// offer the same three formats in the same order.
class ExportMenu extends StatelessWidget {
  const ExportMenu({
    super.key,
    required this.onSelected,
    this.label,
    this.onPrimary = false,
  });

  final ValueChanged<String> onSelected;
  final String? label;

  /// Set when the menu sits on the brand colour rather than on white.
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      position: PopupMenuPosition.under,
      tooltip: 'Export as',
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'pdf',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.picture_as_pdf_outlined, size: 20),
            title: Text('PDF'),
            subtitle: Text('With photographs'),
          ),
        ),
        PopupMenuItem(
          value: 'word',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.description_outlined, size: 20),
            title: Text('Word'),
            subtitle: Text('With photographs'),
          ),
        ),
        PopupMenuItem(
          value: 'excel',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.table_chart_outlined, size: 20),
            title: Text('Excel'),
            subtitle: Text('Photographs listed by name'),
          ),
        ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: onPrimary ? 12 : 14,
          vertical: onPrimary ? 8 : 10,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onPrimary) ...[
              const Icon(Icons.download_rounded, size: 17, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label ?? 'Export',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: onPrimary ? Colors.white : AppTheme.primary,
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 20,
              color: onPrimary ? Colors.white : AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// What to do with a file that has just been written. Shared so the list and
/// the single-record export behave identically.
Future<void> showExportResult(BuildContext context, File file, int count) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Icon(Icons.task_alt_rounded, size: 40, color: AppTheme.success),
          const SizedBox(height: 12),
          Text(
            'Report saved',
            style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count record${count == 1 ? '' : 's'}\n'
            '${file.path.split(Platform.pathSeparator).last}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: AppTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Share.shareXFiles([XFile(file.path)]);
                  },
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    OpenFilex.open(file.path);
                  },
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
