// Official class-advisor roster for the IT department.
//
// This is the source of truth for "which class belongs to which advisor". A
// student picks their year and section and the advisor follows from it, so no
// one has to pick an advisor by hand and no one can be attached to the wrong
// class. It also lets an advisor on this list sign in and go straight to their
// dashboard, without filling in a profile first.
//
// Keeping it in code rather than the database is deliberate: it changes once a
// year, it must be right, and it should be reviewed in a diff.
//
// KNOWN DATA ISSUES - these came with the roster and need the department to
// confirm the correct values:
//
//   * Year 1 Section B (Periyasami) is listed with padmapriya@smvec.ac.in,
//     the same address as Year 1 Section A. Accounts are keyed by email, so
//     until a separate address is supplied, both classes route to the same
//     account and Padmapriya sees Section B's requests too. The section is
//     marked `sharedInbox` so this stays visible rather than silently odd.
//   * Year 2 Section B and Year 3 Section C are listed with gmail addresses.
//     They are allowed to sign in despite the @smvec.ac.in rule, because
//     being on this roster is itself the department vouching for them, but
//     college addresses would be better.

export const DEPARTMENT = 'Information Technology';

export const ADVISOR_ROSTER = [
  // 1st Year
  { year: 1, section: 'A', name: 'Padmapriya', email: 'padmapriya@smvec.ac.in' },
  { year: 1, section: 'B', name: 'Periyasami', email: 'padmapriya@smvec.ac.in', sharedInbox: true },
  { year: 1, section: 'C', name: 'Maheshwaran', email: 'maheshwaranit@smvec.ac.in' },
  // 2nd Year
  { year: 2, section: 'A', name: 'Vanaja', email: 'vanaja.it@smvec.ac.in' },
  { year: 2, section: 'B', name: 'Pradheeshma', email: 'pradeesshma96@gmail.com' },
  { year: 2, section: 'C', name: 'Valarmathi', email: 'valarmathie.it@smvec.ac.in' },
  { year: 2, section: 'D', name: 'Keerthana', email: 'keerthanav.it@smvec.ac.in' },
  // 3rd Year
  { year: 3, section: 'A', name: 'Praveen Kumar', email: 'praveenkumarp.it@smvec.ac.in' },
  { year: 3, section: 'B', name: 'Ranjeeth', email: 'ranjeeth.it@smvec.ac.in' },
  { year: 3, section: 'C', name: 'Poornambigai', email: 'k.poornilashmi15@gmail.com' },
  // 4th Year
  { year: 4, section: 'A', name: 'D Prabhu', email: 'prabhu.it@smvec.ac.in' },
  { year: 4, section: 'B', name: 'Vijayakumar', email: 'vijayakumarb.it@smvec.ac.in' },
  { year: 4, section: 'C', name: 'Vijaya Prabhu', email: 'vijayprabhu.it@smvec.ac.in' },
];

const norm = (v) => String(v ?? '').trim().toLowerCase();

/// The advisor for a class, or null when that class is not on the roster.
export function advisorForClass(year, section) {
  const y = Number(year);
  const s = String(section ?? '').trim().toUpperCase();
  return ADVISOR_ROSTER.find((a) => a.year === y && a.section === s) || null;
}

/// The roster entry for an address. An advisor can hold more than one class
/// (see the shared-inbox note above), so the first match wins for identity and
/// `classesFor` gives the full set.
export function rosterEntryForEmail(email) {
  const e = norm(email);
  return ADVISOR_ROSTER.find((a) => norm(a.email) === e) || null;
}

export function classesFor(email) {
  const e = norm(email);
  return ADVISOR_ROSTER.filter((a) => norm(a.email) === e);
}

export function isRosterEmail(email) {
  return rosterEntryForEmail(email) !== null;
}

/// Years, and the sections that actually exist in each, so the app never
/// offers a class that has no advisor behind it.
export function classMap() {
  const byYear = new Map();
  for (const a of ADVISOR_ROSTER) {
    if (!byYear.has(a.year)) byYear.set(a.year, []);
    byYear.get(a.year).push({ section: a.section, advisorName: a.name, advisorEmail: a.email });
  }
  return [...byYear.entries()]
    .sort((x, y) => x[0] - y[0])
    .map(([year, sections]) => ({
      year,
      sections: sections.sort((x, y) => x.section.localeCompare(y.section)),
    }));
}

/// The batch a given year belongs to right now, e.g. a 3rd year in 2026 is
/// 2024-2028. The academic year is taken to start in July.
export function batchForYear(year, now = new Date()) {
  const y = Number(year);
  if (!Number.isInteger(y) || y < 1 || y > 4) return null;
  const academicStart = now.getMonth() >= 6 ? now.getFullYear() : now.getFullYear() - 1;
  const entryYear = academicStart - (y - 1);
  return `${entryYear}-${entryYear + 4}`;
}
