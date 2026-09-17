'use client';

import { useScrollAnimation } from '@/utils/animations';
import styles from './Features.module.css';

const features = [
  {
    icon: '📱',
    title: 'Easy Event Registration',
    description:
      'Submit your event participation details in minutes with our intuitive form for solo or team entries.',
  },
  {
    icon: '✅',
    title: 'Advisor & HOD Approval',
    description:
      'Two-tier digital approval system. Class Advisor endorses attendance, and HOD grants official sanction.',
  },
  {
    icon: '📊',
    title: 'Result Tracking',
    description:
      'After your event, record achievements, photos, and certificates in one centralized place.',
  },
  {
    icon: '📥',
    title: 'Export Reports',
    description:
      'HOD can generate and download comprehensive reports in Excel, PDF, or Word format with advanced filters.',
  },
  {
    icon: '👥',
    title: 'Solo & Team Support',
    description:
      'Whether you\'re going solo or with a team of up to 5 members, the system handles both seamlessly.',
  },
  {
    icon: '🔒',
    title: 'Secure & Reliable',
    description:
      'Enterprise-grade security with role-based access control. Your data stays safe and private at all times.',
  },
];

export default function Features() {
  const [headerRef, headerVisible] = useScrollAnimation();

  return (
    <section className={styles.features} id="features">
      <div className={styles.container}>
        <div
          ref={headerRef}
          className={`${styles.header} animateOnScroll ${headerVisible ? 'visible' : ''}`}
        >
          <div className={styles.subtitle}>✨ Features</div>
          <h2 className={styles.title}>Everything You Need</h2>
          <p className={styles.description}>
            A complete digital solution for managing event on-duty requests, 
            from submission to approval to results.
          </p>
        </div>

        <div className={styles.grid}>
          {features.map((feature, index) => (
            <FeatureCard key={index} feature={feature} index={index} />
          ))}
        </div>
      </div>
    </section>
  );
}

function FeatureCard({ feature, index }) {
  const [ref, isVisible] = useScrollAnimation(0.1);

  return (
    <div
      ref={ref}
      className={`${styles.card} animateOnScroll ${isVisible ? 'visible' : ''}`}
      style={{ transitionDelay: `${index * 100}ms` }}
    >
      <div className={styles.cardIcon}>
        <span className={styles.cardIconEmoji}>{feature.icon}</span>
      </div>
      <h3 className={styles.cardTitle}>{feature.title}</h3>
      <p className={styles.cardDescription}>{feature.description}</p>
    </div>
  );
}
