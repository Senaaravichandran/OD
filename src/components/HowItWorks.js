'use client';

import { useScrollAnimation } from '@/utils/animations';
import styles from './HowItWorks.module.css';

const steps = [
  {
    number: 1,
    icon: '📝',
    title: 'Register & Login',
    description:
      'Create your student account with your college email. Your department and section are auto-filled.',
  },
  {
    number: 2,
    icon: '📋',
    title: 'Submit Event Details',
    description:
      'Fill in the event form — choose solo or team, select event type, pick the date, and describe the event.',
  },
  {
    number: 3,
    icon: '✅',
    title: 'HOD Reviews & Approves',
    description:
      'Your HOD receives the submission, reviews the details, and approves or provides feedback.',
  },
  {
    number: 4,
    icon: '🏆',
    title: 'Submit Results',
    description:
      'After your event, upload your project details, photos, and whether you won or participated.',
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
          <div className={styles.subtitle}>🔄 How It Works</div>
          <h2 className={styles.title}>Simple 4-Step Process</h2>
          <p className={styles.description}>
            From registration to results — the entire workflow is streamlined and digital.
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
