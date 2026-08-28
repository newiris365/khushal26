process.env.JWT_SECRET = 'test-secret-key-that-is-at-least-32-characters-long';
process.env.SUPABASE_URL = 'http://localhost:54321';
process.env.SUPABASE_ANON_KEY = 'test-anon-key';

const mockDatabase: Record<string, any[]> = {
  institution_purchase_intents: []
};

jest.mock('../src/config/supabase', () => {
  return {
    supabaseAdmin: {
      from: (table: string) => ({
        select: () => ({
          eq: (col: string, val: any) => ({
            maybeSingle: async () => {
              const found = (mockDatabase[table] || []).find((row: any) => row[col] === val);
              return { data: found || null, error: null };
            }
          }),
          order: () => Promise.resolve({ data: mockDatabase[table] || [], error: null })
        }),
        insert: (row: any) => ({
          select: () => ({
            single: async () => {
              const insertedRow = { id: `id_${Date.now()}`, ...row };
              mockDatabase[table] = mockDatabase[table] || [];
              mockDatabase[table].push(insertedRow);
              return { data: insertedRow, error: null };
            }
          })
        })
      })
    }
  };
});

import serviceSubscriptionsRouter from '../src/routes/serviceSubscriptions';

function makeReq(overrides: Record<string, any> = {}) {
  return {
    headers: {},
    body: {},
    query: {},
    ip: '127.0.0.1',
    user: { id: 'admin-user-1', role: 'SuperAdmin' },
    ...overrides,
  } as any;
}

function makeRes() {
  const res: any = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

function getHandler(path: string, method: string = 'post') {
  const routeLayer = serviceSubscriptionsRouter.stack.find(
    (layer: any) => layer.route && layer.route.path === path && layer.route.methods[method]
  );
  if (!routeLayer) {
    throw new Error(`Route layer not found for ${method.toUpperCase()} ${path}`);
  }
  return routeLayer.route.stack[routeLayer.route.stack.length - 1].handle;
}

describe('Uncapped Accounts & Buy Now Purchase Intent Endpoints', () => {
  const calcHandler = getHandler('/calculate-account-plan', 'post');
  const createOrderHandler = getHandler('/purchase-intent/create-order', 'post');
  const verifyHandler = getHandler('/purchase-intent/verify', 'post');
  const listHandler = getHandler('/purchase-intents', 'get');

  it('accepts uncapped account count (50,000 accounts) on /calculate-account-plan and calculates graduated total', async () => {
    const req = makeReq({ body: { account_count: 50000, billing_cycle: 'annual', currency: 'INR' } });
    const res = makeRes();

    await calcHandler(req, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: true,
      account_count: 50000,
      tier: 'enterprise',
      rate_per_person_annual: 90,
      annual_amount_total: 4650000, // 2500x120 + 7500x100 + 40000x90 = 3,00,000 + 7,50,000 + 36,00,000
      monthly_amount: 465000,
    }));
  });

  it('creates purchase order with server-side graduated calculated amount for 50,000 accounts', async () => {
    const req = makeReq({
      body: {
        institution_name: 'Tech University',
        contact_name: 'Dr. Smith',
        contact_email: 'smith@techuni.edu',
        contact_phone: '+91 9999999999',
        tier: 'enterprise',
        account_count: 50000,
        billing_cycle: 'annual',
        currency: 'INR',
      },
    });
    const res = makeRes();

    await createOrderHandler(req, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: true,
      amount: 4650000,
      amount_paise: 465000000,
      currency: 'INR',
    }));
  });

  it('verifies purchase intent and inserts row into institution_purchase_intents with idempotency enforcement', async () => {
    const mockPaymentId = `pay_mock_${Date.now()}`;
    const req = makeReq({
      body: {
        institution_name: 'Tech University',
        contact_name: 'Dr. Smith',
        contact_email: 'smith@techuni.edu',
        contact_phone: '+91 9999999999',
        city: 'Mumbai',
        tier: 'enterprise',
        account_count: 50000,
        billing_cycle: 'annual',
        currency: 'INR',
        razorpay_order_id: 'order_mock_123',
        razorpay_payment_id: mockPaymentId,
        razorpay_signature: 'sig_mock_123',
      },
    });
    const res = makeRes();

    await verifyHandler(req, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: true,
      message: expect.stringContaining('verified'),
    }));

    // Test Idempotency: Duplicate submit with same razorpay_payment_id should be rejected with 409
    const req2 = makeReq({ body: req.body });
    const res2 = makeRes();

    await verifyHandler(req2, res2);

    expect(res2.status).toHaveBeenCalledWith(409);
    expect(res2.json).toHaveBeenCalledWith(expect.objectContaining({
      success: false,
      error: expect.stringContaining('already recorded'),
    }));
  });

  it('lists purchase intents for SuperAdmin on GET /purchase-intents', async () => {
    const req = makeReq();
    const res = makeRes();

    await listHandler(req, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: true,
      purchase_intents: expect.any(Array),
    }));
  });
});
