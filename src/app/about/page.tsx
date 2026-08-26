'use client';

import React, { useState, useEffect, useRef, useCallback } from 'react';
import Link from 'next/link';
import Header from '../../components/Header';
import styles from './about.module.css';
import Footer from '../../components/Footer';
import {
  GraduationCap,
  Utensils,
  Dumbbell,
  Calendar,
  Bed,
  Book,
  Bus,
  Lock,
  BarChart2,
  Bot,
  Shield,
  Check,
  Globe,
  Mail,
  MapPin,
  Award,
  Star,
  Users,
  Menu,
  X,
  ChevronRight,
  ExternalLink,
  CheckCircle2,
  AlertTriangle
} from 'lucide-react';

// Left Column LHS Modules
const LHS_MODULES = [
  {
    id: 'campus-core',
    icon: Shield,
    title: 'Campus Core',
    desc: 'Attendance, grading, exams',
    tagline: 'Automated Academic Lifecycle & Attendance Engine',
    spec: 'Engine: PL/pgSQL Atomic Transaction Router',
    roles: 'Students, Faculty, HOD, Registrar',
    checklist: [
      'RFID scanner sync enabled',
      'Realtime biometric override active',
      'Automatic timetable conflict solver online'
    ],
    telemetry: ['Latency: < 12ms', 'Database SLA: 99.99%', 'Security Index: Hardened']
  },
  {
    id: 'canteen-pay',
    icon: Utensils,
    title: 'Canteen Pay',
    desc: 'Queues, contactless billing',
    tagline: 'Cashless Canteen Pre-orders & Digital Wallets',
    spec: 'Engine: Double-Entry Transaction Ledger',
    roles: 'Students, Vendor, Accountant',
    checklist: [
      'Razorpay webhook listener active',
      'Express Queue POS ticket dispenser ready',
      'Allergy profile cross-reference enabled'
    ],
    telemetry: ['Sync Latency: < 40ms', 'SLA: 99.98%', 'Daily Transactions: 4.2k']
  },
  {
    id: 'fit-zone',
    icon: Dumbbell,
    title: 'FitZone',
    desc: 'Gym, slots, inventories',
    tagline: 'Gym slot reservation & Trainer allocations',
    spec: 'Engine: Redis-backed Locking Semaphore',
    roles: 'Students, Gym Trainer, Warden',
    checklist: [
      'Real-time slot availability check live',
      'Trainer conflict resolver online',
      'Equipment maintenance logger ready'
    ],
    telemetry: ['Slot allocation: < 8ms', 'SLA: 99.95%', 'Daily bookings: 450+']
  },
  {
    id: 'events-hub',
    icon: Calendar,
    title: 'Events Hub',
    desc: 'Tickets, auto slot booking',
    tagline: 'Public ticketing & volunteer shift allocation',
    spec: 'Engine: Dynamic PDF QR Ticket Renderer',
    roles: 'Students, Faculty Coordinator, TPO',
    checklist: [
      'Razorpay webhook listener online',
      'Volunteer shift scheduler compiled',
      'Event catalog search index cached'
    ],
    telemetry: ['Ticketing SLA: 99.99%', 'PDF Gen latency: < 80ms', 'Search response: 4ms']
  },
  {
    id: 'luxe-hostel',
    icon: Bed,
    title: 'Luxe Hostel',
    desc: 'Room allocator, outpass',
    tagline: 'Warden desk, room grids & automated outpasses',
    spec: 'Engine: Automated Room Allocation Optimizer',
    roles: 'Students, Warden, Chief Warden',
    checklist: [
      'Outpass request flow active',
      'Real-time room occupancy grid live',
      'Maintenance ticket dispatcher ready'
    ],
    telemetry: ['Outpass approval: Instant', 'SLA: 99.99%', 'Occupancy load: 94%']
  }
];

// Right Column RHS Modules
const RHS_MODULES = [
  {
    id: 'library-plus',
    icon: Book,
    title: 'Library Plus',
    desc: 'AI book recommendations',
    tagline: 'AI recommendations & Catalog search index',
    spec: 'Engine: pgvector Cosine Similarity Matcher',
    roles: 'Students, Librarian',
    checklist: ['ISBN lookup OCR active', 'AI recommendation engine online', 'Late fee auto-ledger enabled'],
    telemetry: ['AI Search Latency: < 24ms', 'Catalog Index: 140k+', 'SLA: 99.97%']
  },
  {
    id: 'transit-tracker',
    icon: Bus,
    title: 'Transit Tracker',
    desc: 'Live GPS tracking & dispatcher',
    tagline: 'Live bus GPS tracking & dispatching dashboard',
    spec: 'Engine: WebSockets Real-time Stream Gateway',
    roles: 'Students, Bus Driver, Fleet Director',
    checklist: [
      'GPS coordinates socket stream live',
      'Leaflet interactive map rendering online',
      'Route delay notifications active'
    ],
    telemetry: ['Telemetry stream: 1s refresh', 'Map Latency: < 15ms', 'SLA: 99.96%']
  },
  {
    id: 'gate-link',
    icon: Lock,
    title: 'Gate Link',
    desc: 'Biometrics, QR security logs',
    tagline: 'Biometrics & QR security access logs monitor',
    spec: 'Engine: JWT-signed Handshake QR Engine',
    roles: 'Security Guards, Chief Security Officer',
    checklist: [
      'Biometric scanner handshake verified',
      'Visitor pass dynamic override online',
      'Gate 1-4 security cameras sync complete'
    ],
    telemetry: ['QR Scan validation: 2ms', 'Camera uptime: 100%', 'SLA: 99.99%']
  },
  {
    id: 'director-board',
    icon: BarChart2,
    title: 'Director Board',
    desc: 'Strategic financial analytics',
    tagline: 'Strategic institutional analytics & finance board',
    spec: 'Engine: Real-time Financial Consolidation Matrix',
    roles: 'Director, Principal, CFO',
    checklist: [
      'Fee collection analytics sync complete',
      'Multi-tenant insights engine online',
      'Dips/anomaly detector running'
    ],
    telemetry: ['Report compilation: 180ms', 'Analytics accuracy: 100%', 'SLA: 99.99%']
  },
  {
    id: 'ai-concierge',
    icon: Bot,
    title: 'AI Concierge',
    desc: 'Bilingual context search',
    tagline: 'Bilingual semantic contextual helper AI',
    spec: 'Engine: RAG pipeline with Llama-3-70B semantic maps',
    roles: 'All Campus Users, Applicants',
    checklist: [
      'Bilingual parser active (Hindi/English)',
      'Timetable semantic parser ready',
      'Session context memory caching enabled'
    ],
    telemetry: ['LLM Inference time: 82ms', 'RAG vector retrieval: 12ms', 'SLA: 99.95%']
  }
];

// The Problem We Solve cards data
const PROBLEMS = [
  {
    title: 'Manual Attendance',
    desc: 'Registers and Excel sheets, proxy attendance, lost data sheets, and delayed compilation.',
    stat: '40+ hours/month wasted by faculty'
  },
  {
    title: 'Canteen Chaos',
    desc: 'Long queues during breaks, cash-only struggles, manual accounting errors, and missed lunches.',
    stat: '15-min average queue wait time'
  },
  {
    title: 'Event Mismanagement',
    desc: 'Messy WhatsApp groups, paper-based forms, manual ticketing, and zero unified post-event data.',
    stat: 'High coordinator friction'
  },
  {
    title: 'Fee Confusion',
    desc: 'No real-time logs for families, bank clearance delays, and constant manual phone inquiries.',
    stat: 'Lack of transparency'
  },
  {
    title: 'Hostel Hassles',
    desc: 'Manual room allocations grid, slow unattended maintenance tickets, and gate register bypasses.',
    stat: 'Slow ticket resolution loops'
  },
  {
    title: 'Zero Analytics',
    desc: 'Directors have no real-time overview of finances, attendance drops, or system compliance metrics.',
    stat: 'Operating completely blind'
  }
];

export default function AboutPage() {
  const [activeModule, setActiveModule] = useState(LHS_MODULES[0]);
  const [ctaActiveGlow, setCtaActiveGlow] = useState(true);

  // Counter States
  const [modulesCount, setModulesCount] = useState(0);
  const [dashboardsCount, setDashboardsCount] = useState(0);
  const [studentsCount, setStudentsCount] = useState(0);
  const [uptimeCount, setUptimeCount] = useState(0);
  const [countersTriggered, setCountersTriggered] = useState(false);

  // Refs for Scroll Reveal
  const revealRefs = useRef<HTMLElement[]>([]);
  const addToRevealRefs = (el: HTMLElement | null) => {
    if (el && !revealRefs.current.includes(el)) {
      revealRefs.current.push(el);
    }
  };

  // Refs for SVG Paths
  const containerRef = useRef<HTMLDivElement>(null);
  const hudRef = useRef<HTMLDivElement>(null);
  const leftRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const rightRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const [paths, setPaths] = useState<{ id: string; d: string; isActive: boolean }[]>([]);

  // 1. Scroll Reveal IntersectionObserver
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add(styles.revealActive);
          }
        });
      },
      { threshold: 0.1 }
    );

    const currentRefs = revealRefs.current;
    currentRefs.forEach((ref) => {
      if (ref) observer.observe(ref);
    });

    return () => {
      currentRefs.forEach((ref) => {
        if (ref) observer.unobserve(ref);
      });
    };
  }, []);

  // 2. Count-Up Logic triggered by IntersectionObserver
  const statsSectionRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        if (entry.isIntersecting && !countersTriggered) {
          setCountersTriggered(true);
          animateCounters();
        }
      },
      { threshold: 0.25 }
    );

    const node = statsSectionRef.current;
    if (node) {
      observer.observe(node);
    }

    return () => {
      if (node) {
        observer.unobserve(node);
      }
    };
  }, [countersTriggered]);

  const animateCounters = () => {
    const duration = 2000; // 2 seconds
    const easeOutCubic = (x: number): number => 1 - Math.pow(1 - x, 3);

    let startTime: number | null = null;

    const step = (now: number) => {
      if (!startTime) startTime = now;
      const elapsed = now - startTime;
      const progress = Math.min(elapsed / duration, 1);
      const easedProgress = easeOutCubic(progress);

      setModulesCount(Math.floor(easedProgress * 10));
      setDashboardsCount(Math.floor(easedProgress * 11));
      setStudentsCount(Math.floor(easedProgress * 1247));
      setUptimeCount(Math.floor(easedProgress * 365));

      if (progress < 1) {
        requestAnimationFrame(step);
      } else {
        setModulesCount(10);
        setDashboardsCount(11);
        setStudentsCount(1247);
        setUptimeCount(365);
      }
    };

    requestAnimationFrame(step);
  };

  // 3. SVG Connection Paths Calculations
  const updatePaths = useCallback(() => {
    if (!containerRef.current || !hudRef.current) return;

    const containerRect = containerRef.current.getBoundingClientRect();
    const hudRect = hudRef.current.getBoundingClientRect();

    // Only draw paths on desktop resolutions where columns are side-by-side
    if (window.innerWidth < 1024) {
      setPaths([]);
      return;
    }

    const calculatedPaths: { id: string; d: string; isActive: boolean }[] = [];

    // Left Column Calculations (Module card connects on right-mid, HUD on left edge)
    LHS_MODULES.forEach((mod, index) => {
      const cardEl = leftRefs.current[index];
      if (!cardEl) return;

      const cardRect = cardEl.getBoundingClientRect();
      const startX = cardRect.right - containerRect.left;
      const startY = cardRect.top + cardRect.height / 2 - containerRect.top;

      // Draw connection to custom vertical spot on HUD's left border
      const endX = hudRect.left - containerRect.left;
      const endY = hudRect.top + (index + 1) * (hudRect.height / 6) - containerRect.top;

      // Cubic Bezier curve control points
      const deltaX = (endX - startX) / 2;
      const d = `M ${startX} ${startY} C ${startX + deltaX} ${startY}, ${endX - deltaX} ${endY}, ${endX} ${endY}`;
      calculatedPaths.push({
        id: mod.id,
        d,
        isActive: activeModule.id === mod.id
      });
    });

    // Right Column Calculations (Module card connects on left-mid, HUD on right edge)
    RHS_MODULES.forEach((mod, index) => {
      const cardEl = rightRefs.current[index];
      if (!cardEl) return;

      const cardRect = cardEl.getBoundingClientRect();
      const startX = cardRect.left - containerRect.left;
      const startY = cardRect.top + cardRect.height / 2 - containerRect.top;

      // Draw connection to custom vertical spot on HUD's right border
      const endX = hudRect.right - containerRect.left;
      const endY = hudRect.top + (index + 1) * (hudRect.height / 6) - containerRect.top;

      // Cubic Bezier curve control points
      const deltaX = (startX - endX) / 2;
      const d = `M ${startX} ${startY} C ${startX - deltaX} ${startY}, ${endX + deltaX} ${endY}, ${endX} ${endY}`;
      calculatedPaths.push({
        id: mod.id,
        d,
        isActive: activeModule.id === mod.id
      });
    });

    setPaths(calculatedPaths);
  }, [activeModule.id]);

  useEffect(() => {
    if (typeof window === 'undefined') return;

    // Initial timeout to let layout settle
    const timer = setTimeout(updatePaths, 150);

    // Setup modern ResizeObserver for dynamic layout updates
    const observer = new ResizeObserver(() => {
      updatePaths();
    });

    if (containerRef.current) {
      observer.observe(containerRef.current);
    }

    window.addEventListener('resize', updatePaths);

    return () => {
      clearTimeout(timer);
      observer.disconnect();
      window.removeEventListener('resize', updatePaths);
    };
  }, [activeModule, updatePaths]);

  // CTA Glow Interval Loop
  useEffect(() => {
    const interval = setInterval(() => {
      setCtaActiveGlow((prev) => !prev);
    }, 2500);
    return () => clearInterval(interval);
  }, []);

  return (
    <div
      className={`min-h-screen bg-slate-950 dark:bg-slate-950 light:bg-slate-50 text-slate-100 dark:text-slate-100 light:text-slate-900 transition-colors duration-300 flex flex-col font-sans antialiased overflow-x-hidden ${styles.cyberpunkBg}`}
    >
      {/* Ambient Background Video */}
      <video
        autoPlay
        loop
        muted
        playsInline
        className="fixed inset-0 w-full h-full object-cover z-0 pointer-events-none opacity-40 mix-blend-screen"
        src="/bg-video.mp4"
      />
      {/* Background Typography Font Loader */}
      <style jsx global>{`
        @import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@700;800;900&family=JetBrains+Mono:wght@400;500;700&family=Inter:wght@300;400;500;600;700&display=swap');

        .font-heading {
          font-family: 'Orbitron', sans-serif;
        }
        .font-mono {
          font-family: 'JetBrains Mono', monospace;
        }
        .font-sans {
          font-family: 'Inter', sans-serif;
        }
      `}</style>

      {/* Radial backdrop glows */}
      <div className="absolute w-[600px] h-[600px] rounded-full bg-[#8A2BE2]/10 blur-3xl -top-100 -left-100 pointer-events-none"></div>
      <div className="absolute w-[800px] h-[800px] rounded-full bg-[#10b981]/5 blur-3xl top-[40%] right-[-20%] pointer-events-none"></div>
      <div className="absolute w-[700px] h-[700px] rounded-full bg-[#8A2BE2]/5 blur-3xl bottom-[-10%] left-[-10%] pointer-events-none"></div>

      {/* A. NAVIGATION HEADER */}
      <Header />

      {/* B. HERO SECTION */}
      <section
        ref={addToRevealRefs}
        className="relative z-10 pt-[120px] pb-16 px-6 md:px-12 max-w-6xl mx-auto w-full flex flex-col items-center text-center reveal"
      >
        {/* Background Ambient Loop Container */}
        <div className="absolute inset-0 max-h-[420px] w-full overflow-hidden rounded-3xl -z-10 border border-white/5 pointer-events-none opacity-25">
          <video autoPlay loop muted playsInline className="w-full h-full object-cover">
            <source
              src="https://assets.mixkit.co/videos/preview/mixkit-stars-in-space-background-1611-large.mp4"
              type="video/mp4"
            />
          </video>
          {/* Grid overlay */}
          <div className="absolute inset-0 bg-[#050010]/60 bg-[linear-gradient(to_right,rgba(255,255,255,0.03)_1px,transparent_1px),linear-gradient(to_bottom,rgba(255,255,255,0.03)_1px,transparent_1px)] bg-[size:14px_24px]"></div>
          {/* Subtle gradient fading edges */}
          <div className="absolute inset-0 bg-gradient-to-b from-transparent via-[#050010]/80 to-[#050010]"></div>
        </div>

        {/* Breadcrumb */}
        <div className="flex items-center gap-2 text-[10px] font-mono tracking-widest text-[#C4B5FD]/50 mb-6 uppercase">
          <Link href="/" className="hover:text-white transition-colors">
            Home
          </Link>
          <span>&gt;</span>
          <span className="text-[#8A2BE2]">About</span>
        </div>

        {/* Eyebrow Badge (glass-pill) */}
        <div
          className={`px-4 py-1.5 mb-6 text-[10px] font-heading font-semibold tracking-widest text-purple-300 uppercase rounded-full ${styles.glassPill}`}
        >
          ABOUT IRIS 365
        </div>

        {/* Main Headline */}
        <h1 className="font-heading font-black text-3xl sm:text-5xl md:text-6xl text-white tracking-wider leading-[1.1] max-w-4xl">
          CAMPUS INTELLIGENCE,{' '}
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-400 via-purple-300 to-[#10b981] filter drop-shadow-[0_0_15px_rgba(138,43,226,0.3)]">
            REIMAGINED.
          </span>
        </h1>

        {/* Subtitle */}
        <p className="text-xs sm:text-sm text-[#C4B5FD]/75 mt-6 max-w-3xl leading-relaxed font-normal">
          IRIS 365 is not just software. It is a new operating layer for Indian educational institutions — built by
          students, powered by AI, and designed to replace the chaos of manual processes with one unified intelligent
          platform.
        </p>

        {/* Credential Pills */}
        <div className="flex flex-wrap items-center justify-center gap-3 mt-8 max-w-2xl">
          <div className="flex items-center gap-1.5 px-3.5 py-1 text-[9px] font-mono rounded-full bg-white/5 border border-white/8 text-white">
            <Globe className="w-3 h-3 text-[#10b981]" />
            <span>KSL Digital Studio</span>
          </div>
        </div>
      </section>

      {/* C. IMPACT STATS SECTION */}
      <section ref={statsSectionRef} className="px-6 md:px-12 max-w-6xl mx-auto w-full py-10">
        <div
          className={`grid grid-cols-2 md:grid-cols-4 rounded-2xl border border-white/8 p-6 md:p-10 divide-y md:divide-y-0 md:divide-x divide-white/8 ${styles.glassCard}`}
        >
          {/* Stat 1 */}
          <div className="flex flex-col items-center justify-center py-6 md:py-0 text-center">
            <span className="font-heading font-extrabold text-3xl sm:text-4xl md:text-5xl text-white tracking-wider flex items-center justify-center">
              <span>{modulesCount}</span>
              <span className="text-[#8A2BE2] ml-0.5">+</span>
            </span>
            <span className="block mt-2 text-[9px] font-mono tracking-widest text-[#C4B5FD]/50 uppercase">
              MODULES BUILT
            </span>
          </div>
          {/* Stat 2 */}
          <div className="flex flex-col items-center justify-center py-6 md:py-0 text-center">
            <span className="font-heading font-extrabold text-3xl sm:text-4xl md:text-5xl text-white tracking-wider flex items-center justify-center">
              <span>{dashboardsCount}</span>
            </span>
            <span className="block mt-2 text-[9px] font-mono tracking-widest text-[#C4B5FD]/50 uppercase">
              ROLE DASHBOARDS
            </span>
          </div>
          {/* Stat 3 */}
          <div className="flex flex-col items-center justify-center py-6 md:py-0 text-center">
            <span className="font-heading font-extrabold text-3xl sm:text-4xl md:text-5xl text-white tracking-wider flex items-center justify-center">
              <span>{studentsCount}</span>
            </span>
            <span className="block mt-2 text-[9px] font-mono tracking-widest text-[#C4B5FD]/50 uppercase">
              STUDENTS ON PLATFORM
            </span>
          </div>
          {/* Stat 4 */}
          <div className="flex flex-col items-center justify-center py-6 md:py-0 text-center">
            <span className="font-heading font-extrabold text-3xl sm:text-4xl md:text-5xl text-white tracking-wider flex items-center justify-center">
              <span>{uptimeCount}</span>
            </span>
            <span className="block mt-2 text-[9px] font-mono tracking-widest text-[#C4B5FD]/50 uppercase">
              DAYS UPTIME COMMITMENT
            </span>
          </div>
        </div>
      </section>

      {/* D. "WHAT WE BUILD" — INTERACTIVE CYBER COMMAND CENTER */}
      <section id="cyber-command" ref={addToRevealRefs} className="px-6 md:px-12 max-w-6xl mx-auto w-full py-16 reveal">
        <div className="text-center mb-12">
          <h2 className="font-heading font-black text-2xl md:text-3xl tracking-wider text-white">WHAT WE BUILD</h2>
          <p className="text-[10px] font-mono text-[#8A2BE2] tracking-widest uppercase mt-2">
            One platform. Every campus function.
          </p>
        </div>

        {/* Interactive Grid Map */}
        <div ref={containerRef} className="relative grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
          {/* SVG Connection Layer */}
          <svg className="absolute inset-0 w-full h-full pointer-events-none hidden lg:block -z-0">
            <defs>
              <linearGradient id="purpleGlowGradient" x1="0%" y1="0%" x2="100%" y2="0%">
                <stop offset="0%" stopColor="#8A2BE2" stopOpacity="0.2" />
                <stop offset="50%" stopColor="#8A2BE2" stopOpacity="0.8" />
                <stop offset="100%" stopColor="#10b981" stopOpacity="0.2" />
              </linearGradient>
            </defs>
            {/* Render curved connection lines */}
            {paths.map((p) => (
              <path key={p.id} d={p.d} className={p.isActive ? styles.svgPathActive : styles.svgPathDefault} />
            ))}
          </svg>

          {/* Left Column (Core Operationals) */}
          <div className="lg:col-span-3 flex flex-col gap-4 z-10">
            <span className="text-[9px] font-mono tracking-widest text-[#C4B5FD]/40 uppercase mb-1 block lg:text-left text-center">
              LHS // Operationals
            </span>
            {LHS_MODULES.map((mod, idx) => {
              const IconComp = mod.icon;
              const isActive = activeModule.id === mod.id;
              return (
                <button
                  key={mod.id}
                  ref={(el) => {
                    leftRefs.current[idx] = el;
                  }}
                  onClick={() => setActiveModule(mod)}
                  onMouseEnter={() => setActiveModule(mod)}
                  className={`w-full text-left p-4 rounded-xl border flex items-center gap-3.5 transition-all relative overflow-hidden ${
                    isActive
                      ? 'border-[#8A2BE2] bg-[#8A2BE2]/10 shadow-[0_0_15px_rgba(138,43,226,0.15)]'
                      : 'border-white/5 bg-white/2 hover:border-white/20 hover:bg-white/5'
                  }`}
                >
                  <div
                    className={`p-2 rounded-lg ${isActive ? 'bg-[#8A2BE2] text-white' : 'bg-white/5 text-[#C4B5FD]'}`}
                  >
                    <IconComp className="w-4 h-4" />
                  </div>
                  <div>
                    <h4 className="text-xs font-bold text-white uppercase font-heading tracking-wide">{mod.title}</h4>
                    <p className="text-[9px] text-[#C4B5FD]/60 mt-0.5">{mod.desc}</p>
                  </div>
                  {/* Subtle active state indicators */}
                  {isActive && (
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 w-1.5 h-1.5 rounded-full bg-[#10b981] animate-ping"></div>
                  )}
                </button>
              );
            })}
          </div>

          {/* Center Column (Terminal HUD Console) */}
          <div
            ref={hudRef}
            className={`lg:col-span-6 p-6 rounded-2xl ${styles.terminalHud} ${styles.terminalGrid} z-10 flex flex-col min-h-[380px] justify-between`}
          >
            {/* CSS scanning scan beam */}
            <div className={styles.scanningLine}></div>

            {/* Terminal Header */}
            <div className="flex items-center justify-between border-b border-white/10 pb-3 mb-4 font-mono text-[9px] text-[#C4B5FD]/60">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-red-500 animate-pulse"></span>
                <span className="tracking-wider uppercase font-bold text-purple-300">
                  TERMINAL: MON_01 // SECURE_LINK
                </span>
              </div>
              <div className="flex items-center gap-1.5">
                <span className="text-[#10b981] font-bold">SYS ACTIVE</span>
                <span>{'//'}</span>
                <span>ID: {activeModule.id.toUpperCase()}</span>
              </div>
            </div>

            {/* Terminal Body */}
            <div className="flex-1 flex flex-col gap-4 font-mono text-left">
              {/* Module Header */}
              <div>
                <div className="inline-block px-2 py-0.5 rounded text-[8px] bg-[#8A2BE2]/20 border border-[#8A2BE2]/40 text-purple-300 font-bold uppercase mb-2">
                  System Module Core
                </div>
                <h3 className="font-heading font-black text-xl text-white tracking-widest uppercase">
                  {activeModule.title}
                </h3>
                <p className="text-[10px] text-[#C4B5FD] mt-1 font-mono italic">&gt; {activeModule.tagline}</p>
              </div>

              {/* Sub System Information */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 border-y border-white/5 py-4 my-2 text-[10px]">
                <div className="flex flex-col gap-2">
                  <div className="text-white/40 uppercase font-semibold">Engine Specification:</div>
                  <div className="text-[#C4B5FD] font-semibold">{activeModule.spec}</div>
                </div>
                <div className="flex flex-col gap-2">
                  <div className="text-white/40 uppercase font-semibold">Permitted Access Roles:</div>
                  <div className="text-[#10b981] font-semibold flex items-center gap-1">
                    <CheckCircle2 className="w-3.5 h-3.5 shrink-0 text-[#10b981]" />
                    <span>{activeModule.roles}</span>
                  </div>
                </div>
              </div>

              {/* Diagnostic Checkbox Bullet List */}
              <div className="flex flex-col gap-2">
                <div className="text-[9px] text-white/40 uppercase font-semibold">Diagnostic Subsystems Checks:</div>
                <ul className="grid grid-cols-1 md:grid-cols-2 gap-2 text-[9px] text-[#C4B5FD]/80">
                  {activeModule.checklist.map((item, idx) => (
                    <li key={idx} className="flex items-center gap-2">
                      <span className="w-1.5 h-1.5 bg-[#8A2BE2] rounded-full shrink-0"></span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            {/* Terminal Telemetry KPIs Footer */}
            <div className="border-t border-white/10 pt-4 mt-4 grid grid-cols-3 gap-2 font-mono text-[9px] text-center">
              {activeModule.telemetry.map((tel, idx) => (
                <div key={idx} className="bg-white/3 border border-white/5 py-1.5 px-2 rounded">
                  <span className="text-[#C4B5FD] font-semibold block">{tel.split(':')[0]}</span>
                  <span className="text-white/90 font-bold block mt-0.5">{tel.split(':')[1]}</span>
                </div>
              ))}
            </div>
          </div>

          {/* Right Column (Enterprise Extensions) */}
          <div className="lg:col-span-3 flex flex-col gap-4 z-10">
            <span className="text-[9px] font-mono tracking-widest text-[#C4B5FD]/40 uppercase mb-1 block lg:text-left text-center">
              RHS // Extensions
            </span>
            {RHS_MODULES.map((mod, idx) => {
              const IconComp = mod.icon;
              const isActive = activeModule.id === mod.id;
              return (
                <button
                  key={mod.id}
                  ref={(el) => {
                    rightRefs.current[idx] = el;
                  }}
                  onClick={() => setActiveModule(mod)}
                  onMouseEnter={() => setActiveModule(mod)}
                  className={`w-full text-left p-4 rounded-xl border flex items-center gap-3.5 transition-all relative overflow-hidden ${
                    isActive
                      ? 'border-[#8A2BE2] bg-[#8A2BE2]/10 shadow-[0_0_15px_rgba(138,43,226,0.15)]'
                      : 'border-white/5 bg-white/2 hover:border-white/20 hover:bg-white/5'
                  }`}
                >
                  <div
                    className={`p-2 rounded-lg ${isActive ? 'bg-[#8A2BE2] text-white' : 'bg-white/5 text-[#C4B5FD]'}`}
                  >
                    <IconComp className="w-4 h-4" />
                  </div>
                  <div>
                    <h4 className="text-xs font-bold text-white uppercase font-heading tracking-wide">{mod.title}</h4>
                    <p className="text-[9px] text-[#C4B5FD]/60 mt-0.5">{mod.desc}</p>
                  </div>
                  {/* Subtle active state indicators */}
                  {isActive && (
                    <div className="absolute right-3 top-1/2 -translate-y-1/2 w-1.5 h-1.5 rounded-full bg-[#10b981] animate-ping"></div>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Core Value Cards (Below Grid) with staggered entrance animations */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mt-12">
          {/* Card 1 */}
          <div
            ref={addToRevealRefs}
            className={`p-6 rounded-2xl text-left border border-white/6 reveal ${styles.glassCard}`}
          >
            <div className="w-9 h-9 rounded-xl bg-purple-500/10 border border-[#8A2BE2]/30 flex items-center justify-center mb-4 text-[#8A2BE2]">
              <Shield className="w-4 h-4" />
            </div>
            <h3 className="font-heading font-bold text-sm text-white uppercase tracking-wider">Modular Platform</h3>
            <p className="text-xs text-[#C4B5FD]/70 mt-2 leading-relaxed">
              Pay only for what your campus needs. Pick specific operationals or enterprise modules and integrate them
              dynamically into your custom deployment.
            </p>
          </div>

          {/* Card 2 */}
          <div
            ref={addToRevealRefs}
            className={`p-6 rounded-2xl text-left border border-white/6 reveal ${styles.delay100} ${styles.glassCard}`}
          >
            <div className="w-9 h-9 rounded-xl bg-green-500/10 border border-[#10b981]/30 flex items-center justify-center mb-4 text-[#10b981]">
              <Bot className="w-4 h-4" />
            </div>
            <h3 className="font-heading font-bold text-sm text-white uppercase tracking-wider">AI-Powered</h3>
            <p className="text-xs text-[#C4B5FD]/70 mt-2 leading-relaxed">
              Built-in AI automation triggers, semantic vector-based lookup databases, and natural language interfaces
              streamline complex query resolutions instantly.
            </p>
          </div>

          {/* Card 3 */}
          <div
            ref={addToRevealRefs}
            className={`p-6 rounded-2xl text-left border border-white/6 reveal ${styles.delay200} ${styles.glassCard}`}
          >
            <div className="w-9 h-9 rounded-xl bg-purple-500/10 border border-[#8A2BE2]/30 flex items-center justify-center mb-4 text-[#8A2BE2]">
              <Users className="w-4 h-4" />
            </div>
            <h3 className="font-heading font-bold text-sm text-white uppercase tracking-wider">Student Built</h3>
            <p className="text-xs text-[#C4B5FD]/70 mt-2 leading-relaxed">
              Engineered by outstanding student tech partners under the Student Partnership Program 2026. Designed
              directly to address real campus pain points.
            </p>
          </div>
        </div>
      </section>

      {/* E. "THE PROBLEM WE SOLVE" with staggered individual cards */}
      <section ref={addToRevealRefs} className="px-6 md:px-12 max-w-6xl mx-auto w-full py-16 reveal">
        <div className="text-center mb-16">
          <h2 className="font-heading font-black text-2xl md:text-3xl tracking-wider text-white uppercase">
            THE PROBLEM WE SOLVE
          </h2>
          <p className="text-[10px] font-mono text-[#8A2BE2] tracking-widest uppercase mt-2">
            Indian campuses are running on chaos — not systems.
          </p>
        </div>

        {/* 6-Card Grid with staggered entrance animations */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {PROBLEMS.map((prob, idx) => {
            // Apply delay classes based on layout index for stagger effect
            const delayClass =
              idx === 1
                ? styles.delay100
                : idx === 2
                  ? styles.delay200
                  : idx === 3
                    ? styles.delay300
                    : idx === 4
                      ? styles.delay400
                      : idx === 5
                        ? styles.delay500
                        : '';

            return (
              <div
                key={idx}
                ref={addToRevealRefs}
                className={`p-6 rounded-2xl border-y border-r border-white/6 border-l-[3px] border-l-[#8A2BE2] text-left relative overflow-hidden transition-transform duration-300 hover:-translate-y-1 reveal ${delayClass} ${styles.glassCard}`}
              >
                {/* Alert Badge with exact color value */}
                <div className="absolute right-4 top-4 flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-[#ef4444]/10 border border-[#ef4444]/30 text-[#ef4444] text-[8px] font-mono font-bold tracking-wider uppercase">
                  <AlertTriangle className="w-2.5 h-2.5 shrink-0" />
                  <span>UNSOLVED</span>
                </div>

                <h3 className="font-heading font-bold text-sm text-white uppercase tracking-wider mt-4">
                  {prob.title}
                </h3>
                <p className="text-xs text-[#C4B5FD]/70 mt-2.5 leading-relaxed">{prob.desc}</p>

                <div className="mt-5 pt-3 border-t border-white/5 flex items-center justify-between text-[9px] font-mono">
                  <span className="text-[#C4B5FD]/40">Metric Dip:</span>
                  <span className="text-[#ef4444] font-bold">{prob.stat}</span>
                </div>
              </div>
            );
          })}
        </div>

        {/* Bottom Solver Banner */}
        <div
          ref={addToRevealRefs}
          className="mt-10 p-6 rounded-2xl border border-[#10b981]/30 bg-[#10b981]/5 text-center flex flex-col sm:flex-row items-center justify-center gap-3.5 reveal"
        >
          <div className="w-9 h-9 rounded-full bg-[#10b981]/15 border border-[#10b981]/30 flex items-center justify-center text-[#10b981]">
            <CheckCircle2 className="w-5 h-5" />
          </div>
          <div>
            <h4 className="font-heading font-bold text-sm tracking-wider text-white uppercase text-left">
              IRIS 365 SOLVES ALL 6 — IN ONE SECURE LOGIN.
            </h4>
            <p className="text-xs text-[#C4B5FD]/75 mt-0.5 text-left">
              Unified Single Sign-On (SSO) with database isolation maps correct permissions dynamically.
            </p>
          </div>
        </div>
      </section>

      {/* F. DEVELOPED BY / CORPORATE CREDENTIALS */}
      <section ref={addToRevealRefs} className="px-6 md:px-12 max-w-6xl mx-auto w-full py-16 reveal">
        <div
          className={`p-8 md:p-12 rounded-3xl border border-[#8A2BE2]/20 bg-gradient-to-br from-[#0d0020]/80 via-black to-[#050010] text-center md:text-left relative overflow-hidden shadow-[0_0_50px_rgba(138,43,226,0.06)]`}
        >
          {/* Cyber ambient accent lines */}
          <div className="absolute right-0 top-0 w-[300px] h-[300px] rounded-full bg-[#8A2BE2]/10 blur-3xl pointer-events-none -z-10"></div>

          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
            <div className="lg:col-span-12">
              <span className="text-[10px] font-mono text-[#8A2BE2] tracking-widest uppercase">
                FLAGSHIP CAMPUS INITIATIVE
              </span>
              <h2 className="font-heading font-black text-2xl md:text-4xl text-white tracking-wider uppercase mt-2.5">
                KSL Digital Studio
              </h2>
              <p className="text-xs text-[#C4B5FD]/85 mt-4 leading-relaxed max-w-3xl">
                IRIS 365 is designed, compiled, and maintained by KSL Digital Studio under the
                **Student Partnership Program 2026**, bridging the gap between student requirements and professional
                enterprise infrastructure.
              </p>

              {/* Grid Link Details */}
              <div className="grid grid-cols-2 gap-5 mt-8 text-xs font-mono">
                <div className="flex flex-col gap-1.5">
                  <span className="text-[#C4B5FD]/40 uppercase tracking-widest text-[9px]">Contact Link:</span>
                  <a
                    href="mailto:newiris365@gmail.com"
                    className="text-purple-300 hover:text-white flex items-center gap-1 justify-center md:justify-start"
                  >
                    <span>newiris365@gmail.com</span>
                    <Mail className="w-3 h-3" />
                  </a>
                </div>
                <div className="flex flex-col gap-1.5">
                  <span className="text-[#C4B5FD]/40 uppercase tracking-widest text-[9px]">Command HQ:</span>
                  <span className="text-white flex items-center gap-1 justify-center md:justify-start">
                    <MapPin className="w-3.5 h-3.5 text-[#8A2BE2]" />
                    <span>Jodhpur, Rajasthan</span>
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* G. THE TEAM */}
      <section ref={addToRevealRefs} className="px-6 md:px-12 max-w-6xl mx-auto w-full py-16 reveal">
        <div className="text-center mb-16">
          <h2 className="font-heading font-black text-2xl md:text-3xl tracking-wider text-white uppercase">
            THE DEVELOPMENT ENGINE
          </h2>
          <p className="text-[10px] font-mono text-[#8A2BE2] tracking-widest uppercase mt-2">
            Built by students. Guided by vision.
          </p>
        </div>

        {/* Leadership Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8 max-w-4xl mx-auto mb-16">
          {/* Leader 1 */}
          <div
            ref={addToRevealRefs}
            className={`p-6 rounded-2xl border border-white/6 flex flex-col sm:flex-row items-center gap-6 text-center sm:text-left reveal ${styles.glassCard}`}
          >
            <div className={styles.avatarRing}>
              <div className={styles.avatarRingInner}>
                <div className="w-20 h-20 rounded-full bg-gradient-to-tr from-[#8A2BE2] to-[#10b981] flex items-center justify-center text-white font-heading font-black text-xl">
                  HP
                </div>
              </div>
            </div>
            <div>
              <div className="inline-block px-2.5 py-0.5 rounded-full bg-[#10b981]/15 border border-[#10b981]/30 text-[#10b981] text-[8px] font-mono uppercase font-bold tracking-wider mb-2">
                Mentor and Visionary
              </div>
              <h3 className="font-heading font-bold text-base text-white tracking-wide">Er. Harshvardhan Purohit</h3>
              <p className="text-[10px] font-mono text-[#C4B5FD]/50 uppercase mt-0.5 font-bold">Founder & CEO</p>
              <p className="text-xs text-[#C4B5FD]/70 mt-3 leading-relaxed">
                Driving the high-level roadmap and structural alignment for KSL Digital Studio's campus ecosystem.
              </p>
            </div>
          </div>

          {/* Leader 2 */}
          <div
            ref={addToRevealRefs}
            className={`p-6 rounded-2xl border border-white/6 flex flex-col sm:flex-row items-center gap-6 text-center sm:text-left reveal ${styles.delay100} ${styles.glassCard}`}
          >
            <div className={styles.avatarRing}>
              <div className={styles.avatarRingInner}>
                <div className="w-20 h-20 rounded-full bg-gradient-to-tr from-[#8A2BE2] to-[#10b981] flex items-center justify-center text-white font-heading font-black text-xl">
                  SS
                </div>
              </div>
            </div>
            <div>
              <div className="inline-block px-2.5 py-0.5 rounded-full bg-[#8A2BE2]/15 border border-[#8A2BE2]/30 text-purple-300 text-[8px] font-mono uppercase font-bold tracking-wider mb-2">
                Full Stack and AI
              </div>
              <h3 className="font-heading font-bold text-base text-white tracking-wide">Siddharth Singh</h3>
              <p className="text-[10px] font-mono text-[#C4B5FD]/50 uppercase mt-0.5 font-bold">
                Lead Developer, IRIS 365
              </p>
              <p className="text-xs text-[#C4B5FD]/70 mt-3 leading-relaxed">
                Architecting database schema systems, server socket bridges, and telemetry operations models.
              </p>
            </div>
          </div>
        </div>

        {/* Development Team Grid with individual reveals */}
        <div className="border-t border-white/8 pt-10">
          <h4 className="font-heading font-extrabold text-xs text-[#C4B5FD]/40 uppercase tracking-widest text-center mb-8">
            ENGINEERING PARTNERS
          </h4>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-6 text-center">
            {/* Dev 1 */}
            <div ref={addToRevealRefs} className="flex flex-col items-center reveal">
              <div className="w-12 h-12 rounded-xl bg-white/3 border border-white/8 flex items-center justify-center text-white font-mono text-xs font-bold mb-3">
                AK
              </div>
              <h5 className="text-[11px] font-bold text-white uppercase tracking-wide">Arjun Kumar</h5>
              <span className="text-[8px] font-mono text-[#C4B5FD]/50 uppercase mt-0.5">Frontend - Core & Events</span>
            </div>
            {/* Dev 2 */}
            <div ref={addToRevealRefs} className="flex flex-col items-center reveal styles.delay100">
              <div className="w-12 h-12 rounded-xl bg-white/3 border border-white/8 flex items-center justify-center text-white font-mono text-xs font-bold mb-3">
                PM
              </div>
              <h5 className="text-[11px] font-bold text-white uppercase tracking-wide">Priya Mehta</h5>
              <span className="text-[8px] font-mono text-[#C4B5FD]/50 uppercase mt-0.5">UI/UX - Design System</span>
            </div>
            {/* Dev 3 */}
            <div ref={addToRevealRefs} className="flex flex-col items-center reveal styles.delay200">
              <div className="w-12 h-12 rounded-xl bg-white/3 border border-white/8 flex items-center justify-center text-white font-mono text-xs font-bold mb-3">
                RS
              </div>
              <h5 className="text-[11px] font-bold text-white uppercase tracking-wide">Rahul Sharma</h5>
              <span className="text-[8px] font-mono text-[#C4B5FD]/50 uppercase mt-0.5">Backend - Transit & Gate</span>
            </div>
            {/* Dev 4 */}
            <div ref={addToRevealRefs} className="flex flex-col items-center reveal styles.delay300">
              <div className="w-12 h-12 rounded-xl bg-white/3 border border-white/8 flex items-center justify-center text-white font-mono text-xs font-bold mb-3">
                AV
              </div>
              <h5 className="text-[11px] font-bold text-white uppercase tracking-wide">Anita Verma</h5>
              <span className="text-[8px] font-mono text-[#C4B5FD]/50 uppercase mt-0.5">AI - Concierge & Library</span>
            </div>
            {/* Dev 5 */}
            <div
              ref={addToRevealRefs}
              className="flex flex-col items-center col-span-2 md:col-span-1 reveal styles.delay400"
            >
              <div className="w-12 h-12 rounded-xl bg-white/3 border border-white/8 flex items-center justify-center text-white font-mono text-xs font-bold mb-3 mx-auto">
                VJ
              </div>
              <h5 className="text-[11px] font-bold text-white uppercase tracking-wide">Vikram Joshi</h5>
              <span className="text-[8px] font-mono text-[#C4B5FD]/50 uppercase mt-0.5">
                Full Stack - Canteen & Hostel
              </span>
            </div>
          </div>
        </div>
      </section>

      {/* H. CALL TO ACTION (CTA) & FOOTER */}
      <section ref={addToRevealRefs} className="px-6 md:px-12 max-w-4xl mx-auto w-full py-20 reveal">
        <div className="relative overflow-hidden rounded-3xl border border-[#8A2BE2]/30 p-10 md:p-14 text-center">
          {/* Ambient soft glow loop backdrop managed by CSS transition pulsing */}
          <div
            className={`absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 w-[350px] h-[350px] rounded-full bg-[#8A2BE2]/15 blur-3xl pointer-events-none -z-10 transition-all duration-[2500ms] ${
              ctaActiveGlow ? 'opacity-100 scale-110 shadow-[0_0_60px_#8A2BE2]' : 'opacity-50 scale-95 shadow-none'
            }`}
          ></div>

          <h2 className="font-heading font-black text-2xl md:text-4xl text-white tracking-wider uppercase">
            Your Campus Deserves Better.
          </h2>
          <p className="text-xs text-[#C4B5FD]/85 mt-4 leading-relaxed max-w-2xl mx-auto">
            Let IRIS 365 handle the operations — while you focus on education. Run audits, check licensing estimators,
            or request pilot systems instantly.
          </p>

          <div className="flex flex-col sm:flex-row items-center justify-center gap-4 mt-10">
            <Link
              href="/login?fresh=1"
              className="w-full sm:w-auto px-8 py-3.5 rounded-full bg-gradient-to-r from-[#8A2BE2] to-[#6a1cb2] text-white font-bold text-xs uppercase tracking-widest shadow-xl shadow-[#8A2BE2]/20 hover:scale-[1.02] transition-all"
            >
              Request a Free Demo
            </Link>
            <Link
              href="/login?fresh=1"
              className="w-full sm:w-auto px-8 py-3.5 rounded-full bg-white/5 border border-white/10 hover:bg-white/10 text-white font-bold text-xs uppercase tracking-widest transition-all"
            >
              Start 60-Day Free Pilot
            </Link>
          </div>
        </div>
      </section>

      {/* FOOTER SECTION */}
      <Footer />
    </div>
  );
}
