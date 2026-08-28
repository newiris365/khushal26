'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import {
  CreditCard,
  ShieldCheck,
  CheckCircle,
  AlertCircle,
  Loader2,
  Sparkles,
  Calendar,
  User,
  ArrowRight,
  RotateCcw,
  ArrowLeft
} from 'lucide-react';

export default function ParentRenewalPage() {
  const [parentUser, setParentUser] = useState<any | null>(null);
  const [jwtToken, setJwtToken] = useState<string | null>(null);
  const [subStatus, setSubStatus] = useState<any | null>(null);

  const [loading, setLoading] = useState(false);
  const [fetchingStatus, setFetchingStatus] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [renewedSuccess, setRenewedSuccess] = useState(false);

  useEffect(() => {
    // Load Razorpay checkout SDK
    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    document.body.appendChild(script);

    // Retrieve user session
    if (typeof window !== 'undefined') {
      const token = localStorage.getItem('iris_jwt_token');
      const profileStr = localStorage.getItem('iris_user_profile');
      setJwtToken(token);
      if (profileStr) {
        try {
          setParentUser(JSON.parse(profileStr));
        } catch {
          /* ignore */
        }
      }
      if (token) {
        fetchSubscriptionStatus(token);
      } else {
        setFetchingStatus(false);
      }
    }

    return () => {
      if (document.body.contains(script)) {
        document.body.removeChild(script);
      }
    };
  }, []);

  const fetchSubscriptionStatus = async (token: string) => {
    setFetchingStatus(true);
    try {
      const res = await fetch('/api/parent-onboarding/subscription-status', {
        headers: { Authorization: `Bearer ${token}` }
      });
      const data = await res.json();
      if (data.success) {
        setSubStatus(data);
      }
    } catch {
      // Ignore network errors
    } finally {
      setFetchingStatus(false);
    }
  };

  const handlePayRenewalFee = async () => {
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
        throw new Error(data.error || 'Failed to initialize renewal payment.');
      }

      if (typeof window !== 'undefined' && (window as any).Razorpay && data.key_id !== 'rzp_test_mock') {
        const options = {
          key: data.key_id,
          amount: data.amount_paise,
          currency: 'INR',
          name: 'IRIS 365 Platform',
          description: 'Parent Portal 1-Year Subscription Renewal (₹150)',
          order_id: data.order_id,
          handler: (response: any) => {
            setRenewedSuccess(true);
            setTimeout(() => {
              window.location.href = '/parent/dashboard';
            }, 1500);
          },
          prefill: {
            name: parentUser?.name || 'Parent User',
            contact: parentUser?.phone || ''
          },
          theme: { color: '#6C2BD9' }
        };
        const rzp = new (window as any).Razorpay(options);
        rzp.on('payment.failed', (resp: any) => {
          setError(`Payment failed: ${resp.error.description}`);
          setLoading(false);
        });
        rzp.open();
      } else {
        // Dev/Mock fallback
        setRenewedSuccess(true);
        setTimeout(() => {
          window.location.href = '/parent/dashboard';
        }, 1200);
      }
    } catch (err: any) {
      setError(err.message || 'Renewal payment failed.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="min-h-screen bg-[#0D0A1A] text-white p-4 md:p-8 font-sans flex items-center justify-center">
      <div className="max-w-xl w-full mx-auto space-y-6">
        <Link
          href="/parent/dashboard"
          className="inline-flex items-center gap-1.5 text-xs text-[#A78BFA] hover:text-white font-semibold transition-colors mb-2"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Back to Parent Dashboard</span>
        </Link>
        {/* Branding Header */}
        <div className="text-center space-y-3">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-[#6C2BD9]/20 border border-[#6C2BD9]/40 text-[#A78BFA] font-mono text-xs uppercase font-bold">
            <RotateCcw className="w-3.5 h-3.5" />
            Parent Portal Annual Renewal
          </div>
          <h1 className="font-heading font-extrabold text-3xl text-white">Renew Your Parent Access</h1>
          <p className="text-xs text-[#C4B5FD]/70 max-w-sm mx-auto">
            Extend your IRIS 365 Parent Portal access for another full year. Your linked student records remain intact.
          </p>
        </div>

        {error && (
          <div className="p-4 rounded-xl bg-red-500/10 border border-red-500/20 text-red-400 text-xs flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {!renewedSuccess ? (
          <div className="glass-panel p-6 md:p-8 rounded-3xl border border-white/5 space-y-6">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#6C2BD9]/20 border border-[#6C2BD9]/30 flex items-center justify-center">
                <CreditCard className="w-5 h-5 text-[#A78BFA]" />
              </div>
              <div>
                <h2 className="font-heading font-bold text-lg text-white">Annual Pass Renewal</h2>
                <p className="text-xs text-[#C4B5FD]/60">₹150 / year for unlimited Parent Portal access</p>
              </div>
            </div>

            {fetchingStatus ? (
              <div className="py-8 text-center text-xs text-[#C4B5FD]/60 font-mono flex items-center justify-center gap-2">
                <Loader2 className="w-4 h-4 animate-spin text-[#A78BFA]" /> Checking subscription status...
              </div>
            ) : (
              <div className="p-5 rounded-2xl bg-[#13102A] border border-[#6C2BD9]/30 space-y-3 font-mono text-xs">
                <div className="flex justify-between items-center pb-2 border-b border-[#6C2BD9]/20">
                  <span className="text-[#C4B5FD]/70">Account Name:</span>
                  <span className="text-white font-bold">{parentUser?.name || 'Parent Account'}</span>
                </div>
                <div className="flex justify-between items-center pb-2 border-b border-[#6C2BD9]/20">
                  <span className="text-[#C4B5FD]/70">Current Status:</span>
                  <span
                    className={`font-bold px-2 py-0.5 rounded text-[10px] uppercase ${subStatus?.active ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30' : 'bg-red-500/20 text-red-300 border border-red-500/30'}`}
                  >
                    {subStatus?.active ? `Active (${subStatus.days_remaining} days left)` : 'Expired / Inactive'}
                  </span>
                </div>
                {subStatus?.valid_until && (
                  <div className="flex justify-between items-center pb-2 border-b border-[#6C2BD9]/20">
                    <span className="text-[#C4B5FD]/70">Current Expiry Date:</span>
                    <span className="text-white">{new Date(subStatus.valid_until).toLocaleDateString()}</span>
                  </div>
                )}
                <div className="flex justify-between items-center pt-2 text-sm font-bold">
                  <span className="text-[#C4B5FD]/70">Renewal Fee (1 Year):</span>
                  <span className="text-[#A78BFA] text-xl font-extrabold">₹150.00</span>
                </div>
              </div>
            )}

            <div className="space-y-2 text-xs text-[#C4B5FD]/70 font-mono">
              <div className="flex items-center gap-2">
                <CheckCircle className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>Extends access by 365 days from today</span>
              </div>
              <div className="flex items-center gap-2">
                <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>Secure SSL encrypted Razorpay checkout</span>
              </div>
            </div>

            <button
              onClick={handlePayRenewalFee}
              disabled={loading}
              className="w-full py-4 rounded-xl bg-[#6C2BD9] hover:bg-[#5B21B6] disabled:opacity-50 text-white font-extrabold text-sm flex items-center justify-center gap-2 transition-all shadow-lg shadow-[#6C2BD9]/30"
            >
              {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <CreditCard className="w-5 h-5" />}
              <span>Pay ₹150 & Extend Access for 1 Year</span>
            </button>
          </div>
        ) : (
          /* Renewal Success Card */
          <div className="glass-panel p-8 rounded-3xl border border-green-500/30 flex flex-col items-center text-center space-y-4">
            <div className="w-16 h-16 rounded-full bg-green-500/20 border border-green-500/30 flex items-center justify-center">
              <CheckCircle className="w-8 h-8 text-green-400" />
            </div>
            <h3 className="font-heading font-extrabold text-2xl text-white">Subscription Renewed!</h3>
            <p className="text-xs text-[#C4B5FD]/80">
              Your Parent Portal access has been extended for 1 year. Redirecting to your dashboard...
            </p>
            <Loader2 className="w-5 h-5 animate-spin text-[#A78BFA]" />
          </div>
        )}
      </div>
    </main>
  );
}
