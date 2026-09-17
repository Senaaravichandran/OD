'use client';

import { useCountUp } from '@/utils/animations';
import styles from './Stats.module.css';

const stats = [
  { icon: '🎓', number: 500, suffix: '+', label: 'Active Students' },
  { icon: '📋', number: 200, suffix: '+', label: 'Events Managed' },
  { icon: '⚡', number: 100, suffix: '%', label: 'Digital Workflow' },
  { icon: '🕐', number: 24, suffix: '/7', label: 'Access Anytime' },
];

export default function Stats() {
  return (
    <section className={styles.section}>
      <div className={styles.container}>
        <div className={styles.grid}>
          {stats.map((stat, index) => (
            <StatItem key={index} stat={stat} />
          ))}
        </div>
      </div>
    </section>
  );
}

function StatItem({ stat }) {
  const [ref, count] = useCountUp(stat.number, 2000);

  return (
    <div ref={ref} className={styles.stat}>
      <span className={styles.statIcon}>{stat.icon}</span>
      <div className={styles.statNumber}>
        {count}
        <span className={styles.statSuffix}>{stat.suffix}</span>
      </div>
      <div className={styles.statLabel}>{stat.label}</div>
    </div>
  );
}
