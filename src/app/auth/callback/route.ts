import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';

// Force this route to always be server-rendered (never statically cached).
// Required for cookie access on Netlify SSR deployments.
export const dynamic = 'force-dynamic';

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const JWT_SECRET = process.env.JWT_SECRET || '';


// Create a service-role supabase client to fetch profiles bypassed RLS
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false
  }
});

// Standardized mapping of lowercased role strings to their official capitalized casings
const ROLE_CASING_MAP: Record<string, string> = {
  'admin': 'Admin',
  'superadmin': 'SuperAdmin',
  'staff': 'Staff',
  'teacher': 'Teacher',
  'student': 'Student',
  'parent': 'Parent',
  'warden': 'Warden',
  'security': 'Security',
  'vendor': 'Vendor',
  'driver': 'Driver',
  'director': 'Director',
  'tpo': 'TPO',
  'hod': 'HOD',
  'librarian': 'Librarian',
  'gym trainer': 'Gym Trainer',
  'iqac coordinator': 'IQAC Coordinator',
  'admissions officer': 'Admissions Officer',
  'principal': 'Principal',
  'vice principal': 'Vice Principal',
  'vp': 'Vice Principal',
  'hr admin': 'HR Admin',
  'applicant': 'Applicant',
  'company hr': 'Company HR',
  'alumni': 'Alumni'
};

function normalizeRole(role: string | undefined | null): string {
  if (!role) return '';
  const normalized = ROLE_CASING_MAP[role.toLowerCase()];
  return normalized || role;
}

const getRedirectPath = (role: string): string => {
  switch (role) {
    case 'SuperAdmin': return '/admin/global';
    case 'Admin': return '/admin/dashboard';
    case 'Student': return '/student/dashboard';
    case 'Warden': return '/warden/dashboard';
    case 'Security': return '/gate';
    case 'Driver': return '/transit';
    case 'Librarian': return '/librarian/library';
    case 'Director': return '/director';
    case 'Parent': return '/parent/dashboard';
    case 'Teacher': return '/teacher/timetable';
    case 'HOD': return '/hod/dashboard';
    case 'Vendor': return '/vendor/dashboard';
    case 'Principal': return '/principal/dashboard';
    case 'Vice Principal': return '/vp/dashboard';
    case 'VP': return '/vp/dashboard';
    case 'HR Admin': return '/hr/my/dashboard';
    case 'Company HR': return '/company';
    case 'IQAC Coordinator': return '/iqac';
    case 'Admissions Officer': return '/officer/admissions';
    case 'TPO': return '/tpo';
    case 'Staff': return '/faculty';
    default: return '/dashboard';
  }
};

function computeFingerprint(req: NextRequest, deviceId: string): string {
  const userAgent = req.headers.get('user-agent') || 'unknown';

  // Try to resolve client IP
  let ip = req.ip || req.headers.get('x-forwarded-for') || 'unknown';
  if (ip.includes(',')) {
    ip = ip.split(',')[0].trim();
  }

  let ipSegment = ip;
  if (ip.includes(':')) {
    // IPv6 subnet masking
    ipSegment = ip.split(':').slice(0, 4).join(':');
  } else if (ip.includes('.')) {
    // IPv4 subnet masking
    ipSegment = ip.split('.').slice(0, 3).join('.');
  }

  const raw = `${userAgent}-${ipSegment}-${deviceId}`;
  return crypto.createHash('sha256').update(raw).digest('hex');
}

function renderErrorPage(errorMessage: string) {
  const html = `
    <!DOCTYPE html>
    <html>
    <head><title>Authentication Error</title></head>
    <body style="background-color:#0D0A1A;color:white;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
      <div style="text-align:center;max-width:440px;width:100%;padding:32px;border:1px solid rgba(239,68,68,0.25);background-color:#13102A;border-radius:24px;box-shadow:0 20px 25px -5px rgba(0,0,0,0.5);">
        <div style="width:48px;height:48px;border-radius:50%;background-color:rgba(239,68,68,0.1);border:1px solid rgba(239,68,68,0.2);display:inline-flex;align-items:center;justify-content:center;margin-bottom:20px;">
          <svg style="width:24px;height:24px;color:#EF4444;" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"/>
          </svg>
        </div>
        <h2 style="color:#EF4444;font-size:20px;font-weight:800;margin-top:0;margin-bottom:8px;">Authentication Failed</h2>
        <p style="font-size:13px;color:#C4B5FD;line-height:1.6;margin-bottom:24px;">${errorMessage}</p>
        <a href="/login" style="display:block;width:100%;box-sizing:border-box;text-align:center;padding:12px;background:linear-gradient(to right,#6C2BD9,#8B5CF6);color:white;text-decoration:none;border-radius:12px;font-weight:bold;font-size:14px;">Return to Login</a>
      </div>
    </body>
    </html>
  `;
  return new NextResponse(html, { headers: { 'Content-Type': 'text/html' } });
}

function renderClientHashBridge() {
  const html = `
    <!DOCTYPE html>
    <html>
    <head><title>Authenticating...</title></head>
    <body style="background-color:#0D0A1A;color:white;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0;">
      <div style="text-align:center;display:flex;flex-direction:column;align-items:center;gap:16px;">
        <div style="width:40px;height:40px;border:3px solid rgba(124,58,237,0.3);border-top-color:#7C3AED;border-radius:50%;animation:spin 1s infinite linear;"></div>
        <p style="font-size:14px;font-weight:500;color:#C4B5FD;">Verifying Google login parameters...</p>
      </div>
      <style>@keyframes spin{from{transform:rotate(0deg)}to{transform:rotate(360deg)}}</style>
      <script>
        (function(){
          try{
            const hash=window.location.hash;
            if(hash&&hash.includes('access_token=')){
              const params=new URLSearchParams(hash.substring(1));
              const at=params.get('access_token');
              const rt=params.get('refresh_token');
              if(at){
                const u=new URL(window.location.href);
                u.searchParams.set('access_token',at);
                if(rt)u.searchParams.set('refresh_token',rt);
                u.hash='';
                window.location.href=u.toString();
                return;
              }
            }
            window.location.href='/login?error='+encodeURIComponent('No authorization code or session tokens returned from Google.');
          }catch(e){
            window.location.href='/login?error='+encodeURIComponent('Authentication routing error');
          }
        })();
      </script>
    </body>
    </html>
  `;
  return new NextResponse(html, { headers: { 'Content-Type': 'text/html' } });
}

export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);

  const code = requestUrl.searchParams.get('code');
  const accessToken = requestUrl.searchParams.get('access_token');
  const refreshToken = requestUrl.searchParams.get('refresh_token');
  const deviceId = requestUrl.searchParams.get('device_id') || 'unknown-device';

  // If no server-side query params exist, check client-side hash fragment (Implicit flow)
  if (!code && !accessToken) {
    return renderClientHashBridge();
  }

  if (!JWT_SECRET || JWT_SECRET.length < 32) {
    return renderErrorPage('JWT Secret key is missing or invalid on the server.');
  }

  try {
    let authUser: any = null;
    let authSession: { access_token: string; refresh_token: string } | null = null;

    if (code) {
      // ─── STEP 4: PKCE code exchange via createServerClient ─────────────────
      console.log('[auth/callback] STEP 4 — Attempting server-side PKCE code exchange...');
      try {
        const cookieStore = await cookies();
        const supabaseSSR = createServerClient(
          supabaseUrl || process.env.NEXT_PUBLIC_SUPABASE_URL || 'https://bxdfmlqzstwcsujdgejn.supabase.co',
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '',
          {
            cookies: {
              getAll() {
                return cookieStore.getAll();
              },
              setAll(cookiesToSet) {
                try {
                  cookiesToSet.forEach(({ name, value, options }) => {
                    cookieStore.set(name, value, options);
                  });
                } catch {
                  // Ignore in read-only route handler context
                }
              }
            },
            cookieOptions: {
              name: 'sb-auth-token',
              path: '/',
              sameSite: 'lax',
              secure: process.env.NODE_ENV === 'production'
            }
          }
        );

        const { data: authData, error: authError } = await supabaseSSR.auth.exchangeCodeForSession(code);

        if (!authError && authData?.session && authData?.user) {
          authUser = authData.user;
          authSession = {
            access_token: authData.session.access_token,
            refresh_token: authData.session.refresh_token
          };
          console.log('[auth/callback] Server-side PKCE code exchange SUCCEEDED for user:', authUser.email);
        } else {
          console.warn('[auth/callback] Server-side PKCE exchange failed:', authError?.message || 'No session returned');
        }
      } catch (exchangeErr: any) {
        console.warn('[auth/callback] Server-side PKCE exception:', exchangeErr?.message);
      }

      // If server-side exchange failed (e.g. cookie stripped by mobile browser / proxy),
      // redirect to /login with code so the browser client can exchange using document.cookie.
      if (!authUser || !authSession) {
        console.log('[auth/callback] Redirecting to /login for client-side PKCE fallback exchange...');
        const loginExchangeUrl = new URL('/login', requestUrl.origin);
        loginExchangeUrl.searchParams.set('code', code);
        if (deviceId && deviceId !== 'unknown-device') {
          loginExchangeUrl.searchParams.set('device_id', deviceId);
        }
        return NextResponse.redirect(loginExchangeUrl);
      }
    } else if (accessToken) {
      // Implicit flow or client-side bridge fallback
      const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(accessToken);
      if (userError || !userData?.user) {
        throw new Error(userError?.message || 'Failed to retrieve user from access token');
      }
      authUser = userData.user;
      authSession = {
        access_token: accessToken,
        refresh_token: refreshToken || ''
      };
    }

    if (!authUser || !authSession) {
      throw new Error('Authentication session structure is invalid');
    }

    const email = authUser.email;
    if (!email) {
      throw new Error('No email returned from Google authentication provider');
    }

    // Fetch user profile matching the authenticated email
    const { data: userProfile, error: profileError } = await supabaseAdmin
      .from('users')
      .select('*, institutions(name, plan_tier, type)')

      .eq('email', email)
      .single();

    if (profileError) {
      console.error('[auth/callback] Profile lookup error:', profileError.message);
    }

    let resolvedRole = 'Student';
    let resolvedInstitutionId = 'a0000000-0000-0000-0000-000000000001';
    let resolvedName = authUser.user_metadata?.full_name || authUser.user_metadata?.name || 'Google User';
    let resolvedInstitutionName = 'JIET (Jodhpur Institute of Engineering & Technology)';
    let resolvedPlanTier = 'University';
    let resolvedInstituteType = 'college';
    let isActive = true;
    let profileId = authUser.id;

    if (userProfile) {
      resolvedRole = userProfile.role;
      resolvedInstitutionId = userProfile.institution_id;
      resolvedName = userProfile.name;
      resolvedInstitutionName = userProfile.institutions?.name || resolvedInstitutionName;
      resolvedPlanTier = userProfile.institutions?.plan_tier || resolvedPlanTier;
      resolvedInstituteType = userProfile.institutions?.type === 'school' ? 'school' : 'college';
      isActive = userProfile.is_active;
      profileId = userProfile.id;
    } else {
      // Email not found in users table — reject OAuth login
      return NextResponse.redirect(new URL('/login?error=user_not_found', requestUrl.origin));
    }

    if (!isActive) {
      return renderErrorPage('Your platform profile has been deactivated.');
    }

    const normalizedRole = normalizeRole(resolvedRole);

    const tokenClaims = {
      id: profileId,
      institution_id: resolvedInstitutionId,
      role: normalizedRole,
      email,
      // fingerprint intentionally omitted — computed on Vercel serverless IP/UA, never matches Render
      supabase_token: authSession.access_token,
      institute_type: resolvedInstituteType
    };

    const token = jwt.sign(tokenClaims, JWT_SECRET, { expiresIn: '7d' });

    const profileData = {
      id: profileId,
      name: resolvedName,
      email,
      role: normalizedRole,
      institution_id: resolvedInstitutionId,
      institution_name: resolvedInstitutionName,
      plan_tier: resolvedPlanTier,
      institute_type: resolvedInstituteType
    };

    const redirectPath = getRedirectPath(normalizedRole);

    // ─── Reliable token delivery via URL redirect ─────────────────────────────
    // The previous HTML bridge approach (inline <script> writing localStorage)
    // was silently failing — browser security policies (CSP, ITP, incognito mode)
    // can block inline script execution or localStorage access in third-party contexts.
    //
    // New approach: redirect to /login with the token embedded as a URL query param.
    // The login page React code reads it, writes localStorage, then navigates to the
    // correct dashboard — this always runs in a trusted first-party page context.
    // ─────────────────────────────────────────────────────────────────────────────
    const loginRedirectUrl = new URL('/login', requestUrl.origin);
    loginRedirectUrl.searchParams.set('token', token);
    loginRedirectUrl.searchParams.set('refresh', authSession.refresh_token);
    loginRedirectUrl.searchParams.set('profile', JSON.stringify(profileData));
    loginRedirectUrl.searchParams.set('path', redirectPath);

    return NextResponse.redirect(loginRedirectUrl);

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'OAuth authentication failed.';
    console.error('[auth/callback] Error:', message);
    return renderErrorPage(message);
  }
}
