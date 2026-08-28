import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import jwt from 'jsonwebtoken';
import { getRazorpayClient } from '../../../../lib/razorpay';

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

export async function POST(req: NextRequest) {
  try {
    const userPayload = extractUserFromHeader(req);
    const body = await req.json().catch(() => ({}));
    const parentUserId = userPayload?.id || body?.parent_user_id;

    if (!parentUserId) {
      return NextResponse.json(
        { success: false, error: 'Authentication required to create platform payment order.' },
        { status: 401 }
      );
    }

    const amount = 150;
    const amountPaise = 15000;
    const currency = 'INR';

    let orderId = `order_mock_parent_${Date.now()}`;
    let keyId = process.env.RAZORPAY_KEY_ID || 'rzp_test_mock';

    const razorpay = getRazorpayClient();
    if (razorpay) {
      try {
        const order = await razorpay.orders.create({
          amount: amountPaise,
          currency,
          receipt: `prnt_${Date.now().toString().slice(-8)}`,
          notes: {
            parent_user_id: parentUserId,
            purpose: 'parent_platform_access_fee'
          }
        });
        orderId = order.id as string;
      } catch (err: any) {
        console.warn('[CREATE PARENT ORDER] Razorpay API fallback to mock order:', err?.message);
      }
    }

    // Insert record in parent_platform_payments
    const { error: insertError } = await supabaseAdmin.from('parent_platform_payments').insert({
      parent_user_id: parentUserId,
      amount,
      currency,
      razorpay_order_id: orderId,
      status: 'created',
      created_at: new Date().toISOString()
    });

    if (insertError) {
      console.error('Failed to record parent_platform_payments:', insertError);
    }

    return NextResponse.json({
      success: true,
      order_id: orderId,
      amount,
      amount_paise: amountPaise,
      currency,
      key_id: keyId
    });
  } catch (err: any) {
    console.error('[POST /api/parent-onboarding/create-order] Error:', err);
    return NextResponse.json(
      { success: false, error: err?.message || 'Failed to create payment order.' },
      { status: 500 }
    );
  }
}
