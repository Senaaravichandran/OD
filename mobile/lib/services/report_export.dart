import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/od_request.dart';
import 'upload_service.dart';

/// One record ready to print: the request, plus whatever photos were fetched
/// for it.
///
/// The photos live in a private bucket, so they have to be downloaded through
/// a signed URL before they can go into a document. That is a network round
/// trip per image, which is why gathering is a separate, reportable step
/// rather than something buried inside the PDF builder.
class ReportRecord {
  ReportRecord(this.request, this.photos);

  final ODRequest request;

  /// kind -> image bytes. Only the kinds that are images, and only those that
  /// downloaded successfully - a report is still worth having without them.
  final Map<String, Uint8List> photos;

  Uint8List? get eventPhoto =>
      photos['EVENT_PHOTO'] ?? photos['WINNING_PHOTO'] ?? photos['CERTIFICATE'];
}

/// Builds PDF, Excel and Word reports from OD requests.
///
/// The department asked for the record of what students achieved, not the
/// paperwork trail: who they are, what they entered, what came of it, who was
/// on the team and what each of them did, with the photographs. Approval
/// remarks and workflow states are deliberately left out - those belong to the
/// request screens, not to a record of achievement.
class ReportExport {
  static final _generatedOn = DateFormat('d MMM yyyy, h:mm a');
  static final _date = DateFormat('dd MMM yyyy');

  /// Downloading every photo in a department-wide export would take minutes
  /// and tens of megabytes. Past this many, the documents carry the details
  /// and name the photos instead.
  static const int photoBudget = 60;

  // ---------------------------------------------------------------------------
  // Gathering
  // ---------------------------------------------------------------------------

  /// Fetches the photos for [rows], newest first, up to [photoBudget].
  ///
  /// [onProgress] is called as each record is finished so a long export can
  /// show where it has got to. A photo that will not download is skipped
  /// rather than failing the export.
  static Future<List<ReportRecord>> gather(
    List<ODRequest> rows, {
    void Function(int done, int total)? onProgress,
    bool withPhotos = true,
  }) async {
    final records = <ReportRecord>[];
    var budget = withPhotos ? photoBudget : 0;

    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final photos = <String, Uint8List>{};

      if (budget > 0) {
        // One of each kind is enough for a report; a student may have
        // attached several.
        for (final kind in const ['EVENT_PHOTO', 'WINNING_PHOTO', 'CERTIFICATE']) {
          if (budget <= 0) break;
          ODFile? file;
          for (final f in r.files) {
            if (f.kind == kind && f.isImage) {
              file = f;
              break;
            }
          }
          if (file == null) continue;
          final bytes = await _download(file.id);
          if (bytes != null) {
            photos[kind] = bytes;
            budget--;
          }
        }
      }

      records.add(ReportRecord(r, photos));
      onProgress?.call(i + 1, rows.length);
    }
    return records;
  }

  static Future<Uint8List?> _download(String fileId) async {
    try {
      final url = await UploadService.viewUrl(fileId);
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      return res.bodyBytes;
    } catch (_) {
      // A missing photo is not a reason to lose the whole report.
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Shared field extraction
  // ---------------------------------------------------------------------------

  static String dateRange(ODRequest r) => r.spansDays
      ? '${_date.format(r.eventDate)} - ${_date.format(r.eventEndDate)}  (${r.dayCount} days)'
      : '${_date.format(r.eventDate)}  (1 day)';

  static String resultLine(ODRequest r) => switch (r.resultStatus) {
        'WON' => 'Won${r.resultPrize == null || r.resultPrize!.isEmpty ? '' : ' - ${r.resultPrize}'}',
        'PARTICIPATED' => 'Participated',
        _ => 'Result not submitted',
      };

  static String teamLine(ODRequest r) {
    if (!r.isTeam) return 'Individual entry';
    if (r.team.isEmpty) return r.teamMembers.join(', ');
    return r.team.map((m) => m.name).join(', ');
  }

  static String photoLine(ODRequest r) {
    if (r.files.isEmpty) return '-';
    return r.files.map((f) => '${f.kindLabel}: ${f.fileName}').join('; ');
  }

  // ---------------------------------------------------------------------------
  // Files
  // ---------------------------------------------------------------------------

  static Future<Directory> _outputDir() async {
    // Downloads is the obvious place to look on Android; falls back to the
    // app's own documents directory where it does not exist.
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download');
      if (await dir.exists()) return dir;
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<File> _write(String name, String ext, List<int> bytes) async {
    final dir = await _outputDir();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/SMVEC_IT_OD_${name}_$stamp.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  // ---------------------------------------------------------------------------
  // PDF
  // ---------------------------------------------------------------------------

  static Future<File> toPdf({
    required List<ReportRecord> records,
    required String title,
    Map<String, String> filters = const {},
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 30),
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
          pw.SizedBox(height: 4),
          pw.Text(
            '${records.length} record${records.length == 1 ? '' : 's'}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 10),
          for (var i = 0; i < records.length; i++) _pdfRecord(records[i], i + 1),
        ],
      ),
    );

    return _write('Report', 'pdf', await doc.save());
  }

  static pw.Widget _pdfRecord(ReportRecord rec, int n) {
    final r = rec.request;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 14),
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: .6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  '$n.  ${r.studentName}',
                  style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.Text(
                r.registerNumber,
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
            ],
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            'Year ${r.year} · Section ${r.section}',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 7),
          _pdfField('Event', '${r.eventName}  (${r.eventType})'),
          _pdfField('Dates', dateRange(r)),
          _pdfField('Project', r.resultProjectName ?? r.eventName),
          _pdfField('Result', resultLine(r)),
          if (r.resultPrizeDetails != null && r.resultPrizeDetails!.isNotEmpty)
            _pdfField('Prize details', r.resultPrizeDetails!),
          _pdfField(
            'Description',
            (r.resultDescription != null && r.resultDescription!.isNotEmpty)
                ? r.resultDescription!
                : r.description,
          ),
          _pdfField('Team', teamLine(r)),
          if (r.isTeam && r.team.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text('Contribution',
                style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.TableHelper.fromTextArray(
              headers: const ['Member', 'What they contributed'],
              data: [
                for (final m in r.team)
                  [m.name, m.contribution ?? 'Not recorded'],
              ],
              headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(2.4)},
              border: pw.TableBorder.all(color: PdfColors.grey300, width: .4),
            ),
          ],
          if (rec.photos.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final entry in rec.photos.entries)
                  pw.Container(
                    margin: const pw.EdgeInsets.only(right: 8),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 120,
                          height: 90,
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.grey400, width: .5),
                          ),
                          child: pw.Image(
                            pw.MemoryImage(entry.value),
                            fit: pw.BoxFit.cover,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          _photoLabel(entry.key),
                          style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ] else if (r.files.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Attachments: ${photoLine(r)}',
                style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
          ],
        ],
      ),
    );
  }

  static pw.Widget _pdfField(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 70,
              child: pw.Text(
                label,
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
              ),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
      );

  static String _photoLabel(String kind) => switch (kind) {
        'EVENT_PHOTO' => 'Event photo',
        'WINNING_PHOTO' => 'Prize photo',
        'CERTIFICATE' => 'Certificate',
        _ => 'Attachment',
      };

  // ---------------------------------------------------------------------------
  // Excel
  // ---------------------------------------------------------------------------

  static const _headers = [
    'S.No', 'Student', 'Register No', 'Year', 'Section', 'Event', 'Dates',
    'Days', 'Project', 'Result', 'Prize', 'Description', 'Team members',
    'Contribution', 'Photos',
  ];

  static List<String> _row(ODRequest r, int i) => [
        '${i + 1}',
        r.studentName,
        r.registerNumber,
        '${r.year}',
        r.section,
        r.eventName,
        r.spansDays
            ? '${_date.format(r.eventDate)} - ${_date.format(r.eventEndDate)}'
            : _date.format(r.eventDate),
        '${r.dayCount}',
        r.resultProjectName ?? r.eventName,
        resultLine(r),
        r.resultPrize ?? '-',
        (r.resultDescription != null && r.resultDescription!.isNotEmpty)
            ? r.resultDescription!
            : r.description,
        teamLine(r),
        r.isTeam && r.team.isNotEmpty
            ? r.team
                .map((m) => '${m.name}: ${m.contribution ?? 'not recorded'}')
                .join(' | ')
            : '-',
        photoLine(r),
      ];

  static Future<File> toExcel({
    required List<ReportRecord> records,
    required String title,
    Map<String, String> filters = const {},
  }) async {
    final book = xl.Excel.createExcel();
    const sheetName = 'OD Report';
    final sheet = book[sheetName];
    book.setDefaultSheet(sheetName);
    // createExcel() seeds a 'Sheet1'; drop it so the file opens on ours.
    if (book.sheets.keys.contains('Sheet1')) book.delete('Sheet1');

    var r = 0;
    void put(int col, int row, String value, {xl.CellStyle? style}) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = xl.TextCellValue(value);
      if (style != null) cell.cellStyle = style;
    }

    final titleStyle = xl.CellStyle(bold: true, fontSize: 14);
    final headerStyle = xl.CellStyle(
      bold: true,
      fontColorHex: xl.ExcelColor.white,
      backgroundColorHex: xl.ExcelColor.blueGrey800,
    );

    put(0, r++, 'Department of Information Technology', style: titleStyle);
    put(0, r++, title, style: xl.CellStyle(bold: true));
    put(0, r++, 'Generated on ${_generatedOn.format(DateTime.now())}');
    if (filters.isNotEmpty) {
      put(0, r++, filters.entries.map((e) => '${e.key}: ${e.value}').join('  |  '));
    }
    // Spreadsheets cannot carry the photographs; say where they are instead of
    // leaving someone to wonder.
    put(0, r++, 'Photographs are listed by name. The PDF and Word exports embed them.');
    r++;

    for (var c = 0; c < _headers.length; c++) {
      put(c, r, _headers[c], style: headerStyle);
    }
    r++;

    for (var i = 0; i < records.length; i++) {
      final cells = _row(records[i].request, i);
      for (var c = 0; c < cells.length; c++) {
        put(c, r, cells[c]);
      }
      r++;
    }

    const widths = <double>[
      6, 22, 15, 6, 8, 28, 24, 6, 24, 18, 16, 40, 28, 46, 30,
    ];
    for (var c = 0; c < widths.length; c++) {
      sheet.setColumnWidth(c, widths[c]);
    }

    final bytes = book.encode();
    if (bytes == null) throw Exception('Could not build the Excel file.');
    return _write('Report', 'xlsx', bytes);
  }

  // ---------------------------------------------------------------------------
  // Word
  // ---------------------------------------------------------------------------

  /// Builds a real .docx by writing the OOXML parts directly, photographs
  /// included. That avoids depending on a template file, and Word opens it
  /// natively rather than treating it as recovered HTML.
  static Future<File> toWord({
    required List<ReportRecord> records,
    required String title,
    Map<String, String> filters = const {},
  }) async {
    // Images become numbered parts under word/media, each with its own
    // relationship id that the body refers to.
    final media = <_WordImage>[];

    Future<String?> addImage(Uint8List bytes, String ext) async {
      final size = await _imageSize(bytes);
      if (size == null) return null;
      final id = media.length + 2; // rId1 is the document itself
      media.add(_WordImage('image$id.$ext', bytes, ext));
      return 'rId$id';
    }

    final body = StringBuffer()
      ..write(_p('SRI MANAKULA VINAYAGAR ENGINEERING COLLEGE', bold: true, size: 30))
      ..write(_p('Department of Information Technology', size: 22))
      ..write(_p(title, bold: true, size: 26))
      ..write(_p('Generated on ${_generatedOn.format(DateTime.now())}', size: 18));

    if (filters.isNotEmpty) {
      body.write(_p(
        'Filters - ${filters.entries.map((e) => '${e.key}: ${e.value}').join(' | ')}',
        size: 18,
      ));
    }
    body.write(_p(
      '${records.length} record${records.length == 1 ? '' : 's'}',
      size: 18,
      bold: true,
    ));

    for (var i = 0; i < records.length; i++) {
      final rec = records[i];
      final r = rec.request;

      body
        ..write(_p(''))
        ..write(_p('${i + 1}.  ${r.studentName}   (${r.registerNumber})',
            bold: true, size: 24))
        ..write(_p('Year ${r.year} · Section ${r.section}', size: 17))
        ..write(_field('Event', '${r.eventName}  (${r.eventType})'))
        ..write(_field('Dates', dateRange(r)))
        ..write(_field('Project', r.resultProjectName ?? r.eventName))
        ..write(_field('Result', resultLine(r)));

      if (r.resultPrizeDetails != null && r.resultPrizeDetails!.isNotEmpty) {
        body.write(_field('Prize details', r.resultPrizeDetails!));
      }
      body
        ..write(_field(
          'Description',
          (r.resultDescription != null && r.resultDescription!.isNotEmpty)
              ? r.resultDescription!
              : r.description,
        ))
        ..write(_field('Team', teamLine(r)));

      if (r.isTeam && r.team.isNotEmpty) {
        body.write('<w:tbl>'
            '<w:tblPr><w:tblBorders>'
            '<w:top w:val="single" w:sz="4" w:color="999999"/>'
            '<w:left w:val="single" w:sz="4" w:color="999999"/>'
            '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
            '<w:right w:val="single" w:sz="4" w:color="999999"/>'
            '<w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>'
            '<w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>'
            '</w:tblBorders></w:tblPr>'
            '<w:tr>${_cell('Member', bold: true, shade: 'D9E2F3')}'
            '${_cell('What they contributed', bold: true, shade: 'D9E2F3')}</w:tr>');
        for (final m in r.team) {
          body.write('<w:tr>${_cell(m.name)}'
              '${_cell(m.contribution ?? 'Not recorded')}</w:tr>');
        }
        body.write('</w:tbl>');
      }

      if (rec.photos.isNotEmpty) {
        body.write(_p('Photographs', bold: true, size: 18));
        for (final entry in rec.photos.entries) {
          final ext = _extFor(entry.value);
          final rel = await addImage(entry.value, ext);
          if (rel == null) continue;
          final size = await _imageSize(entry.value);
          if (size == null) continue;
          body
            ..write(_image(rel, size, media.length + 1))
            ..write(_p(_photoLabel(entry.key), size: 15));
        }
      } else if (r.files.isNotEmpty) {
        body.write(_field('Attachments', photoLine(r)));
      }
    }

    final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document '
        'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
        'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
        'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<w:body>$body'
        '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr>'
        '</w:body></w:document>';

    final extensions = media.map((m) => m.ext).toSet();
    final contentTypes = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>');
    for (final ext in extensions) {
      contentTypes.write('<Default Extension="$ext" ContentType="image/'
          '${ext == 'jpg' ? 'jpeg' : ext}"/>');
    }
    contentTypes.write(
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>');

    final docRels = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (var i = 0; i < media.length; i++) {
      docRels.write('<Relationship Id="rId${i + 2}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/${media[i].name}"/>');
    }
    docRels.write('</Relationships>');

    final archive = Archive()
      ..addFile(_textFile('[Content_Types].xml', contentTypes.toString()))
      ..addFile(_textFile('_rels/.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
          '</Relationships>'))
      ..addFile(_textFile('word/_rels/document.xml.rels', docRels.toString()))
      ..addFile(_textFile('word/document.xml', document));

    for (final m in media) {
      archive.addFile(ArchiveFile('word/media/${m.name}', m.bytes.length, m.bytes));
    }

    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) throw Exception('Could not build the Word file.');
    return _write('Report', 'docx', bytes);
  }

  // -- OOXML helpers ----------------------------------------------------------

  /// UTF-8, not codeUnits: a student's name may carry characters outside
  /// Latin-1, and codeUnits would write those as broken bytes.
  static ArchiveFile _textFile(String name, String content) {
    final bytes = utf8.encode(content);
    return ArchiveFile(name, bytes.length, bytes);
  }

  static String _p(String text, {bool bold = false, int size = 20}) =>
      '<w:p><w:pPr><w:spacing w:after="60"/></w:pPr><w:r><w:rPr>'
      '${bold ? '<w:b/>' : ''}<w:sz w:val="$size"/></w:rPr>'
      '<w:t xml:space="preserve">${_escape(text)}</w:t></w:r></w:p>';

  static String _field(String label, String value) =>
      '<w:p><w:pPr><w:spacing w:after="40"/></w:pPr>'
      '<w:r><w:rPr><w:b/><w:sz w:val="17"/><w:color w:val="666666"/></w:rPr>'
      '<w:t xml:space="preserve">${_escape(label)}:  </w:t></w:r>'
      '<w:r><w:rPr><w:sz w:val="19"/></w:rPr>'
      '<w:t xml:space="preserve">${_escape(value)}</w:t></w:r></w:p>';

  static String _cell(String text, {bool bold = false, String? shade}) =>
      '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>'
      '${shade != null ? '<w:shd w:val="clear" w:fill="$shade"/>' : ''}</w:tcPr>'
      '<w:p><w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:sz w:val="17"/></w:rPr>'
      '<w:t xml:space="preserve">${_escape(text)}</w:t></w:r></w:p></w:tc>';

  /// An inline picture, sized to 3 inches wide with the aspect ratio kept.
  /// Word measures in EMU: 914,400 to the inch.
  static String _image(String relId, ui.Size size, int id) {
    const widthEmu = 2743200; // 3 inches
    final heightEmu = (widthEmu * size.height / size.width).round();
    return '<w:p><w:pPr><w:spacing w:after="40"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$widthEmu" cy="$heightEmu"/>'
        '<wp:docPr id="$id" name="Picture $id"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic>'
        '<pic:nvPicPr><pic:cNvPr id="$id" name="Picture $id"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="$relId"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/>'
        '<a:ext cx="$widthEmu" cy="$heightEmu"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
        '</pic:pic></a:graphicData></a:graphic>'
        '</wp:inline></w:drawing></w:r></w:p>';
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// Decodes just far enough to learn the dimensions, so the picture is not
  /// stretched in the document.
  static Future<ui.Size?> _imageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = ui.Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      return size.width == 0 || size.height == 0 ? null : size;
    } catch (_) {
      return null;
    }
  }

  /// PNG and WebP announce themselves in their first bytes; everything else
  /// the app uploads is a JPEG.
  static String _extFor(Uint8List bytes) {
    if (bytes.length > 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'png';
    }
    return 'jpg';
  }
}

class _WordImage {
  _WordImage(this.name, this.bytes, this.ext);
  final String name;
  final Uint8List bytes;
  final String ext;
}
