"use client";

import React, { useState } from 'react';
import Image from 'next/image';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Shield, Lock, Mail, Loader2, Sparkles, Terminal } from 'lucide-react';
import { supabase } from '@/lib/supabase';

// Input Zod validator schema matching backend checks
const loginSchema = z.object({
  email: z.string().email('Please enter a valid institutional email address'),
  password: z.string().min(8, 'Password must be at least 8 characters long')
});

type LoginFormValues = z.infer<typeof loginSchema>;

const getRedirectPath = (role: string): string => {
  switch (role) {
    case 'SuperAdmin': return '/admin/global';
    case 'Admin': return '/admin/dashboard';
    case 'Student': return '/student/dashboard';
    case 'Warden': return '/warden/dashboard';
    case 'Security': return '/gate';
    case 'Driver': return '/transit';
    case 'Librarian': return '/librarian/library';
    case 'Director': return '/director';
    case 'Parent': return '/parent/dashboard';
    case 'Teacher': return '/teacher/timetable';
    case 'HOD': return '/hod/dashboard';
    case 'Vendor': return '/vendor/dashboard';
    case 'Principal': return '/principal/dashboard';
    case 'Vice Principal': return '/vp/dashboard';
    case 'VP': return '/vp/dashboard';
    case 'HR Admin': return '/hr/my/dashboard';
    case 'Company HR': return '/company/drives';
    case 'IQAC Coordinator': return '/iqac';
    case 'Admissions Officer': return '/officer/admissions';
    case 'TPO': return '/tpo';
    case 'Staff': return '/staff/dashboard';
    case 'Gym Trainer': return '/gymtrainer/dashboard';
    default: return '/dashboard';
  }
};

const COLLEGE_INST_ID = 'a0000000-0000-0000-0000-000000000001';
const SCHOOL_INST_ID = 'a0000000-0000-0000-0000-000000000002';

const getMockProfile = (email: string, role: string) => {
  const isSchool = email.includes('school');
  const instId = isSchool ? SCHOOL_INST_ID : COLLEGE_INST_ID;
  const instName = isSchool ? 'JIET School' : 'JIET (Jodhpur Institute of Engineering & Technology)';
  const instType = isSchool ? 'school' : 'college';

  switch (role) {
    case 'Student':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000034' : 'b0000000-0000-0000-0000-000000000006',
        student_id: '',
        room_id: 'e4000000-0000-0000-0000-000000000001',
        name: isSchool ? 'School Student' : 'Priyansh Student',
        email: email,
        role: 'Student',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Admin':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000031' : 'b0000000-0000-0000-0000-000000000002',
        name: isSchool ? 'School Admin' : 'Director JIET',
        email: email,
        role: 'Admin',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Warden':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000037' : 'b0000000-0000-0000-0000-000000000012',
        name: isSchool ? 'School Warden' : 'Jaswant Singh',
        email: email,
        role: 'Warden',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Security':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000038' : 'b0000000-0000-0000-0000-000000000015',
        name: isSchool ? 'School Security' : 'Guard Sher Singh',
        email: email,
        role: 'Security',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Driver':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000040' : '',
        name: isSchool ? 'School Driver' : 'Priyansh Driver',
        email: email,
        role: 'Driver',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Staff':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000033' : 'b0000000-0000-0000-0000-000000000030',
        name: isSchool ? 'School Staff' : 'Faculty Staff Member',
        email: email,
        role: 'Staff',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Parent':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000035' : 'b0000000-0000-0000-0000-000000000011',
        name: isSchool ? 'School Parent' : 'Nakshtra Parihar (Parent)',
        email: email,
        role: 'Parent',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Vendor':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000039' : '',
        name: isSchool ? 'School Vendor' : 'Canteen Vendor',
        email: email,
        role: 'Vendor',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Teacher':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000032' : 'b0000000-0000-0000-0000-000000000016',
        name: isSchool ? 'School Teacher' : 'Priyansh Rai (Teacher)',
        email: email,
        role: 'Teacher',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'HOD':
      return {
        id: 'b0000000-0000-0000-0000-000000000017',
        name: 'HOD Member',
        email: email,
        role: 'HOD',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'University',
        institute_type: 'college'
      };
    case 'Librarian':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000036' : 'b0000000-0000-0000-0000-000000000018',
        name: isSchool ? 'School Librarian' : 'Librarian Head',
        email: email,
        role: 'Librarian',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Director':
      return {
        id: 'b0000000-0000-0000-0000-000000000019',
        name: 'Director JIET',
        email: email,
        role: 'Director',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'University',
        institute_type: 'college'
      };
    case 'SuperAdmin':
      return {
        id: 'b0000000-0000-0000-0000-000000000001',
        name: 'Siddharth (SuperAdmin)',
        email: email,
        role: 'SuperAdmin',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'Enterprise',
        institute_type: 'college'
      };
    case 'Principal':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000021' : 'b0000000-0000-0000-0000-000000000021',
        name: isSchool ? 'School Principal' : 'Khushal Khatri (Principal)',
        email: email,
        role: 'Principal',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Vice Principal':
    case 'VP':
      return {
        id: 'b0000000-0000-0000-0000-000000000022',
        name: isSchool ? 'Vice Principal' : 'Vice Principal JIET',
        email: email,
        role: 'Vice Principal',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'TPO':
      return {
        id: 'b0000000-0000-0000-0000-000000000023',
        name: 'TPO Cell Head',
        email: email,
        role: 'TPO',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'University',
        institute_type: 'college'
      };
    case 'IQAC Coordinator':
      return {
        id: 'b0000000-0000-0000-0000-000000000024',
        name: 'IQAC Coordinator',
        email: email,
        role: 'IQAC Coordinator',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'University',
        institute_type: 'college'
      };
    case 'Admissions Officer':
      return {
        id: isSchool ? 'b0000000-0000-0000-0000-000000000042' : 'b0000000-0000-0000-0000-000000000025',
        name: isSchool ? 'School Admissions' : 'Admissions Officer',
        email: email,
        role: 'Admissions Officer',
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
    case 'Gym Trainer':
      return {
        id: 'b0000000-0000-0000-0000-000000000026',
        name: 'Gym Trainer',
        email: email,
        role: 'Gym Trainer',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'University',
        institute_type: 'college'
      };
    case 'HR Admin':
      return {
        id: 'b0000000-0000-0000-0000-000000000027',
        name: 'HR Admin',
        email: email,
        role: 'HR Admin',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'University',
        institute_type: 'college'
      };
    case 'Company HR':
      return {
        id: 'b0000000-0000-0000-0000-000000000028',
        name: 'Company HR Partner',
        email: email,
        role: 'Company HR',
        institution_id: COLLEGE_INST_ID,
        institution_name: 'JIET (Jodhpur Institute of Engineering & Technology)',
        plan_tier: 'University',
        institute_type: 'college'
      };
    default:
      return {
        id: 'b0000000-0000-0000-0000-000000009999',
        name: 'External Guest',
        email: email,
        role: role,
        institution_id: instId,
        institution_name: instName,
        plan_tier: 'University',
        institute_type: instType
      };
  }
};

export default function LoginPage() {
  const [isLoading, setIsLoading] = useState(false);
  const [isCheckingSession, setIsCheckingSession] = useState(true);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const [showForgotModal, setShowForgotModal] = useState(false);
  const [showRegisterModal, setShowRegisterModal] = useState(false);
  const [useOfflineBypass, setUseOfflineBypass] = useState(() => {
    if (typeof window !== 'undefined') {
      var isProd = process.env.NEXT_PUBLIC_ENV === 'production' || window.location.hostname !== 'localhost';
      return !isProd;
    }
    return false;
  });

  const [resetEmail, setResetEmail] = useState('');
  const [resetLoading, setResetLoading] = useState(false);
  const [resetSuccess, setResetSuccess] = useState(false);
  const [resetError, setResetError] = useState<string | null>(null);

  const { register, handleSubmit, setValue, formState: { errors } } = useForm<LoginFormValues>({
    resolver: zodResolver(loginSchema)
  });

  const handleForgotPasswordSubmit = async () => {
    if (!resetEmail || !resetEmail.includes('@')) {
      setResetError('Please enter a valid institutional email address');
      return;
    }
    setResetLoading(true);
    setResetError(null);
    try {
      const { error } = await supabase.auth.resetPasswordForEmail(resetEmail, {
        redirectTo: `${window.location.origin}/auth/reset-password`
      });
      if (error) {
        throw new Error(error.message);
      }
      setResetSuccess(true);
    } catch (err: any) {
      setResetError(err.message || 'Failed to send reset link. Please try again.');
    } finally {
      setResetLoading(false);
    }
  };

  const handleGoogleSignIn = async () => {
    setIsLoading(true);
    setSubmitError(null);
    try {
      // Clear any stale local sessions before starting OAuth redirect
      localStorage.removeItem('iris_jwt_token');
      localStorage.removeItem('iris_user_profile');
      localStorage.removeItem('iris_refresh_token');

      const deviceId = typeof window !== 'undefined' ? localStorage.getItem('iris_client_device_id') || '' : '';
      const { error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo: `${window.location.origin}/auth/callback?device_id=${encodeURIComponent(deviceId)}`
        }
      });
      if (error) {
        throw new Error(error.message);
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'An error occurred initiating Google sign-in.';
      setSubmitError(errorMessage);
      setIsLoading(false);
    }
  };

  React.useEffect(() => {
    let active = true;
    const timeout = setTimeout(() => {
      if (active) setIsCheckingSession(false);
    }, 2000);

    if (typeof window !== 'undefined') {
      let id = localStorage.getItem('iris_client_device_id');
      if (!id) {
        id = 'dev_' + Math.random().toString(36).substring(2, 15) + Math.random().toString(36).substring(2, 15);
        localStorage.setItem('iris_client_device_id', id);
      }

      // Parse URL parameters to check for OAuth callback errors
      const params = new URLSearchParams(window.location.search);

      // ─── OAuth Token Ingestion ────────────────────────────────────────────────
      // The auth/callback route redirects here with token, refresh, profile, and
      // path as query params. We store them in localStorage here — in a trusted
      // first-party context — then navigate to the dashboard.
      // ─────────────────────────────────────────────────────────────────────────
      const oauthToken = params.get('token');
      const oauthRefresh = params.get('refresh');
      const oauthProfile = params.get('profile');
      const oauthPath = params.get('path');

      if (oauthToken && oauthProfile && oauthPath) {
        try {
          localStorage.setItem('iris_jwt_token', oauthToken);
          if (oauthRefresh) {
            localStorage.setItem('iris_refresh_token', oauthRefresh);
          }
          localStorage.setItem('iris_user_profile', oauthProfile);

          const stored = localStorage.getItem('iris_jwt_token');
          if (!stored) {
            throw new Error('Failed to persist JWT in localStorage after OAuth callback.');
          }

          // Remove token from URL before navigating so it's not cached or bookmarked
          window.history.replaceState({}, '', '/login');
          window.location.href = oauthPath;
          return;
        } catch (e: any) {
          setSubmitError('Authentication succeeded but session could not be saved. Please try again.');
          if (active) setIsCheckingSession(false);
          clearTimeout(timeout);
          return;
        }
      }

      const err = params.get('error');
      if (err === 'user_not_found') {
        setSubmitError('User not found. Contact your administrator.');
      } else if (err) {
        setSubmitError(decodeURIComponent(err));
      }

      // ─── Explicit Login Navigation ────────────────────────────────────────────
      // When user clicks "Launch Portal" or "Dashboard Sign In" from the landing
      // page, we pass ?fresh=1 to indicate they explicitly want to log in.
      // In this case, clear any stale session data and show the login form.
      const isFreshLogin = params.get('fresh') === '1';
      if (isFreshLogin) {
        localStorage.removeItem('iris_jwt_token');
        localStorage.removeItem('iris_user_profile');
        localStorage.removeItem('iris_refresh_token');
        // Clean the URL param
        window.history.replaceState({}, '', '/login');
        if (active) setIsCheckingSession(false);
        clearTimeout(timeout);
        return;
      }

      // ─── Stale Mock Token Cleanup ─────────────────────────────────────────────
      const isProduction = process.env.NEXT_PUBLIC_ENV === 'production' || window.location.hostname !== 'localhost';
      const token = localStorage.getItem('iris_jwt_token');
      const savedProfile = localStorage.getItem('iris_user_profile');

      if (token && token.startsWith('mock-sandbox') && isProduction) {
        localStorage.removeItem('iris_jwt_token');
        localStorage.removeItem('iris_user_profile');
        localStorage.removeItem('iris_refresh_token');
      } else if (token && savedProfile) {
        // ─── Auto-Redirect for Existing Session ────────────────────────────────
        // Only auto-redirect if there is a valid, non-stale session already in
        // localStorage. This handles the case where a user's JWT expired and they
        // were redirected back to /login — we re-route them to their dashboard.
        try {
          const parsed = JSON.parse(savedProfile);
          if (parsed && parsed.role) {
            window.location.href = getRedirectPath(parsed.role);
            return;
          }
        } catch (e) {
          // Corrupted profile — clear and show login form
          localStorage.removeItem('iris_jwt_token');
          localStorage.removeItem('iris_user_profile');
          localStorage.removeItem('iris_refresh_token');
        }
      }
    }

    if (active) setIsCheckingSession(false);
    clearTimeout(timeout);
    return () => {
      active = false;
      clearTimeout(timeout);
    };
  }, []);

  if (isCheckingSession) {
    return (
      <main className="min-h-screen flex items-center justify-center p-4 bg-slate-50 dark:bg-[#0D0A1A] transition-colors duration-300">
        <div className="text-center flex flex-col items-center gap-4">
          <Loader2 className="w-8 h-8 animate-spin text-[#8B5CF6]" />
          <p className="text-slate-600 dark:text-slate-400 text-sm font-medium">Loading session...</p>
        </div>
      </main>
    );
  }

  const onSubmit = async (data: LoginFormValues) => {
    setIsLoading(true);
    setSubmitError(null);

    try {
      const deviceId = typeof window !== 'undefined' ? localStorage.getItem('iris_client_device_id') : '';
      const response = await fetch('/api/v1/auth/login', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          ...(deviceId ? { 'X-Client-Device-ID': deviceId } : {})
        },
        body: JSON.stringify(data)
      });

      const result = await response.json();

      if (!response.ok || !result.success) {
        throw new Error(result.error || 'Invalid credentials or login failed');
      }

      // Store jwt and profile
      localStorage.setItem('iris_jwt_token', result.token);
      localStorage.setItem('iris_user_profile', JSON.stringify(result.profile));

      // Verify token exists in localStorage
      const verifyToken = localStorage.getItem('iris_jwt_token');
      if (!verifyToken) {
        throw new Error('Token verification failed: JWT was not correctly saved to localStorage.');
      }

      // Redirect client dashboard based on claims role
      window.location.href = getRedirectPath(result.profile.role);

    } catch (err: any) {
      console.warn('Backend login request failed:', err);
      
      var isProduction = process.env.NEXT_PUBLIC_ENV === 'production' || window.location.hostname !== 'localhost';

      if (!isProduction) {
        // Automatic client-side bypass for sandbox testing profiles on connection failure (local dev only)
        const sandboxEmails = [
          'siddharth@sin.education', 'director@siet.edu.in', 'director2@siet.edu.in',
          'priyansh.24jics153@jietjodhpur.ac.in', 'raipriyansh45@gmail.com',
          'pariharnakshtra21@gmail.com', 'hod@sin.education', 'warden@siet.edu.in',
          'librarian@sin.education', 'canteen@siet.edu.in', 'security@siet.edu.in',
          'raip32380@gmail.com', 'staff@sin.education', 'tpo@siet.edu.in',
          'iqac@sin.education', 'admissions@siet.edu.in', 'gym@sin.education',
          'hr@siet.edu.in', 'companyhr@siet.edu.in', 'applicant@sin.education',
          'admin@school.edu.in', 'khushalkhatri0019@gmail.com',
          'khushal.24jiaiml067@jietjodhpur.ac.in', 'teacher@school.edu.in',
          'staff@school.edu.in', 'student@school.edu.in', 'parent@school.edu.in',
          'librarian@school.edu.in', 'warden@school.edu.in', 'security@school.edu.in',
          'canteen@school.edu.in', 'driver@school.edu.in', 'applicant@school.edu.in',
          'admissions@school.edu.in'
        ];
        if (sandboxEmails.includes(data.email)) {
          let role = 'Student';
          if (data.email === 'siddharth@sin.education') role = 'SuperAdmin';
          else if (data.email === 'director@siet.edu.in') role = 'Admin';
          else if (data.email === 'khushalkhatri0019@gmail.com') role = 'Principal';
          else if (data.email === 'raipriyansh45@gmail.com') role = 'Teacher';
          else if (data.email === 'priyansh.24jics153@jietjodhpur.ac.in') role = 'Student';
          else if (data.email === 'pariharnakshtra21@gmail.com') role = 'Parent';
          else if (data.email === 'raip32380@gmail.com') role = 'Driver';

          const mockProfile = getMockProfile(data.email, role);
          const mockPayload = btoa(unescape(encodeURIComponent(JSON.stringify(mockProfile))));
          const mockToken = `mock-sandbox-jwt-token-value.${mockPayload}.signature`;

          localStorage.setItem('iris_jwt_token', mockToken);
          localStorage.setItem('iris_user_profile', JSON.stringify(mockProfile));

          window.location.href = getRedirectPath(mockProfile.role);
          return;
        }
      }

      setSubmitError(err.message || 'An unexpected error occurred during sign-in.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleQuickLogin = async (email: string, role: string, instituteType?: 'college' | 'school') => {
    setIsLoading(true);
    setSubmitError(null);

    // Populate inputs visually
    setValue('email', email);
    setValue('password', 'password123');

    // Instant login buttons always use client-side mock bypass
    // These are dev/testing accounts — they bypass the real backend entirely
    setTimeout(() => {
      const mockProfile = getMockProfile(email, role);
      if (instituteType) mockProfile.institute_type = instituteType;
      const mockPayload = btoa(unescape(encodeURIComponent(JSON.stringify(mockProfile))));
      const mockToken = `mock-sandbox-jwt-token-value.${mockPayload}.signature`;

      localStorage.setItem('iris_jwt_token', mockToken);
      localStorage.setItem('iris_user_profile', JSON.stringify(mockProfile));

      setIsLoading(false);
      window.location.href = getRedirectPath(mockProfile.role);
    }, 400);
  };

  return (
    <main className="min-h-screen flex items-center justify-center p-4 relative overflow-hidden bg-slate-50 dark:bg-[#0D0A1A] transition-colors duration-300">
      {/* Background radial layers */}
      <div className="absolute w-[400px] h-[400px] rounded-full bg-[#6C2BD9]/10 blur-3xl -top-20 -left-20 pointer-events-none"></div>
      <div className="absolute w-[500px] h-[500px] rounded-full bg-[#8B5CF6]/15 blur-3xl -bottom-20 -right-20 pointer-events-none"></div>

      <div className="w-full max-w-md glass-panel rounded-3xl p-8 relative z-10 shadow-2xl border border-slate-200 dark:border-white/10 bg-white/90 dark:bg-white/5">
        <div className="flex flex-col items-center mb-8 text-center">
          <div className="w-12 h-12 rounded-2xl overflow-hidden flex items-center justify-center shadow-lg shadow-purple-500/10 mb-4 border border-slate-200 dark:border-white/10">
            <Image 
              src="/dark_logo.jpeg" 
              alt="IRIS 365 Logo" 
              width={48}
              height={48}
              className="w-full h-full object-cover"
            />
          </div>
          <h1 className="font-heading font-extrabold text-2xl text-slate-900 dark:text-white tracking-tight">Access IRIS 365</h1>
          <p className="text-xs text-slate-600 dark:text-[#C4B5FD] mt-1 font-light">Campus Intelligence, Reimagined.</p>
        </div>

        {submitError && (
          <div className="mb-6 p-4 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 dark:text-red-400 text-xs font-medium">
            {submitError}
          </div>
        )}

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
          
          {/* Email */}
          <div className="flex flex-col gap-1.5">
            <label className="text-[10px] font-semibold text-slate-700 dark:text-[#C4B5FD] uppercase tracking-wider">Institutional Email</label>
            <div className="relative">
              <span className="absolute left-4 top-3.5 text-slate-400 dark:text-[#C4B5FD]/70"><Mail className="w-4.5 h-4.5" /></span>
              <input 
                type="email"
                required
                className="w-full bg-slate-50 dark:bg-white/5 border border-slate-300 dark:border-[#6C2BD9]/30 focus:border-[#8B5CF6] focus:ring-1 focus:ring-[#8B5CF6] pl-11 pr-4 py-3 rounded-xl text-sm text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-white/20 outline-none transition-all"
                placeholder="registrar@college.edu.in"
                {...register('email')}
              />
            </div>
            {errors.email && (
              <span className="text-[10px] text-red-500 dark:text-red-400 font-medium mt-1">{errors.email.message}</span>
            )}
          </div>

          {/* Password */}
          <div className="flex flex-col gap-1.5">
            <label className="text-[10px] font-semibold text-slate-700 dark:text-[#C4B5FD] uppercase tracking-wider">Password</label>
            <div className="relative">
              <span className="absolute left-4 top-3.5 text-slate-400 dark:text-[#C4B5FD]/70"><Lock className="w-4.5 h-4.5" /></span>
              <input 
                type="password"
                required
                className="w-full bg-slate-50 dark:bg-white/5 border border-slate-300 dark:border-[#6C2BD9]/30 focus:border-[#8B5CF6] focus:ring-1 focus:ring-[#8B5CF6] pl-11 pr-4 py-3 rounded-xl text-sm text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-white/20 outline-none transition-all"
                placeholder="••••••••"
                {...register('password')}
              />
            </div>
            {errors.password && (
              <span className="text-[10px] text-red-500 dark:text-red-400 font-medium mt-1">{errors.password.message}</span>
            )}
          </div>

          {/* Submit Button */}
          <button 
            type="submit" 
            disabled={isLoading}
            className="w-full py-3.5 rounded-xl bg-gradient-to-r from-[#6C2BD9] to-[#8B5CF6] text-white font-heading font-bold text-sm shadow-lg shadow-[#6C2BD9]/20 hover:brightness-110 disabled:opacity-50 transition-all flex items-center justify-center gap-2"
          >
            {isLoading ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                <span>Authenticating User...</span>
              </>
            ) : (
              <span>Sign In to Dashboard →</span>
            )}
          </button>
        </form>

        <div className="relative my-5 flex items-center justify-center">
          <div className="absolute inset-0 flex items-center">
            <div className="w-full border-t border-slate-300 dark:border-white/10"></div>
          </div>
          <span className="relative px-3 bg-white dark:bg-[#0D0A1A] text-[10px] text-slate-500 dark:text-[#C4B5FD]/50 font-bold uppercase tracking-wider">or</span>
        </div>

        <button 
          type="button" 
          disabled={isLoading}
          onClick={handleGoogleSignIn}
          className="w-full py-3 rounded-xl bg-white dark:bg-white border border-slate-200 dark:border-transparent text-gray-900 font-heading font-bold text-sm shadow-sm hover:bg-gray-100 disabled:opacity-50 transition-all flex items-center justify-center gap-3"
        >
          <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
            <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
            <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
            <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.06H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.94l3.66-2.85z" fill="#FBBC05"/>
            <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.06l3.66 2.85c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
          </svg>
          <span>Continue with Google</span>
        </button>

        {/* Instant Login - All Roles (Local Development/Bypass only) */}
        {process.env.NODE_ENV !== 'production' && (
          <div className="mt-6 pt-6 border-t border-slate-200 dark:border-white/10">
            <div className="flex items-center justify-between mb-3">
              <span className="text-[10px] font-bold text-purple-700 dark:text-[#A78BFA] uppercase tracking-wider flex items-center gap-1">
                <Sparkles className="w-3.5 h-3.5 text-purple-700 dark:text-[#A78BFA]" /> Instant Login
              </span>
              <div className="flex items-center gap-1.5">
                <input 
                  type="checkbox" 
                  id="offline-bypass" 
                  checked={useOfflineBypass}
                  onChange={(e) => setUseOfflineBypass(e.target.checked)}
                  className="w-3.5 h-3.5 rounded bg-white/5 border-[#6C2BD9]/30 text-[#6C2BD9] focus:ring-[#8B5CF6] cursor-pointer"
                />
                <label htmlFor="offline-bypass" className="text-[9px] text-slate-600 dark:text-[#C4B5FD]/60 select-none cursor-pointer hover:text-slate-900 dark:hover:text-[#C4B5FD] transition-colors">
                  Force Offline
                </label>
              </div>
            </div>

            <div className="mb-2 mt-4 text-[10px] font-bold text-slate-500 dark:text-white/50 uppercase tracking-wider pl-1">College Roles</div>
            <div className="grid grid-cols-3 gap-1.5">
              {[
                { email: 'siddharth@sin.education', role: 'SuperAdmin', label: 'SuperAdmin', bg: 'bg-rose-500/10', border: 'border-rose-500/25', hoverBorder: 'hover:border-rose-500', hoverBg: 'hover:bg-rose-500/20', text: 'text-rose-600 dark:text-rose-400', hoverText: 'hover:text-rose-700 dark:hover:text-rose-300' },
                { email: 'director@siet.edu.in', role: 'Admin', label: 'Admin', bg: 'bg-blue-500/10', border: 'border-blue-500/25', hoverBorder: 'hover:border-blue-500', hoverBg: 'hover:bg-blue-500/20', text: 'text-blue-600 dark:text-blue-400', hoverText: 'hover:text-blue-700 dark:hover:text-blue-300' },
                { email: 'director2@siet.edu.in', role: 'Director', label: 'Director', bg: 'bg-amber-500/10', border: 'border-amber-500/25', hoverBorder: 'hover:border-amber-500', hoverBg: 'hover:bg-amber-500/20', text: 'text-amber-600 dark:text-amber-400', hoverText: 'hover:text-amber-700 dark:hover:text-amber-300' },
                { email: 'priyansh.24jics153@jietjodhpur.ac.in', role: 'Student', label: 'Student', bg: 'bg-emerald-500/10', border: 'border-emerald-500/25', hoverBorder: 'hover:border-emerald-500', hoverBg: 'hover:bg-emerald-500/20', text: 'text-emerald-600 dark:text-emerald-400', hoverText: 'hover:text-emerald-700 dark:hover:text-emerald-300' },
                { email: 'raipriyansh45@gmail.com', role: 'Teacher', label: 'Teacher', bg: 'bg-purple-500/10', border: 'border-purple-500/25', hoverBorder: 'hover:border-purple-500', hoverBg: 'hover:bg-purple-500/20', text: 'text-purple-600 dark:text-purple-400', hoverText: 'hover:text-purple-700 dark:hover:text-purple-300' },
                { email: 'pariharnakshtra21@gmail.com', role: 'Parent', label: 'Parent', bg: 'bg-pink-500/10', border: 'border-pink-500/25', hoverBorder: 'hover:border-pink-500', hoverBg: 'hover:bg-pink-500/20', text: 'text-pink-600 dark:text-pink-400', hoverText: 'hover:text-pink-700 dark:hover:text-pink-300' },
                { email: 'hod@sin.education', role: 'HOD', label: 'HOD', bg: 'bg-cyan-500/10', border: 'border-cyan-500/25', hoverBorder: 'hover:border-cyan-500', hoverBg: 'hover:bg-cyan-500/20', text: 'text-cyan-600 dark:text-cyan-400', hoverText: 'hover:text-cyan-700 dark:hover:text-cyan-300' },
                { email: 'warden@siet.edu.in', role: 'Warden', label: 'Warden', bg: 'bg-amber-500/10', border: 'border-amber-500/25', hoverBorder: 'hover:border-amber-500', hoverBg: 'hover:bg-amber-500/20', text: 'text-amber-600 dark:text-amber-400', hoverText: 'hover:text-amber-700 dark:hover:text-amber-300' },
                { email: 'librarian@sin.education', role: 'Librarian', label: 'Librarian', bg: 'bg-teal-500/10', border: 'border-teal-500/25', hoverBorder: 'hover:border-teal-500', hoverBg: 'hover:bg-teal-500/20', text: 'text-teal-600 dark:text-teal-400', hoverText: 'hover:text-teal-700 dark:hover:text-teal-300' },
                { email: 'canteen@siet.edu.in', role: 'Vendor', label: 'Vendor', bg: 'bg-lime-500/10', border: 'border-lime-500/25', hoverBorder: 'hover:border-lime-500', hoverBg: 'hover:bg-lime-500/20', text: 'text-lime-700 dark:text-lime-400', hoverText: 'hover:text-lime-800 dark:hover:text-lime-300' },
                { email: 'security@siet.edu.in', role: 'Security', label: 'Security', bg: 'bg-slate-500/10', border: 'border-slate-500/25', hoverBorder: 'hover:border-slate-500', hoverBg: 'hover:bg-slate-500/20', text: 'text-slate-700 dark:text-slate-400', hoverText: 'hover:text-slate-800 dark:hover:text-slate-300' },
                { email: 'raip32380@gmail.com', role: 'Driver', label: 'Driver', bg: 'bg-orange-500/10', border: 'border-orange-500/25', hoverBorder: 'hover:border-orange-500', hoverBg: 'hover:bg-orange-500/20', text: 'text-orange-600 dark:text-orange-400', hoverText: 'hover:text-orange-700 dark:hover:text-orange-300' },
                { email: 'staff@sin.education', role: 'Staff', label: 'Staff', bg: 'bg-blue-400/10', border: 'border-blue-400/25', hoverBorder: 'hover:border-blue-400', hoverBg: 'hover:bg-blue-400/20', text: 'text-blue-600 dark:text-blue-300', hoverText: 'hover:text-blue-700 dark:hover:text-blue-200' },
                { email: 'tpo@siet.edu.in', role: 'TPO', label: 'TPO', bg: 'bg-indigo-500/10', border: 'border-indigo-500/25', hoverBorder: 'hover:border-indigo-500', hoverBg: 'hover:bg-indigo-500/20', text: 'text-indigo-600 dark:text-indigo-400', hoverText: 'hover:text-indigo-700 dark:hover:text-indigo-300' },
                { email: 'iqac@sin.education', role: 'IQAC Coordinator', label: 'IQAC', bg: 'bg-fuchsia-500/10', border: 'border-fuchsia-500/25', hoverBorder: 'hover:border-fuchsia-500', hoverBg: 'hover:bg-fuchsia-500/20', text: 'text-fuchsia-600 dark:text-fuchsia-400', hoverText: 'hover:text-fuchsia-700 dark:hover:text-fuchsia-300' },
                { email: 'admissions@siet.edu.in', role: 'Admissions Officer', label: 'Admissions', bg: 'bg-rose-400/10', border: 'border-rose-400/25', hoverBorder: 'hover:border-rose-400', hoverBg: 'hover:bg-rose-400/20', text: 'text-rose-600 dark:text-rose-300', hoverText: 'hover:text-rose-700 dark:hover:text-rose-200' },
                { email: 'gym@sin.education', role: 'Gym Trainer', label: 'Gym Trainer', bg: 'bg-red-400/10', border: 'border-red-400/25', hoverBorder: 'hover:border-red-400', hoverBg: 'hover:bg-red-400/20', text: 'text-red-600 dark:text-red-300', hoverText: 'hover:text-red-700 dark:hover:text-red-200' },
                { email: 'hr@siet.edu.in', role: 'HR Admin', label: 'HR Admin', bg: 'bg-violet-400/10', border: 'border-violet-400/25', hoverBorder: 'hover:border-violet-400', hoverBg: 'hover:bg-violet-400/20', text: 'text-violet-600 dark:text-violet-300', hoverText: 'hover:text-violet-700 dark:hover:text-violet-200' },
                { email: 'companyhr@siet.edu.in', role: 'Company HR', label: 'Company HR', bg: 'bg-sky-500/10', border: 'border-sky-500/25', hoverBorder: 'hover:border-sky-500', hoverBg: 'hover:bg-sky-500/20', text: 'text-sky-600 dark:text-sky-400', hoverText: 'hover:text-sky-700 dark:hover:text-sky-300' },
              ].map((item) => (
                <button
                  key={`college-${item.role}`}
                  type="button"
                  onClick={() => handleQuickLogin(item.email, item.role, 'college')}
                  className={`p-2 rounded-xl ${item.bg} border ${item.border} ${item.hoverBorder} ${item.hoverBg} transition-all text-left flex flex-col group`}
                >
                  <span className={`text-[10px] font-bold ${item.text} ${item.hoverText} transition-colors`}>
                    {item.label}
                  </span>
                  <span className="text-[7px] text-slate-600 dark:text-[#C4B5FD]/50 font-mono truncate w-full mt-0.5">
                    {item.email}
                  </span>
                </button>
              ))}
            </div>

            <div className="mb-2 mt-4 text-[10px] font-bold text-slate-500 dark:text-white/50 uppercase tracking-wider pl-1">School Roles</div>
            <div className="grid grid-cols-3 gap-1.5">
              {[
                { email: 'admin@school.edu.in', role: 'Admin', label: 'Admin', bg: 'bg-blue-500/10', border: 'border-blue-500/25', hoverBorder: 'hover:border-blue-500', hoverBg: 'hover:bg-blue-500/20', text: 'text-blue-600 dark:text-blue-400', hoverText: 'hover:text-blue-700 dark:hover:text-blue-300' },
                { email: 'khushalkhatri0019@gmail.com', role: 'Principal', label: 'Principal', bg: 'bg-violet-500/10', border: 'border-violet-500/25', hoverBorder: 'hover:border-violet-500', hoverBg: 'hover:bg-violet-500/20', text: 'text-violet-600 dark:text-violet-400', hoverText: 'hover:text-violet-700 dark:hover:text-violet-300' },
                { email: 'khushal.24jiaiml067@jietjodhpur.ac.in', role: 'Vice Principal', label: 'Vice Principal', bg: 'bg-indigo-500/10', border: 'border-indigo-500/25', hoverBorder: 'hover:border-indigo-500', hoverBg: 'hover:bg-indigo-500/20', text: 'text-indigo-600 dark:text-indigo-400', hoverText: 'hover:text-indigo-700 dark:hover:text-indigo-300' },
                { email: 'teacher@school.edu.in', role: 'Teacher', label: 'Teacher', bg: 'bg-purple-500/10', border: 'border-purple-500/25', hoverBorder: 'hover:border-purple-500', hoverBg: 'hover:bg-purple-500/20', text: 'text-purple-600 dark:text-purple-400', hoverText: 'hover:text-purple-700 dark:hover:text-purple-300' },
                { email: 'staff@school.edu.in', role: 'Staff', label: 'Staff', bg: 'bg-blue-400/10', border: 'border-blue-400/25', hoverBorder: 'hover:border-blue-400', hoverBg: 'hover:bg-blue-400/20', text: 'text-blue-600 dark:text-blue-300', hoverText: 'hover:text-blue-700 dark:hover:text-blue-200' },
                { email: 'student@school.edu.in', role: 'Student', label: 'Student', bg: 'bg-emerald-500/10', border: 'border-emerald-500/25', hoverBorder: 'hover:border-emerald-500', hoverBg: 'hover:bg-emerald-500/20', text: 'text-emerald-600 dark:text-emerald-400', hoverText: 'hover:text-emerald-700 dark:hover:text-emerald-300' },
                { email: 'parent@school.edu.in', role: 'Parent', label: 'Parent', bg: 'bg-pink-500/10', border: 'border-pink-500/25', hoverBorder: 'hover:border-pink-500', hoverBg: 'hover:bg-pink-500/20', text: 'text-pink-600 dark:text-pink-400', hoverText: 'hover:text-pink-700 dark:hover:text-pink-300' },
                { email: 'librarian@school.edu.in', role: 'Librarian', label: 'Librarian', bg: 'bg-teal-500/10', border: 'border-teal-500/25', hoverBorder: 'hover:border-teal-500', hoverBg: 'hover:bg-teal-500/20', text: 'text-teal-600 dark:text-teal-400', hoverText: 'hover:text-teal-700 dark:hover:text-teal-300' },
                { email: 'warden@school.edu.in', role: 'Warden', label: 'Warden', bg: 'bg-amber-500/10', border: 'border-amber-500/25', hoverBorder: 'hover:border-amber-500', hoverBg: 'hover:bg-amber-500/20', text: 'text-amber-600 dark:text-amber-400', hoverText: 'hover:text-amber-700 dark:hover:text-amber-300' },
                { email: 'security@school.edu.in', role: 'Security', label: 'Security', bg: 'bg-slate-500/10', border: 'border-slate-500/25', hoverBorder: 'hover:border-slate-500', hoverBg: 'hover:bg-slate-500/20', text: 'text-slate-700 dark:text-slate-400', hoverText: 'hover:text-slate-800 dark:hover:text-slate-300' },
                { email: 'canteen@school.edu.in', role: 'Vendor', label: 'Vendor', bg: 'bg-lime-500/10', border: 'border-lime-500/25', hoverBorder: 'hover:border-lime-500', hoverBg: 'hover:bg-lime-500/20', text: 'text-lime-700 dark:text-lime-400', hoverText: 'hover:text-lime-800 dark:hover:text-lime-300' },
                { email: 'driver@school.edu.in', role: 'Driver', label: 'Driver', bg: 'bg-orange-500/10', border: 'border-orange-500/25', hoverBorder: 'hover:border-orange-500', hoverBg: 'hover:bg-orange-500/20', text: 'text-orange-600 dark:text-orange-400', hoverText: 'hover:text-orange-700 dark:hover:text-orange-300' },
                { email: 'admissions@school.edu.in', role: 'Admissions Officer', label: 'Admissions', bg: 'bg-rose-400/10', border: 'border-rose-400/25', hoverBorder: 'hover:border-rose-400', hoverBg: 'hover:bg-rose-400/20', text: 'text-rose-600 dark:text-rose-300', hoverText: 'hover:text-rose-700 dark:hover:text-rose-200' },
              ].map((item) => (
                <button
                  key={`school-${item.role}`}
                  type="button"
                  onClick={() => handleQuickLogin(item.email, item.role, 'school')}
                  className={`p-2 rounded-xl ${item.bg} border ${item.border} ${item.hoverBorder} ${item.hoverBg} transition-all text-left flex flex-col group`}
                >
                  <span className={`text-[10px] font-bold ${item.text} ${item.hoverText} transition-colors`}>
                    {item.label}
                  </span>
                  <span className="text-[7px] text-slate-600 dark:text-[#C4B5FD]/50 font-mono truncate w-full mt-0.5">
                    {item.email}
                  </span>
                </button>
              ))}
            </div>
          </div>
        )}

        {/* Action links */}
        <div className="flex items-center justify-between mt-5 text-[10px] text-slate-600 dark:text-[#C4B5FD]/50 font-medium">
          <button 
            type="button" 
            onClick={() => setShowForgotModal(true)} 
            className="hover:text-slate-900 dark:hover:text-white transition-colors underline decoration-[#6C2BD9] underline-offset-4"
          >
            Forgot Password?
          </button>
          <button 
            type="button" 
            onClick={() => setShowRegisterModal(true)} 
            className="hover:text-slate-900 dark:hover:text-white transition-colors underline decoration-[#6C2BD9] underline-offset-4"
          >
            Request Enrollment
          </button>
        </div>

        <div className="mt-8 pt-6 border-t border-slate-200 dark:border-white/5 text-center">
          <p className="text-[10px] text-slate-500 dark:text-[#C4B5FD]/50 font-light">&copy; 2026 KSL Studio.</p>
        </div>
      </div>

      {/* Forgot Password Modal */}
      {showForgotModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-sm bg-white dark:bg-[#13102A] border border-slate-200 dark:border-[#6C2BD9]/30 rounded-2xl p-6 shadow-2xl relative">
            <h3 className="font-heading font-bold text-base text-slate-900 dark:text-white mb-2">Reset Password</h3>
            <p className="text-xs text-slate-600 dark:text-[#C4B5FD]/70 leading-relaxed mb-4">
              Enter your institutional email address to receive a secure password reset link.
            </p>
            
            {resetSuccess ? (
              <div className="mb-4 p-3 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-600 dark:text-emerald-400 text-xs font-medium">
                Password reset link sent to your email.
              </div>
            ) : (
              <>
                {resetError && (
                  <div className="mb-4 p-3 rounded-xl bg-red-500/10 border border-red-500/30 text-red-500 dark:text-red-400 text-xs font-medium">
                    {resetError}
                  </div>
                )}
                <div className="flex flex-col gap-1.5 mb-5">
                  <label className="text-[10px] font-semibold text-slate-700 dark:text-[#C4B5FD] uppercase tracking-wider">Institutional Email</label>
                  <input 
                    type="email"
                    required
                    value={resetEmail}
                    onChange={(e) => setResetEmail(e.target.value)}
                    className="w-full bg-slate-50 dark:bg-white/5 border border-slate-300 dark:border-[#6C2BD9]/30 focus:border-[#8B5CF6] focus:ring-1 focus:ring-[#8B5CF6] px-4 py-2.5 rounded-xl text-sm text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-white/20 outline-none transition-all"
                    placeholder="name@institution.edu"
                    disabled={resetLoading}
                  />
                </div>
              </>
            )}

            <div className="flex gap-3">
              <button 
                type="button"
                onClick={() => {
                  setShowForgotModal(false);
                  setResetEmail('');
                  setResetSuccess(false);
                  setResetError(null);
                }} 
                className="flex-1 py-2.5 rounded-xl border border-slate-300 dark:border-white/10 text-slate-700 dark:text-white text-xs font-bold transition-all hover:bg-slate-100 dark:hover:bg-white/5"
              >
                Close
              </button>
              {!resetSuccess && (
                <button 
                  type="button"
                  disabled={resetLoading}
                  onClick={handleForgotPasswordSubmit}
                  className="flex-1 py-2.5 rounded-xl bg-gradient-to-r from-[#6C2BD9] to-[#8B5CF6] hover:brightness-110 disabled:opacity-50 text-white text-xs font-bold transition-all shadow-md shadow-[#6C2BD9]/20 flex items-center justify-center gap-1.5"
                >
                  {resetLoading ? (
                    <>
                      <Loader2 className="w-3.5 h-3.5 animate-spin" />
                      <span>Sending...</span>
                    </>
                  ) : (
                    <span>Send Link</span>
                  )}
                </button>
              )}
            </div>
          </div>
        </div>
      )}

      {/* Request Enrollment Modal */}
      {showRegisterModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-sm bg-white dark:bg-[#13102A] border border-slate-200 dark:border-[#6C2BD9]/30 rounded-2xl p-6 shadow-2xl relative">
            <h3 className="font-heading font-bold text-base text-slate-900 dark:text-white mb-2">Access & Enrollment Request</h3>
            <p className="text-xs text-slate-600 dark:text-[#C4B5FD]/70 leading-relaxed mb-5">
              IRIS 365 is a closed, multi-tenant administrative network. Accounts are pre-provisioned by your institution. If you are a new student or professor, please contact the <strong className="text-slate-900 dark:text-white">Academic Registrar's Office</strong> to fetch your access token.
            </p>
            <button 
              type="button"
              onClick={() => setShowRegisterModal(false)} 
              className="w-full py-2.5 rounded-xl bg-gradient-to-r from-[#6C2BD9] to-[#8B5CF6] hover:brightness-110 text-white text-xs font-bold transition-all shadow-md shadow-[#6C2BD9]/20"
            >
              Acknowledge & Close
            </button>
          </div>
        </div>
      )}
    </main>
  );
}
