'use client';

import React, { useState, useEffect, useRef } from 'react';
import Link from 'next/link';
import dynamic from 'next/dynamic';
import Header from '../components/Header';
import Footer from '../components/Footer';
import {
  Shield,
  BookOpen,
  Coffee,
  Dumbbell,
  Key,
  Calendar,
  Bot,
  ChevronRight,
  CheckCircle,
  Terminal,
  Zap,
  GraduationCap,
  ChevronDown,
  Search,
  MessageSquare,
  ArrowRight,
  Sparkles,
  Lock,
  FileCheck,
  Code
} from 'lucide-react';

// Lazy-load framer-motion for smooth entrance animations
const MotionDiv = dynamic(() => import('framer-motion').then((mod) => mod.motion.div) as any, { ssr: false }) as any;
const AnimatePresence = dynamic(() => import('framer-motion').then((mod) => mod.AnimatePresence) as any, {
  ssr: false
}) as any;

const MODULES = [
  {
    icon: Shield,
    title: 'Campus Core & Biometrics',
    desc: 'Automated student and staff attendance tracking, biometric gate check-ins, and verified profile indexing.',
    badge: 'Core Administrative',
    color: 'from-purple-500/20 to-indigo-500/20'
  },
  {
    icon: BookOpen,
    title: 'Academics & Grading',
    desc: 'Instant grade compilation, online assignment submissions, and automated class timetable scheduling.',
    badge: 'Academic Operations',
    color: 'from-purple-500/20 to-pink-500/20'
  },
  {
    icon: Coffee,
    title: 'Cashless Canteen Wallet',
    desc: 'Pre-order meals, swipe RFID digital wallets, and auto-sync cafeteria balances with complete fraud protection.',
    badge: 'Financial Services',
    color: 'from-[#8A2BE2]/20 to-purple-500/20'
  },
  {
    icon: Dumbbell,
    title: 'FitZone & Wellness Pass',
    desc: 'Reserve gym slots, check equipment availability, and auto-manage sports pass subscriptions.',
    badge: 'Student Wellness',
    color: 'from-purple-500/20 to-[#6C2BD9]/20'
  },
  {
    icon: Calendar,
    title: 'Campus Events & Ticketing',
    desc: 'Digital QR event tickets, seat reservations, and automated volunteer shift scheduling.',
    badge: 'Student Life',
    color: 'from-pink-500/20 to-purple-500/20'
  },
  {
    icon: Key,
    title: 'Hostel & Security Key',
    desc: 'Digital warden outpass approvals, visitor registration logs, and automated night check-in monitoring.',
    badge: 'Residential Security',
    color: 'from-indigo-500/20 to-purple-500/20'
  }
];

const FAQ_DATA = [
  {
    id: 'q1',
    category: 'Architecture',
    question: 'What is IRIS 365 and how does it benefit campus administration?',
    answer:
      'IRIS 365 is a unified Campus Operating System designed for schools, colleges, and universities. It replaces fragmented third-party applications by bringing academics, biometrics, canteen wallets, hostel management, bus transit, and AI support into one single secure cloud workspace.'
  },
  {
    id: 'q2',
    category: 'Security',
    question: 'How is student and financial data protected across the platform?',
    answer:
      'All data is encrypted using enterprise AES-256 at rest and TLS 1.3 in transit. Role-Based Access Control (RBAC) ensures students, teachers, parents, wardens, and directors only view the data relevant to their authorized responsibilities.'
  },
  {
    id: 'q3',
    category: 'Deployment',
    question: 'Can IRIS 365 integrate with our existing hardware terminals?',
    answer:
      'Yes. IRIS 365 seamlessly connects with existing RFID scanners, biometric gate turnstiles, canteen POS machines, and vehicle GPS trackers via standard API webhooks and lightweight edge relays.'
  },
  {
    id: 'q4',
    category: 'Modules',
    question: 'Can institutions start with a few modules and add more later?',
    answer:
      'Execution is completely flexible. Institutions can launch with core modules (such as Attendance & Admissions) and enable additional modules like Canteen Wallet or Transit Tracking at any time without software downtime.'
  },
  {
    id: 'q5',
    category: 'Support',
    question: 'How can an institution schedule a live guided demonstration?',
    answer:
      'You can click "Request Demo" anywhere on this page to schedule a customized walk-through with an IRIS 365 campus solutions specialist for your leadership team.'
  }
];

const WhyIrisSection: React.FC<{ onChipClick: (cat: string) => void }> = ({ onChipClick }) => {
  const cardRef = useRef<HTMLDivElement>(null);
  const [showTechDetails, setShowTechDetails] = useState(false);

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    // Skip 3D tilt on touch devices
    if (typeof window !== 'undefined' && 'ontouchstart' in window) return;

    const card = cardRef.current;
    if (!card) return;
    const rect = card.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    const tiltX = -(y - rect.height / 2) / 18;
    const tiltY = (x - rect.width / 2) / 18;
    card.style.transform = `perspective(1000px) rotateX(${tiltX}deg) rotateY(${tiltY}deg) scale3d(1.02, 1.02, 1.02)`;
    card.style.transition = 'none';
  };

  const handleMouseLeave = () => {
    const card = cardRef.current;
    if (!card) return;
    card.style.transform = `perspective(1000px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)`;
    card.style.transition = 'transform 0.5s cubic-bezier(0.16, 1, 0.3, 1)';
  };

  return (
    <section id="features" className="w-full max-w-[1240px] mx-auto px-6 sm:px-8 py-20 relative z-20">
      <div className="grid grid-cols-1 lg:grid-cols-[1.12fr_0.88fr] gap-12 lg:gap-16 items-center">
        {/* Left Column - Benefit-Led Features */}
        <div className="text-left flex flex-col items-start">
          <div className="flex items-center gap-2 px-3.5 py-1.5 text-xs font-semibold bg-[#8A2BE2]/10 light:bg-purple-100 text-purple-300 light:text-purple-800 rounded-full border border-[#8A2BE2]/30 light:border-purple-300">
            <span className="w-2 h-2 rounded-full bg-[#8A2BE2] animate-pulse" />
            <span className="text-xs uppercase tracking-wide">Why IRIS 365</span>
            <span className="text-xs font-mono tracking-wider bg-white/10 light:bg-purple-200/60 px-2 py-0.5 rounded-full ml-1 text-white light:text-purple-900">
              Built for Leadership
            </span>
          </div>

          <h2 className="text-3xl sm:text-[2.2rem] font-bold text-white light:text-slate-900 font-orbitron mt-5 leading-[1.1] uppercase tracking-tight">
            One Connected Campus. <br /> Zero Manual Chaos.
          </h2>

          <p className="text-slate-300 light:text-slate-600 text-xs sm:text-sm font-sans leading-relaxed mt-5 max-w-[520px]">
            From morning biometric gate check-in to evening hostel curfew, IRIS 365 unifies administrative, academic, financial, and logistical workflows into a single dashboard.
          </p>

          {/* Benefit Rows */}
          <div className="flex flex-col mt-6 w-full max-w-[550px] space-y-3">
            {[
              {
                title: 'Smart Automated Attendance',
                desc: 'Instant QR and biometric marking eliminates manual registers and proxy attendance.'
              },
              {
                title: 'AI Room & Resource Planning',
                desc: 'Hostel rooms, library slots, and gym passes allocated automatically without queues.'
              },
              {
                title: 'Live Real-Time Campus Telemetry',
                desc: 'Monitor bus GPS, security gate passes, and canteen transactions live.'
              },
              {
                title: '11 Tailored Role Portals',
                desc: 'Dedicated dashboards for students, teachers, parents, wardens, and directors.'
              },
              {
                title: 'Unified Cashless Wallet',
                desc: 'One digital wallet for canteen meals, library fees, and campus dues.'
              }
            ].map((row, idx) => (
              <div key={idx} className="p-3.5 rounded-xl bg-white/3 light:bg-slate-100/70 border border-white/8 light:border-slate-200 hover:border-[#8A2BE2]/40 transition-colors">
                <div className="flex items-center gap-2.5">
                  <div className="w-2 h-2 rounded-full bg-[#8A2BE2] shrink-0" />
                  <h3 className="font-semibold text-xs text-white light:text-slate-900">{row.title}</h3>
                </div>
                <p className="text-xs text-slate-300 light:text-slate-600 mt-1 font-light pl-4 leading-relaxed">{row.desc}</p>
              </div>
            ))}
          </div>

          {/* Feature Chips */}
          <div className="flex flex-wrap gap-2.5 mt-7 max-w-[550px]">
            {[
              { label: 'Role-based Access', cat: 'Security' },
              { label: 'Real-time Analytics', cat: 'Architecture' },
              { label: 'QR & Biometrics', cat: 'Deployment' },
              { label: 'AI Concierge', cat: 'Modules' },
              { label: 'PWA Mobile App', cat: 'Support' }
            ].map((chip) => (
              <button
                key={chip.label}
                onClick={() => onChipClick(chip.cat)}
                className="text-xs font-medium text-slate-300 light:text-slate-700 border border-white/10 light:border-slate-300 bg-white/5 light:bg-slate-100 rounded-full px-4 py-1.5 hover:bg-[#8A2BE2]/20 hover:border-[#8A2BE2]/40 hover:text-white light:hover:text-purple-900 transition-all text-left"
              >
                {chip.label}
              </button>
            ))}
          </div>

          {/* Under the Hood Collapsible for Technical Readers */}
          <div className="mt-8 w-full max-w-[550px]">
            <button
              onClick={() => setShowTechDetails(!showTechDetails)}
              className="flex items-center gap-2 text-xs text-purple-300 light:text-purple-700 hover:text-white light:hover:text-purple-900 transition-colors font-mono"
            >
              <Code className="w-4 h-4 text-purple-400 light:text-purple-600" />
              <span>{showTechDetails ? 'Hide Technical Specifications' : 'Technical Specifications (For IT Leads)'}</span>
              <ChevronDown className={`w-3.5 h-3.5 transition-transform ${showTechDetails ? 'rotate-180' : ''}`} />
            </button>

            {showTechDetails && (
              <div className="mt-3 p-4 rounded-xl bg-[#080512] light:bg-purple-50 border border-[#8A2BE2]/30 light:border-purple-200 text-xs font-mono space-y-2 text-slate-300 light:text-purple-950">
                <p>⚡ Database Engine: PostgreSQL 16 with custom atomic RPC transaction routers.</p>
                <p>🔒 Security Model: Stateless JWT fingerprinting with TLS 1.3 encryption.</p>
                <p>🤖 AI Infrastructure: RAG pipeline with pgvector cosine similarity matching.</p>
              </div>
            )}
          </div>
        </div>

        {/* Right Column - Live Overview Card */}
        <div
          ref={cardRef}
          onMouseMove={handleMouseMove}
          onMouseLeave={handleMouseLeave}
          style={{ transformStyle: 'preserve-3d', willChange: 'transform' }}
          className="rounded-3xl p-6 sm:p-7 border border-white/10 light:border-slate-200 bg-[#090117]/80 light:bg-white backdrop-blur-md shadow-2xl relative w-full"
        >
          <div className="flex items-center justify-between mb-4 border-b border-white/10 light:border-slate-200 pb-4">
            <div>
              <div className="flex items-center gap-2">
                <h3 className="font-sans font-semibold text-sm sm:text-base text-white light:text-slate-900">Today's Campus Overview</h3>
                <span className="px-2 py-0.5 rounded-full bg-purple-500/20 light:bg-purple-100 text-purple-300 light:text-purple-800 text-xs font-mono font-medium">
                  Live Preview
                </span>
              </div>
              <p className="text-xs text-slate-400 light:text-slate-500 font-light mt-0.5">Sample Telemetry Data</p>
            </div>
            <div className="flex items-center gap-1.5">
              <div className="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse" />
              <span className="text-xs font-mono text-emerald-400 dark:text-emerald-400 light:text-emerald-600 font-semibold">Active</span>
            </div>
          </div>

          <div className="space-y-3">
            {[
              { title: '🎓 Academic Operations', stat: '23 classes in session · 4 upcoming exams', dotColor: '#8A2BE2' },
              { title: '🍽 Canteen Wallet', stat: '847 meal orders · ₹24,350 processed today', dotColor: '#6C2BD9' },
              { title: '🚌 Transport Fleet', stat: '12 active buses · 3 routes on schedule', dotColor: '#A78BFA' },
              { title: '🤖 AI Assistant', stat: '142 student queries answered today', dotColor: '#C4B5FD' }
            ].map((card) => (
              <div
                key={card.title}
                className="rounded-xl p-4 flex items-center justify-between bg-white/5 light:bg-slate-100/60 hover:bg-white/10 light:hover:bg-slate-100 transition-colors border border-white/5 light:border-slate-200"
              >
                <div className="flex items-center gap-3">
                  <div
                    style={{ backgroundColor: card.dotColor }}
                    className="w-2.5 h-2.5 rounded-full shrink-0 shadow-[0_0_8px_rgba(138,43,226,0.4)]"
                  />
                  <span className="font-semibold text-xs sm:text-sm text-white light:text-slate-900">{card.title}</span>
                </div>
                <span className="font-light text-xs text-slate-300 light:text-slate-600 text-right">{card.stat}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};

export default function LandingPage() {
  const [videoReady, setVideoReady] = useState(false);
  const [showStickyCta, setShowStickyCta] = useState(false);

  // FAQ States
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState('All');
  const [expandedFaqId, setExpandedFaqId] = useState<string | null>(null);

  // Handle scroll for sticky CTA button
  useEffect(() => {
    const handleScroll = () => {
      setShowStickyCta(window.scrollY > 400);
    };
    window.addEventListener('scroll', handleScroll);
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  useEffect(() => {
    const t = requestAnimationFrame(() => setVideoReady(true));
    return () => cancelAnimationFrame(t);
  }, []);

  // Filter FAQs
  const filteredFaqs = FAQ_DATA.filter((faq) => {
    const matchesCategory = selectedCategory === 'All' || faq.category === selectedCategory;
    const matchesQuery =
      faq.question.toLowerCase().includes(searchQuery.toLowerCase()) ||
      faq.answer.toLowerCase().includes(searchQuery.toLowerCase());
    return matchesCategory && matchesQuery;
  });

  const handleChipClick = (cat: string) => {
    setSelectedCategory(cat);
    const faqSection = document.getElementById('faq');
    if (faqSection) {
      faqSection.scrollIntoView({ behavior: 'smooth' });
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-[#050010] text-slate-900 dark:text-slate-100 transition-colors duration-300 flex flex-col font-sans antialiased overflow-x-hidden relative">
      {/* Background Video */}
      {videoReady && (
        <video
          autoPlay
          loop
          muted
          playsInline
          preload="none"
          className="fixed inset-0 w-full h-full object-cover z-0 pointer-events-none opacity-40 mix-blend-screen"
          src="/bg-video.mp4"
        />
      )}

      {/* Radial Glow Backgrounds */}
      <div className="absolute w-[600px] h-[600px] rounded-full bg-[#8A2BE2]/10 blur-3xl -top-100 -left-100 pointer-events-none z-0"></div>
      <div className="absolute w-[800px] h-[800px] rounded-full bg-[#6C2BD9]/8 blur-3xl top-[40%] right-[-20%] pointer-events-none z-0"></div>

      {/* Header */}
      <Header />

      {/* Hero Section */}
      <section
        id="hero"
        className="relative z-10 px-6 pt-28 pb-20 md:pt-40 md:pb-32 max-w-6xl mx-auto flex flex-col items-center text-center"
      >
        <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-[#8A2BE2]/10 light:bg-purple-100 border border-[#8A2BE2]/30 light:border-purple-300 text-purple-300 light:text-purple-800 text-xs font-semibold mb-6">
          <Zap className="w-4 h-4 text-purple-400 light:text-purple-600" />
          <span>Integrated Campus Operating System</span>
        </div>

        <h1 className="font-heading font-extrabold text-4xl sm:text-6xl md:text-7xl text-white light:text-slate-900 tracking-tight leading-none max-w-4xl">
          The Campus{' '}
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-[#8A2BE2] via-[#A78BFA] to-purple-400 light:from-purple-700 light:via-purple-600 light:to-indigo-600">
            Operating System
          </span>{' '}
          of the Future
        </h1>

        <p className="text-xs sm:text-base text-slate-300 light:text-slate-600 mt-6 max-w-2xl font-light leading-relaxed">
          IRIS 365 unifies administrative operations, cashless student wallets, live transit GPS, and AI concierge support into one multi-tenant cloud workspace.
        </p>

        {/* Action Button Group */}
        <div className="flex flex-col sm:flex-row items-center gap-4 mt-10 w-full sm:w-auto">
          <Link
            href="/request-demo"
            className="w-full sm:w-auto px-8 py-4 rounded-xl bg-gradient-to-r from-[#6C2BD9] to-[#8A2BE2] text-white font-bold text-xs uppercase tracking-wider shadow-xl shadow-[#8A2BE2]/20 hover:brightness-110 transition-all flex items-center justify-center gap-2 active:scale-95"
          >
            <Sparkles className="w-4 h-4" /> Request Demo
          </Link>
          <Link
            href="/home"
            className="w-full sm:w-auto px-8 py-4 rounded-xl bg-white/5 light:bg-white border border-white/10 light:border-slate-300 hover:bg-white/10 light:hover:bg-slate-100 text-white light:text-slate-900 font-semibold text-xs uppercase tracking-wider transition-all flex items-center justify-center gap-2 shadow-sm"
          >
            <GraduationCap className="w-4 h-4 text-purple-400 light:text-purple-600" /> Find Institution
          </Link>
        </div>
      </section>

      {/* Admissions Notice Banner */}
      <section className="relative z-10 px-6 py-6 max-w-6xl mx-auto w-full">
        <Link href="/home" className="block group">
          <div className="relative overflow-hidden rounded-2xl border border-[#8A2BE2]/30 light:border-purple-200 bg-gradient-to-r from-[#8A2BE2]/10 via-purple-500/10 to-[#6C2BD9]/10 light:from-purple-100/80 light:via-indigo-50/80 light:to-purple-100/80 px-8 py-6 flex flex-col md:flex-row items-center justify-between gap-4 hover:border-[#8A2BE2]/60 light:hover:border-purple-400 transition-all duration-300 shadow-md light:shadow-sm">
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 rounded-xl bg-gradient-to-tr from-[#6C2BD9] to-[#8A2BE2] flex items-center justify-center shadow-lg shadow-[#8A2BE2]/20 shrink-0">
                <GraduationCap className="w-6 h-6 text-white" />
              </div>
              <div>
                <div className="flex items-center gap-2 mb-0.5">
                  <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/15 border border-emerald-500/30 text-emerald-400 light:text-emerald-700 text-xs font-bold uppercase tracking-wider">
                    Admissions Open
                  </span>
                  <span className="text-xs font-mono text-slate-400 light:text-slate-500 uppercase tracking-wider">2026–27 Academic Cycle</span>
                </div>
                <h3 className="font-heading font-bold text-white light:text-slate-900 text-base md:text-lg group-hover:text-purple-300 light:group-hover:text-purple-700 transition-colors">
                  Explore Partner Colleges & Apply Online
                </h3>
                <p className="text-xs text-slate-300 light:text-slate-600 mt-0.5">
                  Search partner institutions, review program details, and submit application files in one place.
                </p>
              </div>
            </div>
            <div className="flex items-center gap-2 shrink-0 px-6 py-3 rounded-xl bg-gradient-to-r from-[#6C2BD9] to-[#8A2BE2] text-white font-bold text-xs uppercase tracking-wider shadow-lg shadow-[#8A2BE2]/20 group-hover:brightness-110 transition-all">
              <span>Find Institution</span>
              <ChevronRight className="w-4 h-4" />
            </div>
          </div>
        </Link>
      </section>

      {/* Why IRIS Section */}
      <WhyIrisSection onChipClick={handleChipClick} />

      {/* Core Modules Showcase */}
      <section id="modules" className="relative z-10 px-6 py-20 bg-transparent border-y border-white/5 light:border-slate-200">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16 space-y-3">
            <h2 className="font-heading font-extrabold text-3xl md:text-4xl text-white light:text-slate-900">
              Complete Campus Operational Suite
            </h2>
            <p className="text-slate-300 light:text-slate-600 text-xs sm:text-sm max-w-lg mx-auto leading-relaxed">
              Every campus function managed seamlessly with role-based access control and multi-tenant security isolation.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {MODULES.map((mod, index) => {
              const IconComponent = mod.icon;
              return (
                <div
                  key={index}
                  className="rounded-2xl p-6 bg-white/5 light:bg-white border border-white/10 light:border-slate-200 hover:border-[#8A2BE2]/50 light:hover:border-purple-400 transition-all duration-300 group hover:-translate-y-1 light:shadow-sm"
                >
                  <div className="flex items-center justify-between mb-4">
                    <div
                      className={`w-10 h-10 rounded-xl bg-gradient-to-tr ${mod.color} flex items-center justify-center shadow-lg group-hover:scale-110 transition-transform`}
                    >
                      <IconComponent className="w-5 h-5 text-white" />
                    </div>
                    <span className="text-xs font-mono uppercase bg-white/5 light:bg-purple-100 border border-white/10 light:border-purple-200 text-purple-300 light:text-purple-700 px-2.5 py-1 rounded-md">
                      {mod.badge}
                    </span>
                  </div>
                  <h3 className="font-heading font-bold text-base text-white light:text-slate-900 group-hover:text-purple-300 light:group-hover:text-purple-700 transition-colors">
                    {mod.title}
                  </h3>
                  <p className="text-slate-300 light:text-slate-600 text-xs mt-2 leading-relaxed font-light">{mod.desc}</p>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* FAQ Section */}
      <section id="faq" className="relative z-10 px-6 py-20 bg-transparent border-t border-white/5 light:border-slate-200 w-full">
        <div className="max-w-4xl mx-auto">
          {/* Header */}
          <div className="text-center mb-12 space-y-2">
            <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-[#8A2BE2]/10 light:bg-purple-100 border border-[#8A2BE2]/30 light:border-purple-300 text-purple-300 light:text-purple-800 text-xs font-orbitron font-bold uppercase tracking-wider mb-2">
              <MessageSquare className="w-4 h-4 text-purple-400 light:text-purple-600" />
              <span>Institutional FAQ</span>
            </div>
            <h2 className="font-heading font-extrabold text-3xl md:text-4xl text-white light:text-slate-900">Frequently Asked Questions</h2>
            <p className="text-slate-300 light:text-slate-600 text-xs sm:text-sm font-sans">
              Find answers to platform deployment, security specifications, and licensing models.
            </p>
          </div>

          {/* Search and Category Filters */}
          <div className="flex flex-col gap-6 mb-10">
            <div className="relative">
              <input
                type="text"
                placeholder="Search questions or keywords..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full px-5 py-3.5 pl-12 rounded-2xl bg-white/5 light:bg-white border border-white/10 light:border-slate-300 text-xs text-white light:text-slate-900 placeholder-slate-400 light:placeholder-slate-500 outline-none focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10 transition-all duration-300 shadow-sm"
              />
              <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-4.5 h-4.5 text-slate-400 light:text-slate-500 pointer-events-none" />
            </div>

            {/* Category Pills */}
            <div className="flex flex-wrap gap-2 justify-center">
              {['All', 'Architecture', 'Security', 'Deployment', 'Modules', 'Support'].map((cat) => (
                <button
                  key={cat}
                  onClick={() => setSelectedCategory(cat)}
                  className={`px-4 py-2 rounded-full text-xs font-orbitron font-bold uppercase tracking-wider transition-all duration-300 ${
                    selectedCategory === cat
                      ? 'bg-gradient-to-r from-[#6C2BD9] to-[#8A2BE2] text-white border-transparent shadow-md shadow-[#8A2BE2]/20'
                      : 'bg-white/5 light:bg-white border border-white/10 light:border-slate-200 text-slate-300 light:text-slate-700 hover:bg-white/10 light:hover:bg-slate-100 hover:text-white light:hover:text-slate-900'
                  }`}
                >
                  {cat}
                </button>
              ))}
            </div>
          </div>

          {/* FAQ Accordion List */}
          <div className="flex flex-col gap-4">
            <AnimatePresence>
              {filteredFaqs.length > 0 ? (
                filteredFaqs.map((faq) => {
                  const isExpanded = expandedFaqId === faq.id;
                  return (
                    <MotionDiv
                      key={faq.id}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ duration: 0.3 }}
                      className="rounded-2xl border border-white/10 light:border-slate-200 bg-[#090117]/80 light:bg-white hover:border-[#8A2BE2]/40 light:hover:border-purple-400 overflow-hidden transition-all duration-300 light:shadow-sm"
                    >
                      <button
                        onClick={() => setExpandedFaqId(isExpanded ? null : faq.id)}
                        className="w-full px-6 py-5 flex items-center justify-between text-left gap-4"
                      >
                        <div className="flex flex-col gap-1.5 text-left">
                          <span className="text-xs font-mono uppercase bg-white/5 light:bg-purple-100 border border-white/10 light:border-purple-200 text-purple-300 light:text-purple-800 px-2.5 py-0.5 rounded self-start tracking-wider">
                            {faq.category}
                          </span>
                          <span className="font-heading font-bold text-white light:text-slate-900 text-xs sm:text-sm tracking-wide mt-1">
                            {faq.question}
                          </span>
                        </div>
                        <div
                          className={`w-7 h-7 rounded-full bg-white/5 light:bg-slate-100 flex items-center justify-center text-slate-300 light:text-slate-600 transition-transform duration-300 shrink-0 ${
                            isExpanded ? 'rotate-180 text-white light:text-slate-900' : ''
                          }`}
                        >
                          <ChevronDown className="w-4 h-4" />
                        </div>
                      </button>

                      <AnimatePresence initial={false}>
                        {isExpanded && (
                          <MotionDiv
                            initial={{ height: 0, opacity: 0 }}
                            animate={{ height: 'auto', opacity: 1 }}
                            exit={{ height: 0, opacity: 0 }}
                            transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
                          >
                            <div className="px-6 pb-6 text-xs text-slate-300 light:text-slate-600 leading-relaxed font-sans border-t border-white/5 light:border-slate-200 pt-4">
                              {faq.answer}
                            </div>
                          </MotionDiv>
                        )}
                      </AnimatePresence>
                    </MotionDiv>
                  );
                })
              ) : (
                <div className="text-center py-12 px-6 rounded-2xl border border-white/10 light:border-slate-200 bg-white/5 light:bg-white space-y-3">
                  <p className="text-xs text-slate-300 light:text-slate-600 font-medium">No matching questions found for your query.</p>
                  <button
                    onClick={() => {
                      setSearchQuery('');
                      setSelectedCategory('All');
                    }}
                    className="px-4 py-2 rounded-xl bg-white/10 light:bg-slate-100 hover:bg-white/15 light:hover:bg-slate-200 border border-white/10 light:border-slate-300 text-xs font-bold text-white light:text-slate-900 uppercase tracking-wider transition-all"
                  >
                    Clear Filters & Search
                  </button>
                </div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </section>

      {/* Floating Sticky CTA Button on Scroll */}
      {showStickyCta && (
        <div className="fixed bottom-6 right-6 z-40 transition-all duration-300 animate-bounce">
          <Link
            href="/request-demo"
            className="px-5 py-3 rounded-full bg-gradient-to-r from-[#6C2BD9] to-[#8A2BE2] text-white font-bold text-xs uppercase tracking-wider shadow-2xl shadow-[#8A2BE2]/40 flex items-center gap-2 border border-purple-400/30 hover:scale-105 active:scale-95 transition-transform"
          >
            <Sparkles className="w-4 h-4" />
            <span>Request Demo</span>
          </Link>
        </div>
      )}

      {/* Footer */}
      <Footer />
    </div>
  );
}
