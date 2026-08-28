import { Router, Request, Response } from 'express';
import { z } from 'zod';
import { supabaseAdmin } from '../config/supabase';
import { authMiddleware, requireRole } from '../middleware/auth';
import { getRazorpayClient } from '../lib/razorpay';
import crypto from 'crypto';

const router = Router();

const pricingPlanSchema = z.object({
  institution_id: z.string().uuid('Invalid institution_id'),
  service_type: z.enum(['hostel', 'transit', 'gym']),
  name: z.string().min(1, 'Name is required'),
  description: z.string().optional(),
  price: z.number().nonnegative('Price must be non-negative'),
  duration_days: z.number().int().positive().optional().default(30),
  features: z.array(z.string()).optional().default([])
});

const initiateSubscriptionSchema = z.object({
  student_id: z.string().uuid('Invalid student_id'),
  pricing_id: z.string().uuid('Invalid pricing_id')
});

const verifySubscriptionSchema = z.object({
  student_id: z.string().uuid('Invalid student_id'),
  pricing_id: z.string().uuid('Invalid pricing_id'),
  razorpay_order_id: z.string().optional(),
  razorpay_payment_id: z.string().optional(),
  razorpay_signature: z.string().optional()
});

const accountPlanSchema = z.object({
  account_count: z.number().int().min(1, 'Minimum account count is 1'),
  billing_cycle: z.enum(['monthly', 'annual']).default('annual'),
  currency: z.enum(['INR', 'USD', 'EUR', 'GBP']).default('INR')
});

const createPurchaseOrderSchema = z.object({
  institution_name: z.string().min(1, 'Institution name is required'),
  contact_name: z.string().min(1, 'Contact name is required'),
  contact_email: z.string().email('Valid contact email is required'),
  contact_phone: z.string().min(1, 'Contact phone is required'),
  city: z.string().optional().default(''),
  tier: z.enum(['growth', 'scale', 'enterprise']),
  account_count: z.number().int().min(1, 'Minimum account count is 1'),
  billing_cycle: z.enum(['monthly', 'annual']),
  currency: z.enum(['INR', 'USD', 'EUR', 'GBP']).default('INR')
});

const verifyPurchaseSchema = z.object({
  institution_name: z.string().min(1, 'Institution name is required'),
  contact_name: z.string().min(1, 'Contact name is required'),
  contact_email: z.string().email('Valid contact email is required'),
  contact_phone: z.string().min(1, 'Contact phone is required'),
  city: z.string().optional().default(''),
  tier: z.enum(['growth', 'scale', 'enterprise']),
  account_count: z.number().int().min(1, 'Minimum account count is 1'),
  billing_cycle: z.enum(['monthly', 'annual']),
  currency: z.enum(['INR', 'USD', 'EUR', 'GBP']).default('INR'),
  razorpay_order_id: z.string().min(1, 'Razorpay order ID is required'),
  razorpay_payment_id: z.string().min(1, 'Razorpay payment ID is required'),
  razorpay_signature: z.string().min(1, 'Razorpay signature is required')
});

import { computeGraduatedTotal, getTier, TIER_RATES, CurrencyCode } from '../lib/pricing';

// ========== PUBLIC ENDPOINTS ==========

// ========== ACCOUNT-BASED PRICING CALCULATOR ==========
router.post('/calculate-account-plan', async (req: Request, res: Response) => {
  try {
    const parse = accountPlanSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }
    const { account_count, billing_cycle, currency } = parse.data;

    const tier = getTier(account_count);
    const tierConfig = TIER_RATES[tier] || TIER_RATES.growth;
    const config = tierConfig[currency as CurrencyCode] || tierConfig.INR;

    const rate_per_person_annual = config.annual_rate;
    const rate_per_person_monthly = config.monthly_rate;

    const annual_amount_total = computeGraduatedTotal(account_count, 'annual', currency as CurrencyCode);
    const monthly_amount = computeGraduatedTotal(account_count, 'monthly', currency as CurrencyCode);
    const annual_monthly_equivalent = Number((annual_amount_total / 12).toFixed(2));

    return res.status(200).json({
      success: true,
      account_count,
      tier,
      billing_cycle,
      currency,
      currency_symbol: config.symbol,
      locale: config.locale,
      rate_per_person_annual,
      rate_per_person_monthly,
      monthly_amount,
      annual_amount_total,
      annual_monthly_equivalent,
      discount_percent: 17,
      support_level:
        tier === 'growth'
          ? 'Standard Email & Ticket Support (24h SLA)'
          : tier === 'scale'
            ? 'Priority 24/7 Support & Dedicated Onboarding Specialist (4h SLA)'
            : 'Dedicated Account Manager, Custom Hardware Integration & Guaranteed 99.99% Uptime SLA',
      features_included: [
        'Full Campus OS Features (All Modules Unlocked)',
        'Unlimited AI Concierge Queries',
        'Realtime GPS Transit & Gate hardware sync',
        'Automated NAAC / NBA / AISHE Accreditation Reports',
        'Mobile App Access for Students, Parents & Staff'
      ]
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error calculating subscription.' });
  }
});

// ========== PURCHASE INTENT: CREATE ORDER (PUBLIC) ==========
router.post('/purchase-intent/create-order', async (req: Request, res: Response) => {
  try {
    const parse = createPurchaseOrderSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }
    const {
      institution_name,
      contact_name,
      contact_email,
      contact_phone,
      city,
      tier,
      account_count,
      billing_cycle,
      currency
    } = parse.data;

    const computedTotal = computeGraduatedTotal(account_count, billing_cycle, currency as CurrencyCode);
    const amountPaise = Math.round(computedTotal * 100);

    const activeTier = getTier(account_count);
    const tierConfig = TIER_RATES[activeTier] || TIER_RATES.growth;
    const config = tierConfig[currency as CurrencyCode] || tierConfig.INR;

    const razorpay = getRazorpayClient();
    if (razorpay) {
      try {
        const options = {
          amount: amountPaise,
          currency: currency === 'INR' ? 'INR' : 'USD',
          receipt: `purch_${Date.now().toString().slice(-8)}`,
          notes: {
            institution_name,
            contact_email,
            tier: activeTier,
            account_count,
            billing_cycle,
            currency
          }
        };
        const order = await razorpay.orders.create(options);
        return res.status(200).json({
          success: true,
          order_id: order.id,
          amount: computedTotal,
          amount_paise: amountPaise,
          currency,
          currency_symbol: config.symbol,
          key_id: process.env.RAZORPAY_KEY_ID || ''
        });
      } catch (err: any) {
        // Fallback to mock order when Razorpay API key is invalid or unreachable
      }
    }

    // Mock fallback when Razorpay keys are not configured or in test environment
    const mockOrderId = `order_mock_${Date.now()}`;
    return res.status(200).json({
      success: true,
      order_id: mockOrderId,
      amount: computedTotal,
      amount_paise: amountPaise,
      currency,
      currency_symbol: config.symbol,
      key_id: 'rzp_test_mock'
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Failed to create purchase order.' });
  }
});

// ========== PURCHASE INTENT: VERIFY PAYMENT (PUBLIC) ==========
router.post('/purchase-intent/verify', async (req: Request, res: Response) => {
  try {
    const parse = verifyPurchaseSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }
    const {
      institution_name,
      contact_name,
      contact_email,
      contact_phone,
      city,
      tier,
      account_count,
      billing_cycle,
      currency,
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature
    } = parse.data;

    const expectedAmountTotal = computeGraduatedTotal(account_count, billing_cycle, currency as CurrencyCode);
    const expectedPaise = Math.round(expectedAmountTotal * 100);

    const isMock = razorpay_order_id.startsWith('order_mock_') || razorpay_payment_id.startsWith('pay_mock_');

    const razorpay = getRazorpayClient();
    if (razorpay && !isMock) {
      const secret = process.env.RAZORPAY_KEY_SECRET;
      if (!secret) {
        return res.status(500).json({ success: false, error: 'Razorpay secret key not configured on server.' });
      }

      // 1. Verify HMAC Signature
      const generatedSignature = crypto
        .createHmac('sha256', secret)
        .update(`${razorpay_order_id}|${razorpay_payment_id}`)
        .digest('hex');

      const sigBuf = Buffer.from(razorpay_signature);
      const genBuf = Buffer.from(generatedSignature);
      if (sigBuf.length !== genBuf.length || !crypto.timingSafeEqual(sigBuf, genBuf)) {
        return res.status(400).json({ success: false, error: 'Invalid Razorpay payment signature.' });
      }

      // 2. Fetch payment entity from Razorpay API
      const payment = await razorpay.payments.fetch(razorpay_payment_id);
      if (!payment || payment.status !== 'captured') {
        return res.status(400).json({ success: false, error: 'Payment status is not captured.' });
      }

      if (payment.amount !== expectedPaise) {
        return res.status(400).json({
          success: false,
          error: `Payment amount mismatch. Expected ${expectedPaise} paise, but received ${payment.amount} paise.`
        });
      }
    }

    // 3. Idempotency Check & Database Insertion
    const { data: existing } = await supabaseAdmin
      .from('institution_purchase_intents')
      .select('id')
      .eq('razorpay_payment_id', razorpay_payment_id)
      .maybeSingle();

    if (existing) {
      return res
        .status(409)
        .json({ success: false, error: 'Payment ID already recorded. Duplicate submission rejected.' });
    }

    const { data: inserted, error: insertErr } = await supabaseAdmin
      .from('institution_purchase_intents')
      .insert({
        institution_name,
        contact_name,
        contact_email,
        contact_phone,
        city: city || '',
        tier,
        account_count,
        billing_cycle,
        currency,
        amount_paid: expectedAmountTotal,
        razorpay_order_id,
        razorpay_payment_id,
        status: 'paid_pending_setup'
      })
      .select('*')
      .single();

    if (insertErr) {
      return res.status(500).json({ success: false, error: 'Failed to record purchase intent record.' });
    }

    return res.status(200).json({
      success: true,
      message: 'Payment verified and purchase intent recorded successfully.',
      purchase_intent: inserted
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error verifying purchase intent.' });
  }
});

// ========== AUTHENTICATED ENDPOINTS BELOW ==========
router.use(authMiddleware);

// GET /purchase-intents — SuperAdmin / Admin inbox for purchase intents
router.get('/purchase-intents', async (req: Request, res: Response) => {
  try {
    const userRole = req.user?.role;
    if (userRole !== 'SuperAdmin' && userRole !== 'Admin' && userRole !== 'Director') {
      return res.status(403).json({ success: false, error: 'Access denied. SuperAdmin or Admin role required.' });
    }

    const { data, error } = await supabaseAdmin
      .from('institution_purchase_intents')
      .select('*')
      .order('created_at', { ascending: false });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, purchase_intents: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error fetching purchase intents.' });
  }
});

// PATCH /purchase-intent/:id/status — Mark intent as provisioned
router.patch('/purchase-intent/:id/status', async (req: Request, res: Response) => {
  try {
    const userRole = req.user?.role;
    if (userRole !== 'SuperAdmin' && userRole !== 'Admin' && userRole !== 'Director') {
      return res.status(403).json({ success: false, error: 'Access denied. SuperAdmin or Admin role required.' });
    }

    const { id } = req.params;
    const { status } = req.body;
    if (!['paid_pending_setup', 'provisioned'].includes(status)) {
      return res
        .status(400)
        .json({ success: false, error: 'Invalid status. Must be paid_pending_setup or provisioned.' });
    }

    const { data, error } = await supabaseAdmin
      .from('institution_purchase_intents')
      .update({ status, updated_at: new Date().toISOString() })
      .eq('id', id)
      .select('*')
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, purchase_intent: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error updating purchase intent status.' });
  }
});

// ========== PRICING MANAGEMENT (Institute Admin) ==========

// GET /pricing/:institutionId — List all pricing plans for an institution
router.get('/pricing/:institutionId', async (req: Request, res: Response) => {
  try {
    const { institutionId } = req.params;
    const { service_type } = req.query;

    let query = supabaseAdmin
      .from('service_pricing')
      .select('*')
      .eq('institution_id', institutionId)
      .eq('is_active', true)
      .order('service_type')
      .order('price');

    if (service_type) {
      query = query.eq('service_type', service_type);
    }

    const { data, error } = await query;
    if (error) return res.status(500).json({ success: false, error: error.message });

    return res.status(200).json({ success: true, pricing: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

// POST /pricing — Create or update a pricing plan (Admin only)
router.post('/pricing', requireRole(['Admin', 'SuperAdmin']), async (req: Request, res: Response) => {
  try {
    const parse = pricingPlanSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }
    const { institution_id, service_type, name, description, price, duration_days, features } = parse.data;

    const { data, error } = await supabaseAdmin
      .from('service_pricing')
      .upsert(
        {
          institution_id,
          service_type,
          name,
          description: description || null,
          price,
          duration_days: duration_days || 30,
          features: features || [],
          is_active: true,
          updated_at: new Date().toISOString()
        },
        { onConflict: 'institution_id,service_type,name' }
      )
      .select()
      .single();

    if (error) return res.status(500).json({ success: false, error: error.message });
    return res.status(200).json({ success: true, plan: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

// DELETE /pricing/:id — Deactivate a pricing plan (Admin only)
router.delete('/pricing/:id', requireRole(['Admin', 'SuperAdmin']), async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { error } = await supabaseAdmin
      .from('service_pricing')
      .update({ is_active: false, updated_at: new Date().toISOString() })
      .eq('id', id);

    if (error) return res.status(500).json({ success: false, error: error.message });
    return res.status(200).json({ success: true });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

// ========== SUBSCRIPTION STATUS ==========

// GET /status/:studentId — Check if student has active subscription for a service type
router.get('/status/:studentId', async (req: Request, res: Response) => {
  try {
    const { studentId } = req.params;
    const { service_type } = req.query;

    const today = new Date().toISOString().split('T')[0];

    let query = supabaseAdmin
      .from('service_subscriptions')
      .select(
        'id, service_type, start_date, end_date, amount_paid, status, pricing_id, service_pricing(name, price, features)'
      )
      .eq('student_id', studentId)
      .eq('status', 'active')
      .gte('end_date', today);

    if (service_type) {
      query = query.eq('service_type', service_type);
    }

    const { data, error } = await query;
    if (error) return res.status(500).json({ success: false, error: error.message });

    // Build a map: service_type → subscription details
    const subscriptions: Record<string, any> = {};
    for (const sub of data || []) {
      subscriptions[sub.service_type] = {
        id: sub.id,
        end_date: sub.end_date,
        amount_paid: sub.amount_paid,
        plan_name: (sub as any).service_pricing?.name || 'Unknown',
        features: (sub as any).service_pricing?.features || []
      };
    }

    return res.status(200).json({
      success: true,
      has_hostel: !!subscriptions['hostel'],
      has_transit: !!subscriptions['transit'],
      has_gym: !!subscriptions['gym'],
      subscriptions
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

// ========== PURCHASE FLOW ==========

// POST /initiate — Create Razorpay order for a service subscription
router.post('/initiate', async (req: Request, res: Response) => {
  try {
    const parse = initiateSubscriptionSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }
    const { student_id, pricing_id } = parse.data;

    // Fetch pricing plan
    const { data: plan, error: planError } = await supabaseAdmin
      .from('service_pricing')
      .select('*')
      .eq('id', pricing_id)
      .eq('is_active', true)
      .single();

    if (planError || !plan) {
      return res.status(400).json({ success: false, error: 'Pricing plan not found or inactive.' });
    }

    const amount = Math.round(plan.price * 100); // paise
    const razorpay = getRazorpayClient();

    if (razorpay) {
      const order = await razorpay.orders.create({
        amount,
        currency: 'INR',
        receipt: `svc_${plan.service_type}_${student_id}_${Date.now()}`.slice(0, 40),
        notes: {
          type: 'service_subscription',
          service_type: plan.service_type,
          pricing_id: plan.id,
          student_id,
          institution_id: plan.institution_id
        }
      });

      return res.status(200).json({
        success: true,
        order_id: order.id,
        amount: order.amount,
        currency: order.currency,
        key_id: process.env.RAZORPAY_KEY_ID,
        plan_name: plan.name,
        service_type: plan.service_type
      });
    }

    // Mock/Sandbox Mode
    const mockOrderId = 'order_mock_svc_' + Math.random().toString(36).substring(2, 12);
    return res.status(200).json({
      success: true,
      order_id: mockOrderId,
      amount,
      currency: 'INR',
      key_id: 'rzp_test_mock',
      mock: true,
      plan_name: plan.name,
      service_type: plan.service_type
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error initiating payment.' });
  }
});

// POST /verify — Verify Razorpay payment and activate subscription
router.post('/verify', async (req: Request, res: Response) => {
  try {
    const parse = verifySubscriptionSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }
    const { razorpay_order_id, razorpay_payment_id, razorpay_signature, student_id, pricing_id } = parse.data;

    // Fetch pricing plan
    const { data: plan } = await supabaseAdmin.from('service_pricing').select('*').eq('id', pricing_id).single();

    if (!plan) {
      return res.status(400).json({ success: false, error: 'Pricing plan not found.' });
    }

    // Verify Razorpay signature if not mock
    const secret = process.env.RAZORPAY_KEY_SECRET;
    if (secret && razorpay_order_id && !razorpay_order_id.startsWith('order_mock_')) {
      const generatedSignature = crypto
        .createHmac('sha256', secret)
        .update(`${razorpay_order_id}|${razorpay_payment_id}`)
        .digest('hex');

      if (generatedSignature !== razorpay_signature) {
        return res.status(400).json({ success: false, error: 'Razorpay signature validation failed.' });
      }
    }

    // Check for existing active subscription of same type
    const today = new Date().toISOString().split('T')[0];
    const { data: existing } = await supabaseAdmin
      .from('service_subscriptions')
      .select('id, end_date')
      .eq('student_id', student_id)
      .eq('service_type', plan.service_type)
      .eq('status', 'active')
      .gte('end_date', today)
      .maybeSingle();

    if (existing) {
      return res.status(409).json({
        success: false,
        error: `Active ${plan.service_type} subscription already exists until ${existing.end_date}.`
      });
    }

    // Create subscription
    const endDate = new Date(Date.now() + plan.duration_days * 24 * 3600 * 1000).toISOString().split('T')[0];

    const { data: sub, error: subError } = await supabaseAdmin
      .from('service_subscriptions')
      .insert({
        institution_id: plan.institution_id,
        student_id,
        service_type: plan.service_type,
        pricing_id: plan.id,
        start_date: today,
        end_date: endDate,
        amount_paid: plan.price,
        transaction_id: razorpay_payment_id || 'mock_' + Date.now(),
        status: 'active'
      })
      .select()
      .single();

    if (subError) return res.status(500).json({ success: false, error: subError.message });

    return res.status(200).json({
      success: true,
      message: `${plan.service_type} subscription activated successfully.`,
      subscription: sub,
      end_date: endDate
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error verifying payment.' });
  }
});

// GET /my/:studentId — Get all subscriptions for a student
router.get('/my/:studentId', async (req: Request, res: Response) => {
  try {
    const { studentId } = req.params;
    const { data, error } = await supabaseAdmin
      .from('service_subscriptions')
      .select('*, service_pricing(name, price, features, duration_days)')
      .eq('student_id', studentId)
      .order('created_at', { ascending: false });

    if (error) return res.status(500).json({ success: false, error: error.message });

    return res.status(200).json({ success: true, subscriptions: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

export default router;
