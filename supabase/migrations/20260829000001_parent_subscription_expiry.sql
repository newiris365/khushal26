-- Migration: Parent Subscription Validity (1-Year Expiry) & Auto Expiration
-- Date: 2026-08-29

-- 1. Add paid_at and valid_until columns to parent_platform_payments
ALTER TABLE parent_platform_payments
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS valid_until TIMESTAMPTZ;

-- 2. Update constraint on status column to support ('created', 'active', 'expired', 'failed')
ALTER TABLE parent_platform_payments
  DROP CONSTRAINT IF EXISTS parent_platform_payments_status_check;

ALTER TABLE parent_platform_payments
  ADD CONSTRAINT parent_platform_payments_status_check
  CHECK (status IN ('created', 'active', 'expired', 'failed', 'paid'));

-- Migrate existing 'paid' status rows to 'active', setting valid_until to 1 year from creation
UPDATE parent_platform_payments
SET 
  status = 'active',
  paid_at = COALESCE(paid_at, created_at, NOW()),
  valid_until = COALESCE(valid_until, created_at + INTERVAL '1 year', NOW() + INTERVAL '1 year')
WHERE status = 'paid';

-- 3. SQL function to auto-expire subscriptions past valid_until date
CREATE OR REPLACE FUNCTION expire_outdated_parent_subscriptions()
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE parent_platform_payments
  SET 
    status = 'expired',
    updated_at = NOW()
  WHERE status IN ('active', 'paid')
    AND valid_until IS NOT NULL
    AND valid_until < NOW();

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
