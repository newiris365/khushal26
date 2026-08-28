import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

export const dynamic = 'force-dynamic';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || process.env.SUPABASE_URL || '';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: { autoRefreshToken: false, persistSession: false }
});

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { phone } = body || {};

    if (!phone || typeof phone !== 'string' || phone.trim().length < 8) {
      return NextResponse.json({ success: false, error: 'Valid phone number is required.' }, { status: 400 });
    }

    const cleanPhone = phone.trim();

    // Call generate_parent_otp RPC or fallback to generating 6-digit OTP directly
    let otpCode = '123456';
    const { data: rpcData, error: rpcError } = await supabaseAdmin.rpc('generate_parent_otp', {
      p_phone: cleanPhone,
      p_purpose: 'register'
    });

    if (!rpcError && rpcData && rpcData.length > 0 && rpcData[0].otp_code) {
      otpCode = rpcData[0].otp_code;
    } else {
      // Direct fallback table insert into parent_otps
      otpCode = Math.floor(100000 + Math.random() * 900000).toString();
      const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();
      await supabaseAdmin.from('parent_otps').upsert({
        phone: cleanPhone,
        otp_code: otpCode,
        purpose: 'register',
        expires_at: expiresAt,
        is_used: false,
        created_at: new Date().toISOString()
      });
    }

    // Try importing sendTextMessage dynamically or mock send
    try {
      const whatsapp = require('../../../../services/whatsapp');
      if (whatsapp && typeof whatsapp.sendTextMessage === 'function') {
        await whatsapp.sendTextMessage(
          cleanPhone,
          `Your IRIS 365 Parent Registration OTP is ${otpCode}. Valid for 10 minutes.`,
          'auth'
        );
      }
    } catch {
      console.log(`[PARENT ONBOARDING OTP] Phone: ${cleanPhone}, OTP: ${otpCode}`);
    }

    return NextResponse.json({
      success: true,
      message: 'OTP sent successfully to your phone number.',
      // In dev environment when WhatsApp SMS gateway is unconfigured, return mock OTP for ease of test/demo
      dev_otp: process.env.NODE_ENV !== 'production' ? otpCode : undefined
    });
  } catch (err: any) {
    console.error('[POST /api/parent-onboarding/send-otp] Error:', err);
    return NextResponse.json({ success: false, error: err?.message || 'Failed to send OTP.' }, { status: 500 });
  }
}
