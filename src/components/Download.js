'use client';

import { useScrollAnimation } from '@/utils/animations';
import styles from './Download.module.css';

export default function Download() {
  const [ref, isVisible] = useScrollAnimation();

  return (
    <section className={styles.section} id="download">
      <div className={styles.container}>
        <div
          ref={ref}
          className={`${styles.content} animateOnScroll ${isVisible ? 'visible' : ''}`}
        >
          <div className={styles.textSide}>
            <div className={styles.badge}>📲 Download Now</div>
            <h2 className={styles.title}>
              Get the SMVEC OD App on Your Phone
            </h2>
            <p className={styles.description}>
              Download the APK and start managing your event on-duty requests 
              right from your mobile device. Available for Android.
            </p>

            <div className={styles.cta}>
              <a
                href="/downloads/smvec-od.apk"
                className={styles.downloadBtn}
                download="smvec-od.apk"
                id="btn-download-apk"
              >
                <span className={styles.downloadIcon}>⬇️</span>
                Download Android APK
              </a>
              <a
                href="/app"
                className={styles.webAppBtn}
                id="btn-launch-web-portal"
              >
                <span className={styles.downloadIcon}>🚀</span>
                Launch Web Portal
              </a>
              <div className={styles.appInfo}>
                <span className={styles.appInfoItem}>📦 Real Android APK (v2.3.1)</span>
                <span className={styles.appInfoItem}>📱 Android 8.0+ Compatible</span>
                <span className={styles.appInfoItem}>💾 Direct High-Speed Download (~53 MB)</span>
              </div>
            </div>
          </div>

          <div className={styles.visualSide}>
            <div className={styles.downloadCard}>
              <span className={styles.downloadCardIcon}>📱</span>
              <div className={styles.downloadCardTitle}>SMVEC OD Manager</div>
              <div className={styles.downloadCardSub}>IT Department Official App</div>
              <div className={styles.downloadCardBadges}>
                <span className={styles.platformBadge}>🤖 Android</span>
                <span className={styles.platformBadge}>🌐 Web</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
