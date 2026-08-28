'use client';

import React, { useState, useEffect, Suspense } from 'react';
import { useSearchParams } from 'next/navigation';
import Header from '../../components/Header';
import Footer from '../../components/Footer';
import Link from 'next/link';
import {
  CreditCard,
  Building2,
  User,
  Mail,
  Phone,
  MapPin,
  CheckCircle2,
  ShieldCheck,
  Sparkles,
  ArrowLeft,
  Loader2
} from 'lucide-react';

import {
  CurrencyCode,
  TierRateConfig,
  TIER_RATES,
  getTier,
  computeGraduatedTotal,
  getGraduatedBreakdown
} from '../../lib/pricing';

const roundToStep = (n: number) => Math.max(500, Math.round(n / 100) * 100);

function BuyNowForm() {
  const searchParams = useSearchParams();

  const initialTier = (searchParams.get('tier') || 'growth') as 'growth' | 'scale' | 'enterprise';
  const rawAccounts = parseInt(searchParams.get('accounts') || '1500') || 1500;
  const initialAccounts = roundToStep(rawAccounts);
  const initialCycle = (searchParams.get('cycle') || 'annual') as 'monthly' | 'annual';
  const initialCurrency = (searchParams.get('currency') || 'INR') as CurrencyCode;

  const [institutionName, setInstitutionName] = useState('');
  const [contactName, setContactName] = useState('');
  const [contactEmail, setContactEmail] = useState('');
  const [contactPhone, setContactPhone] = useState('');
  const [city, setCity] = useState('');

  const [accountCount, setAccountCount] = useState<number>(initialAccounts);
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'annual'>(initialCycle);
  const [currency, setCurrency] = useState<CurrencyCode>(initialCurrency);

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [purchaseSuccess, setPurchaseSuccess] = useState<any | null>(null);

  const activeTier = getTier(accountCount);

  const getRateConfig = (tier: string, curr: CurrencyCode): TierRateConfig => {
    const tierDict = TIER_RATES[tier] || TIER_RATES.growth;
    return tierDict[curr] || tierDict.INR;
  };

  const currentRateConfig = getRateConfig(activeTier, currency);
  const rate = billingCycle === 'annual' ? currentRateConfig.annual_rate : currentRateConfig.monthly_rate;
  const breakdownData = getGraduatedBreakdown(accountCount, billingCycle, currency);
  const totalAmount = breakdownData.total;

  const formatPrice = (amount: number) => {
    return `${currentRateConfig.symbol}${amount.toLocaleString(currentRateConfig.locale, {
      minimumFractionDigits: amount % 1 === 0 ? 0 : 2,
      maximumFractionDigits: 2
    })}`;
  };

  // Load Razorpay script dynamically if needed
  useEffect(() => {
    const script = document.createElement('script');
    script.src = 'https://checkout.razorpay.com/v1/checkout.js';
    script.async = true;
    document.body.appendChild(script);
    return () => {
      document.body.removeChild(script);
    };
  }, []);

  const handlePurchaseSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!institutionName || !contactName || !contactEmail || !contactPhone) {
      setError('Please fill in all required fields.');
      return;
    }

    setLoading(true);

    try {
      // Step 1: Create Razorpay Order server-side
      const orderRes = await fetch('/api/v1/service-subscriptions/purchase-intent/create-order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          institution_name: institutionName,
          contact_name: contactName,
          contact_email: contactEmail,
          contact_phone: contactPhone,
          city,
          tier: activeTier,
          account_count: accountCount,
          billing_cycle: billingCycle,
          currency
        })
      });

      const orderData = await orderRes.json();
      if (!orderRes.ok || !orderData.success) {
        throw new Error(orderData.error || 'Failed to initialize purchase order.');
      }

      // Step 2: Checkout via Razorpay Modal or Mock Fallback
      if (typeof window !== 'undefined' && (window as any).Razorpay && orderData.key_id !== 'rzp_test_mock') {
        const options = {
          key: orderData.key_id,
          amount: orderData.amount_paise,
          currency: orderData.currency === 'INR' ? 'INR' : 'USD',
          name: 'IRIS 365 Campus OS',
          description: `Subscription: ${activeTier.toUpperCase()} Tier (${accountCount} Accounts)`,
          order_id: orderData.order_id,
          handler: async (response: any) => {
            await verifyPayment(response.razorpay_order_id, response.razorpay_payment_id, response.razorpay_signature);
          },
          prefill: {
            name: contactName,
            email: contactEmail,
            contact: contactPhone
          },
          theme: {
            color: '#4f46e5'
          }
        };
        const rzp = new (window as any).Razorpay(options);
        rzp.on('payment.failed', function (resp: any) {
          setError(`Payment failed: ${resp.error.description}`);
          setLoading(false);
        });
        rzp.open();
      } else {
        // Mock checkout flow for local dev / testing without live Razorpay SDK
        const mockPaymentId = `pay_mock_${Date.now()}`;
        const mockSig = `sig_mock_${Date.now()}`;
        await verifyPayment(orderData.order_id, mockPaymentId, mockSig);
      }
    } catch (err: any) {
      setError(err.message || 'An error occurred processing your request.');
      setLoading(false);
    }
  };

  const verifyPayment = async (orderId: string, paymentId: string, signature: string) => {
    try {
      const verifyRes = await fetch('/api/v1/service-subscriptions/purchase-intent/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          institution_name: institutionName,
          contact_name: contactName,
          contact_email: contactEmail,
          contact_phone: contactPhone,
          city,
          tier: activeTier,
          account_count: accountCount,
          billing_cycle: billingCycle,
          currency,
          razorpay_order_id: orderId,
          razorpay_payment_id: paymentId,
          razorpay_signature: signature
        })
      });

      const verifyData = await verifyRes.json();
      if (!verifyRes.ok || !verifyData.success) {
        throw new Error(verifyData.error || 'Payment verification failed.');
      }

      setPurchaseSuccess(
        verifyData.purchase_intent || {
          institution_name: institutionName,
          contact_name: contactName,
          contact_email: contactEmail,
          tier: activeTier,
          account_count: accountCount,
          amount_paid: totalAmount,
          currency,
          razorpay_payment_id: paymentId
        }
      );
    } catch (err: any) {
      setError(err.message || 'Failed to verify payment.');
    } finally {
      setLoading(false);
    }
  };

  if (purchaseSuccess) {
    return (
      <div className="max-w-2xl mx-auto my-12 p-8 rounded-3xl bg-slate-900 dark:bg-slate-900 light:bg-white border border-emerald-500/30 text-center space-y-6 shadow-2xl">
        <div className="w-16 h-16 rounded-full bg-emerald-500/20 text-emerald-400 mx-auto flex items-center justify-center">
          <CheckCircle2 className="w-10 h-10" />
        </div>

        <div className="space-y-2">
          <h2 className="text-3xl font-extrabold text-white dark:text-white light:text-slate-900">
            Payment Received & Confirmed!
          </h2>
          <p className="text-sm text-slate-300 dark:text-slate-300 light:text-slate-700">
            Thank you,{' '}
            <span className="font-bold text-indigo-400 dark:text-indigo-400 light:text-indigo-600">
              {purchaseSuccess.contact_name}
            </span>
            . Your purchase of IRIS 365 for{' '}
            <span className="font-bold text-white dark:text-white light:text-slate-900">
              {purchaseSuccess.institution_name}
            </span>{' '}
            has been processed successfully.
          </p>
        </div>

        <div className="p-5 rounded-2xl bg-slate-950/80 dark:bg-slate-950/80 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-200 text-left space-y-3 font-mono text-xs text-slate-300 dark:text-slate-300 light:text-slate-700">
          <div className="flex justify-between border-b border-slate-800 dark:border-slate-800 light:border-slate-200 pb-2">
            <span className="text-slate-500 dark:text-slate-500 light:text-slate-600 uppercase">
              Payment Reference:
            </span>
            <span className="text-emerald-400 dark:text-emerald-400 light:text-emerald-700 font-bold">
              {purchaseSuccess.razorpay_payment_id}
            </span>
          </div>
          <div className="flex justify-between border-b border-slate-800 dark:border-slate-800 light:border-slate-200 pb-2">
            <span className="text-slate-500 dark:text-slate-500 light:text-slate-600 uppercase">Plan & Tier:</span>
            <span className="text-white dark:text-white light:text-slate-900 font-bold uppercase">
              {purchaseSuccess.tier} Tier ({purchaseSuccess.account_count} accounts)
            </span>
          </div>
          <div className="flex justify-between border-b border-slate-800 dark:border-slate-800 light:border-slate-200 pb-2">
            <span className="text-slate-500 dark:text-slate-500 light:text-slate-600 uppercase">Billing Cycle:</span>
            <span className="text-white dark:text-white light:text-slate-900 capitalize">
              {purchaseSuccess.billing_cycle}
            </span>
          </div>
          <div className="flex justify-between">
            <span className="text-slate-500 dark:text-slate-500 light:text-slate-600 uppercase">
              Total Amount Paid:
            </span>
            <span className="text-indigo-400 dark:text-indigo-400 light:text-indigo-600 font-bold">
              {formatPrice(purchaseSuccess.amount_paid)}
            </span>
          </div>
        </div>

        <div className="p-4 rounded-xl bg-indigo-500/10 dark:bg-indigo-500/10 light:bg-indigo-50 border border-indigo-500/20 dark:border-indigo-500/20 light:border-indigo-200 text-xs text-slate-300 dark:text-slate-300 light:text-slate-700 text-left space-y-1">
          <span className="font-bold text-indigo-400 dark:text-indigo-400 light:text-indigo-700 block">
            Next Steps (Manual Provisioning):
          </span>
          <p>
            Our deployment engineers will set up your dedicated institution instance and send access credentials to{' '}
            <span className="underline text-white dark:text-white light:text-slate-900">
              {purchaseSuccess.contact_email}
            </span>{' '}
            within 24 hours.
          </p>
        </div>

        <div className="pt-4">
          <Link
            href="/"
            className="inline-flex items-center gap-2 px-6 py-3 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs"
          >
            Return to Homepage
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-4xl mx-auto my-8 grid grid-cols-1 md:grid-cols-12 gap-8 items-start">
      {/* Left Column: Details Form */}
      <div className="md:col-span-7 bg-slate-900/80 dark:bg-slate-900/80 light:bg-white p-8 rounded-3xl border border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-6 shadow-xl">
        <div className="space-y-1">
          <h2 className="text-2xl font-extrabold text-white dark:text-white light:text-slate-900">
            Institution Purchase Details
          </h2>
          <p className="text-xs text-slate-400 dark:text-slate-400 light:text-slate-600">
            Provide your official details to complete your IRIS 365 subscription purchase.
          </p>
        </div>

        {error && (
          <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-400 text-xs font-semibold">
            {error}
          </div>
        )}

        <form onSubmit={handlePurchaseSubmit} className="space-y-4">
          <div className="space-y-1">
            <label className="text-xs font-bold text-slate-300 dark:text-slate-300 light:text-slate-700 uppercase tracking-wider font-mono">
              Institution Name *
            </label>
            <div className="relative">
              <Building2 className="w-4 h-4 text-slate-500 dark:text-slate-500 light:text-slate-400 absolute left-3.5 top-3" />
              <input
                type="text"
                required
                placeholder="e.g. St. Xavier's Institute of Technology"
                value={institutionName}
                onChange={(e) => setInstitutionName(e.target.value)}
                className="w-full bg-slate-950 dark:bg-slate-950 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-300 rounded-xl py-2.5 pl-10 pr-4 text-xs text-white dark:text-white light:text-slate-900 placeholder-slate-600 dark:placeholder-slate-600 light:placeholder-slate-400 focus:outline-none focus:border-indigo-500"
              />
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <label className="text-xs font-bold text-slate-300 dark:text-slate-300 light:text-slate-700 uppercase tracking-wider font-mono">
                Contact Person Name *
              </label>
              <div className="relative">
                <User className="w-4 h-4 text-slate-500 dark:text-slate-500 light:text-slate-400 absolute left-3.5 top-3" />
                <input
                  type="text"
                  required
                  placeholder="Dr. Rajesh Sharma"
                  value={contactName}
                  onChange={(e) => setContactName(e.target.value)}
                  className="w-full bg-slate-950 dark:bg-slate-950 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-300 rounded-xl py-2.5 pl-10 pr-4 text-xs text-white dark:text-white light:text-slate-900 placeholder-slate-600 dark:placeholder-slate-600 light:placeholder-slate-400 focus:outline-none focus:border-indigo-500"
                />
              </div>
            </div>

            <div className="space-y-1">
              <label className="text-xs font-bold text-slate-300 dark:text-slate-300 light:text-slate-700 uppercase tracking-wider font-mono">
                Contact Phone *
              </label>
              <div className="relative">
                <Phone className="w-4 h-4 text-slate-500 dark:text-slate-500 light:text-slate-400 absolute left-3.5 top-3" />
                <input
                  type="tel"
                  required
                  placeholder="+91 98765 43210"
                  value={contactPhone}
                  onChange={(e) => setContactPhone(e.target.value)}
                  className="w-full bg-slate-950 dark:bg-slate-950 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-300 rounded-xl py-2.5 pl-10 pr-4 text-xs text-white dark:text-white light:text-slate-900 placeholder-slate-600 dark:placeholder-slate-600 light:placeholder-slate-400 focus:outline-none focus:border-indigo-500"
                />
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-1">
              <label className="text-xs font-bold text-slate-300 dark:text-slate-300 light:text-slate-700 uppercase tracking-wider font-mono">
                Official Email Address *
              </label>
              <div className="relative">
                <Mail className="w-4 h-4 text-slate-500 dark:text-slate-500 light:text-slate-400 absolute left-3.5 top-3" />
                <input
                  type="email"
                  required
                  placeholder="admin@stxaviers.edu"
                  value={contactEmail}
                  onChange={(e) => setContactEmail(e.target.value)}
                  className="w-full bg-slate-950 dark:bg-slate-950 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-300 rounded-xl py-2.5 pl-10 pr-4 text-xs text-white dark:text-white light:text-slate-900 placeholder-slate-600 dark:placeholder-slate-600 light:placeholder-slate-400 focus:outline-none focus:border-indigo-500"
                />
              </div>
            </div>

            <div className="space-y-1">
              <label className="text-xs font-bold text-slate-300 dark:text-slate-300 light:text-slate-700 uppercase tracking-wider font-mono">
                City / Location
              </label>
              <div className="relative">
                <MapPin className="w-4 h-4 text-slate-500 dark:text-slate-500 light:text-slate-400 absolute left-3.5 top-3" />
                <input
                  type="text"
                  placeholder="Mumbai, MH"
                  value={city}
                  onChange={(e) => setCity(e.target.value)}
                  className="w-full bg-slate-950 dark:bg-slate-950 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-300 rounded-xl py-2.5 pl-10 pr-4 text-xs text-white dark:text-white light:text-slate-900 placeholder-slate-600 dark:placeholder-slate-600 light:placeholder-slate-400 focus:outline-none focus:border-indigo-500"
                />
              </div>
            </div>
          </div>

          {/* Uncapped Account Count (Stepping by 100) & Cycle Controls */}
          <div className="pt-4 border-t border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-4">
            <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
              <label className="text-xs font-bold text-slate-300 dark:text-slate-300 light:text-slate-700 uppercase tracking-wider font-mono">
                Active User Accounts (Students + Staff)
              </label>
              <div className="flex items-center gap-2 bg-slate-950 dark:bg-slate-950 light:bg-slate-100 p-1.5 rounded-xl border border-slate-800 dark:border-slate-800 light:border-slate-300">
                <input
                  type="number"
                  min={500}
                  step={100}
                  value={accountCount}
                  onChange={(e) => setAccountCount(roundToStep(parseInt(e.target.value) || 500))}
                  onBlur={() => setAccountCount(roundToStep(accountCount))}
                  className="w-28 text-lg font-bold text-indigo-400 dark:text-indigo-400 light:text-indigo-600 font-mono bg-transparent text-right focus:outline-none"
                />
                <span className="text-xs text-slate-400 dark:text-slate-400 light:text-slate-600 font-mono pr-2">
                  accounts
                </span>
              </div>
            </div>

            <div className="flex justify-between items-center bg-slate-950 dark:bg-slate-950 light:bg-slate-100 p-3 rounded-xl border border-slate-800 dark:border-slate-800 light:border-slate-300">
              <span className="text-xs text-slate-300 dark:text-slate-300 light:text-slate-700 font-mono font-bold">
                Billing Cycle
              </span>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setBillingCycle('monthly')}
                  className={`px-3 py-1 rounded-lg text-xs font-mono font-bold transition-all ${
                    billingCycle === 'monthly'
                      ? 'bg-indigo-600 text-white'
                      : 'text-slate-400 dark:text-slate-400 light:text-slate-600 hover:bg-slate-900 dark:hover:bg-slate-900 light:hover:bg-slate-200'
                  }`}
                >
                  Monthly
                </button>
                <button
                  type="button"
                  onClick={() => setBillingCycle('annual')}
                  className={`px-3 py-1 rounded-lg text-xs font-mono font-bold transition-all ${
                    billingCycle === 'annual'
                      ? 'bg-indigo-600 text-white'
                      : 'text-slate-400 dark:text-slate-400 light:text-slate-600 hover:bg-slate-900 dark:hover:bg-slate-900 light:hover:bg-slate-200'
                  }`}
                >
                  Annual (~17% Off)
                </button>
              </div>
            </div>
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full py-4 rounded-xl bg-indigo-600 hover:bg-indigo-500 disabled:opacity-50 text-white font-extrabold text-sm shadow-lg shadow-indigo-600/30 flex items-center justify-center gap-2 transition-all"
          >
            {loading ? (
              <>
                <Loader2 className="w-5 h-5 animate-spin" />
                <span>Processing Order...</span>
              </>
            ) : (
              <>
                <CreditCard className="w-5 h-5" />
                <span>Pay Now — {formatPrice(totalAmount)}</span>
              </>
            )}
          </button>
          <p className="text-[11px] text-slate-500 dark:text-slate-500 light:text-slate-400 text-center font-mono pt-1">
            By proceeding, you agree that subscription purchases are final and non-refundable.
          </p>
        </form>
      </div>

      {/* Right Column: Order Summary Box */}
      <div className="md:col-span-5 bg-slate-900/90 dark:bg-slate-900/90 light:bg-white p-6 rounded-3xl border border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-6 shadow-xl">
        <div className="space-y-1">
          <span className="text-[10px] font-mono uppercase tracking-widest text-indigo-400 dark:text-indigo-400 light:text-indigo-600 font-bold block">
            Purchase Summary
          </span>
          <h3 className="text-xl font-extrabold text-white dark:text-white light:text-slate-900">IRIS 365 Campus OS</h3>
        </div>

        <div className="p-4 rounded-2xl bg-slate-950 dark:bg-slate-950 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-3 font-mono text-xs">
          <div className="flex justify-between items-center text-slate-300 dark:text-slate-300 light:text-slate-700">
            <span>Tier Level:</span>
            <span className="text-indigo-400 dark:text-indigo-400 light:text-indigo-600 font-bold uppercase">
              {activeTier} Tier
            </span>
          </div>

          <div className="flex justify-between items-center text-slate-300 dark:text-slate-300 light:text-slate-700">
            <span>Account Count:</span>
            <span className="text-white dark:text-white light:text-slate-900 font-bold">
              {accountCount.toLocaleString()}
            </span>
          </div>

          <div className="flex justify-between items-center text-slate-300 dark:text-slate-300 light:text-slate-700">
            <span>Billing Interval:</span>
            <span className="text-white dark:text-white light:text-slate-900 capitalize">{billingCycle}</span>
          </div>

          {/* Itemized Price Breakdown */}
          <div className="space-y-1.5 border-t border-slate-800 dark:border-slate-800 light:border-slate-200 pt-3">
            <span className="text-[10px] font-mono uppercase text-slate-400 dark:text-slate-400 light:text-slate-500 font-bold block">
              Price Breakdown
            </span>
            {breakdownData.bands.growth.count > 0 && (
              <div className="flex justify-between text-xs font-mono">
                <span className="text-slate-400 dark:text-slate-400 light:text-slate-600">
                  {breakdownData.bands.growth.count.toLocaleString()} × {currentRateConfig.symbol}
                  {breakdownData.bands.growth.rate} (Growth band)
                </span>
                <span className="text-white dark:text-white light:text-slate-900 font-bold">
                  {currentRateConfig.symbol}
                  {breakdownData.bands.growth.amount.toLocaleString(currentRateConfig.locale)}
                </span>
              </div>
            )}
            {breakdownData.bands.scale.count > 0 && (
              <div className="flex justify-between text-xs font-mono">
                <span className="text-slate-400 dark:text-slate-400 light:text-slate-600">
                  {breakdownData.bands.scale.count.toLocaleString()} × {currentRateConfig.symbol}
                  {breakdownData.bands.scale.rate} (Scale band)
                </span>
                <span className="text-white dark:text-white light:text-slate-900 font-bold">
                  {currentRateConfig.symbol}
                  {breakdownData.bands.scale.amount.toLocaleString(currentRateConfig.locale)}
                </span>
              </div>
            )}
            {breakdownData.bands.enterprise.count > 0 && (
              <div className="flex justify-between text-xs font-mono">
                <span className="text-slate-400 dark:text-slate-400 light:text-slate-600">
                  {breakdownData.bands.enterprise.count.toLocaleString()} × {currentRateConfig.symbol}
                  {breakdownData.bands.enterprise.rate} (Enterprise band)
                </span>
                <span className="text-white dark:text-white light:text-slate-900 font-bold">
                  {currentRateConfig.symbol}
                  {breakdownData.bands.enterprise.amount.toLocaleString(currentRateConfig.locale)}
                </span>
              </div>
            )}
            <div className="flex justify-between text-xs font-mono pt-1 text-emerald-400 dark:text-emerald-400 light:text-emerald-700 font-bold">
              <span>Effective Rate:</span>
              <span>
                {currentRateConfig.symbol}
                {breakdownData.effectiveRate.toFixed(2)} / person / {billingCycle === 'annual' ? 'year' : 'month'}{' '}
                (blended)
              </span>
            </div>
          </div>

          <div className="flex justify-between items-center text-slate-100 dark:text-slate-100 light:text-slate-900 font-bold text-sm pt-2 border-t border-slate-800 dark:border-slate-800 light:border-slate-200">
            <span>Total Payable:</span>
            <span className="text-indigo-300 dark:text-indigo-300 light:text-indigo-600 text-base">
              {formatPrice(totalAmount)}
            </span>
          </div>
        </div>

        <div className="space-y-2 text-xs text-slate-400 dark:text-slate-400 light:text-slate-600">
          <div className="flex items-center gap-2">
            <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
            <span>Complete Campus OS module access included</span>
          </div>
          <div className="flex items-start gap-2">
            <ShieldCheck className="w-4 h-4 text-indigo-400 dark:text-indigo-400 light:text-indigo-600 shrink-0 mt-0.5" />
            <span>
              Not sure yet?{' '}
              <Link
                href="/request-demo"
                className="text-indigo-400 dark:text-indigo-400 light:text-indigo-600 font-bold underline hover:opacity-80"
              >
                Try the free demo
              </Link>{' '}
              before you buy — purchases are final and non-refundable.
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}

export default function BuyNowPage() {
  return (
    <div className="min-h-screen bg-slate-950 dark:bg-slate-950 light:bg-slate-50 text-slate-100 dark:text-slate-100 light:text-slate-900 transition-colors duration-300 font-sans">
      <Header />
      <section className="pt-28 pb-16 px-6 md:px-12 max-w-7xl mx-auto space-y-6">
        <Link
          href="/pricing"
          className="inline-flex items-center gap-2 text-xs font-mono text-slate-400 dark:text-slate-400 light:text-slate-600 hover:text-white dark:hover:text-white light:hover:text-slate-900 transition-colors"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Back to Pricing Plans</span>
        </Link>

        <div className="text-center space-y-2 max-w-2xl mx-auto">
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/10 text-indigo-400 font-mono text-xs uppercase font-bold">
            <Sparkles className="w-3.5 h-3.5" />
            Instant Purchase Checkout
          </div>
          <h1 className="text-3xl md:text-5xl font-extrabold text-white dark:text-white light:text-slate-900">
            Secure Your Institution's Plan
          </h1>
        </div>

        <Suspense
          fallback={
            <div className="text-center text-slate-400 dark:text-slate-400 light:text-slate-600 py-12 font-mono">
              Loading checkout...
            </div>
          }
        >
          <BuyNowForm />
        </Suspense>
      </section>
      <Footer />
    </div>
  );
}
