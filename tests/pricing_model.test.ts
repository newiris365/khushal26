process.env.JWT_SECRET = 'test-secret-key-that-is-at-least-32-characters-long';
process.env.SUPABASE_URL = 'http://localhost:54321';
process.env.SUPABASE_ANON_KEY = 'test-anon-key';

import serviceSubscriptionsRouter from '../src/routes/serviceSubscriptions';
import { computeGraduatedTotal } from '../src/lib/pricing';

function makeReq(overrides: Record<string, any> = {}) {
  return {
    headers: {},
    body: {},
    query: {},
    ip: '127.0.0.1',
    user: { id: 'admin-user-1', role: 'Director' },
    ...overrides,
  } as any;
}

function makeRes() {
  const res: any = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

function getCalculateHandler() {
  const routeLayer = serviceSubscriptionsRouter.stack.find(
    (layer: any) => layer.route && layer.route.path === '/calculate-account-plan'
  );
  return routeLayer.route.stack[0].handle;
}

describe('Graduated Pricing Model (/calculate-account-plan)', () => {
  const handler = getCalculateHandler();

  it('calculates Growth band pricing correctly (1,000 accounts -> ₹1,20,000)', async () => {
    const req = makeReq({ body: { account_count: 1000, billing_cycle: 'annual', currency: 'INR' } });
    const res = makeRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: true,
      account_count: 1000,
      tier: 'growth',
      currency: 'INR',
      annual_amount_total: 120000, // 1,000 x 120
      monthly_amount: 12000,
    }));
  });

  it('calculates graduated pricing across Growth and Scale bands (5,000 accounts -> ₹5,50,000)', async () => {
    const req = makeReq({ body: { account_count: 5000, billing_cycle: 'annual', currency: 'INR' } });
    const res = makeRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: true,
      account_count: 5000,
      tier: 'scale',
      currency: 'INR',
      annual_amount_total: 550000, // (2,500 x 120) + (2,500 x 100) = 3,00,000 + 2,50,000
      monthly_amount: 55000,
    }));
  });

  it('verifies strictly monotonic total with no pricing cliff at boundary (10,000 vs 11,000 accounts)', async () => {
    const req10k = makeReq({ body: { account_count: 10000, billing_cycle: 'annual', currency: 'INR' } });
    const res10k = makeRes();
    await handler(req10k, res10k);

    const req11k = makeReq({ body: { account_count: 11000, billing_cycle: 'annual', currency: 'INR' } });
    const res11k = makeRes();
    await handler(req11k, res11k);

    const total10k = res10k.json.mock.calls[0][0].annual_amount_total;
    const total11k = res11k.json.mock.calls[0][0].annual_amount_total;

    expect(total10k).toBe(1050000); // (2,500 x 120) + (7,500 x 100) = 3,00,000 + 7,50,000
    expect(total11k).toBe(1140000); // (2,500 x 120) + (7,500 x 100) + (1,000 x 90) = 10,50,000 + 90,000
    expect(total11k).toBeGreaterThan(total10k);
  });

  it('calculates graduated pricing for Enterprise scale (15,000 accounts -> ₹15,00,000)', async () => {
    const req = makeReq({ body: { account_count: 15000, billing_cycle: 'annual', currency: 'INR' } });
    const res = makeRes();

    await handler(req, res);

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({
      success: true,
      account_count: 15000,
      tier: 'enterprise',
      currency: 'INR',
      annual_amount_total: 1500000, // (2,500 x 120) + (7,500 x 100) + (5,000 x 90)
      monthly_amount: 150000,
    }));
  });

  it('verifies computeGraduatedTotal helper consistency', () => {
    expect(computeGraduatedTotal(1000, 'annual', 'INR')).toBe(120000);
    expect(computeGraduatedTotal(10000, 'annual', 'INR')).toBe(1050000);
    expect(computeGraduatedTotal(11000, 'annual', 'INR')).toBe(1140000);
    expect(computeGraduatedTotal(50000, 'annual', 'INR')).toBe(4650000); // 1050000 + (40000 x 90) = 46,50,000
  });
});
