'use client';

import styles from './Hero.module.css';

export default function Hero() {
  const scrollTo = (id) => {
    const el = document.querySelector(id);
    if (el) {
      const offset = 80;
      const top = el.getBoundingClientRect().top + window.scrollY - offset;
      window.scrollTo({ top, behavior: 'smooth' });
    }
  };

  return (
    <section className={styles.hero} id="home">
      {/* Background */}
      <div className={styles.heroBg}>
        <div className={styles.gridPattern}></div>
      </div>

      <div className={styles.heroContainer}>
        {/* Left Content */}
        <div className={styles.heroContent}>
          <div className={styles.badge}>
            <span className={styles.badgeDot}></span>
            IT Department · SMVEC
          </div>

          <h1 className={styles.heroTitle}>
            Streamline Your{' '}
            <span className={styles.heroTitleAccent}>Event On-Duty</span>{' '}
            Management
          </h1>

          <p className={styles.heroSubtitle}>
            Register for hackathons, internships, and presentations. 
            Get advisor approval and HOD sanction digitally.
          </p>

          <div className={styles.heroDept}>
            <span className={styles.heroDeptLine}></span>
            Sri Manakula Vinayagar Engineering College
          </div>

          <div className={styles.heroCta}>
            <a
              href="/downloads/smvec-od.apk"
              download="smvec-od.apk"
              className="btnPrimary"
              id="hero-download-apk"
            >
              <span className={styles.ctaIcon}>📱</span>
              Download APK
            </a>
            <a
              href="/app"
              className="btnOutline"
              id="hero-launch-portal"
            >
              <span className={styles.ctaIcon}>🚀</span>
              Launch Web Portal
            </a>
          </div>
        </div>

        {/* Right Visual: Phone Mockup */}
        <div className={styles.heroVisual}>
          <div className={styles.phoneMockup}>
            <div className={styles.phoneScreen}>
              <div className={styles.phoneHeader}>
                <img
                  src="/college_logo.png"
                  alt="SMVEC"
                  className={styles.phoneHeaderLogo}
                  width={28}
                  height={28}
                />
                <span className={styles.phoneHeaderText}>SMVEC OD Manager</span>
              </div>
              <div className={styles.phoneBody}>
                <div className={styles.phoneCard}>
                  <div className={styles.phoneCardTitle}>National Hackathon 2026</div>
                  <div className={styles.phoneCardSub}>Sept 20, 2026 · Saturday</div>
                  <span className={`${styles.phoneCardStatus} ${styles.statusApproved}`}>
                    ✓ Approved
                  </span>
                </div>
                <div className={styles.phoneCard}>
                  <div className={styles.phoneCardTitle}>Internship - TCS iON</div>
                  <div className={styles.phoneCardSub}>Oct 5, 2026 · Monday</div>
                  <span className={`${styles.phoneCardStatus} ${styles.statusPending}`}>
                    ⏳ Pending
                  </span>
                </div>
                <div className={styles.phoneCard}>
                  <div className={styles.phoneCardTitle}>Paper Presentation</div>
                  <div className={styles.phoneCardSub}>Oct 12, 2026 · Monday</div>
                  <span className={`${styles.phoneCardStatus} ${styles.statusDenied}`}>
                    ✕ Denied
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Floating Elements */}
          <div className={`${styles.floatingElement} ${styles.floatApproval}`}>
            <span className={styles.floatIcon}>✅</span>
            HOD Approved!
          </div>
          <div className={`${styles.floatingElement} ${styles.floatExport}`}>
            <span className={styles.floatIcon}>📊</span>
            Export Reports
          </div>
        </div>
      </div>
    </section>
  );
}
