import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/od_request.dart';

/// Builds PDF, Excel and Word reports from a list of OD requests.
///
/// Whatever is on screen after filtering is what gets exported, and the
/// applied filters are printed on the document so a shared file explains
/// itself.
class ReportExport {
  static final _generatedOn = DateFormat('d MMM yyyy, h:mm a');
  static final _date = DateFormat('dd/MM/yyyy');

  static const _headers = [
    'S.No', 'Reference', 'Student', 'Register No', 'Year', 'Section',
    'Advisor', 'Event', 'Type', 'Date', 'Status', 'Result', 'Prize', 'Project',
  ];

  static List<String> _row(ODRequest r, int i) => [
        '${i + 1}',
        r.referenceNo,
        r.studentName,
        r.registerNumber,
        '${r.year}',
        r.section,
        r.advisorName,
        r.eventName,
        r.eventType,
        _date.format(r.eventDate),
        r.statusDisplay,
        r.resultStatus == 'PENDING' ? '-' : r.resultStatus,
        r.resultPrize ?? '-',
        r.resultProjectName ?? '-',
      ];

  static Future<Directory> _outputDir() async {
    // Downloads is the obvious place to look on Android; falls back to the
    // app's own documents directory where it does not exist.
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<File> _write(String name, List<int> bytes) async {
    final dir = await _outputDir();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/SMVEC_IT_OD_${name}_$stamp.${_ext(name)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _ext(String name) => switch (name) {
        'Report_PDF' => 'pdf',
        'Report_Excel' => 'xlsx',
        _ => 'docx',
      };

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  static Future<File> toPdf({
    required List<ODRequest> rows,
    required String title,
    required Map<String, String> filters,
  }) async {
    final doc = pw.Document();
    final summary = _summarise(rows);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Text(title,
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('SRI MANAKULA VINAYAGAR ENGINEERING COLLEGE',
                    style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('Department of Information Technology',
                    style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
                pw.SizedBox(height: 8),
                pw.Text(title,
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text('Generated on ${_generatedOn.format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
          ),
          if (filters.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                'Filters: ${filters.entries.map((e) => '${e.key}: ${e.value}').join('   |   ')}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          _pdfSummary(summary),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: _headers,
            data: [for (var i = 0; i < rows.length; i++) _row(rows[i], i)],
            headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            headerHeight: 20,
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellHeight: 17,
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: .4)),
            ),
            headerCellDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey50),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    return _write('Report_PDF', await doc.save());
  }

  static pw.Widget _pdfSummary(Map<String, int> s) {
    return pw.Row(
      children: [
        for (final e in s.entries)
          pw.Expanded(
            child: pw.Container(
              margin: const pw.EdgeInsets.only(right: 6),
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: .5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('${e.value}',
                      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  pw.Text(e.key,
                      style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Excel
  // ---------------------------------------------------------------------------

  static Future<File> toExcel({
    required List<ODRequest> rows,
    required String title,
    required Map<String, String> filters,
  }) async {
    final book = xl.Excel.createExcel();
    final sheetName = 'OD Report';
    final sheet = book[sheetName];
    book.setDefaultSheet(sheetName);
    // createExcel() seeds a 'Sheet1'; drop it so the file opens on ours.
    if (book.sheets.keys.contains('Sheet1') && sheetName != 'Sheet1') {
      book.delete('Sheet1');
    }

    var r = 0;
    void put(int col, int row, xl.CellValue value, {xl.CellStyle? style}) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = value;
      if (style != null) cell.cellStyle = style;
    }

    final titleStyle = xl.CellStyle(bold: true, fontSize: 14);
    final headerStyle = xl.CellStyle(
      bold: true,
      fontColorHex: xl.ExcelColor.white,
      backgroundColorHex: xl.ExcelColor.blueGrey800,
    );

    put(0, r, xl.TextCellValue('Department of Information Technology'), style: titleStyle);
    r++;
    put(0, r, xl.TextCellValue(title), style: xl.CellStyle(bold: true));
    r++;
    put(0, r, xl.TextCellValue('Generated on ${_generatedOn.format(DateTime.now())}'));
    r++;
    if (filters.isNotEmpty) {
      put(0, r,
          xl.TextCellValue(filters.entries.map((e) => '${e.key}: ${e.value}').join('  |  ')));
      r++;
    }
    r++;

    for (var c = 0; c < _headers.length; c++) {
      put(c, r, xl.TextCellValue(_headers[c]), style: headerStyle);
    }
    r++;

    for (var i = 0; i < rows.length; i++) {
      final cells = _row(rows[i], i);
      for (var c = 0; c < cells.length; c++) {
        put(c, r, xl.TextCellValue(cells[c]));
      }
      r++;
    }

    // Widths chosen so names and event titles are readable without wrapping.
    const widths = <double>[6, 15, 22, 15, 6, 8, 18, 30, 16, 12, 16, 13, 16, 22];
    for (var c = 0; c < widths.length; c++) {
      sheet.setColumnWidth(c, widths[c]);
    }

    final bytes = book.encode();
    if (bytes == null) throw Exception('Could not build the Excel file.');
    return _write('Report_Excel', bytes);
  }

  // ---------------------------------------------------------------------------
  // Word
  // ---------------------------------------------------------------------------

  /// Builds a real .docx by writing the OOXML parts directly. That avoids
  /// depending on a template file, and Word opens it natively rather than
  /// treating it as recovered HTML.
  static Future<File> toWord({
    required List<ODRequest> rows,
    required String title,
    required Map<String, String> filters,
  }) async {
    final summary = _summarise(rows);
    final buffer = StringBuffer()
      ..write(
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:body>')
      ..write(_p('SRI MANAKULA VINAYAGAR ENGINEERING COLLEGE', bold: true, size: 30))
      ..write(_p('Department of Information Technology', size: 22))
      ..write(_p(title, bold: true, size: 26))
      ..write(_p('Generated on ${_generatedOn.format(DateTime.now())}', size: 18));

    if (filters.isNotEmpty) {
      buffer.write(_p(
        'Filters — ${filters.entries.map((e) => '${e.key}: ${e.value}').join(' | ')}',
        size: 18,
      ));
    }
    buffer.write(_p(
      summary.entries.map((e) => '${e.key}: ${e.value}').join('   •   '),
      size: 18,
      bold: true,
    ));
    buffer.write(_p('', size: 12));

    buffer.write('<w:tbl>'
        '<w:tblPr><w:tblBorders>'
        '<w:top w:val="single" w:sz="4" w:color="999999"/>'
        '<w:left w:val="single" w:sz="4" w:color="999999"/>'
        '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
        '<w:right w:val="single" w:sz="4" w:color="999999"/>'
        '<w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>'
        '<w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>'
        '</w:tblBorders></w:tblPr>');

    buffer.write('<w:tr>');
    for (final h in _headers) {
      buffer.write(_cell(h, bold: true, shade: 'D9E2F3'));
    }
    buffer.write('</w:tr>');

    for (var i = 0; i < rows.length; i++) {
      buffer.write('<w:tr>');
      for (final c in _row(rows[i], i)) {
        buffer.write(_cell(c));
      }
      buffer.write('</w:tr>');
    }
    buffer.write('</w:tbl>');
    buffer.write('<w:sectPr><w:pgSz w:w="16838" w:h="11906" w:orient="landscape"/></w:sectPr>');
    buffer.write('</w:body></w:document>');

    final archive = Archive()
      ..addFile(_file('[Content_Types].xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
          '</Types>'))
      ..addFile(_file('_rels/.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '</Relationships>'))
      ..addFile(_file('word/document.xml', buffer.toString()));

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) throw Exception('Could not build the Word file.');
    return _write('Report_Word', bytes);
  }

  static ArchiveFile _file(String name, String content) {
    final bytes = content.codeUnits;
    return ArchiveFile(name, bytes.length, bytes);
  }

  static String _p(String text, {bool bold = false, int size = 20}) =>
      '<w:p><w:pPr><w:spacing w:after="60"/></w:pPr><w:r><w:rPr>'
      '${bold ? '<w:b/>' : ''}<w:sz w:val="$size"/></w:rPr>'
      '<w:t xml:space="preserve">${_escape(text)}</w:t></w:r></w:p>';

  static String _cell(String text, {bool bold = false, String? shade}) =>
      '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>'
      '${shade != null ? '<w:shd w:val="clear" w:fill="$shade"/>' : ''}</w:tcPr>'
      '<w:p><w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:sz w:val="16"/></w:rPr>'
      '<w:t xml:space="preserve">${_escape(text)}</w:t></w:r></w:p></w:tc>';

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ---------------------------------------------------------------------------

  static Map<String, int> _summarise(List<ODRequest> rows) => {
        'Total ODs': rows.length,
        'Approved': rows.where((r) => r.isApproved).length,
        'Pending': rows.where((r) => !r.isClosed).length,
        'Rejected': rows.where((r) => r.isRejected).length,
        'Participated': rows.where((r) => r.resultStatus == 'PARTICIPATED').length,
        'Won': rows.where((r) => r.won).length,
      };
}
