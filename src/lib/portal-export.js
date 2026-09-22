'use client';

// PDF, Word and Excel exports for the portal, matching what the Android app
// produces so a report looks the same whichever it came from.
//
// What goes in: who the student is, what they entered, what came of it, who
// was on the team and what each of them did, with the photographs. What does
// not: approval remarks, who approved when, workflow states. Those belong to
// the request screens, not to a record of achievement.
//
// jsPDF and JSZip are loaded on demand, so someone who never exports never
// downloads them.

import { fileBytes, kindLabel } from './portal-upload';

const DATE = (iso) => (iso
  ? new Date(iso).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' })
  : '');

const STAMP = () => new Date().toLocaleString('en-IN', {
  day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
});

/// Downloading every photograph in a department-wide export would take minutes
/// and tens of megabytes. Past this many, the documents carry the details and
/// name the photographs instead.
export const PHOTO_BUDGET = 60;

export const dateRange = (r) => (r.eventEndDate && r.eventEndDate !== r.eventDate
  ? `${DATE(r.eventDate)} - ${DATE(r.eventEndDate)}  (${r.dayCount || 1} days)`
  : `${DATE(r.eventDate)}  (1 day)`);

export const resultLine = (r) => {
  if (r.resultStatus === 'WON') return r.resultPrize ? `Won - ${r.resultPrize}` : 'Won';
  if (r.resultStatus === 'PARTICIPATED') return 'Participated';
  return 'Result not submitted';
};

export const teamLine = (r) => {
  if (r.submissionType !== 'TEAM') return 'Individual entry';
  if (r.team?.length) return r.team.map((m) => m.name).join(', ');
  return (r.teamMembers || []).join(', ');
};

export const photoLine = (r) => ((r.files || []).length
  ? r.files.map((f) => `${kindLabel(f.kind)}: ${f.fileName}`).join('; ')
  : '-');

const describe = (r) => (r.resultDescription && r.resultDescription.trim()
  ? r.resultDescription
  : r.description);

// ---------------------------------------------------------------------------
// Gathering
// ---------------------------------------------------------------------------

/// Fetches the photographs for [rows], up to PHOTO_BUDGET.
///
/// Each one is a signed-URL fetch, so this is the slow part of an export and
/// it reports progress. A photograph that will not download is skipped rather
/// than losing the whole report.
export async function gather(rows, { onProgress, withPhotos = true } = {}) {
  const records = [];
  let budget = withPhotos ? PHOTO_BUDGET : 0;

  for (let i = 0; i < rows.length; i += 1) {
    const r = rows[i];
    const photos = [];

    if (budget > 0) {
      for (const kind of ['EVENT_PHOTO', 'WINNING_PHOTO', 'CERTIFICATE']) {
        if (budget <= 0) break;
        const file = (r.files || []).find(
          (f) => f.kind === kind && String(f.mimeType || '').startsWith('image/'),
        );
        if (!file) continue;
        try {
          photos.push({ kind, bytes: await fileBytes(file.id) });
          budget -= 1;
        } catch {
          // Skip it; the record is still worth printing.
        }
      }
    }

    records.push({ request: r, photos });
    onProgress?.(i + 1, rows.length);
  }
  return records;
}

// ---------------------------------------------------------------------------
// Saving
// ---------------------------------------------------------------------------

function save(blob, name) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  // Give the browser a moment to start the download before revoking.
  setTimeout(() => URL.revokeObjectURL(url), 4000);
}

const stamp = () => new Date().toISOString().slice(0, 19).replace(/[-:T]/g, '');
const fileName = (ext) => `SMVEC_IT_OD_Report_${stamp()}.${ext}`;

// ---------------------------------------------------------------------------
// PDF
// ---------------------------------------------------------------------------

export async function toPdf({ records, title, filters = {} }) {
  const { jsPDF } = await import('jspdf');
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });

  const M = 40;
  const W = doc.internal.pageSize.getWidth();
  const H = doc.internal.pageSize.getHeight();
  let y = M;

  const room = (needed) => {
    if (y + needed > H - M) {
      doc.addPage();
      y = M;
    }
  };

  const line = (text, { size = 9, bold = false, colour = [40, 40, 40], gap = 12 } = {}) => {
    doc.setFont('helvetica', bold ? 'bold' : 'normal');
    doc.setFontSize(size);
    doc.setTextColor(...colour);
    const wrapped = doc.splitTextToSize(String(text ?? ''), W - M * 2);
    room(wrapped.length * gap);
    doc.text(wrapped, M, y);
    y += wrapped.length * gap;
  };

  const field = (label, value) => {
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(120, 120, 120);
    const wrapped = doc.splitTextToSize(String(value ?? ''), W - M * 2 - 75);
    room(wrapped.length * 11 + 2);
    doc.text(`${label}`, M, y);
    doc.setFontSize(9);
    doc.setTextColor(30, 30, 30);
    doc.text(wrapped, M + 75, y);
    y += wrapped.length * 11 + 2;
  };

  line('SRI MANAKULA VINAYAGAR ENGINEERING COLLEGE', { size: 13, bold: true, gap: 16 });
  line('Department of Information Technology', { size: 10, colour: [110, 110, 110] });
  line(title, { size: 11, bold: true, gap: 15 });
  line(`Generated on ${STAMP()}`, { size: 8, colour: [130, 130, 130] });
  if (Object.keys(filters).length) {
    line(`Filters: ${Object.entries(filters).map(([k, v]) => `${k}: ${v}`).join('   |   ')}`,
      { size: 8, colour: [110, 110, 110] });
  }
  line(`${records.length} record${records.length === 1 ? '' : 's'}`,
    { size: 8, colour: [130, 130, 130], gap: 18 });

  for (let i = 0; i < records.length; i += 1) {
    const { request: r, photos } = records[i];
    room(90);

    doc.setDrawColor(200, 200, 200);
    doc.line(M, y - 6, W - M, y - 6);

    line(`${i + 1}.  ${r.studentName}   (${r.registerNumber})`, { size: 11, bold: true, gap: 14 });
    line(`Year ${r.year} · Section ${r.section}`, { size: 8, colour: [130, 130, 130], gap: 14 });

    field('Event', `${r.eventName}  (${r.eventType})`);
    field('Dates', dateRange(r));
    field('Project', r.resultProjectName || r.eventName);
    field('Result', resultLine(r));
    if (r.resultPrizeDetails) field('Prize details', r.resultPrizeDetails);
    field('Description', describe(r));
    field('Team', teamLine(r));

    if (r.submissionType === 'TEAM' && r.team?.length) {
      y += 4;
      line('Contribution', { size: 8, bold: true, gap: 11 });
      for (const m of r.team) {
        field(m.name, m.contribution || 'Not recorded');
      }
    }

    if (photos.length) {
      y += 6;
      room(110);
      let x = M;
      for (const p of photos) {
        try {
          doc.addImage(p.bytes, 'JPEG', x, y, 120, 90);
          doc.setFontSize(7);
          doc.setTextColor(130, 130, 130);
          doc.text(kindLabel(p.kind), x, y + 100);
          x += 130;
        } catch {
          // An image jsPDF cannot decode is skipped, not fatal.
        }
      }
      y += 112;
    } else if ((r.files || []).length) {
      field('Attachments', photoLine(r));
    }
    y += 10;
  }

  const pages = doc.internal.getNumberOfPages();
  for (let p = 1; p <= pages; p += 1) {
    doc.setPage(p);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(150, 150, 150);
    doc.text(`Page ${p} of ${pages}`, W - M, H - 20, { align: 'right' });
  }

  save(doc.output('blob'), fileName('pdf'));
}

// ---------------------------------------------------------------------------
// Word
// ---------------------------------------------------------------------------

const esc = (s) => String(s ?? '')
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;');

const p = (text, { bold = false, size = 20 } = {}) =>
  `<w:p><w:pPr><w:spacing w:after="60"/></w:pPr><w:r><w:rPr>${bold ? '<w:b/>' : ''}`
  + `<w:sz w:val="${size}"/></w:rPr><w:t xml:space="preserve">${esc(text)}</w:t></w:r></w:p>`;

const wField = (label, value) =>
  '<w:p><w:pPr><w:spacing w:after="40"/></w:pPr>'
  + `<w:r><w:rPr><w:b/><w:sz w:val="17"/><w:color w:val="666666"/></w:rPr>`
  + `<w:t xml:space="preserve">${esc(label)}:  </w:t></w:r>`
  + `<w:r><w:rPr><w:sz w:val="19"/></w:rPr>`
  + `<w:t xml:space="preserve">${esc(value)}</w:t></w:r></w:p>`;

const cell = (text, { bold = false, shade = null } = {}) =>
  '<w:tc><w:tcPr><w:tcW w:w="0" w:type="auto"/>'
  + `${shade ? `<w:shd w:val="clear" w:fill="${shade}"/>` : ''}</w:tcPr>`
  + `<w:p><w:r><w:rPr>${bold ? '<w:b/>' : ''}<w:sz w:val="17"/></w:rPr>`
  + `<w:t xml:space="preserve">${esc(text)}</w:t></w:r></w:p></w:tc>`;

/// Reads an image's dimensions so the picture is not stretched in the document.
function imageSize(bytes) {
  return new Promise((resolve) => {
    const blob = new Blob([bytes]);
    const url = URL.createObjectURL(blob);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      resolve({ width: img.naturalWidth, height: img.naturalHeight });
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      resolve(null);
    };
    img.src = url;
  });
}

/// An inline picture, three inches wide. Word measures in EMU: 914,400 an inch.
const drawing = (relId, size, id) => {
  const cx = 2743200;
  const cy = Math.round(cx * size.height / size.width);
  return '<w:p><w:pPr><w:spacing w:after="40"/></w:pPr><w:r><w:drawing>'
    + '<wp:inline distT="0" distB="0" distL="0" distR="0">'
    + `<wp:extent cx="${cx}" cy="${cy}"/>`
    + `<wp:docPr id="${id}" name="Picture ${id}"/>`
    + '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    + '<pic:pic>'
    + `<pic:nvPicPr><pic:cNvPr id="${id}" name="Picture ${id}"/><pic:cNvPicPr/></pic:nvPicPr>`
    + `<pic:blipFill><a:blip r:embed="${relId}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>`
    + `<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${cx}" cy="${cy}"/></a:xfrm>`
    + '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>'
    + '</pic:pic></a:graphicData></a:graphic>'
    + '</wp:inline></w:drawing></w:r></w:p>';
};

export async function toWord({ records, title, filters = {} }) {
  const JSZip = (await import('jszip')).default;
  const zip = new JSZip();
  const media = [];

  let body = p('SRI MANAKULA VINAYAGAR ENGINEERING COLLEGE', { bold: true, size: 30 })
    + p('Department of Information Technology', { size: 22 })
    + p(title, { bold: true, size: 26 })
    + p(`Generated on ${STAMP()}`, { size: 18 });

  if (Object.keys(filters).length) {
    body += p(`Filters - ${Object.entries(filters).map(([k, v]) => `${k}: ${v}`).join(' | ')}`,
      { size: 18 });
  }
  body += p(`${records.length} record${records.length === 1 ? '' : 's'}`, { bold: true, size: 18 });

  for (let i = 0; i < records.length; i += 1) {
    const { request: r, photos } = records[i];

    body += p('')
      + p(`${i + 1}.  ${r.studentName}   (${r.registerNumber})`, { bold: true, size: 24 })
      + p(`Year ${r.year} · Section ${r.section}`, { size: 17 })
      + wField('Event', `${r.eventName}  (${r.eventType})`)
      + wField('Dates', dateRange(r))
      + wField('Project', r.resultProjectName || r.eventName)
      + wField('Result', resultLine(r));

    if (r.resultPrizeDetails) body += wField('Prize details', r.resultPrizeDetails);
    body += wField('Description', describe(r)) + wField('Team', teamLine(r));

    if (r.submissionType === 'TEAM' && r.team?.length) {
      body += '<w:tbl><w:tblPr><w:tblBorders>'
        + '<w:top w:val="single" w:sz="4" w:color="999999"/>'
        + '<w:left w:val="single" w:sz="4" w:color="999999"/>'
        + '<w:bottom w:val="single" w:sz="4" w:color="999999"/>'
        + '<w:right w:val="single" w:sz="4" w:color="999999"/>'
        + '<w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>'
        + '<w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>'
        + '</w:tblBorders></w:tblPr>'
        + `<w:tr>${cell('Member', { bold: true, shade: 'D9E2F3' })}`
        + `${cell('What they contributed', { bold: true, shade: 'D9E2F3' })}</w:tr>`;
      for (const m of r.team) {
        body += `<w:tr>${cell(m.name)}${cell(m.contribution || 'Not recorded')}</w:tr>`;
      }
      body += '</w:tbl>';
    }

    if (photos.length) {
      body += p('Photographs', { bold: true, size: 18 });
      for (const photo of photos) {
        const size = await imageSize(photo.bytes);
        if (!size) continue;
        const id = media.length + 2; // rId1 is the document itself
        media.push({ name: `image${id}.jpg`, bytes: photo.bytes });
        body += drawing(`rId${id}`, size, id) + p(kindLabel(photo.kind), { size: 15 });
      }
    } else if ((r.files || []).length) {
      body += wField('Attachments', photoLine(r));
    }
  }

  const document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<w:document '
    + 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
    + 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    + 'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    + 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    + 'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    + `<w:body>${body}<w:sectPr><w:pgSz w:w="11906" w:h="16838"/></w:sectPr></w:body>`
    + '</w:document>';

  zip.file('[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    + '<Default Extension="xml" ContentType="application/xml"/>'
    + (media.length ? '<Default Extension="jpg" ContentType="image/jpeg"/>' : '')
    + '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    + '</Types>');

  zip.file('_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    + '</Relationships>');

  zip.file('word/_rels/document.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + media.map((m, i) => `<Relationship Id="rId${i + 2}" `
      + 'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      + `Target="media/${m.name}"/>`).join('')
    + '</Relationships>');

  zip.file('word/document.xml', document);
  for (const m of media) zip.file(`word/media/${m.name}`, m.bytes);

  save(await zip.generateAsync({ type: 'blob' }), fileName('docx'));
}

// ---------------------------------------------------------------------------
// Excel
// ---------------------------------------------------------------------------

const HEADERS = [
  'S.No', 'Student', 'Register No', 'Year', 'Section', 'Event', 'Dates', 'Days',
  'Project', 'Result', 'Prize', 'Description', 'Team members', 'Contribution',
  'Photos',
];

const rowFor = (r, i) => [
  `${i + 1}`,
  r.studentName,
  r.registerNumber,
  `${r.year}`,
  r.section,
  r.eventName,
  r.eventEndDate && r.eventEndDate !== r.eventDate
    ? `${DATE(r.eventDate)} - ${DATE(r.eventEndDate)}`
    : DATE(r.eventDate),
  `${r.dayCount || 1}`,
  r.resultProjectName || r.eventName,
  resultLine(r),
  r.resultPrize || '-',
  describe(r),
  teamLine(r),
  r.submissionType === 'TEAM' && r.team?.length
    ? r.team.map((m) => `${m.name}: ${m.contribution || 'not recorded'}`).join(' | ')
    : '-',
  photoLine(r),
];

const COLUMN_WIDTHS = [6, 22, 15, 6, 8, 28, 24, 6, 24, 18, 16, 40, 28, 46, 30];

/// Builds a real .xlsx by writing the OOXML parts directly, the same approach
/// the Word export takes. Everything is written as an inline string, which
/// keeps the file honest without a shared-strings table to keep in step.
export async function toExcel({ records, title, filters = {} }) {
  const JSZip = (await import('jszip')).default;
  const zip = new JSZip();

  const lines = [
    ['Department of Information Technology'],
    [title],
    [`Generated on ${STAMP()}`],
  ];
  if (Object.keys(filters).length) {
    lines.push([Object.entries(filters).map(([k, v]) => `${k}: ${v}`).join('  |  ')]);
  }
  // A spreadsheet cannot carry the photographs; say where they are rather than
  // leaving someone to wonder.
  lines.push(['Photographs are listed by name. The PDF and Word exports embed them.']);
  lines.push([]);
  lines.push(HEADERS);
  records.forEach((rec, i) => lines.push(rowFor(rec.request, i)));

  const colName = (n) => {
    let s = '';
    let i = n;
    while (i >= 0) {
      s = String.fromCharCode(65 + (i % 26)) + s;
      i = Math.floor(i / 26) - 1;
    }
    return s;
  };

  const sheetRows = lines.map((cells, r) => {
    const body = cells.map((value, c) => (value === undefined || value === '' ? '' : (
      `<c r="${colName(c)}${r + 1}" t="inlineStr"${r === 6 ? ' s="1"' : ''}>`
      + `<is><t xml:space="preserve">${esc(value)}</t></is></c>`
    ))).join('');
    return `<row r="${r + 1}">${body}</row>`;
  }).join('');

  zip.file('[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    + '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    + '<Default Extension="xml" ContentType="application/xml"/>'
    + '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    + '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    + '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    + '</Types>');

  zip.file('_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    + '</Relationships>');

  zip.file('xl/workbook.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    + 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    + '<sheets><sheet name="OD Report" sheetId="1" r:id="rId1"/></sheets></workbook>');

  zip.file('xl/_rels/workbook.xml.rels',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    + '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    + '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    + '</Relationships>');

  // One named style: the bold, filled header row.
  zip.file('xl/styles.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    + '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
    + '<font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>'
    + '<fills count="3"><fill><patternFill patternType="none"/></fill>'
    + '<fill><patternFill patternType="gray125"/></fill>'
    + '<fill><patternFill patternType="solid"><fgColor rgb="FF37474F"/>'
    + '<bgColor indexed="64"/></patternFill></fill></fills>'
    + '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    + '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    + '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    + '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
    + '</cellXfs></styleSheet>');

  zip.file('xl/worksheets/sheet1.xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    + '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    + '<cols>'
    + COLUMN_WIDTHS.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join('')
    + '</cols>'
    + `<sheetData>${sheetRows}</sheetData></worksheet>`);

  save(await zip.generateAsync({ type: 'blob' }), fileName('xlsx'));
}

export const EXPORTERS = { pdf: toPdf, word: toWord, excel: toExcel };
