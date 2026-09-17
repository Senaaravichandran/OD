'use client';

import styles from './Footer.module.css';

export default function Footer() {
  const currentYear = new Date().getFullYear();

  return (
    <footer className={styles.footer} id="contact">
      <div className={styles.container}>
        <div className={styles.top}>
          {/* Brand */}
          <div className={styles.brand}>
            <div className={styles.brandLogo}>
              <img
                src="/college_logo.png"
                alt="SMVEC Logo"
                className={styles.brandLogoImg}
                width={40}
                height={40}
              />
              <span className={styles.brandName}>SMVEC OD Manager</span>
            </div>
            <p className={styles.brandDescription}>
              Digital event on-duty management system for the IT Department at 
              Sri Manakula Vinayagar Engineering College, Puducherry.
            </p>
            <div className={styles.social}>
              <a
                href="https://github.com/Senaaravichandran/OD"
                target="_blank"
                rel="noopener noreferrer"
                className={styles.socialIcon}
                title="GitHub"
              >
                🔗
              </a>
              <span className={styles.socialIcon} title="Email">✉️</span>
              <span className={styles.socialIcon} title="Phone">📞</span>
            </div>
          </div>

          {/* Quick Links */}
          <div className={styles.column}>
            <h4 className={styles.columnTitle}>Quick Links</h4>
            <div className={styles.columnLinks}>
              <a href="#home" className={styles.columnLink}>Home</a>
              <a href="#features" className={styles.columnLink}>Features</a>
              <a href="#how-it-works" className={styles.columnLink}>How It Works</a>
              <a href="#download" className={styles.columnLink}>Download</a>
            </div>
          </div>

          {/* Resources */}
          <div className={styles.column}>
            <h4 className={styles.columnTitle}>Resources</h4>
            <div className={styles.columnLinks}>
              <a href="#" className={styles.columnLink}>User Guide</a>
              <a href="#" className={styles.columnLink}>FAQ</a>
              <a href="#" className={styles.columnLink}>Support</a>
              <a
                href="https://github.com/Senaaravichandran/OD"
                target="_blank"
                rel="noopener noreferrer"
                className={styles.columnLink}
              >
                GitHub
              </a>
            </div>
          </div>

          {/* Contact */}
          <div className={styles.column}>
            <h4 className={styles.columnTitle}>Contact</h4>
            <div className={styles.columnLinks}>
              <span className={styles.columnLink}>IT Department</span>
              <span className={styles.columnLink}>SMVEC, Puducherry</span>
              <span className={styles.columnLink}>India - 605107</span>
            </div>
          </div>
        </div>

        {/* Bottom */}
        <div className={styles.bottom}>
          <p className={styles.copyright}>
            © {currentYear}{' '}
            <span className={styles.copyrightHighlight}>SMVEC IT Department</span>.
            All rights reserved.
          </p>
          <div className={styles.bottomLinks}>
            <a href="#" className={styles.bottomLink}>Privacy Policy</a>
            <a href="#" className={styles.bottomLink}>Terms of Service</a>
          </div>
        </div>
      </div>
    </footer>
  );
}
