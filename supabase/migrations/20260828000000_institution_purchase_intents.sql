-- Create table for self-serve purchase intents (Buy Now flow)
CREATE TABLE IF NOT EXISTS institution_purchase_intents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_name TEXT NOT NULL,
  contact_name TEXT NOT NULL,
  contact_email TEXT NOT NULL,
  contact_phone TEXT NOT NULL,
  city TEXT,
  tier TEXT NOT NULL,
  account_count INT NOT NULL,
  billing_cycle TEXT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'INR',
  amount_paid NUMERIC NOT NULL,
  razorpay_order_id TEXT NOT NULL,
  razorpay_payment_id TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'paid_pending_setup',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast ordering by created_at in admin inbox
CREATE INDEX IF NOT EXISTS idx_purchase_intents_created_at ON institution_purchase_intents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_intents_status ON institution_purchase_intents(status);
