'use client';

import { useScrollAnimation } from '@/utils/animations';
import styles from './AppShowcase.module.css';

export default function AppShowcase() {
  const [headerRef, headerVisible] = useScrollAnimation();

  return (
    <section className={styles.section} id="showcase">
      <div className={styles.container}>
        <div
          ref={headerRef}
          className={`${styles.header} animateOnScroll ${headerVisible ? 'visible' : ''}`}
        >
          <div className={styles.subtitle}>📱 App Preview</div>
          <h2 className={styles.title}>See It In Action</h2>
          <p className={styles.description}>
            Take a look at the key screens of the SMVEC OD Management app.
          </p>
        </div>

        <div className={styles.carousel}>
          {/* Student Dashboard */}
          <ScreenCard title="Student Dashboard" index={0}>
            <div className={styles.mockDashboard}>
              <div>
                <div className={styles.mockWelcome}>Welcome, Aravindhan! 👋</div>
                <div className={styles.mockWelcomeSub}>Roll No: 21IT101 · III Year · Section A</div>
              </div>
              <div className={styles.mockStatsRow}>
                <div className={styles.mockStat}>
                  <div className={styles.mockStatNum}>5</div>
                  <div className={styles.mockStatLabel}>Total</div>
                </div>
                <div className={styles.mockStat}>
                  <div className={styles.mockStatNum}>3</div>
                  <div className={styles.mockStatLabel}>Approved</div>
                </div>
                <div className={styles.mockStat}>
                  <div className={styles.mockStatNum}>2</div>
                  <div className={styles.mockStatLabel}>Pending</div>
                </div>
              </div>
              <div className={styles.mockList}>
                <div className={styles.mockListItem}>
                  <div>
                    <div className={styles.mockListTitle}>Smart India Hackathon</div>
                    <div className={styles.mockListDate}>Sept 15, 2026</div>
                  </div>
                  <span className={`${styles.mockBadge} ${styles.badgeGreen}`}>Approved</span>
                </div>
                <div className={styles.mockListItem}>
                  <div>
                    <div className={styles.mockListTitle}>TCS Internship</div>
                    <div className={styles.mockListDate}>Oct 1, 2026</div>
                  </div>
                  <span className={`${styles.mockBadge} ${styles.badgeYellow}`}>Pending</span>
                </div>
              </div>
            </div>
          </ScreenCard>

          {/* Event Form */}
          <ScreenCard title="Event Submission" index={1}>
            <div className={styles.mockForm}>
              <div className={styles.mockToggleRow}>
                <div className={`${styles.mockToggle} ${styles.mockToggleActive}`}>Solo</div>
                <div className={styles.mockToggle}>Team</div>
              </div>
              <div className={styles.mockFormGroup}>
                <span className={styles.mockLabel}>Event Type</span>
                <div className={styles.mockInput}>Hackathon ▾</div>
              </div>
              <div className={styles.mockFormGroup}>
                <span className={styles.mockLabel}>Event Name</span>
                <div className={styles.mockInput}>Smart India Hackathon 2026</div>
              </div>
              <div className={styles.mockFormGroup}>
                <span className={styles.mockLabel}>Event Date</span>
                <div className={styles.mockInput}>📅 Sept 20, 2026 · Saturday</div>
              </div>
              <div className={styles.mockFormGroup}>
                <span className={styles.mockLabel}>Description</span>
                <div className={styles.mockInput}>National level hackathon...</div>
              </div>
              <div className={styles.mockSubmitBtn}>Submit for Approval</div>
            </div>
          </ScreenCard>

          {/* HOD Dashboard */}
          <ScreenCard title="HOD Dashboard" index={2}>
            <div className={styles.mockHod}>
              <div className={styles.mockFilters}>
                <span className={`${styles.mockFilter} ${styles.mockFilterActive}`}>All</span>
                <span className={styles.mockFilter}>Pending</span>
                <span className={styles.mockFilter}>Approved</span>
              </div>
              <div className={styles.mockTable}>
                <div className={styles.mockTableHeader}>
                  <span>Student</span>
                  <span>Event</span>
                  <span>Status</span>
                </div>
                <div className={styles.mockTableRow}>
                  <span>Aravindhan S</span>
                  <span>Hackathon</span>
                  <span className={`${styles.mockBadge} ${styles.badgeGreen}`}>Approved</span>
                </div>
                <div className={styles.mockTableRow}>
                  <span>Priya K</span>
                  <span>Internship</span>
                  <span className={`${styles.mockBadge} ${styles.badgeYellow}`}>Pending</span>
                </div>
                <div className={styles.mockTableRow}>
                  <span>Karthik R</span>
                  <span>Presentation</span>
                  <span className={`${styles.mockBadge} ${styles.badgeYellow}`}>Pending</span>
                </div>
              </div>
              <div className={styles.mockActions}>
                <div className={`${styles.mockActionBtn} ${styles.mockApproveBtn}`}>✓ Approve All</div>
                <div className={`${styles.mockActionBtn} ${styles.mockExportBtn}`}>📥 Export</div>
              </div>
            </div>
          </ScreenCard>
        </div>
      </div>
    </section>
  );
}

function ScreenCard({ title, children, index }) {
  const [ref, isVisible] = useScrollAnimation(0.1);

  return (
    <div
      ref={ref}
      className={`${styles.screenCard} animateOnScroll ${isVisible ? 'visible' : ''}`}
      style={{ transitionDelay: `${index * 150}ms` }}
    >
      <div className={styles.screenCardHeader}>
        <div className={styles.screenDots}>
          <span className={styles.dot}></span>
          <span className={styles.dot}></span>
          <span className={styles.dot}></span>
        </div>
        <span className={styles.screenTitle}>{title}</span>
      </div>
      <div className={styles.screenBody}>{children}</div>
    </div>
  );
}
