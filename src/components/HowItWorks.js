'use client';

import { useScrollAnimation } from '@/utils/animations';
import styles from './HowItWorks.module.css';

const steps = [
  {
    number: 1,
    icon: '📝',
    title: 'Student Submits Application',
    description:
      'Log in with your official @smvec.ac.in email, select solo or team event, and upload your invitation or brochure proof.',
  },
  {
    number: 2,
    icon: '👩‍🏫',
    title: 'Class Advisor Verification',
    description:
      'Your Class Advisor verifies your attendance, checks eligibility, and endorses the OD request.',
  },
  {
    number: 3,
    icon: '👨‍💼',
    title: 'HOD Final Sanction',
    description:
      'The Head of Department reviews the advisor recommendation and grants official college On-Duty sanction.',
  },
  {
    number: 4,
    icon: '🏆',
    title: 'Record Achievements',
    description:
      'After the event, upload certificates and awards directly to college archives.',
  },
];

export default function HowItWorks() {
  const [headerRef, headerVisible] = useScrollAnimation();

  return (
    <section className={styles.section} id="how-it-works">
      <div className={styles.container}>
        <div
          ref={headerRef}
          className={`${styles.header} animateOnScroll ${headerVisible ? 'visible' : ''}`}
        >
          <div className={styles.subtitle}>🔄 Workflow</div>
          <h2 className={styles.title}>Simple 4-Step Process</h2>
          <p className={styles.description}>
            From initial submission to final HOD sanction, the entire workflow is digital and transparent.
          </p>
        </div>

        <div className={styles.steps}>
          {steps.map((step, index) => (
            <StepItem key={step.number} step={step} index={index} />
          ))}
        </div>
      </div>
    </section>
  );
}

function StepItem({ step, index }) {
  const [ref, isVisible] = useScrollAnimation(0.2);

  return (
    <div
      ref={ref}
      className={`${styles.step} animateOnScroll ${isVisible ? 'visible' : ''}`}
      style={{ transitionDelay: `${index * 150}ms` }}
    >
      <div className={styles.stepContent}>
        <span className={styles.stepIcon}>{step.icon}</span>
        <h3 className={styles.stepTitle}>{step.title}</h3>
        <p className={styles.stepDescription}>{step.description}</p>
      </div>
      <div className={styles.stepNumber}>{step.number}</div>
      <div className={styles.stepSpacer}></div>
    </div>
  );
}
