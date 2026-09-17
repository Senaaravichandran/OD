'use client';

import { useState, useEffect } from 'react';
import styles from './Navbar.module.css';

const navItems = [
  { label: 'Home', href: '#home' },
  { label: 'Features', href: '#features' },
  { label: 'How It Works', href: '#how-it-works' },
  { label: 'Download', href: '#download' },
];

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setScrolled(window.scrollY > 30);
    };
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  useEffect(() => {
    if (menuOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [menuOpen]);

  const handleNavClick = (e, href) => {
    e.preventDefault();
    setMenuOpen(false);
    const el = document.querySelector(href);
    if (el) {
      const offset = 80;
      const top = el.getBoundingClientRect().top + window.scrollY - offset;
      window.scrollTo({ top, behavior: 'smooth' });
    }
  };

  return (
    <>
      <nav
        className={`${styles.navbar} ${scrolled ? styles.scrolled : ''}`}
        id="navbar"
      >
        <div className={styles.navContainer}>
          <a href="#home" className={styles.logo} onClick={(e) => handleNavClick(e, '#home')}>
            <img
              src="/college_logo.png"
              alt="SMVEC Logo"
              className={styles.logoImage}
              width={42}
              height={42}
            />
            <div className={styles.logoText}>
              <span className={styles.logoTitle}>SMVEC OD</span>
              <span className={styles.logoDept}>IT Department</span>
            </div>
          </a>

          <div
            className={`${styles.menuToggle} ${menuOpen ? styles.active : ''}`}
            onClick={() => setMenuOpen(!menuOpen)}
            role="button"
            aria-label="Toggle menu"
            tabIndex={0}
          >
            <span className={styles.menuBar}></span>
            <span className={styles.menuBar}></span>
            <span className={styles.menuBar}></span>
          </div>

          <div className={`${styles.navLinks} ${menuOpen ? styles.open : ''}`}>
            {navItems.map((item) => (
              <a
                key={item.href}
                href={item.href}
                className={styles.navLink}
                onClick={(e) => handleNavClick(e, item.href)}
              >
                {item.label}
              </a>
            ))}
            <a
              href="/app"
              className={styles.loginBtn}
              id="nav-portal-login"
            >
              Portal Login
            </a>
          </div>
        </div>
      </nav>
      <div
        className={`${styles.overlay} ${menuOpen ? styles.active : ''}`}
        onClick={() => setMenuOpen(false)}
      />
    </>
  );
}
