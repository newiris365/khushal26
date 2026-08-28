'use client';

import React, { useState, useEffect } from 'react';
import Header from '../../components/Header';
import Footer from '../../components/Footer';
import Link from 'next/link';
import { CheckCircle2, ArrowRight, ShieldCheck, Calculator, Sparkles, Globe } from 'lucide-react';

import {
  CurrencyCode,
  TierRateConfig,
  TIER_RATES,
  CURRENCIES,
  getTier,
  computeGraduatedTotal,
  getGraduatedBreakdown
} from '../../lib/pricing';

const SLIDER_MIN = 500;
const SLIDER_MAX = 15000;
const getPct = (val: number) => Math.min(100, Math.max(0, ((val - SLIDER_MIN) / (SLIDER_MAX - SLIDER_MIN)) * 100));

export default function PricingPage() {
  const [billingCycle, setBillingCycle] = useState<'monthly' | 'annual'>('annual');
  const [accountCount, setAccountCount] = useState<number>(1500);
  const [currency, setCurrency] = useState<CurrencyCode>('INR');

  const activeTier = getTier(accountCount);

  const getRateConfig = (tier: string, curr: CurrencyCode): TierRateConfig => {
    const tierDict = TIER_RATES[tier] || TIER_RATES.growth;
    return tierDict[curr] || tierDict.INR;
  };

  const activeRateConfig = getRateConfig(activeTier, currency);

  // Fallback client-side graduated calculations
  const localAnnualTotal = computeGraduatedTotal(accountCount, 'annual', currency);
  const localMonthlyTotal = computeGraduatedTotal(accountCount, 'monthly', currency);
  const localAnnualMonthlyEquiv = Number((localAnnualTotal / 12).toFixed(2));

  // Backend state synchronized from POST /calculate-account-plan
  const [apiResult, setApiResult] = useState<{
    monthly_amount: number;
    annual_amount_total: number;
    annual_monthly_equivalent: number;
    discount_percent: number;
    currency_symbol: string;
    locale: string;
  } | null>(null);

  useEffect(() => {
    let isMounted = true;
    async function fetchPricingFromBackend() {
      try {
        const res = await fetch('/api/v1/service-subscriptions/calculate-account-plan', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ account_count: accountCount, billing_cycle: billingCycle, currency })
        });
        if (res.ok) {
          const data = await res.json();
          if (data.success && isMounted) {
            setApiResult({
              monthly_amount: data.monthly_amount,
              annual_amount_total: data.annual_amount_total,
              annual_monthly_equivalent: data.annual_monthly_equivalent,
              discount_percent: data.discount_percent,
              currency_symbol: data.currency_symbol || activeRateConfig.symbol,
              locale: data.locale || activeRateConfig.locale
            });
          }
        }
      } catch {
        // Fallback to local computation if backend API is unreachable in static export
      }
    }
    fetchPricingFromBackend();
    return () => {
      isMounted = false;
    };
  }, [accountCount, billingCycle, currency, activeTier]);

  const annualTotalCost = apiResult ? apiResult.annual_amount_total : localAnnualTotal;
  const monthlyTotalCost = apiResult ? apiResult.monthly_amount : localMonthlyTotal;
  const annualMonthlyEquiv = apiResult ? apiResult.annual_monthly_equivalent : localAnnualMonthlyEquiv;
  const currentSymbol = apiResult ? apiResult.currency_symbol : activeRateConfig.symbol;
  const currentLocale = apiResult ? apiResult.locale : activeRateConfig.locale;

  const formatPrice = (amount: number) => {
    return `${currentSymbol}${amount.toLocaleString(currentLocale, { minimumFractionDigits: amount % 1 === 0 ? 0 : 2, maximumFractionDigits: 2 })}`;
  };

  const growthConfig = getRateConfig('growth', currency);
  const scaleConfig = getRateConfig('scale', currency);
  const enterpriseConfig = getRateConfig('enterprise', currency);

  const sharedFeatures = [
    'Complete Campus OS (All 40+ Role Workspaces)',
    'Unlimited AI Concierge & Chat Assistant Queries',
    'Realtime GPS Bus & Transit Telemetry',
    'RFID / QR Gate Security & Attendance Engine',
    'Automated NAAC, NBA, and AISHE Compliance Reports',
    'Hostel, Canteen Wallet & Gym Pass Management',
    'Parent Portal & WhatsApp API Communication Engine',
    'Native Mobile iOS & Android App Access'
  ];

  return (
    <div className="min-h-screen bg-slate-950 dark:bg-slate-950 light:bg-slate-50 text-slate-100 dark:text-slate-100 light:text-slate-900 transition-colors duration-300 font-sans">
      <Header />

      {/* Hero Header */}
      <section className="pt-32 pb-16 px-6 md:px-12 max-w-7xl mx-auto text-center space-y-6">
        <div className="inline-flex items-center gap-2 px-3.5 py-1.5 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 font-mono text-xs uppercase tracking-widest">
          <Sparkles className="w-3.5 h-3.5" />
          Transparent Per-Person Pricing
        </div>

        <h1 className="text-4xl md:text-6xl font-extrabold tracking-tight text-white dark:text-white light:text-slate-900 max-w-4xl mx-auto leading-tight">
          One Platform. Every Feature. <br />
          <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-400 via-sky-400 to-indigo-300">
            Tiered Per-Person Volume Rates.
          </span>
        </h1>

        <p className="text-slate-400 dark:text-slate-400 light:text-slate-600 text-base md:text-lg max-w-2xl mx-auto leading-relaxed">
          No feature gating, account blocks, or hidden add-on costs. Every IRIS 365 plan includes the complete Campus
          Operating System suite for your entire institution.
        </p>

        {/* Currency & Billing Controls */}
        <div className="pt-6 flex flex-col sm:flex-row items-center justify-center gap-6">
          {/* Currency Selector */}
          <div className="flex items-center gap-2 bg-slate-900/80 dark:bg-slate-900/80 light:bg-white p-1.5 rounded-2xl border border-slate-800 dark:border-slate-800 light:border-slate-300 shadow-md">
            <span className="text-[11px] font-mono text-slate-400 pl-2 flex items-center gap-1.5 uppercase font-bold">
              <Globe className="w-3.5 h-3.5 text-indigo-400" />
              Currency:
            </span>
            <div className="flex items-center gap-1">
              {(Object.keys(CURRENCIES) as CurrencyCode[]).map((code) => (
                <button
                  key={code}
                  onClick={() => setCurrency(code)}
                  className={`px-3 py-1 rounded-xl text-xs font-mono font-bold transition-all ${
                    currency === code
                      ? 'bg-indigo-600 text-white shadow-md'
                      : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/50'
                  }`}
                >
                  {CURRENCIES[code].label}
                </button>
              ))}
            </div>
          </div>

          {/* Monthly / Annual Billing Toggle */}
          <div className="flex items-center gap-4 bg-slate-900/80 dark:bg-slate-900/80 light:bg-white p-2 rounded-2xl border border-slate-800 dark:border-slate-800 light:border-slate-300 shadow-md">
            <span
              className={`text-xs font-semibold uppercase tracking-wider ${billingCycle === 'monthly' ? 'text-white dark:text-white light:text-slate-900 font-bold' : 'text-slate-400'}`}
            >
              Monthly
            </span>

            <button
              onClick={() => setBillingCycle(billingCycle === 'monthly' ? 'annual' : 'monthly')}
              className="w-14 h-7 rounded-full bg-slate-800 dark:bg-slate-800 light:bg-slate-200 p-1 relative border border-slate-700 dark:border-slate-700 light:border-slate-300 transition-all focus:outline-none"
              aria-label="Toggle Billing Cycle"
            >
              <div
                className={`w-5 h-5 rounded-full bg-indigo-500 shadow-md transition-transform transform ${
                  billingCycle === 'annual' ? 'translate-x-7 bg-indigo-400' : 'translate-x-0'
                }`}
              />
            </button>

            <div className="flex items-center gap-2">
              <span
                className={`text-xs font-semibold uppercase tracking-wider ${billingCycle === 'annual' ? 'text-white dark:text-white light:text-slate-900 font-bold' : 'text-slate-400'}`}
              >
                Annual
              </span>
              <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 font-mono text-[10px] font-bold uppercase">
                Save ~17%
              </span>
            </div>
          </div>
        </div>
      </section>

      {/* Tier Cards Section */}
      <section className="max-w-7xl mx-auto px-6 md:px-12 pb-20">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 items-stretch">
          {/* Growth Tier */}
          <div className="rounded-3xl border border-slate-800 dark:border-slate-800 light:border-slate-200 bg-slate-900/50 dark:bg-slate-900/50 light:bg-white p-8 flex flex-col justify-between shadow-xl space-y-6">
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <h3 className="text-xl font-bold text-white dark:text-white light:text-slate-900">Growth</h3>
                <span className="px-3 py-1 rounded-full bg-slate-800 dark:bg-slate-800 light:bg-slate-100 text-slate-300 dark:text-slate-300 light:text-slate-700 text-xs font-mono">
                  500 – 2,500 Accounts
                </span>
              </div>

              <p className="text-xs text-slate-400 dark:text-slate-400 light:text-slate-600 leading-relaxed">
                Ideal for growing colleges and single-campus institutions requiring automated core operations.
              </p>

              <div className="pt-2">
                <div className="flex items-baseline gap-2">
                  <span className="text-4xl font-extrabold text-white dark:text-white light:text-slate-900 font-mono">
                    {growthConfig.symbol}
                    {billingCycle === 'annual' ? growthConfig.annual_rate : growthConfig.monthly_rate}
                  </span>
                  <span className="text-xs text-slate-400 font-mono">
                    / person / {billingCycle === 'annual' ? 'year' : 'month'}
                  </span>
                </div>
                {billingCycle === 'annual' ? (
                  <span className="text-[11px] text-emerald-400 font-mono block mt-1">
                    Billed annually (Save ~17% vs monthly)
                  </span>
                ) : (
                  <span className="text-[11px] text-slate-400 font-mono block mt-1">
                    Billed monthly ({growthConfig.symbol}
                    {(growthConfig.monthly_rate * 12).toFixed(2)}/person/yr equivalent)
                  </span>
                )}
              </div>

              <div className="pt-4 border-t border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-2.5">
                <span className="text-[10px] font-mono uppercase tracking-wider text-indigo-400 font-bold block">
                  Support & SLA
                </span>
                <p className="text-xs text-slate-300 dark:text-slate-300 light:text-slate-700 font-medium">
                  Standard Email & Ticket Support (24h SLA)
                </p>
              </div>

              <div className="space-y-2 pt-2">
                <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 block">
                  Features Included
                </span>
                {sharedFeatures.slice(0, 5).map((f, i) => (
                  <div
                    key={i}
                    className="flex items-center gap-2 text-xs text-slate-300 dark:text-slate-300 light:text-slate-700"
                  >
                    <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
                    <span>{f}</span>
                  </div>
                ))}
              </div>
            </div>

            <Link
              href={`/buy-now?tier=growth&accounts=${accountCount}&cycle=${billingCycle}&currency=${currency}`}
              className="w-full py-3 rounded-xl bg-slate-800 dark:bg-slate-800 light:bg-slate-200 hover:bg-slate-700 dark:hover:bg-slate-700 light:hover:bg-slate-300 text-white dark:text-white light:text-slate-900 font-bold text-xs text-center transition-all border border-slate-700 dark:border-slate-700 light:border-slate-300 block"
            >
              Get Started with Growth
            </Link>
          </div>

          {/* Scale Tier (Featured) */}
          <div className="rounded-3xl border-2 border-indigo-500 bg-slate-900/90 dark:bg-slate-900/90 light:bg-white p-8 flex flex-col justify-between shadow-2xl shadow-indigo-500/10 relative space-y-6">
            <div className="absolute -top-3.5 left-1/2 -translate-x-1/2 px-4 py-1 rounded-full bg-indigo-600 text-white font-mono text-[10px] uppercase font-extrabold tracking-widest shadow-md">
              Most Popular Choice
            </div>

            <div className="space-y-4 pt-2">
              <div className="flex justify-between items-center">
                <h3 className="text-xl font-bold text-white dark:text-white light:text-slate-900">Scale</h3>
                <span className="px-3 py-1 rounded-full bg-indigo-500/20 text-indigo-400 text-xs font-mono font-bold">
                  2,500 – 10,000 Accounts
                </span>
              </div>

              <p className="text-xs text-slate-400 dark:text-slate-400 light:text-slate-600 leading-relaxed">
                Designed for multi-department colleges and universities scaling telemetry and live operations.
              </p>

              <div className="pt-2">
                <div className="flex items-baseline gap-2">
                  <span className="text-4xl font-extrabold text-white dark:text-white light:text-slate-900 font-mono">
                    {scaleConfig.symbol}
                    {billingCycle === 'annual' ? scaleConfig.annual_rate : scaleConfig.monthly_rate}
                  </span>
                  <span className="text-xs text-slate-400 font-mono">
                    / person / {billingCycle === 'annual' ? 'year' : 'month'}
                  </span>
                </div>
                {billingCycle === 'annual' ? (
                  <span className="text-[11px] text-emerald-400 font-mono block mt-1">
                    Billed annually (Save ~17% vs monthly)
                  </span>
                ) : (
                  <span className="text-[11px] text-slate-400 font-mono block mt-1">
                    Billed monthly ({scaleConfig.symbol}
                    {(scaleConfig.monthly_rate * 12).toFixed(2)}/person/yr equivalent)
                  </span>
                )}
              </div>

              <div className="pt-4 border-t border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-2.5">
                <span className="text-[10px] font-mono uppercase tracking-wider text-indigo-400 font-bold block">
                  Support & SLA
                </span>
                <p className="text-xs text-slate-300 dark:text-slate-300 light:text-slate-700 font-medium">
                  Priority 24/7 Support & Dedicated Onboarding Specialist (4h SLA)
                </p>
              </div>

              <div className="space-y-2 pt-2">
                <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 block">
                  Features Included
                </span>
                {sharedFeatures.map((f, i) => (
                  <div
                    key={i}
                    className="flex items-center gap-2 text-xs text-slate-300 dark:text-slate-300 light:text-slate-700"
                  >
                    <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
                    <span>{f}</span>
                  </div>
                ))}
              </div>
            </div>

            <Link
              href={`/buy-now?tier=scale&accounts=${accountCount}&cycle=${billingCycle}&currency=${currency}`}
              className="w-full py-3.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs text-center transition-all shadow-lg shadow-indigo-600/25 block active:scale-95"
            >
              Get Started with Scale
            </Link>
          </div>

          {/* Enterprise Tier */}
          <div className="rounded-3xl border border-slate-800 dark:border-slate-800 light:border-slate-200 bg-slate-900/50 dark:bg-slate-900/50 light:bg-white p-8 flex flex-col justify-between shadow-xl space-y-6">
            <div className="space-y-4">
              <div className="flex justify-between items-center">
                <h3 className="text-xl font-bold text-white dark:text-white light:text-slate-900">Enterprise</h3>
                <span className="px-3 py-1 rounded-full bg-slate-800 dark:bg-slate-800 light:bg-slate-100 text-slate-300 dark:text-slate-300 light:text-slate-700 text-xs font-mono">
                  10,000+ Accounts
                </span>
              </div>

              <p className="text-xs text-slate-400 dark:text-slate-400 light:text-slate-600 leading-relaxed">
                For large multi-campus university systems requiring custom SLAs, dedicated infrastructure, and hardware
                integration.
              </p>

              <div className="pt-2">
                <div className="flex items-baseline gap-2">
                  <span className="text-4xl font-extrabold text-white dark:text-white light:text-slate-900 font-mono">
                    {enterpriseConfig.symbol}
                    {billingCycle === 'annual' ? enterpriseConfig.annual_rate : enterpriseConfig.monthly_rate}
                  </span>
                  <span className="text-xs text-slate-400 font-mono">
                    / person / {billingCycle === 'annual' ? 'year' : 'month'}
                  </span>
                </div>
                <span className="text-xs text-slate-400 font-mono block mt-1">
                  Custom SLA & dedicated infrastructure available for large deployments
                </span>
              </div>

              <div className="pt-4 border-t border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-2.5">
                <span className="text-[10px] font-mono uppercase tracking-wider text-indigo-400 font-bold block">
                  Support & SLA
                </span>
                <p className="text-xs text-slate-300 dark:text-slate-300 light:text-slate-700 font-medium">
                  Dedicated Account Manager, Custom Hardware Integration & Guaranteed 99.99% Uptime SLA
                </p>
              </div>

              <div className="space-y-2 pt-2">
                <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 block">
                  Features Included
                </span>
                {sharedFeatures.map((f, i) => (
                  <div
                    key={i}
                    className="flex items-center gap-2 text-xs text-slate-300 dark:text-slate-300 light:text-slate-700"
                  >
                    <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />
                    <span>{f}</span>
                  </div>
                ))}
              </div>
            </div>

            <Link
              href={`/contact?type=enterprise&currency=${currency}`}
              className="w-full py-3.5 rounded-xl bg-slate-800 dark:bg-slate-800 light:bg-slate-200 hover:bg-slate-700 text-white dark:text-white light:text-slate-900 font-bold text-xs text-center transition-all border border-slate-700 block"
            >
              Contact Sales
            </Link>
          </div>
        </div>
      </section>

      {/* Interactive Account Calculator Section */}
      <section className="bg-slate-900/60 dark:bg-slate-900/60 light:bg-white border-y border-slate-800 dark:border-slate-800 light:border-slate-200 py-20 px-6 md:px-12">
        <div className="max-w-5xl mx-auto space-y-12">
          <div className="text-center space-y-3">
            <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/10 text-indigo-400 font-mono text-xs uppercase font-bold">
              <Calculator className="w-4 h-4" />
              Interactive Price Calculator
            </div>
            <h2 className="text-3xl font-extrabold text-white dark:text-white light:text-slate-900 tracking-tight">
              Estimate Your Institution's Exact Investment
            </h2>
            <p className="text-xs text-slate-400 max-w-lg mx-auto">
              Select or type your total combined active user accounts (students + faculty & staff) to calculate your
              exact rate.
            </p>
          </div>

          {/* Calculator Control Panel */}
          <div className="p-8 rounded-3xl bg-slate-950 dark:bg-slate-950 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-200 shadow-2xl space-y-8">
            {/* Account Count Control (Slider + Uncapped Number Input) */}
            <div className="space-y-4">
              <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
                <label className="text-xs font-bold text-slate-300 dark:text-slate-300 light:text-slate-700 uppercase tracking-wider font-mono">
                  Total Active Accounts (Students + Staff)
                </label>
                <div className="flex items-center gap-2 bg-slate-900 dark:bg-slate-900 light:bg-slate-100 p-1.5 rounded-2xl border border-slate-800 dark:border-slate-800 light:border-slate-300 shadow-sm">
                  <input
                    type="number"
                    min={500}
                    step={500}
                    value={accountCount}
                    onChange={(e) => setAccountCount(Math.max(500, parseInt(e.target.value) || 500))}
                    className="w-32 text-2xl font-extrabold text-indigo-400 dark:text-indigo-400 light:text-indigo-600 font-mono bg-transparent text-right focus:outline-none focus:ring-1 focus:ring-indigo-500 rounded-lg px-2"
                  />
                  <span className="text-xs text-slate-400 dark:text-slate-400 light:text-slate-600 font-mono pr-2">
                    accounts
                  </span>
                </div>
              </div>

              <input
                type="range"
                min={SLIDER_MIN}
                max={SLIDER_MAX}
                step={500}
                value={Math.min(SLIDER_MAX, accountCount)}
                onChange={(e) => setAccountCount(parseInt(e.target.value))}
                className="w-full h-3 rounded-lg bg-slate-800 dark:bg-slate-800 light:bg-slate-200 accent-indigo-500 cursor-pointer"
              />

              {/* Absolutely Positioned Tick Labels (Part 1 Fix) */}
              <div className="relative h-6 text-[10px] font-mono text-slate-500 dark:text-slate-500 light:text-slate-600 mt-2">
                <span className="absolute -translate-x-1/2 whitespace-nowrap" style={{ left: `${getPct(500)}%` }}>
                  500
                </span>
                <span className="absolute -translate-x-1/2 whitespace-nowrap" style={{ left: `${getPct(2500)}%` }}>
                  2,500 (Growth)
                </span>
                <span className="absolute -translate-x-1/2 whitespace-nowrap" style={{ left: `${getPct(10000)}%` }}>
                  10,000 (Scale)
                </span>
                <span className="absolute -translate-x-1/2 whitespace-nowrap" style={{ left: `${getPct(15000)}%` }}>
                  15,000+ (Enterprise)
                </span>
              </div>
            </div>

            {/* Calculated Breakdown Grid */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-6 pt-6 border-t border-slate-800 dark:border-slate-800 light:border-slate-200">
              <div className="p-5 rounded-2xl bg-slate-900/60 dark:bg-slate-900/60 light:bg-white border border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-1">
                <span className="text-[10px] font-mono text-slate-400 uppercase block">Recommended Tier</span>
                <span className="text-lg font-bold text-white dark:text-white light:text-slate-900 uppercase font-mono">
                  {activeTier} Tier
                </span>
                <span className="text-[11px] text-slate-400 block font-mono">
                  {currentSymbol}
                  {activeRateConfig.annual_rate}/person/year marginal rate
                </span>
              </div>

              <div className="p-5 rounded-2xl bg-slate-900/60 dark:bg-slate-900/60 light:bg-white border border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-1">
                <span className="text-[10px] font-mono text-slate-400 uppercase block">Monthly Total Rate</span>
                <div className="flex items-baseline gap-2">
                  <span className="text-2xl font-bold text-white dark:text-white light:text-slate-900 font-mono">
                    {formatPrice(billingCycle === 'annual' ? annualMonthlyEquiv : monthlyTotalCost)}
                  </span>
                  <span className="text-xs text-slate-400 font-mono">/ mo</span>
                </div>
                {billingCycle === 'annual' && (
                  <span className="text-[10px] text-slate-500 line-through font-mono">
                    {formatPrice(monthlyTotalCost)} / mo (monthly option)
                  </span>
                )}
              </div>

              <div className="p-5 rounded-2xl bg-indigo-500/10 dark:bg-indigo-500/10 light:bg-indigo-50 border border-indigo-500/30 dark:border-indigo-500/30 light:border-indigo-200 space-y-1">
                <span className="text-[10px] font-mono text-indigo-400 dark:text-indigo-400 light:text-indigo-700 uppercase block font-bold">
                  Annual Total Investment
                </span>
                <span className="text-2xl font-bold text-indigo-300 dark:text-indigo-300 light:text-indigo-600 font-mono">
                  {formatPrice(annualTotalCost)}
                </span>
                <span className="text-[10px] text-emerald-400 dark:text-emerald-400 light:text-emerald-700 font-mono block">
                  Includes ~17% annual billing savings
                </span>
              </div>
            </div>

            {/* Itemized Graduated Price Breakdown & Blended Rate */}
            {(() => {
              const breakdown = getGraduatedBreakdown(accountCount, billingCycle, currency);
              return (
                <div className="p-5 rounded-2xl bg-slate-900/40 dark:bg-slate-900/40 light:bg-slate-50 border border-slate-800 dark:border-slate-800 light:border-slate-200 space-y-2.5">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-400 dark:text-slate-400 light:text-slate-600 font-bold block">
                    Graduated Investment Breakdown ({currency})
                  </span>
                  <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 font-mono text-xs">
                    {breakdown.bands.growth.count > 0 && (
                      <div className="flex justify-between items-center p-3 rounded-xl bg-slate-950 dark:bg-slate-950 light:bg-white border border-slate-800 dark:border-slate-800 light:border-slate-200">
                        <span className="text-slate-400">
                          {breakdown.bands.growth.count.toLocaleString()} × {currentSymbol}
                          {breakdown.bands.growth.rate} (Growth)
                        </span>
                        <span className="text-white dark:text-white light:text-slate-900 font-bold">
                          {currentSymbol}
                          {breakdown.bands.growth.amount.toLocaleString()}
                        </span>
                      </div>
                    )}
                    {breakdown.bands.scale.count > 0 && (
                      <div className="flex justify-between items-center p-3 rounded-xl bg-slate-950 dark:bg-slate-950 light:bg-white border border-slate-800 dark:border-slate-800 light:border-slate-200">
                        <span className="text-slate-400">
                          {breakdown.bands.scale.count.toLocaleString()} × {currentSymbol}
                          {breakdown.bands.scale.rate} (Scale)
                        </span>
                        <span className="text-white dark:text-white light:text-slate-900 font-bold">
                          {currentSymbol}
                          {breakdown.bands.scale.amount.toLocaleString()}
                        </span>
                      </div>
                    )}
                    {breakdown.bands.enterprise.count > 0 && (
                      <div className="flex justify-between items-center p-3 rounded-xl bg-slate-950 dark:bg-slate-950 light:bg-white border border-slate-800 dark:border-slate-800 light:border-slate-200">
                        <span className="text-slate-400">
                          {breakdown.bands.enterprise.count.toLocaleString()} × {currentSymbol}
                          {breakdown.bands.enterprise.rate} (Enterprise)
                        </span>
                        <span className="text-white dark:text-white light:text-slate-900 font-bold">
                          {currentSymbol}
                          {breakdown.bands.enterprise.amount.toLocaleString()}
                        </span>
                      </div>
                    )}
                  </div>
                  <div className="text-xs font-mono text-emerald-400 dark:text-emerald-400 light:text-emerald-700 font-bold pt-1">
                    Blended Effective Rate: {currentSymbol}
                    {breakdown.effectiveRate.toFixed(2)} / person / {billingCycle === 'annual' ? 'year' : 'month'}
                  </div>
                </div>
              );
            })()}

            <div className="flex flex-col sm:flex-row items-center justify-between gap-4 pt-2">
              <div className="flex items-center gap-2 text-xs text-slate-400 dark:text-slate-400 light:text-slate-600">
                <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
                <span>No Long-Term Lock-in. Try the free demo first.</span>
              </div>

              <Link
                href={`/buy-now?tier=${activeTier}&accounts=${accountCount}&cycle=${billingCycle}&currency=${currency}`}
                className="w-full sm:w-auto px-8 py-3.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-bold text-xs tracking-wide shadow-lg shadow-indigo-600/25 flex items-center justify-center gap-2"
              >
                <span>Proceed to Checkout</span>
                <ArrowRight className="w-4 h-4" />
              </Link>
            </div>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
