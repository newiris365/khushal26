'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import {
  Phone,
  KeyRound,
  CreditCard,
  Building2,
  Link2,
  CheckCircle,
  AlertCircle,
  Loader2,
  Search,
  Sparkles,
  ArrowRight,
  ShieldCheck,
  MapPin,
  School,
  GraduationCap,
  ArrowLeft
} from 'lucide-react';

interface Institution {
  id: string;
  name: string;
  type?: string;
  institute_type?: string;
  city?: string;
  state?: string;
  address?: string;
  logo_url?: string;
}

export default function ParentOnboardingPage() {
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);

  // Step 1 State: Phone & OTP
  const [phone, setPhone] = useState('');
  const [name, setName] = useState('');
  const [otp, setOtp] = useState('');
  const [otpSent, setOtpSent] = useState(false);
  const [devOtp, setDevOtp] = useState<string | null>(null);

  // Auth State
  const [jwtToken, setJwtToken] = useState<string | null>(null);
  const [parentUser, setParentUser] = useState<any | null>(null);

  // Step 2 State: Platform Fee Payment
  const [paymentDone, setPaymentDone] = useState(false);
  const [paymentId, setPaymentId] = useState<string | null>(null);

  // Step 3 State: Institute Picker
  const [institutions, setInstitutions] = useState<Institution[]>([]);
  const [cities, setCities] = useState<string[]>([]);
  const [loadingInstitutions, setLoadingInstitutions] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<'all' | 'college' | 'school'>('all');
  const [selectedCity, setSelectedCity] = useState<string>('all');
  const [selectedInstitution, setSelectedInstitution] = useState<Institution | null>(null);

  // Step 4 State: Link Student
  const [rollNumber, setRollNumber] = useState('');
  const [childDob, setChildDob] = useState('');
  const [linkedStudentName, setLinkedStudentName] = useState<string | null>(null);

  // UI General State
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Load Razorpay script dynamically
  useEffect(() => {
    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    document.body.appendChild(script);
    return () => {
      if (document.body.contains(script)) {
        document.body.removeChild(script);
      }
    };
  }, []);

  // Fetch Public Institutions for Step 3
  useEffect(() => {
    if (step === 3) {
      fetchInstitutions();
    }
  }, [step, typeFilter, selectedCity]);

  const fetchInstitutions = async () => {
    setLoadingInstitutions(true);
    try {
      let url = `/api/institutions/public?type=${typeFilter}`;
      if (selectedCity && selectedCity !== 'all') {
        url += `&city=${encodeURIComponent(selectedCity)}`;
      }
      const res = await fetch(url);
      const data = await res.json();
      if (res.ok && data.institutions) {
        setInstitutions(data.institutions);
        if (data.cities && data.cities.length > 0) {
          setCities(data.cities);
        }
      }
    } catch {
      // Ignore network errors
    } finally {
      setLoadingInstitutions(false);
    }
  };

  // Step 1 Handler: Send OTP
  const handleSendOtp = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!phone || phone.trim().length < 8) {
      setError('Please enter a valid 10-digit phone number.');
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/parent-onboarding/send-otp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone: phone.trim() })
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to send verification code.');
      }
      setOtpSent(true);
      if (data.dev_otp) {
        setDevOtp(data.dev_otp);
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred sending OTP.');
    } finally {
      setLoading(false);
    }
  };

  // Step 1 Handler: Verify OTP & Login Parent
  const handleVerifyOtp = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!otp || otp.trim().length < 4) {
      setError('Please enter the 6-digit OTP code.');
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/parent-onboarding/verify-otp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone: phone.trim(), otp: otp.trim(), name: name.trim() })
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Verification failed. Please check your code.');
      }
      if (typeof window !== 'undefined' && data.token) {
        localStorage.setItem('iris_jwt_token', data.token);
      }
      setJwtToken(data.token);
      setParentUser(data.user);
      setStep(2);
    } catch (err: any) {
      setError(err.message || 'Verification failed.');
    } finally {
      setLoading(false);
    }
  };

  // Step 2 Handler: Pay ₹150 Platform Onboarding Access Fee
  const handlePayPlatformFee = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/parent-onboarding/create-order', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: jwtToken ? `Bearer ${jwtToken}` : ''
        },
        body: JSON.stringify({ parent_user_id: parentUser?.id })
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to initialize payment.');
      }

      // Check if Razorpay SDK is available and not in mock mode
      if (typeof window !== 'undefined' && (window as any).Razorpay && data.key_id !== 'rzp_test_mock') {
        const options = {
          key: data.key_id,
          amount: data.amount_paise,
          currency: 'INR',
          name: 'IRIS 365 Platform',
          description: 'Parent Portal One-Time Access Fee (₹150)',
          order_id: data.order_id,
          handler: (response: any) => {
            setPaymentId(response.razorpay_payment_id || `pay_mock_${Date.now()}`);
            setPaymentDone(true);
            setStep(3);
          },
          prefill: {
            name: parentUser?.name || name,
            contact: phone
          },
          theme: {
            color: '#6C2BD9'
          }
        };
        const rzp = new (window as any).Razorpay(options);
        rzp.on('payment.failed', (resp: any) => {
          setError(`Payment failed: ${resp.error.description}`);
          setLoading(false);
        });
        rzp.open();
      } else {
        // Mock fallback for test environment or unconfigured Razorpay keys
        const mockPayId = `pay_mock_${Date.now()}`;
        setPaymentId(mockPayId);
        setPaymentDone(true);
        setStep(3);
      }
    } catch (err: any) {
      setError(err.message || 'Payment processing failed.');
    } finally {
      setLoading(false);
    }
  };

  // Step 4 Handler: Link Student to Parent
  const handleLinkStudent = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedInstitution) {
      setError('Please select an institution first.');
      setStep(3);
      return;
    }
    if (!rollNumber || !childDob) {
      setError("Please provide your child's Roll Number/ID and Date of Birth.");
      return;
    }

    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/parent-onboarding/link-student', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: jwtToken ? `Bearer ${jwtToken}` : ''
        },
        body: JSON.stringify({
          institution_id: selectedInstitution.id,
          student_roll_or_id: rollNumber.trim(),
          dob: childDob.trim(),
          parent_user_id: parentUser?.id
        })
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to link student.');
      }

      setLinkedStudentName(data.student_name || rollNumber);
    } catch (err: any) {
      setError(err.message || 'Linking failed.');
    } finally {
      setLoading(false);
    }
  };

  const filteredInstitutions = institutions.filter((inst) => {
    if (!searchQuery) return true;
    const q = searchQuery.toLowerCase();
    return (
      inst.name.toLowerCase().includes(q) ||
      (inst.city && inst.city.toLowerCase().includes(q)) ||
      (inst.state && inst.state.toLowerCase().includes(q))
    );
  });

  return (
    <main className="min-h-screen bg-[#0D0A1A] text-white p-4 md:p-8 font-sans">
      <div className="max-w-2xl mx-auto space-y-8">
        {/* Top Back Navigation Bar */}
        <div className="flex items-center justify-between">
          <Link
            href="/login?tab=parent"
            className="text-xs text-[#A78BFA] hover:text-white font-semibold flex items-center gap-1.5 transition-colors"
          >
            <ArrowLeft className="w-4 h-4" />
            <span>Back to Login</span>
          </Link>
          {step > 1 && (
            <button
              type="button"
              onClick={() => {
                setStep((s) => (s - 1) as any);
                setError(null);
              }}
              className="text-xs text-[#C4B5FD]/70 hover:text-white font-mono flex items-center gap-1"
            >
              <span>← Previous Step</span>
            </button>
          )}
        </div>

        {/* Top Branding Header */}
        <div className="text-center space-y-3">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[#6C2BD9]/20 border border-[#6C2BD9]/40 text-[#A78BFA] font-mono text-xs uppercase font-bold">
            <Sparkles className="w-3.5 h-3.5" />
            Self-Serve Parent Portal Onboarding
          </div>
          <h1 className="font-heading font-extrabold text-3xl md:text-4xl text-white">
            Connect to Your Child&apos;s School
          </h1>
          <p className="text-xs text-[#C4B5FD]/70 max-w-md mx-auto">
            Direct, institute-agnostic parent registration. Register once, pay a one-time ₹150 access fee, and link to
            any partner institution.
          </p>
        </div>

        {/* 4-Step Progress Indicator */}
        <div className="glass-panel p-4 rounded-2xl border border-white/5 grid grid-cols-4 gap-2 text-center font-mono text-[11px]">
          <div
            className={`p-2 rounded-xl border ${step === 1 ? 'bg-[#6C2BD9]/30 border-[#8B5CF6] text-white font-bold' : step > 1 ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'bg-white/5 border-transparent text-[#C4B5FD]/40'}`}
          >
            <span>1. Verify OTP</span>
          </div>
          <div
            className={`p-2 rounded-xl border ${step === 2 ? 'bg-[#6C2BD9]/30 border-[#8B5CF6] text-white font-bold' : step > 2 ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'bg-white/5 border-transparent text-[#C4B5FD]/40'}`}
          >
            <span>2. ₹150 Access Fee</span>
          </div>
          <div
            className={`p-2 rounded-xl border ${step === 3 ? 'bg-[#6C2BD9]/30 border-[#8B5CF6] text-white font-bold' : step > 3 ? 'bg-emerald-500/10 border-emerald-500/30 text-emerald-400' : 'bg-white/5 border-transparent text-[#C4B5FD]/40'}`}
          >
            <span>3. Select Institute</span>
          </div>
          <div
            className={`p-2 rounded-xl border ${step === 4 ? 'bg-[#6C2BD9]/30 border-[#8B5CF6] text-white font-bold' : 'bg-white/5 border-transparent text-[#C4B5FD]/40'}`}
          >
            <span>4. Link Child</span>
          </div>
        </div>

        {/* Error Alert Banner */}
        {error && (
          <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* STEP 1: Phone & OTP Verification */}
        {step === 1 && (
          <div className="glass-panel p-6 md:p-8 rounded-3xl border border-white/5 space-y-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#6C2BD9]/20 border border-[#6C2BD9]/30 flex items-center justify-center">
                <Phone className="w-5 h-5 text-[#A78BFA]" />
              </div>
              <div>
                <h2 className="font-heading font-bold text-lg text-white">Step 1: Mobile Verification</h2>
                <p className="text-xs text-[#C4B5FD]/60">
                  Enter your official mobile number to receive a verification code
                </p>
              </div>
            </div>

            {!otpSent ? (
              <form onSubmit={handleSendOtp} className="space-y-4">
                <div>
                  <label className="text-[11px] font-bold text-[#C4B5FD]/70 uppercase tracking-wider font-mono block mb-1">
                    Your Full Name (Optional)
                  </label>
                  <input
                    type="text"
                    placeholder="e.g. Ramesh Sharma"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    className="w-full bg-[#13102A] border border-[#6C2BD9]/30 rounded-xl px-4 py-3 text-sm text-white outline-none focus:border-[#8B5CF6] placeholder-[#C4B5FD]/40"
                  />
                </div>

                <div>
                  <label className="text-[11px] font-bold text-[#C4B5FD]/70 uppercase tracking-wider font-mono block mb-1">
                    Mobile Phone Number *
                  </label>
                  <div className="relative">
                    <Phone className="w-4 h-4 text-[#C4B5FD]/50 absolute left-4 top-3.5" />
                    <input
                      type="tel"
                      required
                      placeholder="+91 98765 43210"
                      value={phone}
                      onChange={(e) => setPhone(e.target.value)}
                      className="w-full bg-[#13102A] border border-[#6C2BD9]/30 rounded-xl py-3 pl-11 pr-4 text-sm text-white outline-none focus:border-[#8B5CF6] placeholder-[#C4B5FD]/40"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full py-3.5 rounded-xl bg-[#6C2BD9] hover:bg-[#5B21B6] disabled:opacity-50 text-white font-bold text-sm flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#6C2BD9]/20"
                >
                  {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <ArrowRight className="w-4 h-4" />}
                  <span>Send Verification Code</span>
                </button>
              </form>
            ) : (
              <form onSubmit={handleVerifyOtp} className="space-y-4">
                <div className="p-3 rounded-xl bg-[#6C2BD9]/10 border border-[#6C2BD9]/20 text-xs text-[#C4B5FD] flex items-center justify-between">
                  <span>
                    Code sent to <strong className="text-white">{phone}</strong>
                  </span>
                  <button
                    type="button"
                    onClick={() => {
                      setOtpSent(false);
                      setError(null);
                    }}
                    className="text-[10px] text-[#A78BFA] underline"
                  >
                    Change Phone
                  </button>
                </div>

                {devOtp && (
                  <div className="p-2.5 rounded-xl bg-amber-500/10 border border-amber-500/20 text-amber-300 font-mono text-xs">
                    Dev Test Code: <strong>{devOtp}</strong>
                  </div>
                )}

                <div>
                  <label className="text-[11px] font-bold text-[#C4B5FD]/70 uppercase tracking-wider font-mono block mb-1">
                    Enter 6-Digit OTP Code *
                  </label>
                  <div className="relative">
                    <KeyRound className="w-4 h-4 text-[#C4B5FD]/50 absolute left-4 top-3.5" />
                    <input
                      type="text"
                      required
                      maxLength={6}
                      placeholder="123456"
                      value={otp}
                      onChange={(e) => setOtp(e.target.value)}
                      className="w-full bg-[#13102A] border border-[#6C2BD9]/30 rounded-xl py-3 pl-11 pr-4 text-lg font-mono tracking-widest text-white outline-none focus:border-[#8B5CF6] placeholder-[#C4B5FD]/30 text-center"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full py-3.5 rounded-xl bg-[#6C2BD9] hover:bg-[#5B21B6] disabled:opacity-50 text-white font-bold text-sm flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#6C2BD9]/20"
                >
                  {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle className="w-4 h-4" />}
                  <span>Verify Code & Continue</span>
                </button>
              </form>
            )}
          </div>
        )}

        {/* STEP 2: ₹150 One-Time Platform Access Fee Payment */}
        {step === 2 && (
          <div className="glass-panel p-6 md:p-8 rounded-3xl border border-white/5 space-y-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#6C2BD9]/20 border border-[#6C2BD9]/30 flex items-center justify-center">
                <CreditCard className="w-5 h-5 text-[#A78BFA]" />
              </div>
              <div>
                <h2 className="font-heading font-bold text-lg text-white">Step 2: Platform Access Fee</h2>
                <p className="text-xs text-[#C4B5FD]/60">
                  One-time registration fee for direct self-serve parent portal access
                </p>
              </div>
            </div>

            <div className="p-5 rounded-2xl bg-[#13102A] border border-[#6C2BD9]/30 space-y-4">
              <div className="flex justify-between items-center pb-3 border-b border-[#6C2BD9]/20 font-mono text-xs">
                <span className="text-[#C4B5FD]/70">Account Holder:</span>
                <span className="text-white font-bold">{parentUser?.name || name || phone}</span>
              </div>
              <div className="flex justify-between items-center pb-3 border-b border-[#6C2BD9]/20 font-mono text-xs">
                <span className="text-[#C4B5FD]/70">Platform Fee Description:</span>
                <span className="text-white">Lifetime Parent Access Pass</span>
              </div>
              <div className="flex justify-between items-center font-mono text-sm pt-1">
                <span className="text-[#C4B5FD]/70">Total Fee Payable:</span>
                <span className="text-[#A78BFA] font-extrabold text-xl">₹150.00</span>
              </div>
            </div>

            <div className="space-y-2 text-xs text-[#C4B5FD]/70 font-mono">
              <div className="flex items-center gap-2">
                <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>Self-serve institution linking & real-time child tracking</span>
              </div>
              <div className="flex items-center gap-2">
                <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>Encrypted & secure Razorpay payment checkout</span>
              </div>
            </div>

            <button
              onClick={handlePayPlatformFee}
              disabled={loading}
              className="w-full py-4 rounded-xl bg-[#6C2BD9] hover:bg-[#5B21B6] disabled:opacity-50 text-white font-extrabold text-sm flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#6C2BD9]/30"
            >
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <CreditCard className="w-5 h-5" />}
              <span>Pay ₹150 & Select Institution</span>
            </button>
          </div>
        )}

        {/* STEP 3: Searchable Institute Picker */}
        {step === 3 && (
          <div className="glass-panel p-6 md:p-8 rounded-3xl border border-white/5 space-y-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#6C2BD9]/20 border border-[#6C2BD9]/30 flex items-center justify-center">
                <Building2 className="w-5 h-5 text-[#A78BFA]" />
              </div>
              <div>
                <h2 className="font-heading font-bold text-lg text-white">
                  Step 3: Select Your Child&apos;s Institution
                </h2>
                <p className="text-xs text-[#C4B5FD]/60">Pick your school or college from our partner network</p>
              </div>
            </div>

            {/* Filter & Search Bar */}
            <div className="space-y-3">
              <div className="relative">
                <Search className="w-4 h-4 text-[#C4B5FD]/50 absolute left-4 top-3.5" />
                <input
                  type="text"
                  placeholder="Search by school/college name or city..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full bg-[#13102A] border border-[#6C2BD9]/30 rounded-xl py-3 pl-11 pr-4 text-sm text-white outline-none focus:border-[#8B5CF6] placeholder-[#C4B5FD]/40 font-mono"
                />
              </div>

              {/* Type Filter Chips */}
              <div className="flex flex-wrap gap-2 items-center text-xs font-mono">
                <span className="text-[#C4B5FD]/60 pr-1">Type:</span>
                <button
                  type="button"
                  onClick={() => setTypeFilter('all')}
                  className={`px-3 py-1 rounded-lg border transition-all ${typeFilter === 'all' ? 'bg-[#6C2BD9] border-[#8B5CF6] text-white font-bold' : 'bg-[#13102A] border-[#6C2BD9]/30 text-[#C4B5FD]/70 hover:bg-[#6C2BD9]/20'}`}
                >
                  All Types
                </button>
                <button
                  type="button"
                  onClick={() => setTypeFilter('school')}
                  className={`px-3 py-1 rounded-lg border flex items-center gap-1 transition-all ${typeFilter === 'school' ? 'bg-[#6C2BD9] border-[#8B5CF6] text-white font-bold' : 'bg-[#13102A] border-[#6C2BD9]/30 text-[#C4B5FD]/70 hover:bg-[#6C2BD9]/20'}`}
                >
                  <School className="w-3.5 h-3.5" />
                  Schools
                </button>
                <button
                  type="button"
                  onClick={() => setTypeFilter('college')}
                  className={`px-3 py-1 rounded-lg border flex items-center gap-1 transition-all ${typeFilter === 'college' ? 'bg-[#6C2BD9] border-[#8B5CF6] text-white font-bold' : 'bg-[#13102A] border-[#6C2BD9]/30 text-[#C4B5FD]/70 hover:bg-[#6C2BD9]/20'}`}
                >
                  <GraduationCap className="w-3.5 h-3.5" />
                  Colleges
                </button>
              </div>

              {/* City Filter Chips */}
              {cities.length > 0 && (
                <div className="flex flex-wrap gap-2 items-center text-xs font-mono pt-1">
                  <span className="text-[#C4B5FD]/60 pr-1">City:</span>
                  <button
                    type="button"
                    onClick={() => setSelectedCity('all')}
                    className={`px-2.5 py-0.5 rounded-md border text-[11px] transition-all ${selectedCity === 'all' ? 'bg-indigo-600 border-indigo-400 text-white' : 'bg-[#13102A] border-[#6C2BD9]/20 text-[#C4B5FD]/60'}`}
                  >
                    All Cities
                  </button>
                  {cities.slice(0, 8).map((city) => (
                    <button
                      key={city}
                      type="button"
                      onClick={() => setSelectedCity(city)}
                      className={`px-2.5 py-0.5 rounded-md border text-[11px] transition-all ${selectedCity === city ? 'bg-indigo-600 border-indigo-400 text-white' : 'bg-[#13102A] border-[#6C2BD9]/20 text-[#C4B5FD]/60'}`}
                    >
                      {city}
                    </button>
                  ))}
                </div>
              )}
            </div>

            {/* Institution Cards Grid */}
            {loadingInstitutions ? (
              <div className="py-12 text-center text-[#C4B5FD]/50 font-mono text-xs flex flex-col items-center gap-2">
                <Loader2 className="w-6 h-6 animate-spin text-[#A78BFA]" />
                <span>Loading partner institutions...</span>
              </div>
            ) : filteredInstitutions.length === 0 ? (
              <div className="py-12 text-center text-[#C4B5FD]/60 font-mono text-xs p-6 bg-[#13102A] rounded-2xl border border-white/5">
                No institution found matching your search. Please check your query or filter.
              </div>
            ) : (
              <div className="grid grid-cols-1 gap-3 max-h-80 overflow-y-auto pr-1">
                {filteredInstitutions.map((inst) => {
                  const isSelected = selectedInstitution?.id === inst.id;
                  return (
                    <div
                      key={inst.id}
                      onClick={() => {
                        setSelectedInstitution(inst);
                        setStep(4);
                        setError(null);
                      }}
                      className={`p-4 rounded-2xl border transition-all cursor-pointer flex items-center justify-between gap-4 ${isSelected ? 'bg-[#6C2BD9]/30 border-[#8B5CF6] shadow-md shadow-[#6C2BD9]/20' : 'bg-[#13102A] border-[#6C2BD9]/20 hover:border-[#6C2BD9]/60'}`}
                    >
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-xl bg-[#6C2BD9]/20 border border-[#6C2BD9]/30 flex items-center justify-center font-bold text-white uppercase text-sm shrink-0">
                          {inst.institute_type === 'school' ? (
                            <School className="w-5 h-5 text-[#A78BFA]" />
                          ) : (
                            <Building2 className="w-5 h-5 text-[#A78BFA]" />
                          )}
                        </div>
                        <div>
                          <h4 className="font-heading font-bold text-sm text-white">{inst.name}</h4>
                          <div className="flex items-center gap-2 text-[11px] text-[#C4B5FD]/60 font-mono mt-0.5">
                            {inst.city && (
                              <span className="flex items-center gap-1">
                                <MapPin className="w-3 h-3 text-[#A78BFA]" /> {inst.city}
                                {inst.state ? `, ${inst.state}` : ''}
                              </span>
                            )}
                            <span className="uppercase text-[10px] px-1.5 py-0.5 rounded bg-white/5 border border-white/10 text-[#C4B5FD]">
                              {inst.institute_type || 'Institution'}
                            </span>
                          </div>
                        </div>
                      </div>
                      <ArrowRight className="w-4 h-4 text-[#A78BFA] shrink-0" />
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* STEP 4: Link Student Form */}
        {step === 4 && (
          <div className="glass-panel p-6 md:p-8 rounded-3xl border border-white/5 space-y-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#6C2BD9]/20 border border-[#6C2BD9]/30 flex items-center justify-center">
                <Link2 className="w-5 h-5 text-[#A78BFA]" />
              </div>
              <div>
                <h2 className="font-heading font-bold text-lg text-white">Step 4: Link Your Child</h2>
                <p className="text-xs text-[#C4B5FD]/60">
                  Target Institution: <strong className="text-white">{selectedInstitution?.name}</strong>
                  <button
                    type="button"
                    onClick={() => setStep(3)}
                    className="ml-2 text-[10px] text-[#A78BFA] underline"
                  >
                    Change Institution
                  </button>
                </p>
              </div>
            </div>

            {!linkedStudentName ? (
              <form onSubmit={handleLinkStudent} className="space-y-4">
                <div>
                  <label className="text-[11px] font-bold text-[#C4B5FD]/70 uppercase tracking-wider font-mono block mb-1">
                    Child&apos;s Roll Number or Student ID *
                  </label>
                  <input
                    type="text"
                    required
                    placeholder="e.g. 23CS1001 or STU-987"
                    value={rollNumber}
                    onChange={(e) => {
                      setRollNumber(e.target.value);
                      setError(null);
                    }}
                    className="w-full bg-[#13102A] border border-[#6C2BD9]/30 rounded-xl px-4 py-3 text-sm text-white outline-none focus:border-[#8B5CF6] placeholder-[#C4B5FD]/40 font-mono"
                  />
                </div>

                <div>
                  <label className="text-[11px] font-bold text-[#C4B5FD]/70 uppercase tracking-wider font-mono block mb-1">
                    Child&apos;s Date of Birth *
                  </label>
                  <input
                    type="date"
                    required
                    value={childDob}
                    onChange={(e) => {
                      setChildDob(e.target.value);
                      setError(null);
                    }}
                    className="w-full bg-[#13102A] border border-[#6C2BD9]/30 rounded-xl px-4 py-3 text-sm text-white outline-none focus:border-[#8B5CF6]"
                  />
                </div>

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full py-4 rounded-xl bg-[#6C2BD9] hover:bg-[#5B21B6] disabled:opacity-50 text-white font-extrabold text-sm flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#6C2BD9]/30"
                >
                  {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Link2 className="w-5 h-5" />}
                  <span>Verify & Link Student</span>
                </button>
              </form>
            ) : (
              /* Success Confirmation Card */
              <div className="p-8 rounded-2xl bg-[#13102A] border border-green-500/30 flex flex-col items-center text-center space-y-4">
                <div className="w-16 h-16 rounded-full bg-green-500/20 border border-green-500/30 flex items-center justify-center">
                  <CheckCircle className="w-8 h-8 text-green-400" />
                </div>
                <div className="space-y-1">
                  <h3 className="font-heading font-extrabold text-xl text-white">Child Successfully Linked!</h3>
                  <p className="text-xs text-[#C4B5FD]/70">
                    You are now connected to <strong className="text-white">{linkedStudentName}</strong> at{' '}
                    <strong className="text-[#A78BFA]">{selectedInstitution?.name}</strong>.
                  </p>
                </div>
                <p className="text-[11px] text-[#C4B5FD]/50 max-w-sm">
                  You can now track live attendance, view exam results, fee receipts, and message school administration
                  from your Parent Portal dashboard.
                </p>
                <Link
                  href="/parent/dashboard"
                  className="w-full py-3.5 rounded-xl bg-[#6C2BD9] hover:bg-[#5B21B6] text-white font-bold text-sm text-center transition-all shadow-lg shadow-[#6C2BD9]/30 block"
                >
                  Go to Parent Portal Dashboard
                </Link>
              </div>
            )}
          </div>
        )}
      </div>
    </main>
  );
}
