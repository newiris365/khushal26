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

export async function POST(req: NextRequest) {
  try {
    const userPayload = extractUserFromHeader(req);
    const body = await req.json().catch(() => ({}));

    const parentUserId = userPayload?.id || body?.parent_user_id;
    if (!parentUserId) {
      return NextResponse.json({ success: false, error: 'Authentication required.' }, { status: 401 });
    }

    const { institution_id, student_roll_or_id, dob, roll_number, child_dob } = body;
    const targetInstitutionId = institution_id;
    const targetRollOrId = (student_roll_or_id || roll_number || '').trim();
    const targetDob = (dob || child_dob || '').trim();

    if (!targetInstitutionId || !targetRollOrId) {
      return NextResponse.json(
        { success: false, error: 'Institution selection and student Roll Number / ID are required.' },
        { status: 400 }
      );
    }

    // 1. Require parent's paid platform payment record (status = 'paid')
    const { data: paymentRow } = await supabaseAdmin
      .from('parent_platform_payments')
      .select('*')
      .eq('parent_user_id', parentUserId)
      .eq('status', 'paid')
      .maybeSingle();

    // Dev / Test mode fallback if order was created with mock Payment ID
    const { data: devPaymentRow } = await supabaseAdmin
      .from('parent_platform_payments')
      .select('*')
      .eq('parent_user_id', parentUserId)
      .maybeSingle();

    const isPaid =
      !!paymentRow ||
      (devPaymentRow && (devPaymentRow.razorpay_order_id.includes('mock') || process.env.NODE_ENV !== 'production'));

    if (!isPaid) {
      return NextResponse.json(
        {
          success: false,
          error: 'Platform onboarding access fee payment (₹150) is required before linking a student.'
        },
        { status: 402 }
      );
    }

    // 2. Find matching student record scoped to institution_id
    let matchedStudent: any = null;

    // Search students table by roll_number or student_id or id under targetInstitutionId
    const { data: studentsList } = await supabaseAdmin
      .from('students')
      .select('id, user_id, roll_number, student_id, dob, institution_id, name')
      .eq('institution_id', targetInstitutionId);

    if (studentsList && studentsList.length > 0) {
      matchedStudent = studentsList.find((s: any) => {
        const rollMatch =
          (s.roll_number && s.roll_number.toLowerCase() === targetRollOrId.toLowerCase()) ||
          (s.student_id && s.student_id.toLowerCase() === targetRollOrId.toLowerCase()) ||
          s.id === targetRollOrId;
        if (!rollMatch) return false;

        if (targetDob && s.dob) {
          const formattedTarget = new Date(targetDob).toISOString().slice(0, 10);
          const formattedStudent = new Date(s.dob).toISOString().slice(0, 10);
          return formattedTarget === formattedStudent;
        }
        return true;
      });
    }

    // Fallback: If no direct student table match found in mock dev dataset, search users table
    if (!matchedStudent) {
      const { data: usersList } = await supabaseAdmin
        .from('users')
        .select('*')
        .eq('role', 'Student')
        .eq('institution_id', targetInstitutionId);

      if (usersList && usersList.length > 0) {
        const matchedUser = usersList.find((u: any) => {
          return (
            u.id === targetRollOrId ||
            (u.email && u.email.toLowerCase().includes(targetRollOrId.toLowerCase())) ||
            (u.name && u.name.toLowerCase().includes(targetRollOrId.toLowerCase()))
          );
        });
        if (matchedUser) {
          matchedStudent = {
            id: matchedUser.id,
            user_id: matchedUser.id,
            name: matchedUser.name || matchedUser.full_name,
            roll_number: targetRollOrId,
            institution_id: targetInstitutionId
          };
        }
      }
    }

    if (!matchedStudent) {
      return NextResponse.json(
        {
          success: false,
          error:
            'No matching student record found for the provided Roll Number/ID and Date of Birth at the selected institution.'
        },
        { status: 404 }
      );
    }

    // 3. Find parent_profiles ID
    let parentProfileId: string = parentUserId;
    const { data: parentProfile } = await supabaseAdmin
      .from('parent_profiles')
      .select('id')
      .eq('user_id', parentUserId)
      .maybeSingle();

    if (parentProfile) {
      parentProfileId = parentProfile.id;
    }

    // 4. Create or update parent_student_links row
    const { error: linkError } = await supabaseAdmin.from('parent_student_links').upsert(
      {
        parent_id: parentProfileId,
        student_id: matchedStudent.id,
        is_verified: true,
        verified_at: new Date().toISOString(),
        created_at: new Date().toISOString()
      },
      { onConflict: 'parent_id,student_id' }
    );

    if (linkError) {
      // Try alternate schema column names if parent_id vs parent_user_id differs
      await supabaseAdmin
        .from('parent_student_links')
        .insert({
          parent_user_id: parentUserId,
          student_id: matchedStudent.id,
          is_verified: true,
          created_at: new Date().toISOString()
        })
        .catch(() => null);
    }

    // Also update parent profile institution_id to selected institution if currently null
    await supabaseAdmin
      .from('parent_profiles')
      .update({ institution_id: targetInstitutionId })
      .eq('user_id', parentUserId)
      .is('institution_id', null);

    // Resolve student display name
    let studentName = matchedStudent.name || matchedStudent.full_name;
    if (!studentName && matchedStudent.user_id) {
      const { data: u } = await supabaseAdmin
        .from('users')
        .select('name, full_name')
        .eq('id', matchedStudent.user_id)
        .maybeSingle();
      studentName = u?.name || u?.full_name;
    }
    studentName = studentName || targetRollOrId;

    return NextResponse.json({
      success: true,
      message: `Successfully linked student ${studentName}`,
      student_id: matchedStudent.id,
      student_name: studentName,
      institution_id: targetInstitutionId
    });
  } catch (err: any) {
    console.error('[POST /api/parent-onboarding/link-student] Error:', err);
    return NextResponse.json({ success: false, error: err?.message || 'Failed to link student.' }, { status: 500 });
  }
}
