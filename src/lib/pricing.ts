export type CurrencyCode = 'INR' | 'USD' | 'EUR' | 'GBP';

export const GROWTH_BAND_MAX = 2500;
export const SCALE_BAND_MAX = 10000;

export interface TierRateConfig {
  annual_rate: number;
  monthly_rate: number;
  symbol: string;
  locale: string;
}

export const TIER_RATES: Record<string, Record<CurrencyCode, TierRateConfig>> = {
  growth: {
    INR: { annual_rate: 120, monthly_rate: 12, symbol: '₹', locale: 'en-IN' },
    USD: { annual_rate: 1.5, monthly_rate: 0.18, symbol: '$', locale: 'en-US' },
    EUR: { annual_rate: 1.38, monthly_rate: 0.17, symbol: '€', locale: 'de-DE' },
    GBP: { annual_rate: 1.2, monthly_rate: 0.14, symbol: '£', locale: 'en-GB' }
  },
  scale: {
    INR: { annual_rate: 100, monthly_rate: 10, symbol: '₹', locale: 'en-IN' },
    USD: { annual_rate: 1.25, monthly_rate: 0.15, symbol: '$', locale: 'en-US' },
    EUR: { annual_rate: 1.15, monthly_rate: 0.14, symbol: '€', locale: 'de-DE' },
    GBP: { annual_rate: 1.0, monthly_rate: 0.12, symbol: '£', locale: 'en-GB' }
  },
  enterprise: {
    INR: { annual_rate: 90, monthly_rate: 9, symbol: '₹', locale: 'en-IN' },
    USD: { annual_rate: 1.1, monthly_rate: 0.13, symbol: '$', locale: 'en-US' },
    EUR: { annual_rate: 1.0, monthly_rate: 0.12, symbol: '€', locale: 'de-DE' },
    GBP: { annual_rate: 0.9, monthly_rate: 0.11, symbol: '£', locale: 'en-GB' }
  }
};

export const CURRENCIES: Record<CurrencyCode, { label: string; symbol: string }> = {
  INR: { label: 'INR (₹)', symbol: '₹' },
  USD: { label: 'USD ($)', symbol: '$' },
  EUR: { label: 'EUR (€)', symbol: '€' },
  GBP: { label: 'GBP (£)', symbol: '£' }
};

/**
 * Resolves active tier name based on account count.
 */
export function getTier(accountCount: number): 'growth' | 'scale' | 'enterprise' {
  if (accountCount > SCALE_BAND_MAX) return 'enterprise';
  if (accountCount > GROWTH_BAND_MAX) return 'scale';
  return 'growth';
}

export interface GraduatedBreakdown {
  total: number;
  effectiveRate: number;
  currencySymbol: string;
  locale: string;
  bands: {
    growth: { count: number; rate: number; amount: number };
    scale: { count: number; rate: number; amount: number };
    enterprise: { count: number; rate: number; amount: number };
  };
}

/**
 * Calculates itemized graduated pricing breakdown and blended effective rate.
 */
export function getGraduatedBreakdown(
  accountCount: number,
  billingCycle: 'annual' | 'monthly' = 'annual',
  currency: CurrencyCode = 'INR'
): GraduatedBreakdown {
  const g = TIER_RATES.growth[currency] || TIER_RATES.growth.INR;
  const s = TIER_RATES.scale[currency] || TIER_RATES.scale.INR;
  const e = TIER_RATES.enterprise[currency] || TIER_RATES.enterprise.INR;

  const r1 = billingCycle === 'annual' ? g.annual_rate : g.monthly_rate;
  const r2 = billingCycle === 'annual' ? s.annual_rate : s.monthly_rate;
  const r3 = billingCycle === 'annual' ? e.annual_rate : e.monthly_rate;

  const inGrowthBand = Math.min(accountCount, GROWTH_BAND_MAX);
  const inScaleBand = Math.max(0, Math.min(accountCount, SCALE_BAND_MAX) - GROWTH_BAND_MAX);
  const inEnterpriseBand = Math.max(0, accountCount - SCALE_BAND_MAX);

  const amountGrowth = Number((inGrowthBand * r1).toFixed(2));
  const amountScale = Number((inScaleBand * r2).toFixed(2));
  const amountEnterprise = Number((inEnterpriseBand * r3).toFixed(2));

  const total = Number((amountGrowth + amountScale + amountEnterprise).toFixed(2));
  const effectiveRate = accountCount > 0 ? Number((total / accountCount).toFixed(2)) : 0;

  return {
    total,
    effectiveRate,
    currencySymbol: g.symbol,
    locale: g.locale,
    bands: {
      growth: { count: inGrowthBand, rate: r1, amount: amountGrowth },
      scale: { count: inScaleBand, rate: r2, amount: amountScale },
      enterprise: { count: inEnterpriseBand, rate: r3, amount: amountEnterprise }
    }
  };
}

/**
 * Computes graduated (marginal / tax-bracket style) total pricing.
 */
export function computeGraduatedTotal(
  accountCount: number,
  billingCycle: 'annual' | 'monthly' = 'annual',
  currency: CurrencyCode = 'INR'
): number {
  return getGraduatedBreakdown(accountCount, billingCycle, currency).total;
}

/**
 * Formats amount with currency symbol and locale formatting.
 */
export function formatPrice(amount: number, currency: CurrencyCode = 'INR'): string {
  const config = TIER_RATES.growth[currency] || TIER_RATES.growth.INR;
  return `${config.symbol}${amount.toLocaleString(config.locale, {
    minimumFractionDigits: amount % 1 === 0 ? 0 : 2,
    maximumFractionDigits: 2
  })}`;
}
