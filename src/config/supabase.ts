import { createClient, SupabaseClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import { AsyncLocalStorage } from 'async_hooks';
import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import logger from './logger';

dotenv.config();

// Request context store for dynamic JWT scoping
export const authLocalStorage = new AsyncLocalStorage<string>();

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!supabaseUrl || !supabaseServiceKey) {
  logger.warn('Supabase URL or Service Key is missing. Operating with fallback client configuration.');
}

// Internal admin client lazily initialized on first use to prevent synchronous throws when env credentials are missing at import time
let _supabaseAdminInternalClient: SupabaseClient | null = null;
export function getSupabaseAdminInternal(): SupabaseClient {
  if (!_supabaseAdminInternalClient) {
    const url = process.env.SUPABASE_URL || 'https://placeholder-url.supabase.co';
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY || 'placeholder-service-key-for-test-environments';
    _supabaseAdminInternalClient = createClient(url, key, {
      auth: {
        autoRefreshToken: false,
        persistSession: false
      }
    });
  }
  return _supabaseAdminInternalClient;
}

export let isSupabaseOffline = false;

// Simple connectivity check (periodic every 60s)
async function checkConnectivity() {
  if (process.env.NODE_ENV === 'test') {
    isSupabaseOffline = true;
    return;
  }
  if (!supabaseUrl || !supabaseServiceKey) {
    isSupabaseOffline = true;
    return;
  }
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);
    const res = await fetch(`${supabaseUrl}/rest/v1/`, {
      method: 'GET',
      headers: { apikey: supabaseServiceKey },
      signal: controller.signal
    });
    clearTimeout(timeoutId);
    if (res.ok || res.status === 404 || res.status === 401) {
      if (isSupabaseOffline) {
        logger.info('[SUPABASE CONNECTIVITY] Supabase connection restored.');
      }
      isSupabaseOffline = false;
    } else {
      isSupabaseOffline = true;
    }
  } catch (err) {
    isSupabaseOffline = true;
    console.warn(`[SUPABASE CONNECTIVITY] Supabase is offline or unreachable (${supabaseUrl}).`);
  }
}
if (process.env.NODE_ENV !== 'test') {
  checkConnectivity();
  const intervalId = setInterval(checkConnectivity, 60000);
  if (intervalId && intervalId.unref) {
    intervalId.unref();
  }
} else {
  isSupabaseOffline = true;
}

/**
 * Exponential backoff retry wrapper for Supabase database/auth calls.
 */
export async function retrySupabaseCall<T>(fn: () => Promise<T>, maxRetries = 3, initialDelay = 100): Promise<T> {
  let attempt = 0;
  while (true) {
    try {
      return await fn();
    } catch (err: any) {
      attempt++;
      if (attempt >= maxRetries || (err.status && err.status >= 400 && err.status < 500)) {
        throw err;
      }
      const delay = initialDelay * Math.pow(2, attempt);
      console.warn(`[SUPABASE RETRY] Call failed (attempt ${attempt}/${maxRetries}). Retrying in ${delay}ms... Error: ${err.message || err}`);
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

// Helper to get client dynamically
export function getDynamicSupabaseClient(): SupabaseClient {
  const token = authLocalStorage.getStore();
  if (token && supabaseUrl) {
    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      throw new Error('CRITICAL SECURITY VIOLATION: JWT_SECRET environment variable is required!');
    }
    let decodedClaims: any = null;
    let isBackendToken = false;
    if (token.startsWith('mock-sandbox')) {
      if (process.env.NODE_ENV === 'production') {
        throw new Error('CRITICAL SECURITY VIOLATION: Sandbox mock tokens are disabled in production.');
      }
      isBackendToken = true;
      try {
        const parts = token.split('.');
        const payloadBase64 = parts[1];
        const payloadJson = Buffer.from(payloadBase64, 'base64').toString('utf-8');
        decodedClaims = JSON.parse(payloadJson);
      } catch (e) {}
    } else {
      try {
        decodedClaims = jwt.verify(token, jwtSecret);
        isBackendToken = true;
      } catch (e) {
        // Not a valid backend token
      }
    }

    if (isBackendToken) {
      if (decodedClaims && decodedClaims.supabase_token) {
        const anonKey = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || supabaseServiceKey;
        return createClient(supabaseUrl, anonKey, {
          auth: {
            persistSession: false,
            autoRefreshToken: false
          },
          global: {
            headers: {
              Authorization: `Bearer ${decodedClaims.supabase_token}`
            }
          }
        });
      }
      return getSupabaseAdminInternal();
    }

    const anonKey = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || supabaseServiceKey;
    return createClient(supabaseUrl, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      },
      global: {
        headers: {
          Authorization: `Bearer ${token}`
        }
      }
    });
  }
  return getSupabaseAdminInternal();
}

// Define Mock course registrations in-memory store for student courses view
export let mockCourseRegistrations: any[] = [
  {
    id: 'reg-wt',
    student_id: 'test-student-id',
    course_id: 'c-wt',
    status: 'active',
    registered_at: new Date().toISOString(),
    dropped_at: null,
    academic_year: new Date().getFullYear().toString(),
    course: {
      id: 'c-wt',
      course_code: 'CS-302',
      course_name: 'Web Technologies',
      credits: 4,
      course_type: 'core',
      semester: 5
    }
  }
];

export let mockStudentDocuments: any[] = [
  {
    id: 'doc-1',
    institution_id: 'a0000000-0000-0000-0000-000000000001',
    student_id: 'test-student-id',
    document_name: '10th Marksheet',
    document_type: '10th_marksheet',
    file_url: 'https://example.com/marksheet10.pdf',
    file_size_kb: 150,
    uploaded_at: new Date().toISOString(),
    uploaded_by: 'b0000000-0000-0000-0000-000000000002'
  }
];

export let mockTimetableHistory: any[] = [
  {
    id: 'tth-1',
    institution_id: 'a0000000-0000-0000-0000-000000000001',
    department_id: 'd1',
    semester: 5,
    batch_year: '2024-2028',
    version: 1,
    timetable_data: [],
    created_at: new Date().toISOString(),
    created_by: 'b0000000-0000-0000-0000-000000000002'
  }
];

export let mockSupplementaryExams: any[] = [
  {
    id: 'supp-1',
    institution_id: 'a0000000-0000-0000-0000-000000000001',
    exam_id: 'e1',
    student_id: 'test-student-id',
    subject: 'Computer Networks',
    status: 'applied',
    applied_at: new Date().toISOString(),
    remarks: 'Needs supplementary attempt'
  }
];

export let mockReEvaluationRequests: any[] = [
  {
    id: 're-eval-1',
    institution_id: 'a0000000-0000-0000-0000-000000000001',
    result_id: 'res-1',
    student_id: 'test-student-id',
    exam_id: 'e1',
    subject: 'Operating Systems',
    reason: 'Total calculation error',
    status: 'applied',
    previous_marks: 38,
    new_marks: null,
    applied_at: new Date().toISOString(),
    resolved_at: null,
    resolved_by: null,
    remarks: null
  }
];

export let mockAlumni: any[] = [
  {
    id: 'alumni-123',
    institution_id: 'a0000000-0000-0000-0000-000000000001',
    student_id: 'test-student-id',
    graduation_year: 2026,
    current_company: 'Google',
    current_role: 'SWE',
    is_mentor: true,
    created_at: new Date().toISOString()
  }
];

export let mockGateLockdown: any[] = [];
export let mockEquipmentMaintenanceLogs: any[] = [];
export let mockVisitorPasses: any[] = [];
export let mockGymEquipment: any[] = [
  {
    id: 'equip-1',
    institution_id: 'a0000000-0000-0000-0000-000000000001',
    name: 'Treadmill',
    category: 'Cardio',
    quantity: 2,
    condition: 'good',
    is_active: true
  }
];
export let mockBookReservations: any[] = [];
export let mockStudentTransitLogs: any[] = [];
export let mockEventCertificates: any[] = [];
export let mockSchoolAttendance: any[] = [];
export let mockInstitutionFeatures: any[] = [];
export let mockAttendanceMethods: any[] = [
  { id: 'm-qr', institution_id: 'a0000000-0000-0000-0000-000000000001', method_key: 'qr', is_enabled: true, config: { rotate_interval_minutes: 5, geo_lat: 26.2389, geo_lng: 73.0243, geo_radius: 200 } },
  { id: 'm-bio', institution_id: 'a0000000-0000-0000-0000-000000000001', method_key: 'biometric', is_enabled: true, config: { require_session: true, auto_match: true } },
  { id: 'm-rfid', institution_id: 'a0000000-0000-0000-0000-000000000001', method_key: 'rfid', is_enabled: true, config: { require_session: true } },
  { id: 'm-man', institution_id: 'a0000000-0000-0000-0000-000000000001', method_key: 'manual', is_enabled: true, config: {} }
];
export let mockAttendanceDevices: any[] = [];
export let mockInstitutions: any[] = [
  {
    id: 'a0000000-0000-0000-0000-000000000001',
    name: 'JIET (Jodhpur Institute of Engineering & Technology)',
    type: 'university',
    plan_tier: 'University',
    plan_price_monthly: 25000,
    is_active: true,
    subscription_period: 'monthly',
    gemini_api_key: '',
    openai_api_key: '',
    claude_api_key: '',
    institute_type: 'college',
  }
];


// Define Mock client details for offline simulation mode
const mockAuth = {
  signInWithPassword: async ({ email }: { email: string }) => {
    let id = 'b0000000-0000-0000-0000-000000000002';
    if (email === 'khushal@gmail.com') id = 'b0000000-0000-0000-0000-000000000006';
    else if (email === 'guard@siet.edu.in') id = 'b0000000-0000-0000-0000-000000000015';
    return {
      data: {
        user: { id, email, role: 'authenticated' },
        session: { access_token: 'mock-token', refresh_token: 'mock-refresh-token' }
      },
      error: null
    };
  },
  signUp: async ({ email }: { email: string }) => {
    return {
      data: { user: { id: 'new-mock-user-id', email } },
      error: null
    };
  },
  signOut: async () => {
    return { error: null };
  },
  refreshSession: async ({ refresh_token }: { refresh_token: string }) => {
    return {
      data: {
        user: { id: 'b0000000-0000-0000-0000-000000000006', email: 'khushal@gmail.com', role: 'authenticated' },
        session: { access_token: 'mock-token-refreshed', refresh_token: 'mock-refresh-token-refreshed' }
      },
      error: null
    };
  }
};

const mockStorage = {
  from: () => ({
    upload: async () => ({ data: { path: 'mock-path' }, error: null }),
    getPublicUrl: () => ({ data: { publicUrl: 'https://example.com/mock-report.pdf' } })
  })
};

function getMockDataForTable(tableName: string) {
  const today = new Date().toISOString().split('T')[0];
  switch (tableName) {
    case 'users':
      return [
        {
          id: 'b0000000-0000-0000-0000-000000000002',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          role: 'Director',
          name: 'Dr. K. R. Sharma (Mock Sandbox)',
          email: 'director@siet.edu.in',
          phone: '+919876543211',
          is_active: true,
          institutions: {
            name: 'JIET (Jodhpur Institute of Engineering & Technology)',
            plan_tier: 'University'
          }
        },
        {
          id: 'b0000000-0000-0000-0000-000000000006',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          role: 'Student',
          name: 'Khushal Gehlot (Mock Sandbox)',
          email: 'khushal@gmail.com',
          phone: '+919999988888',
          is_active: true,
          institutions: {
            name: 'JIET (Jodhpur Institute of Engineering & Technology)',
            plan_tier: 'University'
          }
        },
        {
          id: 'b0000000-0000-0000-0000-000000000015',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          role: 'Security',
          name: 'Vikram Singh (Security Guard Mock)',
          email: 'guard@siet.edu.in',
          phone: '+919876543299',
          is_active: true,
          institutions: {
            name: 'JIET (Jodhpur Institute of Engineering & Technology)',
            plan_tier: 'University'
          }
        }
      ];
    case 'students':
      return [
        {
          id: 'test-student-id',
          roll_number: 'CS23B1042',
          user_id: 'b0000000-0000-0000-0000-000000000006',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          department_id: 'd1',
          semester: '5',
          users: {
            name: 'Khushal Gehlot',
            full_name: 'Khushal Gehlot',
            phone: '+919999988888',
            email: 'khushal@gmail.com'
          },
          departments: {
            name: 'Computer Science'
          }
        },
        {
          id: '',
          roll_number: 'CS23B1042',
          user_id: 'b0000000-0000-0000-0000-000000000006',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          department_id: 'd1',
          semester: '5',
          users: {
            name: 'Khushal Gehlot',
            full_name: 'Khushal Gehlot',
            phone: '+919999988888',
            email: 'khushal@gmail.com'
          },
          departments: {
            name: 'Computer Science'
          }
        },
        {
          id: 'school-student-1',
          roll_number: 'SCH1001',
          user_id: 'b0000000-0000-0000-0000-000000000010',
          institution_id: 'a0000000-0000-0000-0000-000000000002',
          department_id: 'd-school-1',
          semester: null,
          users: {
            name: 'Aarav Patel',
            full_name: 'Aarav Patel',
            phone: '+919876543210',
            email: 'aarav@school.internal'
          },
          departments: {
            name: 'Class 10'
          }
        },
        {
          id: 'school-student-2',
          roll_number: 'SCH1002',
          user_id: 'b0000000-0000-0000-0000-000000000011',
          institution_id: 'a0000000-0000-0000-0000-000000000002',
          department_id: 'd-school-1',
          semester: null,
          users: {
            name: 'Diya Sharma',
            full_name: 'Diya Sharma',
            phone: '+919876543211',
            email: 'diya@school.internal'
          },
          departments: {
            name: 'Class 10'
          }
        },
        {
          id: 'school-student-3',
          roll_number: 'SCH1003',
          user_id: 'b0000000-0000-0000-0000-000000000012',
          institution_id: 'a0000000-0000-0000-0000-000000000002',
          department_id: 'd-school-2',
          semester: null,
          users: {
            name: 'Rohan Gupta',
            full_name: 'Rohan Gupta',
            phone: '+919876543212',
            email: 'rohan@school.internal'
          },
          departments: {
            name: 'Class 8'
          }
        },
        {
          id: 'school-student-4',
          roll_number: 'SCH1004',
          user_id: 'b0000000-0000-0000-0000-000000000013',
          institution_id: 'a0000000-0000-0000-0000-000000000002',
          department_id: 'd-school-2',
          semester: null,
          users: {
            name: 'Sneha Verma',
            full_name: 'Sneha Verma',
            phone: '+919876543213',
            email: 'sneha@school.internal'
          },
          departments: {
            name: 'Class 8'
          }
        }
      ];
    case 'director_alerts':
      return [
        {
          id: 'alert-1',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          alert_type: 'attendance',
          title: 'Low Attendance Alert',
          description: 'CS Department attendance dropped below 75%',
          severity: 'high',
          is_read: false,
          is_resolved: false,
          created_at: new Date().toISOString()
        },
        {
          id: 'alert-2',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          alert_type: 'complaint',
          title: 'Critical Water Leakage',
          description: 'Hostel Block B reported major plumbing breakdown',
          severity: 'critical',
          is_read: false,
          is_resolved: false,
          created_at: new Date().toISOString()
        }
      ];
    case 'alert_thresholds':
      return [
        { id: 't-1', alert_type: 'attendance', threshold_value: 75, comparison: 'lt', is_enabled: true, notify_via: ['push', 'email'] },
        { id: 't-2', alert_type: 'fees', threshold_value: 10000, comparison: 'gt', is_enabled: true, notify_via: ['sms', 'email'] }
      ];
    case 'ai_insights':
      return [
        {
          id: 'insight-1',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          insight_type: 'academic_risk',
          title: 'Declining Midterm Scores',
          description: '3rd semester CS students show 12% lower marks in mathematics compared to last year.',
          severity: 'medium',
          recommendation: 'Arrange extra tutorial classes for math courses.',
          affected_entities: { count: 18 },
          generated_at: new Date().toISOString(),
          is_dismissed: false
        }
      ];
    case 'canteen_menu':
    case 'canteen_items':
      return [
        { id: 'm1', name: 'Masala Dosa', price: 50, category: 'Breakfast', is_available: true },
        { id: 'm2', name: 'Veg Thali', price: 80, category: 'Lunch', is_available: true }
      ];
    case 'canteen_orders':
    case 'fee_payments':
    case 'daily_attendance_summary':
      return [
        { date: today, attendance_percent: 85, total_collected: 185000, amount_paid: 15000, status: 'Completed', payment_date: today }
      ];
    case 'daily_fee_summary':
      return [
        { date: today, total_collected: 185000 }
      ];
    case 'campus_occupancy':
      return [
        { students_inside: 120, timestamp: new Date().toISOString() }
      ];
    case 'hostel_complaints':
      return [
        { id: 'c1', category: 'Plumbing', status: 'open', created_at: new Date().toISOString(), description: 'Leaking pipe' }
      ];
    case 'hostel_rooms':
      return [
        { id: 'r1', room_number: '101', capacity: 4, occupancy: 3, floor: 1 }
      ];
    case 'bus_trips':
      return [
        { id: 'trip1', route_name: 'Route A', status: 'active', driver_name: 'Ramesh Kumar', bus_number: 'KA-01-F-1234' },
        {
          id: '70000000-0000-0000-0000-000000000001',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          bus_id: '70000000-0000-0000-0000-000000000001',
          route_id: '80000000-0000-0000-0000-000000000001',
          status: 'active',
          passenger_count: 5
        }
      ];
    case 'buses':
      return [
        {
          id: '70000000-0000-0000-0000-000000000001',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          vehicle_number: 'RJ-19-PB-4050',
          device_id: 'GPS-DEV-4050',
          route_id: '80000000-0000-0000-0000-000000000001'
        }
      ];
    case 'parent_student_links':
      return [
        {
          id: 'link-1',
          parent_user_id: 'parent-1',
          student_id: '',
          relationship: 'father',
          verified: true,
          users: {
            phone: '+919999988889'
          }
        }
      ];
    case 'events':
      return [
        {
          id: 'e0000000-0000-0000-0000-000000000001',
          title: 'Tech Fest 2026',
          start_datetime: new Date().toISOString(),
          venue: 'Main Auditorium',
          institution_id: 'a0000000-0000-0000-0000-000000000001'
        }
      ];
    case 'event_registrations':
      return [
        {
          id: 'reg-1',
          event_id: 'e0000000-0000-0000-0000-000000000001',
          student_id: '',
          attendance_marked: true,
          institution_id: 'a0000000-0000-0000-0000-000000000001'
        }
      ];
    case 'bus_routes':
      return [
        { id: 'route1', route_name: 'Route A', stops: ['Stop 1', 'Stop 2', 'Stop 3'] }
      ];
    case 'library_books':
    case 'books':
      return [
        { id: 'b1', title: 'Introduction to Algorithms', author: 'CLRS', available_copies: 5, category: 'Computer Science' }
      ];
    case 'library_issues':
      return [
        { id: 'issue1', book_title: 'Clean Code', issue_date: today, due_date: today, status: 'issued' }
      ];
    case 'gate_entries':
    case 'security_incidents':
      return [
        { id: 'g1', person_id: 'p1', person_name: 'Vikram Singh', direction: 'in', timestamp: new Date().toISOString(), location: 'Main Gate' }
      ];
    case 'admissions':
    case 'admissions_applications':
      return [
        { id: 'adm1', applicant_name: 'Aarav Mehta', course: 'Computer Science', status: 'Applied' }
      ];
    case 'placement_drives':
    case 'drives':
      return [
        { id: 'd1', company_name: 'Google', role: 'Software Engineer', package: '35 LPA', status: 'Active', drive_date: today }
      ];
    case 'assignments':
      return [
        { id: 'a1', title: 'Database Normalization', due_date: today, subject: 'DBMS', max_marks: 50 }
      ];
    case 'director_reports':
      return [
        { id: 'rep1', report_type: 'weekly', report_date: today, pdf_url: 'https://example.com/mock-report.pdf', generated_at: new Date().toISOString() }
      ];
    case 'academic_calendar':
    case 'get_academic_calendar_upcoming':
      return [
        {
          id: 'ev-1',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          title: 'Orientation & Induction Programme',
          event_type: 'orientation',
          description: 'Welcome orientation for new batch of students.',
          start_date: '2026-07-02',
          end_date: '2026-07-03',
          semester: 1,
          batch_year: '2026',
          color: '#10B981',
          days_until: 15
        },
        {
          id: 'ev-2',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          title: 'Commencement of Classes (Sem 3, 5, 7)',
          event_type: 'semester_start',
          description: 'Classes begin for all odd semesters.',
          start_date: '2026-07-15',
          end_date: '2026-07-15',
          semester: 5,
          batch_year: '2024',
          color: '#6366F1',
          days_until: 28
        },
        {
          id: 'ev-3',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          title: 'First Mid-Term Examination',
          event_type: 'internal_exam',
          description: 'Midterm testing for all departments.',
          start_date: '2026-09-10',
          end_date: '2026-09-15',
          semester: 5,
          batch_year: '2024',
          color: '#F59E0B',
          days_until: 85
        },
        {
          id: 'ev-4',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          title: 'Autumn Break Vacation',
          event_type: 'vacation',
          description: 'College closed for festive autumn break.',
          start_date: '2026-10-22',
          end_date: '2026-10-28',
          semester: null,
          batch_year: '',
          color: '#8B5CF6',
          days_until: 127
        },
        {
          id: 'ev-5',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          title: 'End Semester Practical Exams',
          event_type: 'exam_start',
          description: 'Practical lab assessments.',
          start_date: '2026-11-20',
          end_date: '2026-11-25',
          semester: 5,
          batch_year: '2024',
          color: '#EF4444',
          days_until: 156
        }
      ];
    case 'academic_calendar_holidays':
      return [
        { id: 'hol-1', institution_id: 'a0000000-0000-0000-0000-000000000001', name: 'Independence Day', date: '2026-08-15', is_optional: false },
        { id: 'hol-2', institution_id: 'a0000000-0000-0000-0000-000000000001', name: 'Raksha Bandhan', date: '2026-08-28', is_optional: true },
        { id: 'hol-3', institution_id: 'a0000000-0000-0000-0000-000000000001', name: 'Gandhi Jayanti', date: '2026-10-02', is_optional: false },
        { id: 'hol-4', institution_id: 'a0000000-0000-0000-0000-000000000001', name: 'Diwali Holiday', date: '2026-11-08', is_optional: false }
      ];
    case 'employees':
      return [
        { id: 'emp1', name: 'Dr. John Doe', role: 'Professor', department: 'Computer Science' }
      ];
    case 'get_parent_child_info':
      return [
        {
          child_id: 'test-student-id',
          student_id: 'test-student-id',
          child_name: 'Khushal Gehlot',
          student_name: 'Khushal Gehlot',
          roll_number: 'CS23B1042',
          class: 'Semester 5 CS',
          attendance_percent: 88,
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          institute_type: mockInstitutions[0]?.institute_type || 'college'
        }
      ];
    case 'get_parent_daily_summary':
      return [
        {
          student_name: 'Khushal Gehlot',
          attendance_present: 1,
          attendance_total: 1,
          attendance_pct: 100,
          canteen_spend: 120,
          canteen_spent: 120,
          bus_boarded: true,
          bus_status: 'On time',
          bus_time: '08:30:00',
          gate_in: '08:45:00',
          gate_out: '16:00:00',
          pending_fees: 0,
          wallet_balance: 500
        }
      ];
    case 'school_attendance':
      return mockSchoolAttendance;
    case 'institution_features':
      return mockInstitutionFeatures;
    case 'attendance_methods':
      return mockAttendanceMethods;
    case 'attendance_devices':
      return mockAttendanceDevices;
    case 'courses':
      return [
        {
          id: 'c-dbms',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          course_code: 'CS-301',
          course_name: 'Database Management Systems',
          credits: 4,
          course_type: 'core',
          semester: 5,
          academic_year: new Date().getFullYear().toString(),
          is_active: true,
          department: { id: 'd1', name: 'Computer Science' }
        },
        {
          id: 'c-wt',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          course_code: 'CS-302',
          course_name: 'Web Technologies',
          credits: 4,
          course_type: 'core',
          semester: 5,
          academic_year: new Date().getFullYear().toString(),
          is_active: true,
          department: { id: 'd1', name: 'Computer Science' }
        },
        {
          id: 'c-ai',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          course_code: 'CS-305',
          course_name: 'Introduction to Artificial Intelligence',
          credits: 3,
          course_type: 'elective',
          semester: 5,
          academic_year: new Date().getFullYear().toString(),
          is_active: true,
          department: { id: 'd1', name: 'Computer Science' }
        },
        {
          id: 'c-os-lab',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          course_code: 'CS-308',
          course_name: 'Operating Systems Lab',
          credits: 2,
          course_type: 'lab',
          semester: 5,
          academic_year: new Date().getFullYear().toString(),
          is_active: true,
          department: { id: 'd1', name: 'Computer Science' }
        }
      ];
    case 'course_registrations':
      return mockCourseRegistrations;
    case 'student_documents':
      return mockStudentDocuments;
    case 'timetable_history':
      return mockTimetableHistory;
    case 'supplementary_exams':
      return mockSupplementaryExams;
    case 're_evaluation_requests':
      return mockReEvaluationRequests;
    case 'alumni':
      return mockAlumni;
    case 'gate_lockdown':
      return mockGateLockdown;
    case 'equipment_maintenance_logs':
      return mockEquipmentMaintenanceLogs;
    case 'visitor_passes':
      return mockVisitorPasses;
    case 'gym_equipment':
      return mockGymEquipment;
    case 'book_reservations':
      return mockBookReservations;
    case 'student_transit_logs':
      return mockStudentTransitLogs;
    case 'event_certificates':
      return mockEventCertificates;
    case 'exam_results':
      return [
        {
          id: 'res-1',
          institution_id: 'a0000000-0000-0000-0000-000000000001',
          student_id: 'test-student-id',
          exam_id: 'exam-1',
          subject: 'Maths',
          marks_obtained: 75,
          max_marks: 100,
          grade: 'B',
          created_at: new Date().toISOString()
        }
      ];
    case 'parent_topup_child_wallet':
      return [
        {
          success: true,
          new_balance: 500
        }
      ];
    case 'get_child_bus_status':
      return [
        {
          is_on_bus: true,
          bus_name: 'Tata Starbus 40-Seater',
          route_name: 'Jodhpur Central Route',
          last_stop: 'Sardarpura 4th Road',
          eta_minutes: 10,
          latitude: 26.2912,
          longitude: 73.0156,
          last_updated: new Date().toISOString()
        }
      ];
    case 'get_bus_eta_for_student':
      return [
        {
          bus_id: '70000000-0000-0000-0000-000000000001',
          bus_name: 'Tata Starbus 40-Seater',
          route_name: 'Jodhpur Central Route',
          stop_name: 'Sardarpura 4th Road',
          stop_index: 0,
          distance_km: 1.2,
          eta_minutes: 10,
          latitude: 26.2912,
          longitude: 73.0156,
          last_updated: new Date().toISOString()
        }
      ];
    default:
      return [];
  }
}

function createMockBuilder(tableName: string) {
  const mockBuilder: any = {
    tableName,
    chain: [] as string[],
    insertedData: null as any,
    updatedData: null as any,
    eqFilters: {} as Record<string, any>,
    inFilters: {} as Record<string, any[]>,
    lteFilters: {} as Record<string, any>,
    gteFilters: {} as Record<string, any>,
    then(onfulfilled: any, onrejected: any) {
      const isSingle = this.chain.includes('single') || this.chain.includes('maybeSingle');
      
      let resolvedData: any;
      
      // Perform simulated write operations
      if ((this.chain.includes('insert') || this.chain.includes('upsert')) && this.insertedData) {
        const records = Array.isArray(this.insertedData) ? this.insertedData : [this.insertedData];
        const newRecords = records.map((rec: any) => {
          const newRec = {
            id: rec.id || `mock-id-${Math.random().toString(36).substr(2, 9)}`,
            ...rec,
            registered_at: rec.registered_at || new Date().toISOString()
          };
          if (tableName === 'course_registrations') {
            // Enrich with mock course info
            const mockCourses = getMockDataForTable('courses');
            const courseObj = mockCourses.find((c: any) => c.id === rec.course_id);
            newRec.course = courseObj ? {
              id: courseObj.id,
              course_code: courseObj.course_code,
              course_name: courseObj.course_name,
              credits: courseObj.credits,
              course_type: courseObj.course_type,
              semester: courseObj.semester
            } : null;
            mockCourseRegistrations.push(newRec);
          } else if (tableName === 'student_documents') {
            mockStudentDocuments.push(newRec);
          } else if (tableName === 'timetable_history') {
            mockTimetableHistory.push(newRec);
          } else if (tableName === 'supplementary_exams') {
            mockSupplementaryExams.push(newRec);
          } else if (tableName === 're_evaluation_requests') {
            mockReEvaluationRequests.push(newRec);
          } else if (tableName === 'alumni') {
            mockAlumni.push(newRec);
          } else if (tableName === 'gate_lockdown') {
            mockGateLockdown.push(newRec);
          } else if (tableName === 'equipment_maintenance_logs') {
            mockEquipmentMaintenanceLogs.push(newRec);
          } else if (tableName === 'visitor_passes') {
            mockVisitorPasses.push(newRec);
          } else if (tableName === 'gym_equipment') {
            mockGymEquipment.push(newRec);
          } else if (tableName === 'book_reservations') {
            mockBookReservations.push(newRec);
          } else if (tableName === 'student_transit_logs') {
            mockStudentTransitLogs.push(newRec);
          } else if (tableName === 'event_certificates') {
            mockEventCertificates.push(newRec);
          } else if (tableName === 'school_attendance') {
            mockSchoolAttendance.push(newRec);
          } else if (tableName === 'institution_features') {
            const idx = mockInstitutionFeatures.findIndex(
              (f: any) => f.institution_id === rec.institution_id && f.feature_key === rec.feature_key
            );
            if (idx >= 0) {
              mockInstitutionFeatures[idx] = newRec;
            } else {
              mockInstitutionFeatures.push(newRec);
            }
          } else if (tableName === 'attendance_methods') {
            const idx = mockAttendanceMethods.findIndex(
              (m: any) => m.institution_id === rec.institution_id && m.method_key === rec.method_key
            );
            if (idx >= 0) {
              mockAttendanceMethods[idx] = newRec;
            } else {
              mockAttendanceMethods.push(newRec);
            }
          } else if (tableName === 'attendance_devices') {
            mockAttendanceDevices.push(newRec);
          }
          return newRec;
        });
        resolvedData = newRecords;
      } else {
        if (this.chain.includes('update') && this.updatedData) {
          if (tableName === 'course_registrations') {
            const targetId = this.eqFilters.id || this.eqFilters.course_id;
            mockCourseRegistrations = mockCourseRegistrations.map(r => {
              if (r.id === targetId || r.course_id === targetId) {
                return { ...r, ...this.updatedData, status: this.updatedData.status || r.status };
              }
              return r;
            });
          } else if (tableName === 'supplementary_exams') {
            const targetId = this.eqFilters.id;
            mockSupplementaryExams = mockSupplementaryExams.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 're_evaluation_requests') {
            const targetId = this.eqFilters.id;
            mockReEvaluationRequests = mockReEvaluationRequests.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'alumni') {
            const targetId = this.eqFilters.id;
            mockAlumni = mockAlumni.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'gate_lockdown') {
            const targetId = this.eqFilters.id;
            mockGateLockdown = mockGateLockdown.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'equipment_maintenance_logs') {
            const targetId = this.eqFilters.id;
            mockEquipmentMaintenanceLogs = mockEquipmentMaintenanceLogs.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'visitor_passes') {
            const targetId = this.eqFilters.id || this.eqFilters.pass_number;
            mockVisitorPasses = mockVisitorPasses.map(r => {
              if (r.id === targetId || r.pass_number === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'gym_equipment') {
            const targetId = this.eqFilters.id;
            mockGymEquipment = mockGymEquipment.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'book_reservations') {
            const targetId = this.eqFilters.id;
            mockBookReservations = mockBookReservations.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'institutions') {
            const targetId = this.eqFilters.id;
            mockInstitutions = mockInstitutions.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'school_attendance') {
            const targetId = this.eqFilters.id;
            mockSchoolAttendance = mockSchoolAttendance.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          } else if (tableName === 'institution_features') {
            const targetId = this.eqFilters.id;
            const targetKey = this.eqFilters.feature_key;
            mockInstitutionFeatures = mockInstitutionFeatures.map(r => {
              if (r.id === targetId || (r.feature_key === targetKey && r.institution_id === this.eqFilters.institution_id)) {
                return { ...r, ...this.updatedData };
              }
              return r;
            });
          } else if (tableName === 'attendance_methods') {
            const targetId = this.eqFilters.id;
            const targetKey = this.eqFilters.method_key;
            mockAttendanceMethods = mockAttendanceMethods.map(r => {
              if (r.id === targetId || (r.method_key === targetKey && r.institution_id === this.eqFilters.institution_id)) {
                return { ...r, ...this.updatedData };
              }
              return r;
            });
          } else if (tableName === 'attendance_devices') {
            const targetId = this.eqFilters.id;
            mockAttendanceDevices = mockAttendanceDevices.map(r => {
              if (r.id === targetId) return { ...r, ...this.updatedData };
              return r;
            });
          }
        }

        if (tableName === 'course_registrations') {
          resolvedData = mockCourseRegistrations;
        } else if (tableName === 'student_documents') {
          resolvedData = mockStudentDocuments;
        } else if (tableName === 'timetable_history') {
          resolvedData = mockTimetableHistory;
        } else if (tableName === 'supplementary_exams') {
          resolvedData = mockSupplementaryExams;
        } else if (tableName === 're_evaluation_requests') {
          resolvedData = mockReEvaluationRequests;
        } else if (tableName === 'alumni') {
          resolvedData = mockAlumni;
        } else if (tableName === 'gate_lockdown') {
          resolvedData = mockGateLockdown;
        } else if (tableName === 'equipment_maintenance_logs') {
          resolvedData = mockEquipmentMaintenanceLogs;
        } else if (tableName === 'visitor_passes') {
          resolvedData = mockVisitorPasses;
        } else if (tableName === 'gym_equipment') {
          resolvedData = mockGymEquipment;
        } else if (tableName === 'book_reservations') {
          resolvedData = mockBookReservations;
        } else if (tableName === 'student_transit_logs') {
          resolvedData = mockStudentTransitLogs;
        } else if (tableName === 'event_certificates') {
          resolvedData = mockEventCertificates;
        } else if (tableName === 'institutions') {
          resolvedData = mockInstitutions;
        } else if (tableName === 'school_attendance') {
          resolvedData = mockSchoolAttendance;
        } else if (tableName === 'attendance_methods') {
          resolvedData = mockAttendanceMethods;
        } else if (tableName === 'attendance_devices') {
          resolvedData = mockAttendanceDevices;
        } else {
          resolvedData = getMockDataForTable(this.tableName);
        }

        // Apply eq filters if present
        if (Object.keys(this.eqFilters).length > 0) {
          resolvedData = resolvedData.filter((item: any) => {
            for (const [key, value] of Object.entries(this.eqFilters)) {
              if (item[key] !== undefined && item[key] !== value) {
                return false;
              }
            }
            return true;
          });
        }
        if (Object.keys(this.inFilters).length > 0) {
          resolvedData = resolvedData.filter((item: any) => {
            for (const [key, values] of Object.entries(this.inFilters)) {
              if (item[key] !== undefined && (!Array.isArray(values) || !values.includes(item[key]))) {
                return false;
              }
            }
            return true;
          });
        }
        if (Object.keys(this.lteFilters).length > 0) {
          resolvedData = resolvedData.filter((item: any) => {
            for (const [key, val] of Object.entries(this.lteFilters)) {
              if (item[key] !== undefined && item[key] > val) {
                return false;
              }
            }
            return true;
          });
        }
        if (Object.keys(this.gteFilters).length > 0) {
          resolvedData = resolvedData.filter((item: any) => {
            for (const [key, val] of Object.entries(this.gteFilters)) {
              if (item[key] !== undefined && item[key] < val) {
                return false;
              }
            }
            return true;
          });
        }
      }

      if (isSingle) {
        resolvedData = resolvedData && resolvedData.length > 0 ? resolvedData[0] : null;
      }
      const count = Array.isArray(resolvedData) ? resolvedData.length : (resolvedData ? 1 : 0);
      return Promise.resolve({
        data: resolvedData,
        error: null,
        count
      }).then(onfulfilled, onrejected);
    }
  };

  const proxy: any = new Proxy(mockBuilder, {
    get(target, prop, receiver) {
      if (prop === 'then') {
        return target.then.bind(target);
      }
      return (...args: any[]) => {
        if (typeof prop === 'string') {
          target.chain.push(prop);
          if ((prop === 'insert' || prop === 'upsert') && args[0]) {
            target.insertedData = args[0];
          }
          if (prop === 'update' && args[0]) {
            target.updatedData = args[0];
          }
          if (prop === 'eq' && args[0] && args[1] !== undefined) {
            target.eqFilters[args[0]] = args[1];
          }
          if (prop === 'in' && args[0] && Array.isArray(args[1])) {
            target.inFilters[args[0]] = args[1];
          }
          if (prop === 'lte' && args[0] && args[1] !== undefined) {
            target.lteFilters[args[0]] = args[1];
          }
          if (prop === 'gte' && args[0] && args[1] !== undefined) {
            target.gteFilters[args[0]] = args[1];
          }
        }
        return proxy;
      };
    }
  });
  return proxy;
}

const mockSupabaseClient = {
  auth: mockAuth,
  storage: mockStorage,
  from: (tableName: string) => createMockBuilder(tableName),
  rpc: (funcName: string) => createMockBuilder(funcName)
} as any;

// Export supabaseAdmin as a Proxy that dynamically routes to getDynamicSupabaseClient()
export const supabaseAdmin = new Proxy({} as SupabaseClient, {
  get(target, prop, receiver) {
    if (isSupabaseOffline && process.env.NODE_ENV !== 'production') {
      const value = Reflect.get(mockSupabaseClient, prop, mockSupabaseClient);
      if (typeof value === 'function') {
        return value.bind(mockSupabaseClient);
      }
      return value;
    }
    const dynamicClient = getDynamicSupabaseClient();
    const value = Reflect.get(dynamicClient, prop, dynamicClient);
    if (typeof value === 'function') {
      return value.bind(dynamicClient);
    }
    return value;
  }
});

// Export a raw, un-proxied client for explicit administrative actions
export const supabaseServiceRole = new Proxy({} as SupabaseClient, {
  get(target, prop, receiver) {
    if (isSupabaseOffline && process.env.NODE_ENV !== 'production') {
      const value = Reflect.get(mockSupabaseClient, prop, mockSupabaseClient);
      if (typeof value === 'function') {
        return value.bind(mockSupabaseClient);
      }
      return value;
    }
    const adminClient = getSupabaseAdminInternal();
    const value = Reflect.get(adminClient, prop, adminClient);
    if (typeof value === 'function') {
      return value.bind(adminClient);
    }
    return value;
  }
}) as any;

export function getSupabaseClient(req?: Request) {
  if (isSupabaseOffline && process.env.NODE_ENV !== 'production') {
    return mockSupabaseClient;
  }
  const authHeader = req?.headers?.authorization;
  const token = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : null;

  if (token && supabaseUrl) {
    const anonKey = process.env.SUPABASE_ANON_KEY || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || supabaseServiceKey;
    return createClient(supabaseUrl, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false
      },
      global: {
        headers: {
          Authorization: `Bearer ${token}`
        }
      }
    });
  }
  return getSupabaseAdminInternal();
}

// Middleware: block requests when Supabase is offline (returns 503)
export function requireSupabaseOnline(req: Request, res: Response, next: NextFunction) {
  if (isSupabaseOffline && process.env.NODE_ENV === 'production') {
    return res.status(503).json({
      success: false,
      error: 'Database service is temporarily unavailable. Please try again later.'
    });
  }
  next();
}

// Helper: check if Supabase is available, return true if online
export async function checkSupabaseOnline(): Promise<boolean> {
  if (!supabaseUrl || !supabaseServiceKey) return false;
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000);
    const res = await fetch(`${supabaseUrl}/rest/v1/`, {
      method: 'GET',
      headers: { apikey: supabaseServiceKey },
      signal: controller.signal
    });
    clearTimeout(timeoutId);
    return res.ok || res.status === 404 || res.status === 401;
  } catch {
    return false;
  }
}
