process.env.JWT_SECRET = 'test-secret-key-that-is-at-least-32-characters-long';
process.env.NEXT_PUBLIC_SUPABASE_URL = 'http://localhost:54321';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-key';

import { POST as sendOtpHandler } from '../src/app/api/parent-onboarding/send-otp/route';
import { POST as verifyOtpHandler } from '../src/app/api/parent-onboarding/verify-otp/route';
import { POST as createOrderHandler } from '../src/app/api/parent-onboarding/create-order/route';
import { POST as linkStudentHandler } from '../src/app/api/parent-onboarding/link-student/route';
import { GET as getSubscriptionStatusHandler } from '../src/app/api/parent-onboarding/subscription-status/route';

const mockDb: Record<string, any[]> = {
  users: [],
  parent_profiles: [],
  parent_otps: [],
  parent_platform_payments: [],
  parent_student_links: [],
  students: [
    {
      id: 'stu_101',
      user_id: 'user_stu_101',
      roll_number: '23CS1001',
      student_id: 'STU-101',
      dob: '2008-05-15',
      name: 'Rohan Sharma',
      institution_id: 'inst_school_01'
    }
  ]
};

jest.mock('@supabase/supabase-js', () => ({
  createClient: () => ({
    rpc: async (fnName: string, args: any) => {
      if (fnName === 'generate_parent_otp') {
        return { data: [{ otp_code: '123456' }], error: null };
      }
      if (fnName === 'verify_parent_otp') {
        return { data: args.p_otp === '123456', error: null };
      }
      return { data: null, error: null };
    },
    from: (table: string) => ({
      select: (cols?: string) => ({
        eq: (col: string, val: any) => ({
          eq: (col2: string, val2: any) => ({
            maybeSingle: async () => {
              const rows = (mockDb[table] || []).filter((r: any) => r[col] === val && r[col2] === val2);
              return { data: rows[0] || null, error: null };
            }
          }),
          or: (cond: string) => ({
            maybeSingle: async () => {
              const rows = (mockDb[table] || []).filter((r: any) => r[col] === val);
              return { data: rows[0] || null, error: null };
            }
          }),
          maybeSingle: async () => {
            const rows = (mockDb[table] || []).filter((r: any) => r[col] === val);
            return { data: rows[0] || null, error: null };
          },
          order: () => ({
            then: (resolve: any) => {
              const rows = (mockDb[table] || []).filter((r: any) => r[col] === val);
              resolve({ data: rows, error: null });
            }
          }),
          then: (resolve: any) => {
            const rows = (mockDb[table] || []).filter((r: any) => r[col] === val);
            resolve({ data: rows, error: null });
          }
        }),
        in: () => ({
          lt: () => ({
            catch: () => Promise.resolve({ data: null, error: null })
          })
        }),
        or: (cond: string) => ({
          maybeSingle: async () => {
            return { data: mockDb[table]?.[0] || null, error: null };
          }
        })
      }),
      insert: (row: any) => {
        const inserted = { id: row.id || `id_${Date.now()}`, ...row };
        mockDb[table] = mockDb[table] || [];
        mockDb[table].push(inserted);
        return {
          select: () => ({
            single: async () => ({ data: inserted, error: null })
          }),
          then: (resolve: any) => resolve({ data: [inserted], error: null })
        };
      },
      update: (row: any) => ({
        in: () => ({
          lt: () => ({
            catch: () => Promise.resolve({ data: null, error: null })
          })
        }),
        eq: (col: string, val: any) => ({
          is: (col2: string, val2: any) => Promise.resolve({ data: [], error: null }),
          then: (resolve: any) => {
            (mockDb[table] || []).forEach((r: any) => {
              if (r[col] === val) Object.assign(r, row);
            });
            resolve({ data: [], error: null });
          }
        })
      }),
      upsert: (row: any) => {
        mockDb[table] = mockDb[table] || [];
        mockDb[table].push(row);
        return {
          then: (resolve: any) => resolve({ data: [row], error: null })
        };
      }
    })
  })
}));

describe('Parent Self-Onboarding API Flow', () => {
  let authToken = '';
  let parentUserId = '';

  it('1. POST /api/parent-onboarding/send-otp sends OTP to mobile number', async () => {
    const req = new Request('http://localhost/api/parent-onboarding/send-otp', {
      method: 'POST',
      body: JSON.stringify({ phone: '+919876543210' })
    }) as any;

    const res = await sendOtpHandler(req);
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.success).toBe(true);
    expect(json.dev_otp).toBe('123456');
  });

  it('2. POST /api/parent-onboarding/verify-otp verifies OTP and returns JWT token & user', async () => {
    const req = new Request('http://localhost/api/parent-onboarding/verify-otp', {
      method: 'POST',
      body: JSON.stringify({ phone: '+919876543210', otp: '123456', name: 'Test Parent' })
    }) as any;

    const res = await verifyOtpHandler(req);
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.success).toBe(true);
    expect(json.token).toBeDefined();
    expect(json.user.role).toBe('Parent');

    authToken = json.token;
    parentUserId = json.user.id;
  });

  it('3. POST /api/parent-onboarding/create-order creates ₹150 platform access fee order', async () => {
    const req = new Request('http://localhost/api/parent-onboarding/create-order', {
      method: 'POST',
      headers: { Authorization: `Bearer ${authToken}` },
      body: JSON.stringify({ parent_user_id: parentUserId })
    }) as any;

    const res = await createOrderHandler(req);
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.success).toBe(true);
    expect(json.amount).toBe(150);
    expect(json.order_id).toBeDefined();

    // Mark status='active' in mock DB for subsequent tests
    if (mockDb.parent_platform_payments.length > 0) {
      mockDb.parent_platform_payments[0].status = 'active';
      mockDb.parent_platform_payments[0].valid_until = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString();
    }
  });

  it('4. POST /api/parent-onboarding/link-student verifies paid status and links student to parent', async () => {
    const req = new Request('http://localhost/api/parent-onboarding/link-student', {
      method: 'POST',
      headers: { Authorization: `Bearer ${authToken}` },
      body: JSON.stringify({
        institution_id: 'inst_school_01',
        student_roll_or_id: '23CS1001',
        dob: '2008-05-15',
        parent_user_id: parentUserId
      })
    }) as any;

    const res = await linkStudentHandler(req);
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.success).toBe(true);
    expect(json.student_name).toBe('Rohan Sharma');
  });

  it('5. GET /api/parent-onboarding/subscription-status checks active status & days remaining', async () => {
    const req = new Request(`http://localhost/api/parent-onboarding/subscription-status?parent_user_id=${parentUserId}`, {
      method: 'GET',
      headers: { Authorization: `Bearer ${authToken}` }
    }) as any;

    const res = await getSubscriptionStatusHandler(req);
    const json = await res.json();

    expect(res.status).toBe(200);
    expect(json.success).toBe(true);
    expect(json.active).toBe(true);
    expect(json.days_remaining).toBeGreaterThan(300);
  });
});

