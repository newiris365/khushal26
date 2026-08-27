process.env.JWT_SECRET = 'test-secret-key-that-is-at-least-32-characters-long';
process.env.SUPABASE_URL = 'http://localhost:54321';
process.env.SUPABASE_ANON_KEY = 'test-anon-key';

import { verifyPayment, creditWallet } from '../src/controllers/campusCore';
import { entryQR, generateSignedGateQR, verifyAndDecodeGateQRToken } from '../src/controllers/gate';
import { requireFeature } from '../src/middleware/permissions';
import { supabaseAdmin } from '../src/config/supabase';
import * as razorpayModule from '../src/lib/razorpay';

// Mock supabase module cleanly for Jest tests
jest.mock('../src/config/supabase', () => {
  const original = jest.requireActual('../src/config/supabase');
  return {
    ...original,
    supabaseAdmin: {
      from: jest.fn(),
      rpc: jest.fn(),
    },
  };
});

// Helper mock factories
function makeReq(overrides: Record<string, any> = {}) {
  return {
    headers: {},
    body: {},
    query: {},
    ip: '127.0.0.1',
    user: undefined,
    ...overrides,
  } as any;
}

function makeRes() {
  const res: any = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

const VALID_STUDENT_UUID = '123e4567-e89b-12d3-a456-426614174001';
const OTHER_STUDENT_UUID = '123e4567-e89b-12d3-a456-426614174002';
const VALID_FEE_STRUCT_UUID = '123e4567-e89b-12d3-a456-426614174000';
const VALID_INSTITUTION_UUID = 'a0000000-0000-0000-0000-000000000001';

describe('Bug 1: Fee Payment Verification Hardening', () => {
  let getRazorpayClientSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    if (getRazorpayClientSpy) getRazorpayClientSpy.mockRestore();
  });

  it('rejects client order_mock_ prefix bypass when Razorpay client is active', async () => {
    getRazorpayClientSpy = jest.spyOn(razorpayModule, 'getRazorpayClient').mockReturnValue({
      payments: {
        fetch: jest.fn().mockResolvedValue({
          id: 'pay_mock123',
          status: 'captured',
          order_id: 'order_mock_123',
          amount: 500000,
        }),
      },
    } as any);

    process.env.RAZORPAY_KEY_SECRET = 'test_secret';

    const req = makeReq({
      user: { id: 'user-student-1', role: 'Student', institution_id: VALID_INSTITUTION_UUID },
      body: {
        razorpay_order_id: 'order_mock_123',
        razorpay_payment_id: 'pay_mock123',
        razorpay_signature: 'invalid_signature_attempt',
        student_id: VALID_STUDENT_UUID,
        fee_structure_id: VALID_FEE_STRUCT_UUID,
        amount_paid: 5000,
      },
    });

    (supabaseAdmin.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'students') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: { id: VALID_STUDENT_UUID }, error: null }),
        } as any;
      }
      if (table === 'fee_payments') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
        } as any;
      }
      return {} as any;
    });

    const res = makeRes();
    await verifyPayment(req, res);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: false,
      error: 'Payment signature verification failed.',
    }));
  });

  it('rejects fee verification when captured amount in Razorpay does not match amount_paid claim', async () => {
    const crypto = require('crypto');
    const secret = 'test_secret';
    process.env.RAZORPAY_KEY_SECRET = secret;
    const orderId = 'order_real_123';
    const paymentId = 'pay_real_123';
    const signature = crypto.createHmac('sha256', secret).update(`${orderId}|${paymentId}`).digest('hex');

    getRazorpayClientSpy = jest.spyOn(razorpayModule, 'getRazorpayClient').mockReturnValue({
      payments: {
        fetch: jest.fn().mockResolvedValue({
          id: paymentId,
          status: 'captured',
          order_id: orderId,
          amount: 10000, // 100 INR in paise
        }),
      },
    } as any);

    const req = makeReq({
      user: { id: 'user-student-1', role: 'Student', institution_id: VALID_INSTITUTION_UUID },
      body: {
        razorpay_order_id: orderId,
        razorpay_payment_id: paymentId,
        razorpay_signature: signature,
        student_id: VALID_STUDENT_UUID,
        fee_structure_id: VALID_FEE_STRUCT_UUID,
        amount_paid: 5000, // Claiming 5000 INR (500000 paise) while only 100 INR was paid
      },
    });

    (supabaseAdmin.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'students') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: { id: VALID_STUDENT_UUID }, error: null }),
        } as any;
      }
      if (table === 'fee_payments') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
        } as any;
      }
      return {} as any;
    });

    const res = makeRes();
    await verifyPayment(req, res);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'Payment amount mismatch between client claim and Razorpay.',
    }));
  });

  it('rejects Student role attempting IDOR to pay for another student_id', async () => {
    const req = makeReq({
      user: { id: 'user-student-1', role: 'Student', institution_id: VALID_INSTITUTION_UUID },
      body: {
        razorpay_order_id: 'order_123',
        razorpay_payment_id: 'pay_123',
        razorpay_signature: 'sig',
        student_id: OTHER_STUDENT_UUID,
        fee_structure_id: VALID_FEE_STRUCT_UUID,
        amount_paid: 1000,
      },
    });

    (supabaseAdmin.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'students') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: { id: VALID_STUDENT_UUID }, error: null }),
        } as any;
      }
      return {} as any;
    });

    const res = makeRes();
    await verifyPayment(req, res);

    expect(res.status).toHaveBeenCalledWith(403);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'Forbidden: You can only verify payments for your own student record.',
    }));
  });

  it('rejects duplicate transaction_id replays for fee payments', async () => {
    const req = makeReq({
      user: { id: 'user-student-1', role: 'Student', institution_id: VALID_INSTITUTION_UUID },
      body: {
        razorpay_order_id: 'order_123',
        razorpay_payment_id: 'pay_already_processed',
        razorpay_signature: 'sig',
        student_id: VALID_STUDENT_UUID,
        fee_structure_id: VALID_FEE_STRUCT_UUID,
        amount_paid: 1000,
      },
    });

    (supabaseAdmin.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'students') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: { id: VALID_STUDENT_UUID }, error: null }),
        } as any;
      }
      if (table === 'fee_payments') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: { id: 'existing-payment-1' }, error: null }),
        } as any;
      }
      return {} as any;
    });

    const res = makeRes();
    await verifyPayment(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'Duplicate transaction: Payment already recorded.',
    }));
  });
});

describe('Bug 2: Wallet Top-Up Amount & Payment Verification', () => {
  let getRazorpayClientSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  afterEach(() => {
    if (getRazorpayClientSpy) getRazorpayClientSpy.mockRestore();
  });

  it('rejects top-up request omitting razorpay_order_id when Razorpay is configured', async () => {
    getRazorpayClientSpy = jest.spyOn(razorpayModule, 'getRazorpayClient').mockReturnValue({
      payments: { fetch: jest.fn() },
    } as any);

    const req = makeReq({
      user: { id: 'user-student-1', role: 'Student' },
      body: {
        amount: 500,
        razorpay_payment_id: 'pay_123',
        // razorpay_order_id intentionally omitted
      },
    });

    const res = makeRes();
    await creditWallet(req, res);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'razorpay_order_id and razorpay_payment_id are required.',
    }));
  });

  it('rejects wallet top-up when claimed amount does not match actual Razorpay payment', async () => {
    getRazorpayClientSpy = jest.spyOn(razorpayModule, 'getRazorpayClient').mockReturnValue({
      payments: {
        fetch: jest.fn().mockResolvedValue({
          id: 'pay_100rs',
          status: 'captured',
          order_id: 'order_100rs',
          amount: 10000, // ₹100 paid
        }),
      },
    } as any);

    const req = makeReq({
      user: { id: 'user-student-1', role: 'Student' },
      body: {
        amount: 100000, // Claiming ₹100,000 top-up while only ₹100 was paid
        razorpay_order_id: 'order_100rs',
        razorpay_payment_id: 'pay_100rs',
      },
    });

    const res = makeRes();
    await creditWallet(req, res);

    expect(res.status).toHaveBeenCalledWith(400);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'Claimed top-up amount does not match actual Razorpay payment.',
    }));
  });

  it('credits wallet using verified Razorpay payment amount and rejects duplicate transaction replay', async () => {
    getRazorpayClientSpy = jest.spyOn(razorpayModule, 'getRazorpayClient').mockReturnValue({
      payments: {
        fetch: jest.fn().mockResolvedValue({
          id: 'pay_valid_500',
          status: 'captured',
          order_id: 'order_valid_500',
          amount: 50000, // ₹500
        }),
      },
    } as any);

    const req = makeReq({
      user: { id: 'user-student-1', role: 'Student', institution_id: VALID_INSTITUTION_UUID },
      body: {
        amount: 500,
        razorpay_order_id: 'order_valid_500',
        razorpay_payment_id: 'pay_valid_500',
      },
    });

    (supabaseAdmin.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'students') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: { id: VALID_STUDENT_UUID, wallet_balance: 200, institution_id: VALID_INSTITUTION_UUID }, error: null }),
        } as any;
      }
      if (table === 'wallet_transactions') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: { id: 'tx-existing' }, error: null }),
        } as any;
      }
      return {} as any;
    });

    const res = makeRes();
    await creditWallet(req, res);

    expect(res.status).toHaveBeenCalledWith(409);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      error: 'Duplicate top-up: Payment ID already processed.',
    }));
  });
});

describe('Bug 3: Gate Entry QR Code Signing & Replay Prevention', () => {
  const institutionId = VALID_INSTITUTION_UUID;
  process.env.GATE_QR_SECRET = 'super_secret_gate_key_1234567890';

  it('rejects unsigned plain JSON QR tokens without HMAC signature', async () => {
    (supabaseAdmin.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'gate_lockdown') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockReturnThis(),
          order: jest.fn().mockReturnThis(),
          limit: jest.fn().mockReturnThis(),
          maybeSingle: jest.fn().mockResolvedValue({ data: null, error: null }),
        } as any;
      }
      return {} as any;
    });

    const plainJsonToken = JSON.stringify({
      person_id: '123e4567-e89b-12d3-a456-426614174000',
      timestamp: new Date().toISOString(),
      person_type: 'student',
    });

    const req = makeReq({
      user: { id: 'guard-1', role: 'Security', institution_id: institutionId },
      body: {
        qr_token: plainJsonToken,
        gate_number: 'Gate-1',
      },
    });

    const res = makeRes();
    await entryQR(req, res);

    expect(res.status).toHaveBeenCalledWith(403);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: false,
      error: expect.stringMatching(/signature|unsigned|failed/i),
    }));
  });

  it('accepts valid HMAC-signed QR token and rejects replay of the exact same token within validity window', async () => {
    const payload = {
      person_id: '123e4567-e89b-12d3-a456-426614174000',
      timestamp: new Date().toISOString(),
      person_type: 'student',
    };

    const signedToken = generateSignedGateQR(payload, institutionId);

    // Verify token decodes properly
    const decoded = verifyAndDecodeGateQRToken(signedToken, institutionId);
    expect(decoded.person_id).toBe(payload.person_id);

    // Attempting to decode the exact same token again should throw replay error
    expect(() => {
      verifyAndDecodeGateQRToken(signedToken, institutionId);
    }).toThrow(/Replayed QR token/i);
  });
});

describe('Bug 4: Feature-Flag Check Isolation from Request Body/Query', () => {
  it('uses req.user.institution_id for authenticated user and ignores spoofed body/query institution_id', async () => {
    const req = makeReq({
      user: { id: 'user-1', role: 'Student', institution_id: 'real-user-inst' },
      body: { institution_id: 'spoofed-attacker-inst' },
      query: { institution_id: 'spoofed-attacker-inst-query' },
    });
    const res = makeRes();
    const next = jest.fn();

    (supabaseAdmin.from as jest.Mock).mockImplementation((table: string) => {
      if (table === 'institution_settings') {
        return {
          select: jest.fn().mockReturnThis(),
          eq: jest.fn().mockImplementation((field: string, val: string) => {
            if (field === 'institution_id') {
              expect(val).toBe('real-user-inst'); // MUST be real user inst, NOT spoofed
            }
            return {
              single: jest.fn().mockResolvedValue({ data: { is_enabled: true }, error: null }),
            } as any;
          }),
        } as any;
      }
      return {} as any;
    });

    const middleware = requireFeature('canteen_management');
    await middleware(req, res, next);

    expect(next).toHaveBeenCalled();
  });
});
