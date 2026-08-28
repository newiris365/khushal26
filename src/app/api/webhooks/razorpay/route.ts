import { NextRequest, NextResponse } from 'next/server';
import crypto from 'crypto';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '';
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';
const supabase = createClient(supabaseUrl, supabaseKey);

const webhookSecret = process.env.RAZORPAY_WEBHOOK_SECRET || 'super-secret-razorpay-webhook';

export async function POST(req: NextRequest) {
  try {
    const rawBody = await req.text();
    const signature = req.headers.get('x-razorpay-signature');

    if (!signature) {
      return NextResponse.json({ success: false, error: 'Missing signature' }, { status: 400 });
    }

    // Verify webhook signature
    const expectedSignature = crypto.createHmac('sha256', webhookSecret).update(rawBody).digest('hex');

    if (expectedSignature !== signature) {
      return NextResponse.json({ success: false, error: 'Invalid webhook signature' }, { status: 400 });
    }

    const body = JSON.parse(rawBody);
    const event = body.event;

    // Handle captured payments
    if (event === 'payment.captured') {
      const payment = body.payload.payment.entity;
      const orderId = payment.order_id;
      const amount = payment.amount / 100; // in INR

      console.log(`Payment captured: ID ${payment.id}, Order ${orderId}, Amount ₹${amount}`);

      // Update fee_payments status to Completed based on order_id
      const { error: feeError } = await supabase
        .from('fee_payments')
        .update({ status: 'Completed', transaction_id: payment.id })
        .eq('transaction_id', orderId); // orderId was saved as transaction_id temporarily during checkout

      if (feeError) {
        console.error('Webhook: failed to update fee payment record:', feeError);
      }

      // Check and update parent_platform_payments table
      const now = new Date();
      const validUntil = new Date(now.getTime() + 365 * 24 * 60 * 60 * 1000);
      const { error: parentPaymentError } = await supabase
        .from('parent_platform_payments')
        .update({
          status: 'active',
          paid_at: now.toISOString(),
          valid_until: validUntil.toISOString(),
          razorpay_payment_id: payment.id,
          updated_at: now.toISOString()
        })
        .eq('razorpay_order_id', orderId);

      if (parentPaymentError) {
        console.error('Webhook: failed to update parent_platform_payments record:', parentPaymentError);
      }
    }

    return NextResponse.json({ success: true });
  } catch (err: any) {
    console.error('Webhook error:', err);
    return NextResponse.json({ success: false, error: err.message }, { status: 500 });
  }
}
