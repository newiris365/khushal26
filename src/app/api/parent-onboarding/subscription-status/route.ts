import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import jwt from 'jsonwebtoken';

export const dynamic = 'force-dynamic';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { autoRefreshToken: false, persistSession: false }
});

const JWT_SECRET = process.env.JWT_SECRET || 'test-secret-key-that-is-at-least-32-characters-long';

function extractUserFromHeader(req: NextRequest): any {
  const authHeader = req.headers.get('authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return null;
  }
  const token = authHeader.substring(7);
  try {
    return jwt.verify(token, JWT_SECRET);
  } catch {
    return null;
  }
}

export async function GET(req: NextRequest) {
  try {
    const userPayload = extractUserFromHeader(req);
    const { searchParams } = new URL(req.url);
    const parentUserId = userPayload?.id || searchParams.get('parent_user_id');

    if (!parentUserId) {
      return NextResponse.json({ success: false, error: 'Authentication required.' }, { status: 401 });
    }

    const now = new Date();

    // 1. Trigger auto-expiration RPC for any outdated active payments
    await supabaseAdmin.rpc('expire_outdated_parent_subscriptions').catch(() => null);

    // Also run direct fallback update for outdated rows
    await supabaseAdmin
      .from('parent_platform_payments')
      .update({ status: 'expired', updated_at: now.toISOString() })
      .in('status', ['active', 'paid'])
      .lt('valid_until', now.toISOString())
      .catch(() => null);

    // 2. Fetch latest active/paid record for this parent
    const { data: payments } = await supabaseAdmin
      .from('parent_platform_payments')
      .select('*')
      .eq('parent_user_id', parentUserId)
      .order('created_at', { ascending: false });

    if (!payments || payments.length === 0) {
      return NextResponse.json({
        success: true,
        active: false,
        valid_until: null,
        days_remaining: 0,
        status: 'none'
      });
    }

    const latestPayment = payments.find((p: any) => p.status === 'active' || p.status === 'paid') || payments[0];

    let validUntilDate: Date | null = null;
    if (latestPayment.valid_until) {
      validUntilDate = new Date(latestPayment.valid_until);
    } else if (latestPayment.created_at && (latestPayment.status === 'active' || latestPayment.status === 'paid')) {
      validUntilDate = new Date(new Date(latestPayment.created_at).getTime() + 365 * 24 * 60 * 60 * 1000);
    }

    const isActiveStatus =
      (latestPayment.status === 'active' || latestPayment.status === 'paid') &&
      (!validUntilDate || validUntilDate.getTime() > now.getTime());

    let daysRemaining = 0;
    if (isActiveStatus && validUntilDate) {
      const diffTime = validUntilDate.getTime() - now.getTime();
      daysRemaining = Math.max(0, Math.ceil(diffTime / (1000 * 60 * 60 * 24)));
    }

    return NextResponse.json({
      success: true,
      active: isActiveStatus,
      valid_until: validUntilDate ? validUntilDate.toISOString() : null,
      days_remaining: daysRemaining,
      status: latestPayment.status
    });
  } catch (err: any) {
    console.error('[GET /api/parent-onboarding/subscription-status] Error:', err);
    return NextResponse.json(
      { success: false, error: err?.message || 'Failed to check subscription status.' },
      { status: 500 }
    );
  }
}
