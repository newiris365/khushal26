-- Migration: Parent Self Onboarding & Platform Payments
-- Date: 2026-08-29

-- 1. Make institution_id nullable on parent_profiles for platform-registered parents
ALTER TABLE parent_profiles ALTER COLUMN institution_id DROP NOT NULL;

-- 2. Create parent_platform_payments table for self-serve parent onboarding fee (₹150)
CREATE TABLE IF NOT EXISTS parent_platform_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 150,
  currency TEXT NOT NULL DEFAULT 'INR',
  razorpay_order_id TEXT NOT NULL,
  razorpay_payment_id TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'paid', 'failed')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_parent_payments_order ON parent_platform_payments(razorpay_order_id);
CREATE INDEX IF NOT EXISTS idx_parent_payments_user ON parent_platform_payments(parent_user_id);
CREATE INDEX IF NOT EXISTS idx_parent_payments_status ON parent_platform_payments(status);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE parent_platform_payments ENABLE ROW LEVEL SECURITY;

-- Policy: Parent can read own platform payment records
CREATE POLICY parent_read_own_payments ON parent_platform_payments
  FOR SELECT
  USING (auth.uid() = parent_user_id);

-- Policy: Service role has full access
CREATE POLICY service_role_full_access_parent_payments ON parent_platform_payments
  FOR ALL
  USING (true)
  WITH CHECK (true);
