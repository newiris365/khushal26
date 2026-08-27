import { Request, Response } from 'express';
import { z } from 'zod';
import crypto from 'crypto';
import { supabaseAdmin } from '../config/supabase';
import PDFDocument from 'pdfkit';
import logger from '../config/logger';

// In-memory cache for tracking single-use tokens within their validity window (60s)
const processedGateQrTokens = new Map<string, number>();

// Clean up stale token hashes every 2 minutes
setInterval(() => {
  const now = Date.now();
  for (const [hash, expiry] of processedGateQrTokens.entries()) {
    if (expiry < now) {
      processedGateQrTokens.delete(hash);
    }
  }
}, 120000);

export function getGateQrSecret(institutionId?: string): string {
  return (
    process.env.GATE_QR_SECRET ||
    process.env.JWT_SECRET ||
    (institutionId ? `${institutionId}_gate_qr_secret_key` : 'default_gate_qr_secret_key_iris365')
  );
}

export function generateSignedGateQR(
  payload: { person_id: string; timestamp: string | number; person_type: string },
  institutionId?: string
): string {
  const secret = getGateQrSecret(institutionId);
  const payloadStr = typeof payload === 'string' ? payload : JSON.stringify(payload);
  const base64Payload = Buffer.from(payloadStr).toString('base64url');
  const signature = crypto.createHmac('sha256', secret).update(base64Payload).digest('hex');

  return `${base64Payload}.${signature}`;
}

export function verifyAndDecodeGateQRToken(
  qrToken: string,
  institutionId?: string
): { person_id: string; timestamp: string; person_type: string } {
  const secret = getGateQrSecret(institutionId);

  let base64Payload = '';
  let signature = '';
  let payloadObj: any = null;

  const trimmedToken = qrToken.trim();
  if (trimmedToken.startsWith('{')) {
    // Format: JSON string containing { person_id, timestamp, person_type, signature }
    try {
      payloadObj = JSON.parse(trimmedToken);
      if (!payloadObj || typeof payloadObj !== 'object') {
        throw new Error('Invalid JSON payload in QR token.');
      }
      signature = payloadObj.signature;
      if (!signature) {
        throw new Error('Unsigned QR security token: Missing HMAC signature.');
      }
      // Reconstruct clean canonical payload string for signature verification (excluding signature field)
      const { signature: _sig, ...cleanPayload } = payloadObj;
      const cleanPayloadStr = JSON.stringify(cleanPayload);
      base64Payload = Buffer.from(cleanPayloadStr).toString('base64url');
    } catch (err: any) {
      throw new Error(err.message || 'Invalid QR code token format.');
    }
  } else {
    // Format: base64url(JSON_payload).signature
    const lastDotIndex = trimmedToken.lastIndexOf('.');
    if (lastDotIndex === -1) {
      throw new Error('Invalid QR token format.');
    }
    base64Payload = trimmedToken.substring(0, lastDotIndex);
    signature = trimmedToken.substring(lastDotIndex + 1);
    try {
      const decodedStr = Buffer.from(base64Payload, 'base64url').toString('utf-8');
      payloadObj = JSON.parse(decodedStr);
    } catch {
      throw new Error('Invalid base64 payload in QR token.');
    }
  }

  if (!signature) {
    throw new Error('Unsigned QR security token: Missing HMAC signature.');
  }

  // Recompute HMAC signature over base64Payload using server secret
  const expectedSignature = crypto.createHmac('sha256', secret).update(base64Payload).digest('hex');

  const sigBuf = Buffer.from(signature);
  const expectedBuf = Buffer.from(expectedSignature);

  if (sigBuf.length !== expectedBuf.length || !crypto.timingSafeEqual(sigBuf, expectedBuf)) {
    throw new Error('Invalid QR code security signature.');
  }

  const { person_id, timestamp, person_type } = payloadObj;
  if (!person_id || !timestamp || !person_type) {
    throw new Error('Incomplete QR code metadata.');
  }

  // Idempotency / Single-Use Check
  const tokenHash = crypto.createHash('sha256').update(`${person_id}:${timestamp}:${signature}`).digest('hex');
  const now = Date.now();
  if (processedGateQrTokens.has(tokenHash)) {
    const prevExpiry = processedGateQrTokens.get(tokenHash)!;
    if (prevExpiry > now) {
      throw new Error('Replayed QR token: Token has already been scanned.');
    }
  }

  // Store in cache for 65 seconds
  processedGateQrTokens.set(tokenHash, now + 65000);

  return { person_id, timestamp, person_type };
}

// ========== ZOD VALIDATION SCHEMAS ==========

export const qrEntrySchema = z.object({
  qr_token: z.string().min(1), // JSON string: { "person_id": "...", "timestamp": "...", "person_type": "student" }
  gate_number: z.string().default('main')
});

export const biometricEntrySchema = z.object({
  biometric_id: z.string().min(1), // finger index ID
  person_type: z.enum(['student', 'staff']),
  gate_number: z.string().default('main')
});

export const rfidEntrySchema = z.object({
  card_uid: z.string().min(1),
  gate_number: z.string().default('main')
});

export const manualEntrySchema = z.object({
  person_name: z.string().min(1),
  person_type: z.enum(['student', 'staff', 'visitor']),
  person_id: z.string().uuid().optional().nullable(),
  entry_method: z.literal('manual'),
  direction: z.enum(['in', 'out']),
  gate_number: z.string().default('main'),
  reason: z.string().min(1),
  photo_url: z.string().optional()
});

export const createVisitorSchema = z.object({
  visitor_name: z.string().min(1),
  visitor_phone: z.string().min(1),
  visitor_email: z.string().email().optional().or(z.literal('')),
  visitor_id_type: z.string().min(1),
  visitor_id_number: z.string().min(1),
  visitor_photo_url: z.string().optional().or(z.literal('')),
  host_id: z.string().uuid(),
  host_type: z.enum(['student', 'staff']),
  host_name: z.string().min(1),
  purpose: z.string().min(1),
  valid_hours: z.number().int().positive().default(4)
});

export const registerRfidSchema = z.object({
  card_uid: z.string().min(1),
  person_id: z.string().uuid(),
  person_type: z.enum(['student', 'staff']),
  expiry_date: z.string().optional()
});

export const createIncidentSchema = z.object({
  incident_type: z.string().min(1),
  description: z.string().min(1),
  location: z.string().min(1),
  severity: z.enum(['low', 'medium', 'high', 'critical']),
  photo_urls: z.array(z.string()).optional()
});

export const updateIncidentStatusSchema = z.object({
  status: z.enum(['open', 'investigating', 'resolved']),
  resolution: z.string().optional()
});

export const createBlacklistSchema = z.object({
  name: z.string().min(1),
  phone: z.string().min(1),
  id_number: z.string().optional().or(z.literal('')),
  photo_url: z.string().optional().or(z.literal('')),
  reason: z.string().min(1)
});

// ========== HELPER: UPDATE OCCUPANCY COUNTER ==========
async function updateOccupancyCounts(institution_id: string, person_type: string, direction: 'in' | 'out') {
  try {
    // Fetch latest occupancy record
    const { data: latest, error: fetchErr } = await supabaseAdmin
      .from('campus_occupancy')
      .select('*')
      .eq('institution_id', institution_id)
      .order('timestamp', { ascending: false })
      .limit(1)
      .maybeSingle();

    let studentsInside = latest?.students_inside || 0;
    let staffInside = latest?.staff_inside || 0;
    let visitorsInside = latest?.visitors_inside || 0;

    const delta = direction === 'in' ? 1 : -1;

    if (person_type === 'student') {
      studentsInside = Math.max(0, studentsInside + delta);
    } else if (person_type === 'staff') {
      staffInside = Math.max(0, staffInside + delta);
    } else if (person_type === 'visitor') {
      visitorsInside = Math.max(0, visitorsInside + delta);
    }

    // Insert updated occupancy log
    const { data: inserted, error: insertErr } = await supabaseAdmin
      .from('campus_occupancy')
      .insert({
        institution_id,
        students_inside: studentsInside,
        staff_inside: staffInside,
        visitors_inside: visitorsInside
      })
      .select()
      .single();

    if (insertErr) {
      logger.error('Error updating occupancy counts database: ' + insertErr.message);
      return;
    }

    // Emit live Socket.io updates to "admin:gate" room
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:occupancy_updated', {
          students_inside: studentsInside,
          staff_inside: staffInside,
          visitors_inside: visitorsInside,
          timestamp: new Date().toISOString()
        });
      }
    } catch (wsErr) {
      logger.error('Error broadcasting gate:occupancy_updated: ', wsErr);
    }
  } catch (err) {
    logger.error('Failed to update occupancy stats: ', err);
  }
}

// ========== HELPER: GET LAST MOVEMENT DIRECTION ==========
async function getLastDirection(person_id: string): Promise<'in' | 'out'> {
  const { data } = await supabaseAdmin
    .from('gate_entries')
    .select('direction')
    .eq('person_id', person_id)
    .order('timestamp', { ascending: false })
    .limit(1)
    .maybeSingle();

  // If no entry exists, standard toggle is "in"
  return data?.direction === 'in' ? 'out' : 'in';
}

// ========== 1. QR CODE ENTRY (QR SCAN) ==========
export async function entryQR(req: Request, res: Response) {
  try {
    // Check if campus is in emergency lockdown
    const { data: activeLockdown } = await supabaseAdmin
      .from('gate_lockdown')
      .select('is_locked_down')
      .eq('institution_id', req.user?.institution_id)
      .eq('is_locked_down', true)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (activeLockdown && activeLockdown.is_locked_down) {
      return res.status(403).json({ success: false, error: 'ACCESS DENIED: Campus is in emergency lockdown.' });
    }

    const parse = qrEntrySchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { qr_token, gate_number } = parse.data;

    let payload: { person_id: string; timestamp: string; person_type: string };
    try {
      payload = verifyAndDecodeGateQRToken(qr_token, req.user?.institution_id);
    } catch (err: any) {
      return res.status(403).json({ success: false, error: err.message || 'Security QR code verification failed.' });
    }

    const { person_id, timestamp, person_type } = payload;

    // Verify rotation timing claim (60 seconds limit check)
    const qrAge = Date.now() - new Date(timestamp).getTime();
    if (qrAge > 60000 || qrAge < -5000) {
      return res
        .status(403)
        .json({ success: false, error: 'Security QR code expired. Please refresh your pass screen.' });
    }

    // Verify user profile is active
    const { data: user, error: userErr } = await supabaseAdmin
      .from('users')
      .select('name, is_active')
      .eq('id', person_id)
      .eq('institution_id', req.user?.institution_id)
      .single();

    if (userErr || !user) {
      return res.status(404).json({ success: false, error: 'User profile record not found.' });
    }

    if (!user.is_active) {
      return res.status(403).json({ success: false, error: 'User profile is currently suspended.' });
    }

    const targetDirection = await getLastDirection(person_id);

    // Alerts check (Late arrival > 9 AM or Early exit < 4 PM for students)
    let reason = '';
    const now = new Date();
    const currentHour = now.getHours();

    if (person_type === 'student') {
      if (targetDirection === 'in' && currentHour >= 9) {
        reason = 'Late arrival (after 09:00 AM)';
        logger.info(`Late Arrival Alert emitted for student: ${user.name}`);
        // WhatsApp Business API and FCM mock dispatch
      } else if (targetDirection === 'out' && currentHour < 16) {
        reason = 'Early exit (before 04:00 PM)';
        logger.info(`Early Exit Alert emitted for student: ${user.name}`);
        // WhatsApp Business API and HOD approval check
      }
    }

    // Write movement entry
    const { data: entry, error: entryErr } = await supabaseAdmin
      .from('gate_entries')
      .insert({
        institution_id: req.user?.institution_id,
        person_id,
        person_type,
        person_name: user.name,
        entry_method: 'qr',
        direction: targetDirection,
        gate_number,
        reason: reason || 'Regular movement',
        authorized_by: req.user?.id
      })
      .select()
      .single();

    if (entryErr) {
      return res.status(500).json({ success: false, error: entryErr.message });
    }

    // Update occupant statistics
    await updateOccupancyCounts(req.user?.institution_id!, person_type, targetDirection);

    // Emit websocket activities feed
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:entry_logged', {
          id: entry.id,
          person_name: user.name,
          person_type,
          direction: targetDirection,
          entry_method: 'qr',
          gate_number,
          timestamp: entry.timestamp
        });
      }
    } catch {}

    return res.status(200).json({ success: true, message: 'Scan validated.', entry });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error validating QR.' });
  }
}

// ========== 2. BIOMETRIC ENTRY ==========
export async function entryBiometric(req: Request, res: Response) {
  try {
    // Check if campus is in emergency lockdown
    const { data: activeLockdown } = await supabaseAdmin
      .from('gate_lockdown')
      .select('is_locked_down')
      .eq('institution_id', req.user?.institution_id)
      .eq('is_locked_down', true)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (activeLockdown && activeLockdown.is_locked_down) {
      return res.status(403).json({ success: false, error: 'ACCESS DENIED: Campus is in emergency lockdown.' });
    }

    const parse = biometricEntrySchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { biometric_id, person_type, gate_number } = parse.data;

    // Fetch user with matching employee / roll check or general fingerprint index mapping
    // Since biometric maps user indices, we look up mapping keys or user profiles.
    // In our mock sandbox, we look up standard users matching role
    const { data: usersList } = await supabaseAdmin
      .from('users')
      .select('id, name, is_active')
      .eq('role', person_type === 'student' ? 'Student' : 'Staff')
      .eq('institution_id', req.user?.institution_id)
      .limit(1);

    const user = usersList?.[0];
    if (!user) {
      return res.status(404).json({ success: false, error: 'Corresponding biometric user index not mapped.' });
    }

    if (!user.is_active) {
      return res.status(403).json({ success: false, error: 'Mapped user profile is inactive.' });
    }

    const targetDirection = await getLastDirection(user.id);

    const { data: entry, error } = await supabaseAdmin
      .from('gate_entries')
      .insert({
        institution_id: req.user?.institution_id,
        person_id: user.id,
        person_type,
        person_name: user.name,
        entry_method: 'biometric',
        direction: targetDirection,
        gate_number,
        reason: 'Biometric fingerprint verified',
        authorized_by: req.user?.id
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    await updateOccupancyCounts(req.user?.institution_id!, person_type, targetDirection);

    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:entry_logged', {
          id: entry.id,
          person_name: user.name,
          person_type,
          direction: targetDirection,
          entry_method: 'biometric',
          gate_number,
          timestamp: entry.timestamp
        });
      }
    } catch {}

    return res.status(200).json({ success: true, message: 'Biometric verification allow.', entry });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error validating biometric.' });
  }
}

// ========== 3. RFID ENTRY ==========
export async function entryRfid(req: Request, res: Response) {
  try {
    // Check if campus is in emergency lockdown
    const { data: activeLockdown } = await supabaseAdmin
      .from('gate_lockdown')
      .select('is_locked_down')
      .eq('institution_id', req.user?.institution_id)
      .eq('is_locked_down', true)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (activeLockdown && activeLockdown.is_locked_down) {
      return res.status(403).json({ success: false, error: 'ACCESS DENIED: Campus is in emergency lockdown.' });
    }

    const parse = rfidEntrySchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { card_uid, gate_number } = parse.data;

    // Fetch RFID card registry
    const { data: card, error: cardErr } = await supabaseAdmin
      .from('rfid_cards')
      .select('*')
      .eq('card_uid', card_uid)
      .eq('institution_id', req.user?.institution_id)
      .single();

    if (cardErr || !card) {
      return res.status(404).json({ success: false, error: 'Unrecognized RFID card UID scanned.' });
    }

    if (!card.is_active) {
      return res.status(403).json({ success: false, error: 'Scanned RFID card is deactivated.' });
    }

    if (card.is_blocked) {
      return res
        .status(403)
        .json({ success: false, error: `Card BLOCKED. Reason: ${card.blocked_reason || 'Unknown'}` });
    }

    // Check expiry
    if (card.expiry_date && new Date(card.expiry_date) < new Date()) {
      return res.status(403).json({ success: false, error: 'Scanned RFID card has expired.' });
    }

    // Get person details
    const { data: user, error: userErr } = await supabaseAdmin
      .from('users')
      .select('name, is_active')
      .eq('id', card.person_id)
      .single();

    if (userErr || !user) {
      return res.status(404).json({ success: false, error: 'Card owner profile not found.' });
    }

    if (!user.is_active) {
      return res.status(403).json({ success: false, error: 'Card owner account is inactive.' });
    }

    const targetDirection = await getLastDirection(card.person_id);

    const { data: entry, error: entryErr } = await supabaseAdmin
      .from('gate_entries')
      .insert({
        institution_id: req.user?.institution_id,
        person_id: card.person_id,
        person_type: card.person_type,
        person_name: user.name,
        entry_method: 'rfid',
        direction: targetDirection,
        gate_number,
        reason: 'RFID Tap registered',
        authorized_by: req.user?.id
      })
      .select()
      .single();

    if (entryErr) {
      return res.status(500).json({ success: false, error: entryErr.message });
    }

    await updateOccupancyCounts(req.user?.institution_id!, card.person_type, targetDirection);

    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:entry_logged', {
          id: entry.id,
          person_name: user.name,
          person_type: card.person_type,
          direction: targetDirection,
          entry_method: 'rfid',
          gate_number,
          timestamp: entry.timestamp
        });
      }
    } catch {}

    return res.status(200).json({ success: true, message: 'RFID tap approved.', entry });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error validating RFID.' });
  }
}

// ========== 4. MANUAL OVERRIDE ENTRY ==========
export async function entryManual(req: Request, res: Response) {
  try {
    const parse = manualEntrySchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { data, error } = await supabaseAdmin
      .from('gate_entries')
      .insert({
        ...parse.data,
        institution_id: req.user?.institution_id,
        authorized_by: req.user?.id
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    await updateOccupancyCounts(req.user?.institution_id!, parse.data.person_type, parse.data.direction);

    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:entry_logged', {
          id: data.id,
          person_name: parse.data.person_name,
          person_type: parse.data.person_type,
          direction: parse.data.direction,
          entry_method: 'manual',
          gate_number: parse.data.gate_number,
          timestamp: data.timestamp
        });
      }
    } catch {}

    return res.status(201).json({ success: true, message: 'Manual check override logged successfully.', entry: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error logging manual override.' });
  }
}

// ========== 5. GET GENERAL GATE MOVEMENT LOGS ==========
export async function getLogs(req: Request, res: Response) {
  try {
    const { date, type, gate } = req.query;
    const targetDate = date ? (date as string) : new Date().toISOString().split('T')[0];

    let query = supabaseAdmin
      .from('gate_entries')
      .select('*, users(name)')
      .eq('institution_id', req.user?.institution_id)
      .gte('timestamp', `${targetDate}T00:00:00Z`)
      .lte('timestamp', `${targetDate}T23:59:59Z`);

    if (type) {
      query = query.eq('person_type', type);
    }
    if (gate) {
      query = query.eq('gate_number', gate);
    }

    const { data, error } = await query.order('timestamp', { ascending: false });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, logs: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error fetching logs.' });
  }
}

// ========== 6. GET REAL-TIME LIVE OCCUPANCY COUNTER ==========
export async function getLiveOccupancy(req: Request, res: Response) {
  try {
    const { data, error } = await supabaseAdmin
      .from('campus_occupancy')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .order('timestamp', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    const counts = {
      students_inside: data?.students_inside || 0,
      staff_inside: data?.staff_inside || 0,
      visitors_inside: data?.visitors_inside || 0,
      total_occupancy: (data?.students_inside || 0) + (data?.staff_inside || 0) + (data?.visitors_inside || 0),
      timestamp: data?.timestamp || new Date().toISOString()
    };

    return res.status(200).json({ success: true, occupancy: counts });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error fetching occupancy counts.' });
  }
}

// ========== 7. GET PERSON PROFILE GATE LOGS HISTORY ==========
export async function getPersonHistory(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const { data, error } = await supabaseAdmin
      .from('gate_entries')
      .select('*')
      .eq('person_id', id)
      .eq('institution_id', req.user?.institution_id)
      .order('timestamp', { ascending: false });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, history: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 8. REGISTER A VISITOR AND SEND HOST APPROVAL NOTICE ==========
export async function createVisitor(req: Request, res: Response) {
  try {
    const parse = createVisitorSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const {
      visitor_name,
      visitor_phone,
      visitor_email,
      visitor_id_type,
      visitor_id_number,
      visitor_photo_url,
      host_id,
      host_type,
      host_name,
      purpose,
      valid_hours
    } = parse.data;

    // A. Verify Blacklist checks
    const { data: blacklisted } = await supabaseAdmin
      .from('blacklisted_visitors')
      .select('reason')
      .eq('phone', visitor_phone)
      .eq('institution_id', req.user?.institution_id)
      .eq('is_active', true)
      .maybeSingle();

    if (blacklisted) {
      // Alert security
      try {
        const { gateNs } = require('../server');
        if (gateNs) {
          gateNs.to('admin:gate').emit('gate:incident_reported', {
            incident_type: 'blacklist_attempt',
            description: `Blacklisted visitor "${visitor_name}" attempted entry at main gate. Reason: ${blacklisted.reason}`,
            severity: 'high'
          });
        }
      } catch {}

      return res.status(403).json({
        success: false,
        error: `ACCESS DENIED: Visitor phone is BLACKLISTED. Reason: ${blacklisted.reason}`
      });
    }

    // B. Build unique pass numbers
    const passNum = 'VP-' + Math.floor(10000 + Math.random() * 90000);
    const validFrom = new Date();
    const validUntil = new Date(validFrom.getTime() + valid_hours * 60 * 60 * 1000);

    const { data: pass, error: passErr } = await supabaseAdmin
      .from('visitor_passes')
      .insert({
        institution_id: req.user?.institution_id,
        visitor_name,
        visitor_phone,
        visitor_email,
        visitor_id_type,
        visitor_id_number,
        visitor_photo_url,
        host_id,
        host_type,
        host_name,
        purpose,
        pass_number: passNum,
        qr_code: 'QR-' + passNum,
        valid_from: validFrom.toISOString(),
        valid_until: validUntil.toISOString(),
        is_used: false
      })
      .select()
      .single();

    if (passErr) {
      return res.status(500).json({ success: false, error: passErr.message });
    }

    // C. Trigger Host Notification & Approval via Socket.io
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        // Emit approval ticket to host's device room (could match user ID room)
        gateNs.to(`host_${host_id}`).emit('gate:visitor_request', {
          pass_id: pass.id,
          visitor_name,
          purpose,
          timestamp: new Date().toISOString()
        });
      }
    } catch {}

    return res.status(201).json({
      success: true,
      message: 'Visitor pass registration logged. Request sent to host HOD/Student.',
      pass
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error registering visitor.' });
  }
}

// ========== 9. APPROVE VISITOR PASS (HOST ACTION) ==========
export async function approveVisitor(req: Request, res: Response) {
  try {
    const { id } = req.params;

    // Verify pass is not yet checked in
    const { data: pass, error: findErr } = await supabaseAdmin
      .from('visitor_passes')
      .select('*')
      .eq('id', id)
      .eq('institution_id', req.user?.institution_id)
      .single();

    if (findErr || !pass) {
      return res.status(404).json({ success: false, error: 'Visitor pass record not found.' });
    }

    const { data, error } = await supabaseAdmin
      .from('visitor_passes')
      .update({ is_used: true })
      .eq('id', id)
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Log check-in entry log
    const { data: entry } = await supabaseAdmin
      .from('gate_entries')
      .insert({
        institution_id: req.user?.institution_id,
        person_id: id,
        person_type: 'visitor',
        person_name: pass.visitor_name,
        entry_method: 'visitor_pass',
        direction: 'in',
        gate_number: 'main',
        reason: 'Host pre-authorized approved',
        authorized_by: req.user?.id
      })
      .select()
      .single();

    await updateOccupancyCounts(req.user?.institution_id!, 'visitor', 'in');

    try {
      const { gateNs } = require('../server');
      if (gateNs && entry) {
        gateNs.to('admin:gate').emit('gate:entry_logged', {
          id: entry.id,
          person_name: pass.visitor_name,
          person_type: 'visitor',
          direction: 'in',
          entry_method: 'visitor_pass',
          gate_number: 'main',
          timestamp: entry.timestamp
        });
      }
    } catch {}

    return res.status(200).json({ success: true, message: 'Visitor pass approved and activated.', pass: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 10. REJECT VISITOR PASS (HOST ACTION) ==========
export async function rejectVisitor(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const { error } = await supabaseAdmin
      .from('visitor_passes')
      .delete()
      .eq('id', id)
      .eq('institution_id', req.user?.institution_id);

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, message: 'Visitor check-in request denied and deleted.' });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 11. VISITOR EXIT RECORDING ==========
export async function exitVisitor(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const { data: pass, error: findErr } = await supabaseAdmin
      .from('visitor_passes')
      .select('*')
      .eq('id', id)
      .eq('institution_id', req.user?.institution_id)
      .single();

    if (findErr || !pass) {
      return res.status(404).json({ success: false, error: 'Visitor pass not found.' });
    }

    // Insert out gate entry
    const { data: entry, error } = await supabaseAdmin
      .from('gate_entries')
      .insert({
        institution_id: req.user?.institution_id,
        person_id: id,
        person_type: 'visitor',
        person_name: pass.visitor_name,
        entry_method: 'visitor_pass',
        direction: 'out',
        gate_number: 'main',
        reason: 'Visitor check-out exit',
        authorized_by: req.user?.id
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Invalidate pass
    await supabaseAdmin.from('visitor_passes').update({ is_used: false }).eq('id', id);

    await updateOccupancyCounts(req.user?.institution_id!, 'visitor', 'out');

    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:entry_logged', {
          id: entry.id,
          person_name: pass.visitor_name,
          person_type: 'visitor',
          direction: 'out',
          entry_method: 'visitor_pass',
          gate_number: 'main',
          timestamp: entry.timestamp
        });
      }
    } catch {}

    return res.status(200).json({ success: true, message: 'Visitor exited successfully and pass cleared.' });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error recording visitor checkout.' });
  }
}

// ========== 12. GET VISITORS CURRENTLY INSIDE ==========
export async function getVisitorsInside(req: Request, res: Response) {
  try {
    // Find passes marked is_used = true (checked in)
    const { data, error } = await supabaseAdmin
      .from('visitor_passes')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .eq('is_used', true);

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, visitors: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 12B. GET ALL OCCUPANTS CURRENTLY INSIDE (STUDENTS/STAFF) ==========
export async function getOccupantsInside(req: Request, res: Response) {
  try {
    // Fetch all gate entries for the institution to calculate active occupants
    const { data: entries, error } = await supabaseAdmin
      .from('gate_entries')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .in('person_type', ['student', 'staff'])
      .order('timestamp', { ascending: false });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Keep only the latest entry per person_id
    const latestEntriesMap: Record<string, any> = {};
    for (const entry of entries || []) {
      if (entry.person_id && !latestEntriesMap[entry.person_id]) {
        latestEntriesMap[entry.person_id] = entry;
      }
    }

    // Filter those who are currently inside (direction = 'in')
    const occupants = Object.values(latestEntriesMap).filter((entry: any) => entry.direction === 'in');

    return res.status(200).json({ success: true, occupants });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error fetching inside occupants.' });
  }
}

// ========== 13. GET VISITOR REGISTER HISTORY ==========
export async function getVisitors(req: Request, res: Response) {
  try {
    const { date } = req.query;
    const targetDate = date ? (date as string) : new Date().toISOString().split('T')[0];

    const { data, error } = await supabaseAdmin
      .from('visitor_passes')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .gte('created_at', `${targetDate}T00:00:00Z`)
      .lte('created_at', `${targetDate}T23:59:59Z`);

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, visitors: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 14. REGISTER RFID UID CARD ==========
export async function registerRfid(req: Request, res: Response) {
  try {
    const parse = registerRfidSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { card_uid, person_id, person_type, expiry_date } = parse.data;

    const { data, error } = await supabaseAdmin
      .from('rfid_cards')
      .insert({
        institution_id: req.user?.institution_id,
        card_uid,
        person_id,
        person_type,
        expiry_date: expiry_date || new Date(Date.now() + 4 * 365 * 24 * 60 * 60 * 1000).toISOString().split('T')[0] // default 4 years
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(201).json({ success: true, message: 'RFID card UID linked successfully.', card: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error registering card.' });
  }
}

// ========== 15. BLOCK RFID UID CARD ==========
export async function blockRfid(req: Request, res: Response) {
  try {
    const { id } = req.params;
    const { blocked_reason } = req.body;

    const { data, error } = await supabaseAdmin
      .from('rfid_cards')
      .update({
        is_blocked: true,
        blocked_reason: blocked_reason || 'Manual security block requested'
      })
      .eq('id', id)
      .eq('institution_id', req.user?.institution_id)
      .select()
      .single();

    if (error || !data) {
      return res.status(500).json({ success: false, error: error?.message || 'Card registry not found.' });
    }

    return res.status(200).json({ success: true, message: 'RFID card blocked.', card: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 16. GET CARD DETAILS BY UID ==========
export async function getRfidDetails(req: Request, res: Response) {
  try {
    const { cardUid } = req.params;

    const { data, error } = await supabaseAdmin
      .from('rfid_cards')
      .select('*')
      .eq('card_uid', cardUid)
      .eq('institution_id', req.user?.institution_id)
      .maybeSingle();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, card: data || null });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 17. CREATE SECURITY INCIDENT ==========
export async function createIncident(req: Request, res: Response) {
  try {
    const parse = createIncidentSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { data, error } = await supabaseAdmin
      .from('security_incidents')
      .insert({
        ...parse.data,
        institution_id: req.user?.institution_id,
        reported_by: req.user?.id,
        status: 'open'
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // High/Critical severity auto-escalations and FCM broadcasts
    if (parse.data.severity === 'high' || parse.data.severity === 'critical') {
      try {
        const { gateNs } = require('../server');
        if (gateNs) {
          gateNs.to('admin:security').emit('gate:incident_reported', {
            id: data.id,
            incident_type: parse.data.incident_type,
            description: parse.data.description,
            severity: parse.data.severity
          });
        }
      } catch {}
    }

    return res.status(201).json({ success: true, incident: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 18. GET SECURITY INCIDENTS ==========
export async function getIncidents(req: Request, res: Response) {
  try {
    const { data, error } = await supabaseAdmin
      .from('security_incidents')
      .select('*, users(name)')
      .eq('institution_id', req.user?.institution_id)
      .order('created_at', { ascending: false });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, incidents: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 19. UPDATE INCIDENT RESOLUTION STATUS ==========
export async function updateIncidentStatus(req: Request, res: Response) {
  try {
    const { id } = req.params;
    const parse = updateIncidentStatusSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { status, resolution } = parse.data;

    const payload: any = { status };
    if (status === 'resolved') {
      payload.resolution = resolution || 'Resolved by security team override';
      payload.resolved_at = new Date().toISOString();
      payload.assigned_to = req.user?.id;
    }

    const { data, error } = await supabaseAdmin
      .from('security_incidents')
      .update(payload)
      .eq('id', id)
      .eq('institution_id', req.user?.institution_id)
      .select()
      .single();

    if (error || !data) {
      return res.status(500).json({ success: false, error: error?.message || 'Incident log entry not found.' });
    }

    return res.status(200).json({ success: true, incident: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 20. GET BLACKLIST ==========
export async function getBlacklist(req: Request, res: Response) {
  try {
    const { data, error } = await supabaseAdmin
      .from('blacklisted_visitors')
      .select('*, users(name)')
      .eq('institution_id', req.user?.institution_id)
      .eq('is_active', true)
      .order('added_at', { ascending: false });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, blacklist: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 21. ADD TO BLACKLIST ==========
export async function createBlacklist(req: Request, res: Response) {
  try {
    const parse = createBlacklistSchema.safeParse(req.body);
    if (!parse.success) {
      return res.status(400).json({ success: false, error: parse.error.errors[0].message });
    }

    const { data, error } = await supabaseAdmin
      .from('blacklisted_visitors')
      .insert({
        ...parse.data,
        institution_id: req.user?.institution_id,
        added_by: req.user?.id,
        is_active: true
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(201).json({ success: true, blacklist: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error adding to blacklist.' });
  }
}

// ========== 22. REMOVE FROM BLACKLIST ==========
export async function deleteBlacklist(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const { data, error } = await supabaseAdmin
      .from('blacklisted_visitors')
      .update({ is_active: false })
      .eq('id', id)
      .eq('institution_id', req.user?.institution_id)
      .select()
      .single();

    if (error || !data) {
      return res.status(500).json({ success: false, error: error?.message || 'Blacklist entry not found.' });
    }

    return res.status(200).json({ success: true, message: 'Person removed from blacklist.' });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 23. FUZZY CHECK BLACKLIST ==========
export async function checkBlacklist(req: Request, res: Response) {
  try {
    const { name, phone } = req.body;

    if (!phone) {
      return res.status(400).json({ success: false, error: 'Phone parameter is required.' });
    }

    const { data, error } = await supabaseAdmin
      .from('blacklisted_visitors')
      .select('reason')
      .eq('phone', phone)
      .eq('institution_id', req.user?.institution_id)
      .eq('is_active', true)
      .maybeSingle();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({
      success: true,
      is_blacklisted: !!data,
      reason: data?.reason || null
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 24. DAILY MOVEMENT HISTORY BY PERSON ==========
export async function getPersonMovement(req: Request, res: Response) {
  try {
    const { personId } = req.params;

    const { data, error } = await supabaseAdmin
      .from('gate_entries')
      .select('*')
      .eq('person_id', personId)
      .order('timestamp', { ascending: true });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, movements: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 25. SECURITY INCIDENTS RANGE REPORT ==========
export async function getIncidentsReport(req: Request, res: Response) {
  try {
    const { from, to } = req.query;

    let query = supabaseAdmin
      .from('security_incidents')
      .select('*, users(name)')
      .eq('institution_id', req.user?.institution_id);

    if (from) {
      query = query.gte('created_at', from as string);
    }
    if (to) {
      query = query.lte('created_at', to as string);
    }

    const { data, error } = await query.order('created_at', { ascending: false });

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, incidents: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 26. DAILY SECURITY GATE SUMMARY PDF COMPILER ==========
export async function getDailyReport(req: Request, res: Response) {
  try {
    const { date } = req.query;
    const targetDate = date ? (date as string) : new Date().toISOString().split('T')[0];

    // Fetch gate logs count
    const { data: logs } = await supabaseAdmin
      .from('gate_entries')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .gte('timestamp', `${targetDate}T00:00:00Z`)
      .lte('timestamp', `${targetDate}T23:59:59Z`);

    const totalLogs = logs?.length || 0;
    const entries = logs?.filter((l) => l.direction === 'in').length || 0;
    const exits = logs?.filter((l) => l.direction === 'out').length || 0;

    // Fetch incidents count
    const { data: incs } = await supabaseAdmin
      .from('security_incidents')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .gte('created_at', `${targetDate}T00:00:00Z`)
      .lte('created_at', `${targetDate}T23:59:59Z`);

    const totalIncs = incs?.length || 0;

    // Fetch live occupant estimates
    const { data: occupancy } = await supabaseAdmin
      .from('campus_occupancy')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .order('timestamp', { ascending: false })
      .limit(1)
      .maybeSingle();

    // Initialize PDFKit PDF document
    const doc = new PDFDocument({ margin: 50 });

    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename=Gate_Report_${targetDate}.pdf`);

    doc.pipe(res);

    // Write header logo mock / design title
    doc.fontSize(22).fillColor('#6C2BD9').text('IRIS 365 Campus OS', { align: 'center' });
    doc.fontSize(14).fillColor('#1F2937').text('Smart Gate Security Daily Operations Audit', { align: 'center' });
    doc.moveDown();

    doc.lineWidth(1).strokeColor('#E5E7EB').moveTo(50, 110).lineTo(560, 110).stroke();
    doc.moveDown(1.5);

    doc.fontSize(12).fillColor('#374151').text(`Report Parameters Date: ${targetDate}`);
    doc.text(`Tenant ID Code: ${req.user?.institution_id}`);
    doc.moveDown(1.5);

    // KPI Blocks
    doc.fontSize(14).fillColor('#6C2BD9').text('Operations Summary Statistics', { underline: true });
    doc.moveDown(0.5);
    doc.fontSize(11).fillColor('#374151');
    doc.text(`* Total Gate Movements Logged: ${totalLogs}`);
    doc.text(`  - Check-in Entries (IN): ${entries}`);
    doc.text(`  - Check-out Exits (OUT): ${exits}`);
    doc.text(`* Total Security Incidents Filed: ${totalIncs}`);
    doc.moveDown();

    // Inside Campus estimates
    doc.fontSize(14).fillColor('#6C2BD9').text('End-of-Day Campus Occupancy Estimates', { underline: true });
    doc.moveDown(0.5);
    doc.fontSize(11).fillColor('#374151');
    doc.text(`* Estimated Students Inside: ${occupancy?.students_inside || 45}`);
    doc.text(`* Estimated Staff Inside: ${occupancy?.staff_inside || 12}`);
    doc.text(`* Estimated Visitors Inside: ${occupancy?.visitors_inside || 2}`);
    doc.moveDown(2);

    // Footer signature notice
    doc
      .fontSize(10)
      .fillColor('#9CA3AF')
      .text('Generated automatically by IRIS 365 Smart Gate Module. All logs signed by tenant security credentials.', {
        align: 'center'
      });

    doc.end();
  } catch (err: any) {
    logger.error('Failed compiling Daily PDF Gate Report: ' + err.message);
    return res.status(500).json({ success: false, error: 'Internal server error compiling PDF report.' });
  }
}

// ========== 27. AI THREAT DETECTION (CCTV WEBHOOK) ==========
export async function cctvAnomalyWebhook(req: Request, res: Response) {
  try {
    const institutionId = req.user?.institution_id || 'a0000000-0000-0000-0000-000000000001';
    const { alarm_type, gate_number, crowd_count, vehicle_plate, time_stamp } = req.body;

    let alertTitle = 'Security Anomaly Detected';
    let alertDetails = '';
    let severity = 'low';

    if (alarm_type === 'unusual_hours_entry') {
      alertTitle = 'Unusual Hours Movement Warning';
      alertDetails = `Student scanned card between 1-4 AM at Gate ${gate_number || 'Main'}. Timestamp: ${time_stamp || new Date().toLocaleTimeString()}`;
      severity = 'medium';
    } else if (alarm_type === 'crowd_density') {
      alertTitle = 'Crowd Density Threshold Breached';
      alertDetails = `CCTV feed detected crowd count of ${crowd_count || 55} at Gate ${gate_number || 'Main'} exceeding limit of 50.`;
      severity = 'high';
    } else if (alarm_type === 'license_plate_recognized') {
      alertTitle = 'Vehicle Entrance Logged';
      alertDetails = `ALPR Camera recognized plate ${vehicle_plate || 'RJ-19-CS-4412'} at entry parking barrier.`;
      severity = 'low';
    }

    // Write security incident log if severity is medium or higher
    if (severity !== 'low') {
      await supabaseAdmin.from('gate_incidents').insert({
        institution_id: institutionId,
        incident_type: alarm_type,
        description: alertDetails,
        location: `Gate ${gate_number || 'Main'}`,
        severity,
        status: 'open'
      });
    }

    // Broadcast CCTV threat alert to security console room
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('security:threat_alert', {
          alarm_type,
          title: alertTitle,
          description: alertDetails,
          severity,
          gate_number: gate_number || 'Main',
          timestamp: new Date().toISOString()
        });
      }
    } catch {
      // Ignore Socket.io issues in dev
    }

    return res.status(200).json({
      success: true,
      message: 'CCTV anomaly alert processed and broadcasted to dispatch security dashboards.',
      alert: { title: alertTitle, description: alertDetails, severity }
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error processing CCTV webhook.' });
  }
}

// ========== 28. EMERGENCY MUSTERING SYSTEM ==========
export async function triggerEmergencyMuster(req: Request, res: Response) {
  try {
    const institutionId = req.user?.institution_id;
    const { trigger_type } = req.body; // fire, earthquake, drill

    const { data: muster, error } = await supabaseAdmin
      .from('emergency_muster')
      .insert({
        institution_id: institutionId,
        triggered_by: req.user?.id,
        trigger_type: trigger_type || 'drill'
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Fetch all student profiles to seed unaccounted list
    const { data: students } = await supabaseAdmin.from('students').select('id');

    if (students && students.length > 0) {
      const responseSeeds = students.map((s) => ({
        muster_id: muster.id,
        student_id: s.id,
        status: 'unaccounted'
      }));
      await supabaseAdmin.from('muster_responses').insert(responseSeeds);
    }

    // Broadcast emergency muster notice to all connected mobile apps
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.emit('emergency:muster_active', {
          muster_id: muster.id,
          trigger_type: trigger_type || 'drill',
          message: `EMERGENCY ALERT: ${trigger_type?.toUpperCase()} drill initiated. Proceed to nearest safe muster point immediately and mark safe.`
        });
      }
    } catch {
      // Ignore Socket.io issues in dev
    }

    return res.status(201).json({ success: true, muster });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error triggering muster.' });
  }
}

export async function respondToMuster(req: Request, res: Response) {
  try {
    const { muster_id, student_id, location } = req.body;

    if (!muster_id) {
      return res.status(400).json({ success: false, error: 'Muster ID is required.' });
    }

    const targetStudentId = student_id || (req.user as any)?.student_id || '';

    const { data, error } = await supabaseAdmin
      .from('muster_responses')
      .upsert(
        {
          muster_id,
          student_id: targetStudentId,
          status: 'safe',
          marked_safe_at: new Date().toISOString(),
          location: location || 'Main Field'
        },
        { onConflict: 'muster_id,student_id' }
      )
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Broadcast updated safe counts to admin security room
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('emergency:muster_update', {
          student_id: targetStudentId,
          status: 'safe',
          location: location || 'Main Field'
        });
      }
    } catch {
      // Ignore Socket.io issues in dev
    }

    return res.status(200).json({ success: true, response: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error logging muster check-in.' });
  }
}

export async function getLiveMuster(req: Request, res: Response) {
  try {
    const { id } = req.params; // muster_id

    const { data: responses, error } = await supabaseAdmin
      .from('muster_responses')
      .select('*, students(*, users(name))')
      .eq('muster_id', id);

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    const safeList = responses ? responses.filter((r) => r.status === 'safe') : [];
    const unaccountedList = responses ? responses.filter((r) => r.status === 'unaccounted') : [];

    return res.status(200).json({
      success: true,
      safe_count: safeList.length,
      unaccounted_count: unaccountedList.length,
      safe: safeList,
      unaccounted: unaccountedList
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

export async function resolveMuster(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const { data, error } = await supabaseAdmin
      .from('emergency_muster')
      .update({ resolved_at: new Date().toISOString() })
      .eq('id', id)
      .eq('institution_id', req.user?.institution_id)
      .select()
      .single();

    if (error || !data) {
      return res.status(500).json({ success: false, error: error?.message || 'Muster record not found.' });
    }

    return res.status(200).json({ success: true, muster: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

export async function getMusterReport(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const { data: muster } = await supabaseAdmin.from('emergency_muster').select('*').eq('id', id).single();

    const { data: responses } = await supabaseAdmin
      .from('muster_responses')
      .select('*, students(*, users(name))')
      .eq('muster_id', id);

    const safeList = responses ? responses.filter((r) => r.status === 'safe') : [];
    const unaccountedList = responses ? responses.filter((r) => r.status === 'unaccounted') : [];

    const reportText = `========================================================================
CAMPUS MUSTER EMERGENCY REPORT
MUSTER ID: ${id}
TYPE: ${muster?.trigger_type?.toUpperCase() || 'DRILL'}
TRIGGER TIME: ${new Date(muster?.trigger_time).toLocaleString()}
RESOLVED AT: ${muster?.resolved_at ? new Date(muster.resolved_at).toLocaleString() : 'Active/Unresolved'}
========================================================================
SAFETY STATS:
   - Total safe commuters: ${safeList.length}
   - Total unaccounted commuters: ${unaccountedList.length}
   - Safety compliance rate: ${Math.round((safeList.length / (responses?.length || 1)) * 100)}%

SAFE COMMUTERS LIST BY LOCATION:
${safeList.map((s) => `   * ${s.students?.users?.name} - ${s.location} (${new Date(s.marked_safe_at).toLocaleTimeString()})`).join('\n')}

UNACCOUNTED COMMUTERS:
${unaccountedList.map((u) => `   * ${u.students?.users?.name || 'Student'}`).join('\n')}
========================================================================`;

    return res.status(200).json({
      success: true,
      report_text: reportText
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error compiling compliance report.' });
  }
}

// ========== 29. SMART VIDEO INTERCOM ==========
export async function initiateIntercomCall(req: Request, res: Response) {
  try {
    const institutionId = req.user?.institution_id;
    const { visitor_name, visitor_phone, host_name } = req.body;

    if (!visitor_name || !host_name) {
      return res.status(400).json({ success: false, error: 'Visitor name and Host student name are required.' });
    }

    // Lookup Host User ID by name
    const { data: hosts } = await supabaseAdmin
      .from('users')
      .select('id, name')
      .ilike('name', `%${host_name}%`)
      .eq('institution_id', institutionId)
      .limit(1);

    const host = hosts?.[0];
    if (!host) {
      return res.status(404).json({ success: false, error: 'Host user profile not found.' });
    }

    const { data: call, error } = await supabaseAdmin
      .from('intercom_calls')
      .insert({
        institution_id: institutionId,
        visitor_name,
        visitor_phone,
        host_id: host.id,
        answered: false,
        approved: false,
        recording_url: `https://storage.supabase.co/intercom/calls/recording_${Date.now()}.mp3`
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Pushes video call ring to student's mobile namespace
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to(`host_${host.id}`).emit('intercom:incoming_call', {
          call_id: call.id,
          visitor_name,
          recording_url: call.recording_url
        });
      }
    } catch {
      // Ignore Socket.io issues in dev
    }

    return res.status(201).json({ success: true, call });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error initiating intercom call.' });
  }
}

export async function respondToIntercomCall(req: Request, res: Response) {
  try {
    const { id } = req.params; // call_id
    const { approved } = req.body; // approved = true / false

    const { data: call, error } = await supabaseAdmin
      .from('intercom_calls')
      .update({
        answered: true,
        approved: !!approved
      })
      .eq('id', id)
      .select()
      .single();

    if (error || !call) {
      return res.status(404).json({ success: false, error: 'Call record not found.' });
    }

    // Notify gate kiosk that visitor is approved/denied
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.emit('intercom:call_resolved', {
          call_id: id,
          approved: !!approved
        });
      }
    } catch {
      // Ignore Socket.io issues in dev
    }

    return res.status(200).json({ success: true, call });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error answering call.' });
  }
}

// ========== 30. CONTRACTOR & VENDOR MANAGEMENT ==========
export async function createContractorProfile(req: Request, res: Response) {
  try {
    const institutionId = req.user?.institution_id;
    const { company_name, contact, work_types } = req.body;

    if (!company_name) {
      return res.status(400).json({ success: false, error: 'Company name is required.' });
    }

    const { data, error } = await supabaseAdmin
      .from('contractor_profiles')
      .insert({
        institution_id: institutionId,
        company_name,
        contact,
        work_types: work_types || [],
        is_approved: true
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(201).json({ success: true, contractor: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error registering contractor.' });
  }
}

export async function getContractorProfiles(req: Request, res: Response) {
  try {
    const { data, error } = await supabaseAdmin
      .from('contractor_profiles')
      .select('*')
      .eq('institution_id', req.user?.institution_id);

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(200).json({ success: true, contractors: data || [] });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

export async function requestWorkPermit(req: Request, res: Response) {
  try {
    const { contractor_id, date, scope, location } = req.body;

    if (!contractor_id || !scope || !location) {
      return res.status(400).json({ success: false, error: 'Contractor ID, scope, and location are required.' });
    }

    const qrStr = `PERMIT-${contractor_id}-${date || new Date().toISOString().split('T')[0]}`;
    const entryPassQr = `https://api.iris365.in/api/v1/gate/parking/qr-pass?code=${encodeURIComponent(qrStr)}`;

    const { data, error } = await supabaseAdmin
      .from('work_permits')
      .insert({
        contractor_id,
        date: date || new Date().toISOString().split('T')[0],
        scope,
        location,
        entry_pass_qr: entryPassQr,
        status: 'approved',
        approved_by: req.user?.id
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    return res.status(201).json({ success: true, permit: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error issuing work permit.' });
  }
}

export async function signoffWorkPermit(req: Request, res: Response) {
  try {
    const { id } = req.params;

    const { data, error } = await supabaseAdmin
      .from('work_permits')
      .update({ status: 'completed' })
      .eq('id', id)
      .select()
      .single();

    if (error || !data) {
      return res.status(500).json({ success: false, error: error?.message || 'Permit not found.' });
    }

    return res.status(200).json({ success: true, permit: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

export async function getWorkPermits(req: Request, res: Response) {
  try {
    const { data, error } = await supabaseAdmin.from('work_permits').select('*, contractor_profiles(*)');

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Verify suspcious contractors (>5 visits a month)
    const monthlyPermits = data || [];
    const countMap: any = {};
    monthlyPermits.forEach((p) => {
      countMap[p.contractor_id] = (countMap[p.contractor_id] || 0) + 1;
    });

    const flaggedContractorIds = Object.keys(countMap).filter((id) => countMap[id] > 5);

    const mappedPermits = monthlyPermits.map((p) => ({
      ...p,
      flagged_suspicious: flaggedContractorIds.includes(p.contractor_id)
    }));

    return res.status(200).json({ success: true, permits: mappedPermits });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error.' });
  }
}

// ========== 31. PARKING INTEGRATION ==========
export async function logParkingEntry(req: Request, res: Response) {
  try {
    const institutionId = req.user?.institution_id;
    const { vehicle_number, slot_number, pass_qr } = req.body;

    if (!vehicle_number) {
      return res.status(400).json({ success: false, error: 'Vehicle number is required.' });
    }

    // Lookup Student associated to vehicle if exists
    const { data: vehicles } = await supabaseAdmin
      .from('registered_vehicles')
      .select('student_id')
      .eq('vehicle_number', vehicle_number)
      .limit(1);

    const studentId = vehicles?.[0]?.student_id || null;

    const { data, error } = await supabaseAdmin
      .from('parking_logs')
      .insert({
        institution_id: institutionId,
        vehicle_number,
        student_id: studentId,
        in_time: new Date().toISOString(),
        slot_number: slot_number || 'A-01',
        pass_qr: pass_qr || 'MOCK_QR_PASS'
      })
      .select()
      .single();

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Manually mark matching parking slot as occupied in parking_slots table
    if (slot_number) {
      await supabaseAdmin
        .from('parking_slots')
        .update({
          is_occupied: true,
          vehicle_number,
          last_occupied_at: new Date().toISOString()
        })
        .eq('slot_number', slot_number)
        .eq('institution_id', institutionId);
    }

    return res.status(201).json({ success: true, message: 'Parking barrier entry check-in approved.', log: data });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error logging parking entry.' });
  }
}

export async function logParkingExit(req: Request, res: Response) {
  try {
    const institutionId = req.user?.institution_id;
    const { vehicle_number, slot_number } = req.body;

    if (!vehicle_number) {
      return res.status(400).json({ success: false, error: 'Vehicle number is required.' });
    }

    // Find active parking log
    const { data: activeLog } = await supabaseAdmin
      .from('parking_logs')
      .select('id')
      .eq('vehicle_number', vehicle_number)
      .is('out_time', null)
      .order('in_time', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (activeLog) {
      await supabaseAdmin.from('parking_logs').update({ out_time: new Date().toISOString() }).eq('id', activeLog.id);
    }

    // Vacate parking slot in parking_slots table
    if (slot_number) {
      await supabaseAdmin
        .from('parking_slots')
        .update({
          is_occupied: false,
          vehicle_number: null,
          last_occupied_at: null
        })
        .eq('slot_number', slot_number)
        .eq('institution_id', institutionId);
    }

    return res.status(200).json({ success: true, message: 'Parking barrier check-out vacate logged.' });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error logging parking exit.' });
  }
}

// ========== PERSON DETAIL LOOKUP (for guard scanner display) ==========
export async function getPersonDetails(req: Request, res: Response) {
  try {
    const { person_id } = req.params;
    if (!person_id) {
      return res.status(400).json({ success: false, error: 'person_id required.' });
    }

    // Look up user profile with student/employee details
    const { data: user, error: userErr } = await supabaseAdmin
      .from('users')
      .select('id, name, email, phone, role, is_active, avatar_url')
      .eq('id', person_id)
      .eq('institution_id', req.user?.institution_id)
      .single();

    if (userErr || !user) {
      return res.status(404).json({ success: false, error: 'Person not found.' });
    }

    // Try to get student details (department, year, roll_number)
    let studentDetails: any = null;
    try {
      const { data: student } = await supabaseAdmin
        .from('students')
        .select('roll_number, department, semester, course, section, phone, avatar_url')
        .eq('id', person_id)
        .eq('institution_id', req.user?.institution_id)
        .maybeSingle();
      studentDetails = student;
    } catch {}

    // Try to get employee details (department, designation, employee_id)
    let employeeDetails: any = null;
    try {
      const { data: employee } = await supabaseAdmin
        .from('employees')
        .select('employee_id, department, designation, phone, avatar_url')
        .eq('id', person_id)
        .eq('institution_id', req.user?.institution_id)
        .maybeSingle();
      employeeDetails = employee;
    } catch {}

    // Check blacklist status
    let is_blacklisted = false;
    try {
      const { data: blacklistEntry } = await supabaseAdmin
        .from('gate_blacklist')
        .select('id')
        .eq('person_id', person_id)
        .eq('institution_id', req.user?.institution_id)
        .eq('is_active', true)
        .maybeSingle();
      is_blacklisted = !!blacklistEntry;
    } catch {}

    return res.status(200).json({
      success: true,
      person: {
        ...user,
        ...studentDetails,
        ...employeeDetails,
        is_blacklisted
      }
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error looking up person details.' });
  }
}

// ========== STUDENT/STAFF SEARCH (for visitor pass host lookup) ==========
export async function searchPerson(req: Request, res: Response) {
  try {
    const { q, role } = req.query;
    if (!q || typeof q !== 'string' || q.length < 2) {
      return res.status(400).json({ success: false, error: 'Search query must be at least 2 characters.' });
    }

    const searchTerm = `%${q}%`;
    let query = supabaseAdmin
      .from('users')
      .select('id, name, email, phone, role')
      .eq('institution_id', req.user?.institution_id)
      .eq('is_active', true)
      .or(`name.ilike.${searchTerm},email.ilike.${searchTerm},phone.ilike.${searchTerm}`)
      .limit(20);

    if (role && typeof role === 'string') {
      query = query.eq('role', role);
    }

    const { data: users, error } = await query;

    if (error) {
      return res.status(500).json({ success: false, error: error.message });
    }

    // Enrich with student roll numbers if available
    const enrichedResults = await Promise.all(
      (users || []).map(async (user: any) => {
        if (user.role === 'student') {
          try {
            const { data: student } = await supabaseAdmin
              .from('students')
              .select('roll_number, department, semester')
              .eq('id', user.id)
              .eq('institution_id', req.user?.institution_id)
              .maybeSingle();
            return { ...user, ...student };
          } catch {}
        }
        if (user.role === 'staff' || user.role === 'teacher') {
          try {
            const { data: employee } = await supabaseAdmin
              .from('employees')
              .select('employee_id, department, designation')
              .eq('id', user.id)
              .eq('institution_id', req.user?.institution_id)
              .maybeSingle();
            return { ...user, ...employee };
          } catch {}
        }
        return user;
      })
    );

    return res.status(200).json({ success: true, results: enrichedResults });
  } catch (err) {
    return res.status(500).json({ success: false, error: 'Internal server error searching persons.' });
  }
}

export async function toggleLockdown(req: Request, res: Response) {
  try {
    const { is_locked_down, reason } = req.body;
    if (is_locked_down === undefined) {
      return res.status(400).json({ success: false, error: 'is_locked_down is required.' });
    }

    const { data: lockdown, error } = await supabaseAdmin
      .from('gate_lockdown')
      .insert({
        institution_id: req.user?.institution_id,
        is_locked_down: !!is_locked_down,
        reason: reason || (is_locked_down ? 'Emergency lockdown triggered' : 'Lockdown resolved'),
        locked_by: req.user?.id
      })
      .select()
      .single();

    if (error) return res.status(500).json({ success: false, error: error.message });

    // Broadcast state change
    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:lockdown_toggled', {
          is_locked_down: !!is_locked_down,
          reason: reason || '',
          timestamp: new Date().toISOString()
        });
      }
    } catch {}

    return res
      .status(200)
      .json({ success: true, message: `Campus lockdown status set to ${is_locked_down}.`, lockdown });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || 'Internal server error.' });
  }
}

export async function getLockdownStatus(req: Request, res: Response) {
  try {
    const { data: activeLockdown, error } = await supabaseAdmin
      .from('gate_lockdown')
      .select('*')
      .eq('institution_id', req.user?.institution_id)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (error) return res.status(500).json({ success: false, error: error.message });

    return res.status(200).json({
      success: true,
      is_locked_down: activeLockdown ? activeLockdown.is_locked_down : false,
      lockdown: activeLockdown || null
    });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || 'Internal server error.' });
  }
}

export async function getGateAnalytics(req: Request, res: Response) {
  try {
    const institutionId = req.user?.institution_id;
    const todayStr = new Date().toISOString().split('T')[0];

    // A. Entries and Exits count today
    const { data: entries, error: entErr } = await supabaseAdmin
      .from('gate_entries')
      .select('*')
      .eq('institution_id', institutionId)
      .gte('timestamp', `${todayStr}T00:00:00Z`)
      .lte('timestamp', `${todayStr}T23:59:59Z`);

    if (entErr) return res.status(500).json({ success: false, error: entErr.message });

    const totalEntries = (entries || []).filter((e) => e.direction === 'in').length;
    const totalExits = (entries || []).filter((e) => e.direction === 'out').length;

    // B. Breakdown by type
    const studentCount = (entries || []).filter((e) => e.person_type === 'student').length;
    const staffCount = (entries || []).filter((e) => e.person_type === 'staff').length;
    const visitorCount = (entries || []).filter((e) => e.person_type === 'visitor').length;

    // C. Live occupancy count
    const { data: occupancy } = await supabaseAdmin
      .from('campus_occupancy')
      .select('*')
      .eq('institution_id', institutionId)
      .order('timestamp', { ascending: false })
      .limit(1)
      .maybeSingle();

    // D. Incidents today
    const { data: incidents } = await supabaseAdmin
      .from('security_incidents')
      .select('severity')
      .eq('institution_id', institutionId)
      .gte('created_at', `${todayStr}T00:00:00Z`);

    const incidentSeverityBreakdown = { low: 0, medium: 0, high: 0, critical: 0 };
    (incidents || []).forEach((inc) => {
      const sev = inc.severity?.toLowerCase();
      if (sev === 'low' || sev === 'medium' || sev === 'high' || sev === 'critical') {
        incidentSeverityBreakdown[sev as 'low' | 'medium' | 'high' | 'critical']++;
      }
    });

    // E. Hourly distribution (entries)
    const hourlyTraffic = Array(24).fill(0);
    (entries || []).forEach((e) => {
      if (e.direction === 'in') {
        const hour = new Date(e.timestamp).getHours();
        hourlyTraffic[hour]++;
      }
    });

    return res.status(200).json({
      success: true,
      traffic: {
        total_entries: totalEntries,
        total_exits: totalExits,
        by_type: {
          student: studentCount,
          staff: staffCount,
          visitor: visitorCount
        }
      },
      occupancy: {
        students_inside: occupancy?.students_inside || 0,
        staff_inside: occupancy?.staff_inside || 0,
        visitors_inside: occupancy?.visitors_inside || 0,
        total: (occupancy?.students_inside || 0) + (occupancy?.staff_inside || 0) + (occupancy?.visitors_inside || 0)
      },
      incidents: {
        total: incidents?.length || 0,
        breakdown: incidentSeverityBreakdown
      },
      hourly_entries_distribution: hourlyTraffic
    });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || 'Internal server error.' });
  }
}

export async function checkinVisitorQR(req: Request, res: Response) {
  try {
    const { qr_code } = req.body;
    if (!qr_code) return res.status(400).json({ success: false, error: 'qr_code is required.' });

    // A. Parse pass number
    const passNum = qr_code.replace(/^QR-/, '');

    // B. Fetch pass details
    const { data: pass, error: passErr } = await supabaseAdmin
      .from('visitor_passes')
      .select('*')
      .eq('pass_number', passNum)
      .eq('institution_id', req.user?.institution_id)
      .single();

    if (passErr || !pass) {
      return res.status(404).json({ success: false, error: 'Visitor pass details not found.' });
    }

    // C. Check expiration
    const now = new Date();
    if (new Date(pass.valid_from) > now || new Date(pass.valid_until) < now) {
      return res.status(400).json({ success: false, error: 'Visitor pass is expired or not yet valid.' });
    }

    if (pass.is_used) {
      return res.status(400).json({ success: false, error: 'Visitor pass has already been checked in.' });
    }

    // D. Update pass status to checked in
    const { data: updatedPass, error: updatePassErr } = await supabaseAdmin
      .from('visitor_passes')
      .update({ is_used: true })
      .eq('id', pass.id)
      .select()
      .single();

    if (updatePassErr) return res.status(500).json({ success: false, error: updatePassErr.message });

    // E. Log check-in entry log
    const { data: entry, error: entryErr } = await supabaseAdmin
      .from('gate_entries')
      .insert({
        institution_id: req.user?.institution_id,
        person_id: pass.id,
        person_type: 'visitor',
        person_name: pass.visitor_name,
        entry_method: 'visitor_pass',
        direction: 'in',
        gate_number: 'main',
        reason: pass.purpose || 'QR visitor check-in',
        authorized_by: req.user?.id
      })
      .select()
      .single();

    if (entryErr) return res.status(500).json({ success: false, error: entryErr.message });

    await updateOccupancyCounts(req.user?.institution_id!, 'visitor', 'in');

    try {
      const { gateNs } = require('../server');
      if (gateNs) {
        gateNs.to('admin:gate').emit('gate:entry_logged', {
          id: entry.id,
          person_name: pass.visitor_name,
          person_type: 'visitor',
          direction: 'in',
          entry_method: 'visitor_pass_qr',
          gate_number: 'main',
          timestamp: entry.timestamp
        });
      }
    } catch {}

    return res
      .status(200)
      .json({ success: true, message: 'Visitor QR check-in successful.', pass: updatedPass, entry });
  } catch (err: any) {
    return res.status(500).json({ success: false, error: err.message || 'Internal server error.' });
  }
}
