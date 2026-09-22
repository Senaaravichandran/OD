import 'dart:io';

import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../models/od_request.dart';
import '../../services/od_service.dart';
import '../../services/report_export.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../shared/request_tile.dart';
import 'report_detail_screen.dart';

enum ReportScope { student, advisor, hod }

/// Reports, with search, filters, and export to PDF, Excel or Word.
///
/// The advisor only ever sees their own classes and the HOD sees the
/// department, because the data behind this was already scoped by the server.
/// Exporting writes whatever is on screen after filtering, and prints the
/// applied filters onto the document.
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key, required this.scope});

  final ReportScope scope;

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _od = ODService();
  final _search = TextEditingController();

  String _query = '';
  int? _year;
  String? _section;
  String? _eventType;
  String? _status;
  String? _result;
  DateTimeRange? _range;
  bool _exporting = false;
  String _exportStep = '';

  @override
  void initState() {
    super.initState();
    _od.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _od.removeListener(_onUpdate);
    _search.dispose();
    super.dispose();
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  bool get _hasFilters =>
      _year != null ||
      _section != null ||
      _eventType != null ||
      _status != null ||
      _result != null ||
      _range != null ||
      _query.isNotEmpty;

  Map<String, String> get _appliedFilters => {
        if (_year != null) 'Year': '$_year',
        if (_section != null) 'Section': _section!,
        if (_eventType != null) 'Event type': _eventType!,
        if (_status != null) 'Status': _status!,
        if (_result != null) 'Result': _result!,
        if (_range != null)
          'Date range': '${fmtDate(_range!.start)} - ${fmtDate(_range!.end)}',
        if (_query.isNotEmpty) 'Search': _query,
      };

  List<ODRequest> get _filtered {
    var list = _od.allRequests;

    if (_year != null) list = list.where((r) => r.year == _year).toList();
    if (_section != null) list = list.where((r) => r.section == _section).toList();
    if (_eventType != null) list = list.where((r) => r.eventType == _eventType).toList();
    if (_status != null) {
      list = switch (_status) {
        'Approved' => list.where((r) => r.isApproved).toList(),
        'Rejected' => list.where((r) => r.isRejected).toList(),
        'Pending' => list.where((r) => !r.isClosed).toList(),
        _ => list,
      };
    }
    if (_result != null) {
      list = switch (_result) {
        'Won' => list.where((r) => r.won).toList(),
        'Participated' => list.where((r) => r.resultStatus == 'PARTICIPATED').toList(),
        'No result' => list.where((r) => !r.hasResult).toList(),
        _ => list,
      };
    }
    if (_range != null) {
      list = list
          .where((r) =>
              !r.eventDate.isBefore(_range!.start) &&
              !r.eventDate.isAfter(_range!.end.add(const Duration(days: 1))))
          .toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((r) {
        return r.studentName.toLowerCase().contains(q) ||
            r.registerNumber.toLowerCase().contains(q) ||
            r.eventName.toLowerCase().contains(q) ||
            (r.resultProjectName ?? '').toLowerCase().contains(q) ||
            (r.resultPrize ?? '').toLowerCase().contains(q) ||
            r.advisorName.toLowerCase().contains(q) ||
            r.eventType.toLowerCase().contains(q);
      }).toList();
    }
    return list;
  }

  void _clearFilters() {
    setState(() {
      _year = null;
      _section = null;
      _eventType = null;
      _status = null;
      _result = null;
      _range = null;
      _query = '';
      _search.clear();
    });
  }

  /// Exports what is on screen. With nothing filtered that is everything the
  /// caller is allowed to see, which the server already decided.
  Future<void> _export(String format) async {
    final rows = _filtered;
    if (rows.isEmpty) {
      showToast(
        context,
        _hasFilters ? 'Nothing matches these filters.' : 'There is nothing to export yet.',
        error: true,
      );
      return;
    }
    setState(() {
      _exporting = true;
      _exportStep = 'Collecting photographs…';
    });
    try {
      // Each photograph is a signed-URL fetch, so this is the slow part; say
      // where it has got to rather than showing a spinner for a minute.
      final records = await ReportExport.gather(
        rows,
        // Excel cannot embed images, so there is no point downloading them.
        withPhotos: format != 'excel',
        onProgress: (done, total) {
          if (mounted && total > 1) {
            setState(() => _exportStep = 'Preparing $done of $total…');
          }
        },
      );
      if (!mounted) return;
      setState(() => _exportStep = 'Building the document…');

      final File file = switch (format) {
        'pdf' => await ReportExport.toPdf(
            records: records, title: _title, filters: _appliedFilters),
        'excel' => await ReportExport.toExcel(
            records: records, title: _title, filters: _appliedFilters),
        _ => await ReportExport.toWord(
            records: records, title: _title, filters: _appliedFilters),
      };
      if (!mounted) return;
      setState(() {
        _exporting = false;
        _exportStep = '';
      });
      await showExportResult(context, file, rows.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          _exporting = false;
          _exportStep = '';
        });
        showToast(context, 'Export failed: $e', error: true);
      }
    }
  }

  String get _title => switch (widget.scope) {
        ReportScope.hod => 'Department OD Report',
        ReportScope.advisor => 'Class OD Report',
        ReportScope.student => 'My OD Report',
      };

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final all = _od.allRequests;
    final years = all.map((r) => r.year).toSet().toList()..sort();
    final sections = all.map((r) => r.section).toSet().toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.scope == ReportScope.student
                ? 'Search event, project, prize'
                : 'Search student, register no., event, project, prize',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              // A student only ever sees their own class, so offering to
              // filter by it would be a control that does nothing.
              if (widget.scope != ReportScope.student) ...[
                _dropdown<int>('Year', _year, years,
                    (v) => setState(() => _year = v), (v) => 'Year $v'),
                _dropdown<String>('Section', _section, sections,
                    (v) => setState(() => _section = v), (v) => 'Section $v'),
              ],
              _dropdown<String>('Event', _eventType, AppConfig.eventTypes,
                  (v) => setState(() => _eventType = v), (v) => v),
              _dropdown<String>('Status', _status,
                  const ['Approved', 'Pending', 'Rejected'],
                  (v) => setState(() => _status = v), (v) => v),
              _dropdown<String>('Result', _result,
                  const ['Won', 'Participated', 'No result'],
                  (v) => setState(() => _result = v), (v) => v),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 15),
                  label: Text(
                    _range == null
                        ? 'Date range'
                        : '${fmtDate(_range!.start)} – ${fmtDate(_range!.end)}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: _range,
                    );
                    if (picked != null) setState(() => _range = picked);
                  },
                ),
              ),
              if (_hasFilters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.clear_all_rounded, size: 15),
                    label: const Text('Clear', style: TextStyle(fontSize: 12.5)),
                    onPressed: _clearFilters,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${rows.length} record${rows.length == 1 ? '' : 's'}'
                  '${_hasFilters ? ' (filtered)' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              if (_exporting)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_exportStep.isNotEmpty) ...[
                      Text(
                        _exportStep,
                        style: const TextStyle(fontSize: 12, color: AppTheme.muted),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                )
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: ExportMenu(
                    onSelected: _export,
                    label: _hasFilters ? 'Export filtered' : 'Export all',
                    onPrimary: true,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(
                  icon: Icons.analytics_outlined,
                  title: _hasFilters ? 'Nothing matches' : 'No data yet',
                  message: _hasFilters
                      ? 'Try widening or clearing the filters.'
                      : widget.scope == ReportScope.student
                          ? 'Your reports appear here once you have raised an OD.'
                          : 'Reports fill in as OD requests are raised.',
                  action: _hasFilters
                      ? TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear filters'),
                        )
                      : null,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: rows.length,
                  itemBuilder: (_, i) => RequestTile(
                    request: rows[i],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ReportDetailScreen(request: rows[i]),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _dropdown<T>(
    String label,
    T? value,
    List<T> options,
    void Function(T?) onChanged,
    String Function(T) display,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<T?>(
        onSelected: onChanged,
        position: PopupMenuPosition.under,
        itemBuilder: (_) => [
          PopupMenuItem<T?>(value: null, child: Text('All ${label.toLowerCase()}s')),
          for (final o in options)
            PopupMenuItem<T?>(value: o, child: Text(display(o))),
        ],
        child: Chip(
          label: Text(
            value == null ? label : display(value),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: value == null ? AppTheme.muted : AppTheme.primary,
            ),
          ),
          avatar: Icon(
            Icons.arrow_drop_down_rounded,
            size: 18,
            color: value == null ? AppTheme.muted : AppTheme.primary,
          ),
          backgroundColor:
              value == null ? Colors.white : AppTheme.tint(AppTheme.primary),
        ),
      ),
    );
  }
}
