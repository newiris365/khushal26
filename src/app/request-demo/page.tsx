'use client';

import React, { useState, useEffect, Suspense } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { motion, AnimatePresence } from 'framer-motion';
import Header from '../../components/Header';
import Footer from '../../components/Footer';
import {
  Check,
  Sparkles,
  AlertCircle,
  Shield,
  Cpu,
  Zap,
  Lock,
  Building2,
  Mail,
  Phone,
  RefreshCw,
  Home,
  Clock,
  Layers,
  Users,
  CheckCircle2
} from 'lucide-react';

interface FormValues {
  firstName: string;
  lastName: string;
  contactNumber: string;
  email: string;
  institutionName: string;
  designation: string;
  institutionSize: string;
  additionalNotes: string;
}

function RequestDemoFormContent() {
  const searchParams = useSearchParams();
  const rawTier = searchParams.get('tier');
  const rawAccounts = searchParams.get('accounts');
  const rawCycle = searchParams.get('cycle');

  const [formValues, setFormValues] = useState<FormValues>({
    firstName: '',
    lastName: '',
    contactNumber: '',
    email: '',
    institutionName: '',
    designation: '',
    institutionSize: '500 - 1500',
    additionalNotes: ''
  });

  const [evaluationContext, setEvaluationContext] = useState<{
    tier?: string;
    accounts?: string;
    cycle?: string;
  } | null>(null);

  const [errors, setErrors] = useState<Record<string, string>>({});
  const [submitStatus, setSubmitStatus] = useState<'idle' | 'sending' | 'success'>('idle');
  const [submittedValues, setSubmittedValues] = useState<{
    firstName: string;
    lastName: string;
    email: string;
  } | null>(null);

  // Read URL query parameters passed from pricing page
  useEffect(() => {
    if (rawTier || rawAccounts || rawCycle) {
      const tierName = rawTier ? rawTier.charAt(0).toUpperCase() + rawTier.slice(1) : undefined;
      const cycleName = rawCycle ? rawCycle.charAt(0).toUpperCase() + rawCycle.slice(1) : undefined;
      const accountsCount = rawAccounts || undefined;

      setEvaluationContext({
        tier: tierName,
        accounts: accountsCount,
        cycle: cycleName
      });

      // Map accounts count to institutionSize dropdown
      let size = '500 - 1500';
      if (rawAccounts) {
        const count = parseInt(rawAccounts, 10);
        if (!isNaN(count)) {
          if (count < 500) size = '< 500';
          else if (count <= 1500) size = '500 - 1500';
          else if (count <= 5000) size = '1500 - 5000';
          else size = '5000+';
        }
      }

      // Pre-fill form values with evaluation context
      setFormValues((prev) => {
        const notesParts: string[] = [];
        if (tierName) notesParts.push(`${tierName} Plan`);
        if (cycleName) notesParts.push(`${cycleName} Billing`);
        if (accountsCount) notesParts.push(`~${accountsCount} accounts`);

        const autoNote = notesParts.length > 0 ? `Evaluating: ${notesParts.join(', ')}.` : '';

        return {
          ...prev,
          institutionSize: size,
          additionalNotes: prev.additionalNotes || autoNote
        };
      });
    }
  }, [rawTier, rawAccounts, rawCycle]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    const { name, value } = e.target;
    setFormValues((prev) => ({ ...prev, [name]: value }));

    if (errors[name]) {
      setErrors((prev) => ({ ...prev, [name]: '' }));
    }
  };

  const validate = () => {
    const tempErrors: Record<string, string> = {};
    if (!formValues.firstName.trim()) tempErrors.firstName = 'First name is required';
    if (!formValues.lastName.trim()) tempErrors.lastName = 'Last name is required';
    if (!formValues.contactNumber.trim()) tempErrors.contactNumber = 'Contact number is required';

    if (!formValues.email.trim()) {
      tempErrors.email = 'Work email is required';
    } else if (!/\S+@\S+\.\S+/.test(formValues.email)) {
      tempErrors.email = 'Invalid email format';
    }

    if (!formValues.institutionName.trim()) tempErrors.institutionName = 'Institution name is required';
    if (!formValues.designation) tempErrors.designation = 'Please select your designation';

    setErrors(tempErrors);
    return Object.keys(tempErrors).length === 0;
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (validate()) {
      setSubmitStatus('sending');

      // Simulate network request for 1.8 seconds
      setTimeout(() => {
        setSubmittedValues({
          firstName: formValues.firstName,
          lastName: formValues.lastName,
          email: formValues.email
        });
        setSubmitStatus('success');
      }, 1800);
    }
  };

  const handleReset = () => {
    setFormValues({
      firstName: '',
      lastName: '',
      contactNumber: '',
      email: '',
      institutionName: '',
      designation: '',
      institutionSize: '500 - 1500',
      additionalNotes: ''
    });
    setErrors({});
    setSubmitStatus('idle');
    setSubmittedValues(null);
  };

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-[#050010] text-slate-900 dark:text-slate-100 transition-colors duration-300 flex flex-col font-sans antialiased relative overflow-x-hidden pb-20">
      {/* Ambient Background Video */}
      <video
        autoPlay
        loop
        muted
        playsInline
        className="fixed inset-0 w-full h-full object-cover z-0 pointer-events-none opacity-40 mix-blend-screen"
        src="/bg-video.mp4"
      />

      {/* Cyber Mesh & Ambient Glows */}
      <div className="absolute inset-0 bg-[linear-gradient(rgba(138,43,226,0.03)_1px,transparent_1px),linear-gradient(90deg,rgba(138,43,226,0.03)_1px,transparent_1px)] bg-[size:40px_40px] pointer-events-none -z-10"></div>
      <div className="absolute w-[600px] h-[600px] rounded-full bg-[#8A2BE2]/8 blur-[130px] -top-80 -left-60 pointer-events-none -z-10"></div>
      <div className="absolute w-[800px] h-[800px] rounded-full bg-[#6C2BD9]/5 blur-[150px] top-[40%] right-[-10%] pointer-events-none -z-10"></div>

      {/* Navigation Header */}
      <Header />

      {/* Hero Section */}
      <section className="max-w-6xl mx-auto w-full px-6 pt-24 pb-12 text-center">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, ease: [0.16, 1, 0.3, 1] }}
          className="flex flex-col items-center"
        >
          {/* Eyebrow Badge */}
          <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-white/5 border border-white/10 backdrop-blur-md shadow-md mb-6">
            <Sparkles className="w-3.5 h-3.5 text-purple-400 animate-pulse" />
            <span className="text-xs font-orbitron font-bold tracking-widest text-purple-300 uppercase">
              ✨ CUSTOM TAILORED FOR YOUR INSTITUTION
            </span>
          </div>

          {/* Heading */}
          <h1 className="font-orbitron font-black text-4xl sm:text-5xl md:text-6xl text-slate-900 dark:text-white uppercase tracking-wider mb-6 leading-tight">
            Request a Demo of{' '}
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-[#6C2BD9] via-[#8A2BE2] to-purple-400 filter drop-shadow-[0_0_12px_rgba(138,43,226,0.3)]">
              IRIS 365
            </span>
          </h1>

          {/* Subtitle */}
          <p className="text-xs sm:text-sm text-slate-600 dark:text-slate-300 max-w-3xl leading-relaxed">
            Experience the complete institutional operating system before deployment. Explore modules, automation
            workflows, analytics, and AI-powered campus management tailored specifically for your institution.
          </p>
        </motion.div>
      </section>

      {/* 1-Month Free Trial / Demo Access Showcase Section */}
      <section className="max-w-4xl mx-auto w-full px-6 py-8">
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: [0.16, 1, 0.3, 1] }}
          className="p-6 sm:p-8 rounded-2xl bg-white dark:bg-[#090117]/80 border border-slate-200 dark:border-[#8A2BE2]/30 backdrop-blur-xl shadow-2xl relative overflow-hidden text-left"
        >
          {/* Corner Ambient Glow */}
          <div className="absolute top-0 right-0 w-64 h-64 rounded-full bg-gradient-to-br from-[#8A2BE2]/20 to-[#6C2BD9]/10 blur-3xl pointer-events-none -z-10" />

          <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-6 border-b border-slate-200 dark:border-white/10">
            <div>
              <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-purple-500/10 dark:bg-[#8A2BE2]/20 border border-purple-500/20 dark:border-[#8A2BE2]/40 text-purple-700 dark:text-purple-300 text-xs font-mono font-bold mb-2">
                <Clock className="w-3.5 h-3.5" />
                <span>30-Day Full Evaluation Period</span>
              </div>
              <h2 className="font-heading font-extrabold text-2xl text-slate-900 dark:text-white">
                1-Month Full-Access Demo Trial
              </h2>
              <p className="text-xs text-slate-600 dark:text-slate-300 mt-1 font-light">
                Get complete platform access for 30 days — no credit card required, zero commitment.
              </p>
            </div>
            <div className="shrink-0">
              <span className="px-4 py-2 rounded-xl bg-emerald-500/15 border border-emerald-500/30 text-emerald-600 dark:text-emerald-400 text-xs font-bold font-mono uppercase tracking-wider block text-center">
                100% Free Trial
              </span>
            </div>
          </div>

          {/* Feature Bullets Grid */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mt-6">
            <div className="flex items-start gap-3 p-3.5 rounded-xl bg-slate-50 dark:bg-white/5 border border-slate-200 dark:border-white/5">
              <Layers className="w-5 h-5 text-purple-600 dark:text-purple-400 shrink-0 mt-0.5" />
              <div>
                <h3 className="text-xs font-bold text-slate-900 dark:text-white uppercase tracking-wider font-mono">All 11 Core Modules Unlocked</h3>
                <p className="text-xs text-slate-600 dark:text-slate-300 mt-0.5 font-light">Explore Academics, Biometric Attendance, Canteen Wallet, Hostel, Transit, & AI Concierge.</p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3.5 rounded-xl bg-slate-50 dark:bg-white/5 border border-slate-200 dark:border-white/5">
              <Users className="w-5 h-5 text-purple-600 dark:text-purple-400 shrink-0 mt-0.5" />
              <div>
                <h3 className="text-xs font-bold text-slate-900 dark:text-white uppercase tracking-wider font-mono">Dedicated 1-on-1 Onboarding</h3>
                <p className="text-xs text-slate-600 dark:text-slate-300 mt-0.5 font-light">Custom staging setup and live guided walk-through for your administrative leadership team.</p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3.5 rounded-xl bg-slate-50 dark:bg-white/5 border border-slate-200 dark:border-white/5">
              <Zap className="w-5 h-5 text-purple-600 dark:text-purple-400 shrink-0 mt-0.5" />
              <div>
                <h3 className="text-xs font-bold text-slate-900 dark:text-white uppercase tracking-wider font-mono">Priority Engineering Support</h3>
                <p className="text-xs text-slate-600 dark:text-slate-300 mt-0.5 font-light">Direct support from our team to test integrations with your hardware scanners and GPS units.</p>
              </div>
            </div>

            <div className="flex items-start gap-3 p-3.5 rounded-xl bg-slate-50 dark:bg-white/5 border border-slate-200 dark:border-white/5">
              <CheckCircle2 className="w-5 h-5 text-purple-600 dark:text-purple-400 shrink-0 mt-0.5" />
              <div>
                <h3 className="text-xs font-bold text-slate-900 dark:text-white uppercase tracking-wider font-mono">Zero Commitment & Easy Export</h3>
                <p className="text-xs text-slate-600 dark:text-slate-300 mt-0.5 font-light">Evaluate risk-free for 30 days. Export all your data or transition seamlessly at Day 30.</p>
              </div>
            </div>
          </div>
        </motion.div>
      </section>

      {/* Demo Request Form Section */}
      <section className="max-w-4xl mx-auto w-full px-6 py-8">
        <AnimatePresence mode="wait">
          {submitStatus !== 'success' ? (
            <motion.div
              id="request-demo-form"
              initial={{ opacity: 0, scale: 0.98 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.98 }}
              transition={{ duration: 0.5 }}
              className="p-6 sm:p-10 rounded-2xl bg-white dark:bg-[#090117]/80 border border-slate-200 dark:border-[#8A2BE2]/30 backdrop-blur-xl shadow-2xl text-left"
            >
              {/* Form Heading */}
              <div className="text-center mb-8 space-y-2">
                <h2 className="font-heading font-extrabold text-2xl tracking-wider text-slate-900 dark:text-white uppercase">
                  REQUEST YOUR 1-MONTH TRIAL
                </h2>
                <p className="text-xs text-slate-600 dark:text-slate-300">
                  Fill in your institutional details below. Our team will prepare your trial workspace within 24 hours.
                </p>

                {/* Carried Evaluation Context Badge (from Pricing Page URL params) */}
                {evaluationContext && (
                  <div className="inline-flex items-center gap-2 px-4 py-2 rounded-xl bg-purple-500/10 border border-purple-500/30 text-purple-700 dark:text-purple-300 text-xs font-mono mt-3 shadow-sm">
                    <Sparkles className="w-4 h-4 text-purple-600 dark:text-purple-400 shrink-0" />
                    <span>
                      Evaluating Context:{' '}
                      <strong className="text-purple-900 dark:text-white font-bold">
                        {evaluationContext.tier ? `${evaluationContext.tier} Tier` : 'IRIS 365'}
                      </strong>
                      {evaluationContext.accounts && ` (${evaluationContext.accounts} accounts)`}
                      {evaluationContext.cycle && `, ${evaluationContext.cycle} Billing`}
                    </span>
                  </div>
                )}
              </div>

              {/* Input Form */}
              <form onSubmit={handleSubmit} className="flex flex-col gap-5">
                {/* 1. First & Last Names */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                      First Name *
                    </label>
                    <input
                      type="text"
                      name="firstName"
                      value={formValues.firstName}
                      onChange={handleChange}
                      placeholder="Harshvardhan"
                      className={`w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 ${
                        errors.firstName
                          ? 'border-[#EF4444] focus:ring-4 focus:ring-[#EF4444]/15'
                          : 'border-slate-200 dark:border-white/10 focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10'
                      }`}
                    />
                    {errors.firstName && (
                      <div className="flex items-center gap-1 mt-1 text-[#EF4444] text-xs">
                        <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                        <span>{errors.firstName}</span>
                      </div>
                    )}
                  </div>

                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                      Last Name *
                    </label>
                    <input
                      type="text"
                      name="lastName"
                      value={formValues.lastName}
                      onChange={handleChange}
                      placeholder="Purohit"
                      className={`w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 ${
                        errors.lastName
                          ? 'border-[#EF4444] focus:ring-4 focus:ring-[#EF4444]/15'
                          : 'border-slate-200 dark:border-white/10 focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10'
                      }`}
                    />
                    {errors.lastName && (
                      <div className="flex items-center gap-1 mt-1 text-[#EF4444] text-xs">
                        <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                        <span>{errors.lastName}</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* 2. Contact Number & Work Email */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                      Contact Number *
                    </label>
                    <div className="relative">
                      <input
                        type="text"
                        name="contactNumber"
                        value={formValues.contactNumber}
                        onChange={handleChange}
                        placeholder="+91 86190 19653"
                        className={`w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 ${
                          errors.contactNumber
                            ? 'border-[#EF4444] focus:ring-4 focus:ring-[#EF4444]/15'
                            : 'border-slate-200 dark:border-white/10 focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10'
                        }`}
                      />
                      <Phone className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
                    </div>
                    {errors.contactNumber && (
                      <div className="flex items-center gap-1 mt-1 text-[#EF4444] text-xs">
                        <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                        <span>{errors.contactNumber}</span>
                      </div>
                    )}
                  </div>

                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                      Work Email *
                    </label>
                    <div className="relative">
                      <input
                        type="email"
                        name="email"
                        value={formValues.email}
                        onChange={handleChange}
                        placeholder="newiris365@gmail.com"
                        className={`w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 ${
                          errors.email
                            ? 'border-[#EF4444] focus:ring-4 focus:ring-[#EF4444]/15'
                            : 'border-slate-200 dark:border-white/10 focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10'
                        }`}
                      />
                      <Mail className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
                    </div>
                    {errors.email && (
                      <div className="flex items-center gap-1 mt-1 text-[#EF4444] text-xs">
                        <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                        <span>{errors.email}</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* 3. Institution Name & Designation */}
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                      Institution Name *
                    </label>
                    <div className="relative">
                      <input
                        type="text"
                        name="institutionName"
                        value={formValues.institutionName}
                        onChange={handleChange}
                        placeholder="e.g. JIET Jodhpur"
                        className={`w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 ${
                          errors.institutionName
                            ? 'border-[#EF4444] focus:ring-4 focus:ring-[#EF4444]/15'
                            : 'border-slate-200 dark:border-white/10 focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10'
                        }`}
                      />
                      <Building2 className="absolute right-4 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 pointer-events-none" />
                    </div>
                    {errors.institutionName && (
                      <div className="flex items-center gap-1 mt-1 text-[#EF4444] text-xs">
                        <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                        <span>{errors.institutionName}</span>
                      </div>
                    )}
                  </div>

                  <div className="flex flex-col gap-1.5">
                    <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                      Designation *
                    </label>
                    <select
                      name="designation"
                      value={formValues.designation}
                      onChange={handleChange}
                      className={`w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 appearance-none ${
                        errors.designation
                          ? 'border-[#EF4444] focus:ring-4 focus:ring-[#EF4444]/15'
                          : 'border-slate-200 dark:border-white/10 focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10'
                      }`}
                      style={{
                        backgroundImage:
                          "url(\"data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 20 20'%3E%3Cpath stroke='%23888888' stroke-linecap='round' stroke-linejoin='round' stroke-width='1.5' d='M6 8l4 4 4-4'/%3E%3C/svg%3E\")",
                        backgroundPosition: 'right 1rem center',
                        backgroundRepeat: 'no-repeat',
                        backgroundSize: '1.25em auto',
                        paddingRight: '2.5rem'
                      }}
                    >
                      <option value="" disabled className="text-gray-900 bg-white">
                        Select Designation
                      </option>
                      <option value="Director" className="text-gray-900 bg-white">
                        Director / Trustee
                      </option>
                      <option value="Principal" className="text-gray-900 bg-white">
                        Principal / Vice-Chancellor
                      </option>
                      <option value="Administrator" className="text-gray-900 bg-white">
                        Campus Administrator
                      </option>
                      <option value="IT Manager" className="text-gray-900 bg-white">
                        IT & Systems Manager
                      </option>
                      <option value="Faculty" className="text-gray-900 bg-white">
                        Head of Department / Faculty
                      </option>
                      <option value="Other" className="text-gray-900 bg-white">
                        Other Representative
                      </option>
                    </select>
                    {errors.designation && (
                      <div className="flex items-center gap-1 mt-1 text-[#EF4444] text-xs">
                        <AlertCircle className="w-3.5 h-3.5 shrink-0" />
                        <span>{errors.designation}</span>
                      </div>
                    )}
                  </div>
                </div>

                {/* 4. Institution Size (Informational for Onboarding Sizing) */}
                <div className="flex flex-col gap-1.5">
                  <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                    Institution Size (For Onboarding Sizing)
                  </label>
                  <select
                    name="institutionSize"
                    value={formValues.institutionSize}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border border-slate-200 dark:border-white/10 text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 appearance-none focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10"
                    style={{
                      backgroundImage:
                        "url(\"data:image/svg+xml;charset=utf-8,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 20 20'%3E%3Cpath stroke='%23888888' stroke-linecap='round' stroke-linejoin='round' stroke-width='1.5' d='M6 8l4 4 4-4'/%3E%3C/svg%3E\")",
                      backgroundPosition: 'right 1rem center',
                      backgroundRepeat: 'no-repeat',
                      backgroundSize: '1.25em auto',
                      paddingRight: '2.5rem'
                    }}
                  >
                    <option value="< 500" className="text-gray-900 bg-white">
                      Small Campus (&lt; 500 students)
                    </option>
                    <option value="500 - 1500" className="text-gray-900 bg-white">
                      Medium Campus (500 – 1,500 students)
                    </option>
                    <option value="1500 - 5000" className="text-gray-900 bg-white">
                      Large Campus (1,500 – 5,000 students)
                    </option>
                    <option value="5000+" className="text-gray-900 bg-white">
                      Enterprise Campus (5,000+ students)
                    </option>
                  </select>
                </div>

                {/* 5. Additional Notes */}
                <div className="flex flex-col gap-1.5">
                  <label className="text-xs font-mono font-bold uppercase tracking-wider text-slate-700 dark:text-slate-300">
                    Specific Operational Focus / Custom Notes
                  </label>
                  <textarea
                    name="additionalNotes"
                    value={formValues.additionalNotes}
                    onChange={handleChange}
                    placeholder="Mention key areas of interest (e.g., Biometric Gate Pass, Canteen Wallet, Transport Telemetry, Academic Grading)..."
                    rows={4}
                    className="w-full px-4 py-2.5 rounded-xl bg-slate-50 dark:bg-white/5 border border-slate-200 dark:border-white/10 text-xs text-slate-900 dark:text-white placeholder-slate-400 outline-none transition-all duration-300 resize-none focus:border-[#8A2BE2] focus:ring-4 focus:ring-[#8A2BE2]/10"
                  />
                </div>

                {/* Submit Button */}
                <div className="mt-4">
                  <button
                    type="submit"
                    disabled={submitStatus === 'sending'}
                    className={`w-full py-4 rounded-xl text-xs font-bold font-orbitron uppercase tracking-wider flex items-center justify-center gap-2 transition-all duration-300 shadow-lg ${
                      submitStatus === 'sending'
                        ? 'bg-gradient-to-r from-[#6C2BD9] to-[#8A2BE2] text-white opacity-85 cursor-wait animate-pulse'
                        : 'bg-gradient-to-r from-[#6C2BD9] to-[#8A2BE2] hover:brightness-110 hover:scale-[1.01] active:scale-[0.99] text-white shadow-[#8A2BE2]/20'
                    }`}
                  >
                    {submitStatus === 'sending' ? (
                      <>
                        <RefreshCw className="w-4 h-4 text-white animate-spin" />
                        <span>Preparing Your Trial Workspace...</span>
                      </>
                    ) : (
                      <>
                        <Sparkles className="w-4 h-4 text-white" />
                        <span>Request 1-Month Free Trial</span>
                      </>
                    )}
                  </button>
                </div>
              </form>
            </motion.div>
          ) : (
            /* Success Confirmation State */
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ duration: 0.5 }}
              className="p-8 sm:p-12 rounded-2xl bg-white dark:bg-[#090117]/80 border border-emerald-500/30 backdrop-blur-xl shadow-2xl text-center flex flex-col items-center gap-6"
            >
              {/* Green Animated Success Icon */}
              <motion.div
                initial={{ scale: 0, rotate: -45 }}
                animate={{ scale: 1, rotate: 0 }}
                transition={{ type: 'spring', stiffness: 200, damping: 15 }}
                className="w-16 h-16 rounded-full bg-emerald-500/20 border border-emerald-500/40 flex items-center justify-center text-emerald-600 dark:text-emerald-400"
              >
                <Check className="w-8 h-8 stroke-[3px]" />
              </motion.div>

              <div>
                <h2 className="font-heading font-extrabold text-2xl tracking-wider text-emerald-600 dark:text-emerald-400 uppercase">
                  Trial Request Confirmed
                </h2>

                <div className="text-xs sm:text-sm text-slate-600 dark:text-slate-300 mt-5 space-y-4 max-w-xl mx-auto font-light leading-relaxed">
                  <p>
                    Thank you,{' '}
                    <strong className="text-slate-900 dark:text-white font-bold">
                      {submittedValues?.firstName} {submittedValues?.lastName}
                    </strong>
                    .
                  </p>
                  <p>
                    We've received your request for a{' '}
                    <strong className="text-purple-700 dark:text-purple-300 font-bold">1-Month Full-Access IRIS 365 Trial</strong>.
                  </p>
                  <p>
                    Our campus onboarding team will contact you at{' '}
                    <strong className="text-slate-900 dark:text-white font-semibold underline">{submittedValues?.email}</strong> within 24 hours to provision your dedicated evaluation environment.
                  </p>
                </div>
              </div>

              {/* Action Buttons */}
              <div className="flex flex-col sm:flex-row items-center gap-4 mt-6 w-full justify-center">
                <button
                  onClick={handleReset}
                  className="w-full sm:w-auto px-6 py-3 rounded-full border border-slate-200 dark:border-white/10 hover:bg-slate-100 dark:hover:bg-white/5 text-xs font-bold font-orbitron uppercase tracking-wider transition-all"
                >
                  Submit Another Request
                </button>
                <Link
                  href="/"
                  className="w-full sm:w-auto px-6 py-3 rounded-full bg-gradient-to-r from-[#6C2BD9] to-[#8A2BE2] text-white hover:brightness-110 text-xs font-bold font-orbitron uppercase tracking-wider transition-all flex items-center justify-center gap-2"
                >
                  <Home className="w-4 h-4" />
                  <span>Return Home</span>
                </Link>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </section>

      {/* Trust & Compliance Section */}
      <section className="max-w-6xl mx-auto w-full px-6 py-12">
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          {/* Card 1 */}
          <div className="p-6 rounded-2xl bg-white dark:bg-white/5 border border-slate-200 dark:border-white/10 backdrop-blur-xl shadow-md text-left flex flex-col gap-4">
            <div className="w-9 h-9 rounded-xl bg-purple-500/10 border border-purple-500/20 dark:border-[#8A2BE2]/30 flex items-center justify-center text-purple-700 dark:text-purple-300">
              <Shield className="w-4 h-4" />
            </div>
            <div>
              <h4 className="font-orbitron font-bold text-xs uppercase tracking-wider text-slate-900 dark:text-white">
                ISO 27001 Certified
              </h4>
              <p className="text-xs text-slate-600 dark:text-slate-300 mt-1 leading-normal font-light">
                Enterprise security metrics auditing mapped across compliance bounds.
              </p>
            </div>
          </div>

          {/* Card 2 */}
          <div className="p-6 rounded-2xl bg-white dark:bg-white/5 border border-slate-200 dark:border-white/10 backdrop-blur-xl shadow-md text-left flex flex-col gap-4">
            <div className="w-9 h-9 rounded-xl bg-purple-500/10 border border-purple-500/20 dark:border-[#8A2BE2]/30 flex items-center justify-center text-purple-700 dark:text-purple-300">
              <Cpu className="w-4 h-4" />
            </div>
            <div>
              <h4 className="font-orbitron font-bold text-xs uppercase tracking-wider text-slate-900 dark:text-white">
                AI Powered Automation
              </h4>
              <p className="text-xs text-slate-600 dark:text-slate-300 mt-1 leading-normal font-light">
                Llama-3 semantic maps and pgvector retrieval handlers integrated.
              </p>
            </div>
          </div>

          {/* Card 3 */}
          <div className="p-6 rounded-2xl bg-white dark:bg-white/5 border border-slate-200 dark:border-white/10 backdrop-blur-xl shadow-md text-left flex flex-col gap-4">
            <div className="w-9 h-9 rounded-xl bg-purple-500/10 border border-purple-500/20 dark:border-[#8A2BE2]/30 flex items-center justify-center text-purple-700 dark:text-purple-300">
              <Zap className="w-4 h-4" />
            </div>
            <div>
              <h4 className="font-orbitron font-bold text-xs uppercase tracking-wider text-slate-900 dark:text-white">
                Instant API Onboarding
              </h4>
              <p className="text-xs text-slate-600 dark:text-slate-300 mt-1 leading-normal font-light">
                Stateless webhook endpoints sync client directories instantaneously.
              </p>
            </div>
          </div>

          {/* Card 4 */}
          <div className="p-6 rounded-2xl bg-white dark:bg-white/5 border border-slate-200 dark:border-white/10 backdrop-blur-xl shadow-md text-left flex flex-col gap-4">
            <div className="w-9 h-9 rounded-xl bg-purple-500/10 border border-purple-500/20 dark:border-[#8A2BE2]/30 flex items-center justify-center text-purple-700 dark:text-purple-300">
              <Lock className="w-4 h-4" />
            </div>
            <div>
              <h4 className="font-orbitron font-bold text-xs uppercase tracking-wider text-slate-900 dark:text-white">
                Zero Vendor Lock-in
              </h4>
              <p className="text-xs text-slate-600 dark:text-slate-300 mt-1 leading-normal font-light">
                Open schema exports and standard SQL structures assure database portability.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer Section */}
      <Footer />
    </div>
  );
}

export default function RequestDemoPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-slate-50 dark:bg-[#050010]" />}>
      <RequestDemoFormContent />
    </Suspense>
  );
}
