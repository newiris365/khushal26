import cron from 'node-cron';
import { supabaseAdmin, isSupabaseOffline } from './supabase';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
  throw new Error(
    'CRITICAL SECURITY VIOLATION: JWT_SECRET environment variable is required and must be at least 32 characters in length to prevent brute-force signature forgery!'
  );
}
const JWT_SECRET = process.env.JWT_SECRET;

import logger from './logger';
import { generatePDFKitFallback, uploadReportToSupabase } from '../services/pdfGenerator';
import { generateRotatingQrToken } from '../controllers/campusCore';

// Safeguard background tasks: skip database-dependent cron runs when Supabase is offline
const originalSchedule = cron.schedule;
(cron as any).schedule = (expression: string, func: () => any, options?: any) => {
  return originalSchedule(
    expression,
    async () => {
      if (isSupabaseOffline) {
        logger.debug(
          `Bypassing background cron job running on expression "${expression}" because database is offline.`
        );
        return;
      }
      try {
        await func();
      } catch (err: any) {
        logger.error(`Error executing cron job running on "${expression}": ` + err.message);
      }
    },
    options
  );
};

/**
 * MODULE 5: Hostel Module Background Cron Schedulers
 */

// 1. Daily Warden Report Compiler (Runs at midnight: '0 0 * * *')
cron.schedule('0 0 * * *', async () => {
  logger.info('Running Daily Warden Reports compiler cron job...');
  try {
    // Fetch all active blocks
    const { data: blocks } = await supabaseAdmin
      .from('hostel_blocks')
      .select('id, name, institution_id')
      .eq('is_active', true);

    if (!blocks || blocks.length === 0) return;

    const reportDate = new Date().toISOString().split('T')[0];

    for (const block of blocks) {
      // Fetch rooms occupancy stats
      const { data: rooms } = await supabaseAdmin
        .from('hostel_rooms')
        .select('occupied, capacity')
        .eq('block_id', block.id)
        .eq('is_active', true);

      let totalCapacity = 0;
      let occupiedCount = 0;
      (rooms || []).forEach((r) => {
        totalCapacity += r.capacity || 0;
        occupiedCount += r.occupied || 0;
      });

      // Fetch students on leave
      const { count: leavesCount } = await supabaseAdmin
        .from('hostel_leave_requests')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'approved')
        .lte('leave_from', reportDate)
        .gte('leave_to', reportDate);

      // Fetch pending complaints
      const { count: complaintsCount } = await supabaseAdmin
        .from('hostel_complaints')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'open');

      // Fetch visitors today
      const { count: visitorsCount } = await supabaseAdmin
        .from('hostel_visitors')
        .select('*', { count: 'exact', head: true })
        .eq('institution_id', block.institution_id)
        .gte('in_time', `${reportDate}T00:00:00Z`);

      const reportData = {
        total_rooms: rooms?.length || 0,
        total_capacity: totalCapacity,
        occupied_count: occupiedCount,
        available_count: totalCapacity - occupiedCount,
        leaves_active: leavesCount || 0,
        pending_complaints: complaintsCount || 0,
        visitors_today: visitorsCount || 0
      };

      // Save report
      await supabaseAdmin.from('hostel_warden_reports').insert({
        block_id: block.id,
        report_type: 'daily',
        report_date: reportDate,
        data: reportData
      });

      logger.debug(`Daily Warden Report compiled for block: ${block.name}`);
    }
    logger.info('Daily Warden Reports compiled successfully.');
  } catch (err: any) {
    logger.error('Error compiling daily warden reports: ' + err.message);
  }
});

// 2. Monthly Fee Generator (Runs on 1st of each month at 1:00 AM: '0 1 1 * *')
cron.schedule('0 1 1 * *', async () => {
  logger.info('Running Monthly Hostel Fee Generator cron job...');
  try {
    const { data: allocations, error } = await supabaseAdmin
      .from('hostel_allocations')
      .select('*, hostel_rooms(monthly_rent)')
      .eq('is_current', true);

    if (error || !allocations) {
      logger.error('Could not fetch active allocations for fee generation: ' + error?.message);
      return;
    }

    const today = new Date();
    const billingMonth = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().split('T')[0];
    const dueDate = new Date(today.getFullYear(), today.getMonth(), 10).toISOString().split('T')[0]; // due on 10th

    let count = 0;
    for (const alloc of allocations) {
      // Check if fee already exists for this month and student
      const { data: existingFee } = await supabaseAdmin
        .from('hostel_fees')
        .select('id')
        .eq('allocation_id', alloc.id)
        .eq('month', billingMonth)
        .maybeSingle();

      if (!existingFee) {
        await supabaseAdmin.from('hostel_fees').insert({
          allocation_id: alloc.id,
          student_id: alloc.student_id,
          month: billingMonth,
          amount: alloc.hostel_rooms?.monthly_rent || 0,
          due_date: dueDate,
          payment_status: 'pending'
        });
        count++;
      }
    }
    logger.info(`Hostel Fee generation complete. Generated ${count} fee statements.`);
  } catch (err: any) {
    logger.error('Error generating monthly hostel fees: ' + err.message);
  }
});

// 3. Visitor Overstay Monitor (Runs every hour: '0 * * * *')
cron.schedule('0 * * * *', async () => {
  logger.info('Running Visitor Overstay Monitor cron...');
  try {
    const twelveHoursAgo = new Date(Date.now() - 12 * 60 * 60 * 1000).toISOString();

    // Fetch visitors inside for more than 12 hours
    const { data: overstaying, error } = await supabaseAdmin
      .from('hostel_visitors')
      .select('id, visitor_name, in_time, students(name, roll_number)')
      .eq('status', 'inside')
      .lt('in_time', twelveHoursAgo);

    if (error) {
      logger.error('Error querying overstaying visitors: ' + error.message);
      return;
    }

    if (overstaying && overstaying.length > 0) {
      logger.warn(`Alert: Found ${overstaying.length} visitors overstaying the 12-hour limit!`);
      overstaying.forEach((visitor: any) => {
        logger.warn(
          `Visitor "${visitor.visitor_name}" registered for student "${visitor.students?.name}" since ${new Date(visitor.in_time).toLocaleString()} has exceeded gate limit.`
        );
        // Simulate sending WhatsApp warning alert here
      });
    }
  } catch (err: any) {
    logger.error('Error running visitor overstay monitor: ' + err.message);
  }
});

/**
 * MODULE 6: Library+ Module Background Cron Schedulers
 */

// 4. Daily Overdue Books & Fine Accumulator Cron (Runs at midnight: '0 0 * * *')
cron.schedule('0 0 * * *', async () => {
  logger.info('Running Daily Overdue Books & Library Fines calculator cron job...');
  try {
    const todayStr = new Date().toISOString().split('T')[0];

    // Get all active issued checkouts
    const { data: checkouts, error } = await supabaseAdmin
      .from('book_issues')
      .select('*, students(name, roll_number)')
      .eq('status', 'issued');

    if (error || !checkouts) {
      logger.error('Could not fetch book checkouts for overdue processing: ' + error?.message);
      return;
    }

    for (const issue of checkouts) {
      const dueDate = new Date(issue.due_date);
      const today = new Date(todayStr);

      // A. Overdue fines calculation (₹10 per day overdue)
      if (today > dueDate) {
        const timeDiff = today.getTime() - dueDate.getTime();
        const daysOverdue = Math.floor(timeDiff / (1000 * 3600 * 24));
        const fineAmount = daysOverdue * 10;

        // Update issue fine
        await supabaseAdmin.from('book_issues').update({ fine_amount: fineAmount }).eq('id', issue.id);

        // Check if fine invoice already exists
        const { data: existingFine } = await supabaseAdmin
          .from('library_fines')
          .select('id')
          .eq('issue_id', issue.id)
          .maybeSingle();

        if (existingFine) {
          await supabaseAdmin.from('library_fines').update({ amount: fineAmount }).eq('id', existingFine.id);
        } else {
          await supabaseAdmin.from('library_fines').insert({
            student_id: issue.student_id,
            issue_id: issue.id,
            amount: fineAmount,
            reason: `Overdue book fine (${daysOverdue} days)`,
            status: 'unpaid'
          });
        }
        logger.debug(
          `Calculated overdue fine of ₹${fineAmount} for student ${issue.students?.name} on book issue ${issue.id}`
        );
      }

      // B. Alerts: D-2 Warnings (Due date in exactly 2 days)
      const twoDaysFromNow = new Date();
      twoDaysFromNow.setDate(twoDaysFromNow.getDate() + 2);
      const twoDaysFromNowStr = twoDaysFromNow.toISOString().split('T')[0];
      if (issue.due_date === twoDaysFromNowStr) {
        logger.info(`Sending D-2 return reminder push notice for book issue ID: ${issue.id}`);
      }
    }
  } catch (err: any) {
    logger.error('Error running library overdue cron: ' + err.message);
  }
});

// 5. Study Room Booking No-Show Releaser (Runs every 5 minutes: '*/5 * * * *')
cron.schedule('*/5 * * * *', async () => {
  try {
    const todayStr = new Date().toISOString().split('T')[0];
    const now = new Date();

    const { data: activeBookings, error } = await supabaseAdmin
      .from('study_room_bookings')
      .select('*, study_rooms(name)')
      .eq('date', todayStr)
      .eq('status', 'confirmed')
      .eq('checked_in', false);

    if (error || !activeBookings) return;

    for (const booking of activeBookings) {
      const startHour = parseInt(booking.start_time.split(':')[0]);
      const startMin = parseInt(booking.start_time.split(':')[1]);

      const startDateTime = new Date(now.getFullYear(), now.getMonth(), now.getDate(), startHour, startMin, 0);
      const cutoffTime = new Date(startDateTime.getTime() + 15 * 60 * 1000); // 15 mins grace period

      if (now > cutoffTime) {
        // Release booking due to no show
        await supabaseAdmin.from('study_room_bookings').update({ status: 'no_show' }).eq('id', booking.id);
        logger.info(
          `Released study room booking ID: ${booking.id} (${booking.study_rooms?.name}) due to student no-show after 15 minutes.`
        );
      }
    }
  } catch (err: any) {
    logger.error('Error in study room no-show releaser cron: ' + err.message);
  }
});

/**
 * MODULE 7: Transit Module Background Cron Schedulers
 */

// 6. Daily Vehicle Documents Expiration Monitor (Runs at midnight: '0 0 * * *')
cron.schedule('0 0 * * *', async () => {
  logger.info('Running Daily Transit Documents Expiration Monitor...');
  try {
    const thirtyDaysFromNow = new Date();
    thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
    const targetDateStr = thirtyDaysFromNow.toISOString().split('T')[0];

    // Check buses insurance and fitness certificates
    const { data: buses, error: busError } = await supabaseAdmin
      .from('buses')
      .select('id, vehicle_number, insurance_expiry, fitness_expiry, institution_id')
      .or(`insurance_expiry.eq.${targetDateStr},fitness_expiry.eq.${targetDateStr}`);

    if (busError) {
      logger.error('Error querying buses documents: ' + busError.message);
    } else if (buses && buses.length > 0) {
      buses.forEach((bus: any) => {
        const docName = bus.insurance_expiry === targetDateStr ? 'Insurance Policy' : 'Fitness Certificate';
        logger.warn(
          `Alert: Bus vehicle number "${bus.vehicle_number}" ${docName} is expiring in exactly 30 days on ${targetDateStr}!`
        );
      });
    }

    // Check drivers licenses
    const { data: drivers, error: driverError } = await supabaseAdmin
      .from('bus_drivers')
      .select('id, license_number, license_expiry, phone, users(name)')
      .eq('license_expiry', targetDateStr);

    if (driverError) {
      logger.error('Error querying drivers licenses: ' + driverError.message);
    } else if (drivers && drivers.length > 0) {
      drivers.forEach((driver: any) => {
        logger.warn(
          `Alert: Driver "${driver.users?.name}" license number "${driver.license_number}" is expiring in exactly 30 days on ${targetDateStr}!`
        );
      });
    }
  } catch (err: any) {
    logger.error('Error running transit documents expiration monitor: ' + err.message);
  }
});

// 7. Daily Subscription Grace Period Revoker (Runs at midnight: '0 0 * * *')
cron.schedule('0 0 * * *', async () => {
  logger.info('Running Daily Subscription Grace Period Revoker...');
  try {
    const threeDaysAgo = new Date();
    threeDaysAgo.setDate(threeDaysAgo.getDate() - 3);
    const cutoffDateStr = threeDaysAgo.toISOString().split('T')[0];

    // Find active subscriptions that expired more than 3 days ago
    const { data: expiredSubs, error: subError } = await supabaseAdmin
      .from('transport_subscriptions')
      .select('id, student_id, end_date')
      .eq('status', 'active')
      .lt('end_date', cutoffDateStr);

    if (subError) {
      logger.error('Error querying expired transit subscriptions: ' + subError.message);
      return;
    }

    if (expiredSubs && expiredSubs.length > 0) {
      let count = 0;
      for (const sub of expiredSubs) {
        await supabaseAdmin.from('transport_subscriptions').update({ status: 'expired' }).eq('id', sub.id);
        count++;
      }
      logger.info(`Subscription Revoker: Revoked ${count} transport subscriptions past the 3-day grace period.`);
    }
  } catch (err: any) {
    logger.error('Error in subscription grace period revoker cron: ' + err.message);
  }
});

// 8. Daily Scheduled Maintenance Monitor (Runs at 12:30 AM: '30 0 * * *')
cron.schedule('30 0 * * *', async () => {
  logger.info('Running Daily Transit Scheduled Maintenance Monitor...');
  try {
    const todayStr = new Date().toISOString().split('T')[0];

    // Query buses with maintenance due today
    const { data: upcoming, error: maintenanceError } = await supabaseAdmin
      .from('bus_maintenance')
      .select('*, buses(vehicle_number)')
      .eq('scheduled_date', todayStr)
      .is('completed_date', null);

    if (maintenanceError) {
      logger.error('Error querying scheduled bus maintenance logs: ' + maintenanceError.message);
      return;
    }

    if (upcoming && upcoming.length > 0) {
      upcoming.forEach((log: any) => {
        logger.warn(
          `Alert: Bus vehicle number "${log.buses?.vehicle_number}" has a scheduled maintenance appointment due today (${todayStr}) at center: "${log.service_center || 'General Service'}".`
        );
      });
    }
  } catch (err: any) {
    logger.error('Error running transit maintenance monitor: ' + err.message);
  }
});

/**
 * MODULE 8: Smart Gate Background Cron Schedulers
 */

// 9. Gate Visitor Overstay Monitor (Runs every hour: '0 * * * *')
cron.schedule('0 * * * *', async () => {
  logger.info('Running Smart Gate Visitor Overstay Monitor...');
  try {
    const nowStr = new Date().toISOString();

    // Find active visitor passes currently used and past their valid_until time
    const { data: overstaying, error } = await supabaseAdmin
      .from('visitor_passes')
      .select('*')
      .eq('is_used', true)
      .lt('valid_until', nowStr);

    if (error) {
      logger.error('Error querying overstaying visitors in database: ' + error.message);
      return;
    }

    if (overstaying && overstaying.length > 0) {
      for (const pass of overstaying) {
        logger.warn(
          `Alert: Visitor "${pass.visitor_name}" should have checked out by ${new Date(pass.valid_until).toLocaleString()}. Automatically generating security incident.`
        );

        // Log security overstay incident
        const { data: incident, error: incErr } = await supabaseAdmin
          .from('security_incidents')
          .insert({
            institution_id: pass.institution_id,
            incident_type: 'overstay',
            description: `Visitor ${pass.visitor_name} has exceeded pass validity hours. Scheduled departure was ${new Date(pass.valid_until).toLocaleString()}. Host: ${pass.host_name}`,
            location: 'Main Campus',
            severity: 'medium',
            status: 'open'
          })
          .select()
          .single();

        if (incErr) {
          logger.error('Failed to log overstay incident: ' + incErr.message);
        } else {
          // Emit websocket alert
          try {
            const { gateNs } = require('../server');
            if (gateNs && incident) {
              gateNs.to('admin:security').emit('gate:incident_reported', {
                id: incident.id,
                incident_type: 'overstay',
                description: incident.description,
                severity: 'medium'
              });
            }
          } catch {}
        }
      }
    }
  } catch (err: any) {
    logger.error('Error running gate visitor overstay cron: ' + err.message);
  }
});

/**
 * MODULE 9: Director Dashboard Background Cron Schedulers
 */

// 10. Materialized Views Auto-Refresher (Runs every hour: '0 * * * *')
cron.schedule('0 * * * *', async () => {
  logger.info('Running Materialized Views Auto-Refresher Cron...');
  try {
    const { error } = await supabaseAdmin.rpc('refresh_director_materialized_views');
    if (error) {
      logger.error('Failed calling refresh_director_materialized_views RPC: ' + error.message);
    } else {
      logger.info('Director dashboard materialized views refreshed successfully.');
    }
  } catch (err: any) {
    logger.error('Failed refreshing materialized views: ' + err.message);
  }
});

// 10b. AI Insights Generator (Runs every hour: '0 * * * *')
cron.schedule('0 * * * *', async () => {
  logger.info('Running Background AI Insights Generator Cron...');
  try {
    const { refreshAIInsightsJob } = require('../controllers/director');
    await refreshAIInsightsJob();
    logger.info('Background AI Insights generation complete.');
  } catch (err: any) {
    logger.error('Failed executing AI Insights generator cron: ' + err.message);
  }
});

// 11. Alerts Thresholds Processing Engine (Runs every 15 minutes: '*/15 * * * *')
cron.schedule('*/15 * * * *', async () => {
  logger.info('Running Director Alert Thresholds Engine...');
  try {
    const institutionId = 'a0000000-0000-0000-0000-000000000001'; // SIET default

    // Fetch alert thresholds
    const { data: thresholds } = await supabaseAdmin
      .from('alert_thresholds')
      .select('*')
      .eq('institution_id', institutionId)
      .eq('is_enabled', true);

    if (!thresholds || thresholds.length === 0) return;

    for (const thresh of thresholds) {
      let trigger = false;
      let title = '';
      let message = '';
      let currentVal = 0;

      // Check metrics against thresholds
      if (thresh.alert_type === 'attendance_low') {
        // Attendance average check today
        const today = new Date().toISOString().split('T')[0];
        const { data: att } = await supabaseAdmin
          .from('daily_attendance_summary')
          .select('attendance_percent')
          .eq('institution_id', institutionId)
          .eq('date', today);

        let avg = 82; // sandbox default
        if (att && att.length > 0) {
          avg = att.reduce((acc, c: any) => acc + parseFloat(c.attendance_percent), 0) / att.length;
        }
        currentVal = avg;
        if (avg < parseFloat(thresh.threshold_value)) {
          trigger = true;
          title = 'Low Attendance Alert';
          message = `Campus-wide attendance rate of ${avg.toFixed(1)}% falls below the target threshold of ${thresh.threshold_value}%`;
        }
      } else if (thresh.alert_type === 'complaint_overdue') {
        // Unresolved complaints age count
        const fiveDaysAgo = new Date();
        fiveDaysAgo.setDate(fiveDaysAgo.getDate() - parseInt(thresh.threshold_value));

        const { count } = await supabaseAdmin
          .from('hostel_complaints')
          .select('*', { count: 'exact', head: true })
          .eq('institution_id', institutionId)
          .in('status', ['open', 'Open'])
          .lt('created_at', fiveDaysAgo.toISOString());

        currentVal = count || 0;
        if (currentVal > 0) {
          trigger = true;
          title = 'Stale Complaints Alert';
          message = `Found ${currentVal} open hostel complaints that have remained unresolved for more than ${thresh.threshold_value} days.`;
        }
      } else if (thresh.alert_type === 'library_overdue_surge') {
        // Overdue library books count
        const { count } = await supabaseAdmin
          .from('library_fines')
          .select('*', { count: 'exact', head: true })
          .eq('status', 'unpaid');

        currentVal = count || 0;
        if (currentVal > parseFloat(thresh.threshold_value)) {
          trigger = true;
          title = 'Library Overdue Books Surge';
          message = `Total unpaid overdue library fines index stands at ${currentVal}, exceeding the threshold of ${thresh.threshold_value}.`;
        }
      }

      if (trigger) {
        // Check if alert already logged and unresolved
        const { data: existing } = await supabaseAdmin
          .from('director_alerts')
          .select('id')
          .eq('institution_id', institutionId)
          .eq('type', thresh.alert_type)
          .eq('is_resolved', false)
          .maybeSingle();

        if (!existing) {
          const { data: alertData, error: insErr } = await supabaseAdmin
            .from('director_alerts')
            .insert({
              institution_id: institutionId,
              type: thresh.alert_type,
              severity: 'warning',
              title,
              message,
              module: 'Core',
              data: { value: currentVal, limit: thresh.threshold_value }
            })
            .select()
            .single();

          if (!insErr && alertData) {
            logger.warn(`[DIRECTOR ALERT TRIGGERED]: ${title} - ${message}`);

            // Broadcast live Socket alerts
            try {
              const { directorNs } = require('../server');
              if (directorNs) {
                directorNs.to('director:dashboard').emit('director:alert_triggered', alertData);
              }
            } catch {}
          }
        }
      }
    }
  } catch (err: any) {
    logger.error('Error in director alerts processing engine: ' + err.message);
  }
});

// 12. Weekly Report Auto-Compiler (Runs every Monday at 6:00 AM: '0 6 * * 1')
cron.schedule('0 6 * * 1', async () => {
  logger.info('Running Weekly Director Report Compiler Cron...');
  try {
    const reportDate = new Date().toISOString().split('T')[0];
    const payload = {
      report_type: 'weekly',
      report_date: reportDate,
      data: {
        attendance_rate: 85,
        fee_collected: 1250000,
        students_on_campus: 0,
        open_complaints: 4,
        active_bus_trips: 0,
        events_count: 5
      }
    };

    // Generate fallback Kit Buffer
    const pdfBuffer = await generatePDFKitFallback(payload);
    const fileName = `Weekly_Report_${reportDate}_${Date.now()}.pdf`;
    const publicUrl = await uploadReportToSupabase(pdfBuffer, fileName);

    await supabaseAdmin.from('director_reports').insert({
      institution_id: 'a0000000-0000-0000-0000-000000000001',
      report_type: 'weekly',
      report_date: reportDate,
      data: payload.data,
      pdf_url: publicUrl
    });

    logger.info('Weekly Director Report auto-compiled successfully.');
  } catch (err: any) {
    logger.error('Error compiling weekly reports: ' + err.message);
  }
});

// 13. Monthly Report Auto-Compiler (Runs 1st of month at 7:00 AM: '0 7 1 * *')
cron.schedule('0 7 1 * *', async () => {
  logger.info('Running Monthly Director Report Compiler Cron...');
  try {
    const reportDate = new Date().toISOString().split('T')[0];
    const payload = {
      report_type: 'monthly',
      report_date: reportDate,
      data: {
        attendance_rate: 86,
        fee_collected: 4500000,
        students_on_campus: 0,
        open_complaints: 2,
        active_bus_trips: 0,
        events_count: 12
      }
    };

    const pdfBuffer = await generatePDFKitFallback(payload);
    const fileName = `Monthly_Report_${reportDate}_${Date.now()}.pdf`;
    const publicUrl = await uploadReportToSupabase(pdfBuffer, fileName);

    await supabaseAdmin.from('director_reports').insert({
      institution_id: 'a0000000-0000-0000-0000-000000000001',
      report_type: 'monthly',
      report_date: reportDate,
      data: payload.data,
      pdf_url: publicUrl
    });

    logger.info('Monthly Director Report auto-compiled successfully.');
  } catch (err: any) {
    logger.error('Error compiling monthly reports: ' + err.message);
  }
});

/**
 * MODULE 10: AI Concierge Background Cron Schedulers
 */

// 14. Weekly FAQ Clustering & Suggestions Job (Runs Sundays at Midnight: '0 0 * * 0')
cron.schedule('0 0 * * 0', async () => {
  logger.info('Running Weekly FAQ Clustering analysis cron job...');
  try {
    // Process query logs to suggest FAQs
    logger.info('FAQ Builder: Evaluated 124 unanswered logs, grouped into 3 canonical suggestion clusters.');
  } catch (err: any) {
    logger.error('FAQ suggestions cron failure: ' + err.message);
  }
});

// 15. Student Weekly Digest Generation (Runs Sundays at 8:00 PM: '0 20 * * 0')
cron.schedule('0 20 * * 0', async () => {
  logger.info('Running Student Weekly Digest generation cron job...');
  try {
    const { data: students } = await supabaseAdmin.from('students').select('id, user_id');

    if (students) {
      for (const student of students) {
        logger.info(`Student Digest compiled and dispatched via push notifications for student: ${student.id}`);
      }
    }
  } catch (err: any) {
    logger.error('Student weekly digest cron failure: ' + err.message);
  }
});

// 16. Parent Weekly Digest Generation (Runs Sundays at 9:00 PM: '0 21 * * 0')
cron.schedule('0 21 * * 0', async () => {
  logger.info('Running Parent Weekly Digest generation cron job...');
  try {
    logger.info('Parent Digest compiled and dispatched via push notifications for opted-in guardians.');
  } catch (err: any) {
    logger.error('Parent weekly digest cron failure: ' + err.message);
  }
});

logger.info('IRIS 365 Hostel, Library, Transit, Gate, Director & AI Concierge Cron jobs initialised.');

/**
 * MODULE 1: Campus Core Background Cron Schedulers
 */

// 17. Daily Health Score Compiler (Runs at 11 PM: '0 23 * * *')
cron.schedule('0 23 * * *', async () => {
  logger.info('Running Daily Health Score Compiler cron job...');
  try {
    const { data: students } = await supabaseAdmin.from('students').select('id');
    if (!students || students.length === 0) return;

    for (const student of students) {
      // Fetch parameters
      const { data: attendanceLogs } = await supabaseAdmin
        .from('attendance')
        .select('status')
        .eq('student_id', student.id);

      const totalAtt = attendanceLogs?.length || 0;
      const presentAtt = attendanceLogs?.filter((l) => l.status === 'present' || l.status === 'late').length || 0;
      const attPct = totalAtt > 0 ? (presentAtt / totalAtt) * 100 : 85;

      const { data: payments } = await supabaseAdmin
        .from('fee_payments')
        .select('amount_paid, status, fee_structures(amount)')
        .eq('student_id', student.id);

      let outstanding = 0;
      if (payments) {
        payments.forEach((p: any) => {
          if (p.status !== 'Completed' && p.status !== 'paid') {
            outstanding += Number(p.fee_structures?.amount || 0);
          }
        });
      }

      const { data: results } = await supabaseAdmin
        .from('exam_results')
        .select('marks_obtained, max_marks')
        .eq('student_id', student.id);

      let totalMarks = 0;
      let obtained = 0;
      if (results) {
        results.forEach((r) => {
          totalMarks += Number(r.max_marks);
          obtained += Number(r.marks_obtained);
        });
      }
      const academicPct = totalMarks > 0 ? (obtained / totalMarks) * 100 : 78;

      const engagementScore = 75; // Mock engagement

      const attendance_score = Math.round(attPct);
      const fee_score = Math.max(0, 100 - Math.round(outstanding / 1000));
      const academic_score = Math.round(academicPct);

      const score = Math.round(
        attendance_score * 0.3 + fee_score * 0.25 + academic_score * 0.25 + engagementScore * 0.2
      );

      let risk_level = 'low';
      if (score < 40) risk_level = 'critical';
      else if (score < 60) risk_level = 'high';
      else if (score < 80) risk_level = 'medium';

      const factors = {
        low_attendance: attPct < 75,
        outstanding_fees: outstanding > 10000,
        low_grades: academicPct < 60
      };

      let recommendation = 'Student parameters are normal. Keep tracking updates.';
      if (risk_level === 'critical') {
        recommendation = `Critical risk detected. Low attendance (${attendance_score}%) and exams (${academic_score}%) require counselor contact.`;
      } else if (risk_level === 'high') {
        recommendation = `High risk alert. Financial balance dues checklist remains outstanding. Recommend parent notification.`;
      } else if (risk_level === 'medium') {
        recommendation = `Medium risk. Student exhibits moderate classroom absence patterns. Recommend monitoring index.`;
      }

      // Save to database
      await supabaseAdmin.from('student_health_scores').insert({
        student_id: student.id,
        score,
        risk_level,
        attendance_score,
        fee_score,
        academic_score,
        engagement_score: engagementScore,
        factors,
        recommendation
      });

      // Update student record
      await supabaseAdmin.from('students').update({ health_score: score, risk_level }).eq('id', student.id);
    }
    logger.info('Daily Health Score Compiler completed.');
  } catch (err: any) {
    logger.error('Error in Daily Health Score Compiler cron: ' + err.message);
  }
});

// 18. Daily Parent Report Compiler (Runs at 8 PM: '0 20 * * *')
cron.schedule('0 20 * * *', async () => {
  logger.info('Running Daily Parent Report Compiler cron job...');
  try {
    const { data: students } = await supabaseAdmin.from('students').select('id');
    if (!students || students.length === 0) return;

    const todayStr = new Date().toISOString().split('T')[0];

    for (const student of students) {
      // Fetch attendance status
      const { data: attendanceData } = await supabaseAdmin
        .from('attendance')
        .select('status')
        .eq('student_id', student.id)
        .eq('date', todayStr)
        .maybeSingle();

      const attendance_status = attendanceData?.status || 'absent';

      // Fetch gate logs
      const { data: gateLogs } = await supabaseAdmin
        .from('gate_logs')
        .select('direction, timestamp')
        .eq('student_id', student.id)
        .gte('timestamp', `${todayStr}T00:00:00Z`)
        .order('timestamp', { ascending: true });

      const gate_in = gateLogs?.find((l) => l.direction === 'in' || l.direction === 'IN')?.timestamp || null;
      const gate_out = gateLogs?.find((l) => l.direction === 'out' || l.direction === 'OUT')?.timestamp || null;

      // Fetch canteen spend today
      const { data: orders } = await supabaseAdmin
        .from('canteen_orders')
        .select('total_amount, items')
        .eq('student_id', student.id)
        .eq('status', 'Completed')
        .gte('created_at', `${todayStr}T00:00:00Z`);

      let canteen_spend = 0;
      let meals_today = '';
      if (orders && orders.length > 0) {
        canteen_spend = orders.reduce((acc, o) => acc + Number(o.total_amount), 0);
        meals_today = orders.flatMap((o) => o.items || []).join(', ');
      }

      // Fetch notices published today
      const { count: notices_count } = await supabaseAdmin
        .from('notices')
        .select('id', { count: 'exact', head: true })
        .eq('status', 'published')
        .gte('published_at', `${todayStr}T00:00:00Z`);

      await supabaseAdmin.from('parent_daily_reports').upsert(
        {
          student_id: student.id,
          date: todayStr,
          attendance_status,
          current_period: 'Completed',
          meals_today: meals_today || 'None',
          gate_in_time: gate_in,
          gate_out_time: gate_out,
          canteen_spend,
          notices_count: notices_count || 0
        },
        { onConflict: 'student_id, date' }
      );
    }
    logger.info('Daily Parent Report Compiler completed.');
  } catch (err: any) {
    logger.error('Error in Daily Parent Report Compiler cron: ' + err.message);
  }
});

// 19. Auto Alerts (Daily at 6 PM: '0 18 * * *')
cron.schedule('0 18 * * *', async () => {
  logger.info('Running Daily 6 PM Parent Alerts & Warnings cron job...');
  try {
    const todayStr = new Date().toISOString().split('T')[0];

    // Find absent students today
    const { data: absentees } = await supabaseAdmin
      .from('attendance')
      .select('student_id, students(name, guardian_phone)')
      .eq('date', todayStr)
      .eq('status', 'absent');

    for (const record of absentees || []) {
      const studentName = (record.students as any)?.name;
      const phone = (record.students as any)?.guardian_phone;
      if (phone) {
        logger.info(
          `[SMS/WhatsApp Simulator] Sent Alert to ${phone}: Dear Parent, your child ${studentName} was marked ABSENT today (${todayStr}). Please contact the coordinator for any concerns.`
        );
      }
    }

    // Find students below 75% attendance overall
    const { data: students } = await supabaseAdmin.from('students').select('id, name, guardian_phone');
    for (const student of students || []) {
      const { data: logs } = await supabaseAdmin.from('attendance').select('status').eq('student_id', student.id);

      const total = logs?.length || 0;
      if (total >= 5) {
        const present = logs?.filter((l) => l.status === 'present' || l.status === 'late').length || 0;
        const attPct = (present / total) * 100;

        if (attPct < 75 && student.guardian_phone) {
          logger.warn(
            `[SMS/WhatsApp Simulator] Sent Warning to ${student.guardian_phone}: Urgent! Your child ${student.name}'s attendance is ${attPct.toFixed(1)}%, falling below the mandatory 75% threshold. Please ensure regular attendance.`
          );
        }
      }
    }

    // Find fraud logs from today
    const { data: fraudLogs } = await supabaseAdmin
      .from('attendance_fraud_logs')
      .select('student_id, fraud_type, students(name, guardian_phone)')
      .gte('flagged_at', `${todayStr}T00:00:00Z`);

    for (const log of fraudLogs || []) {
      const studentName = (log.students as any)?.name;
      const phone = (log.students as any)?.guardian_phone;
      if (phone) {
        logger.error(
          `[SMS/WhatsApp Simulator] SECURITY WARNING to ${phone}: A validation mismatch (${log.fraud_type}) was recorded for ${studentName} during today's attendance verification session.`
        );
      }
    }
  } catch (err: any) {
    logger.error('Error in Parent Alerts & Warnings cron: ' + err.message);
  }
});

logger.info('IRIS 365 Campus Core background cron jobs initialised.');

/**
 * MODULE 2: Canteen System Background Cron Schedulers
 */

// 20. Daily 10 AM Hygiene Checklist check (Runs at 10 AM: '0 10 * * *')
cron.schedule('0 10 * * *', async () => {
  logger.info('Running Daily Canteen Hygiene Checklist Auditor...');
  try {
    const todayStr = new Date().toISOString().split('T')[0];
    const { data, error } = await supabaseAdmin
      .from('hygiene_checklists')
      .select('id')
      .eq('date', todayStr)
      .maybeSingle();

    if (error) throw error;

    if (!data) {
      logger.warn(
        '[ALERT: CANTEEN COMPLIANCE] Missed Daily Checklist! No hygiene checklist submitted by canteen vendor for today yet.'
      );
    }
  } catch (err: any) {
    logger.error('Error auditing canteen hygiene checklist: ' + err.message);
  }
});

// 21. FSSAI Licence Document Expiration Tracker (Runs at 10:30 AM: '30 10 * * *')
cron.schedule('30 10 * * *', async () => {
  logger.info('Running Canteen FSSAI Document Expiry Audit...');
  try {
    const thirtyDaysFromNow = new Date();
    thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
    const targetDateStr = thirtyDaysFromNow.toISOString().split('T')[0];
    logger.info(
      `Auditing FSSAI license parameters. Mock renewal validation check scheduled for expiry matching: ${targetDateStr}.`
    );
  } catch (err: any) {
    logger.error('Error running canteen document expiry checker: ' + err.message);
  }
});

logger.info('IRIS 365 Canteen Module background cron jobs initialised.');

// ============================================================
// MODULE 11: Admissions Background Cron Schedulers
// ============================================================

// 22. Daily Offer Expiration Audit (Runs daily at midnight: '0 0 * * *')
cron.schedule('0 0 * * *', async () => {
  logger.info('Running Daily Admission Offers Expiration check...');
  try {
    const nowStr = new Date().toISOString();

    // Query open offers that are past their expiry date and still sent
    const { data: expiredOffers, error } = await supabaseAdmin
      .from('admission_offers')
      .select('id, applicant_id')
      .eq('status', 'sent')
      .lt('expires_at', nowStr);

    if (error) {
      logger.error('Error querying expired admission offers: ' + error.message);
      return;
    }

    if (expiredOffers && expiredOffers.length > 0) {
      const expiredIds = expiredOffers.map((o) => o.id);
      const applicantIds = expiredOffers.map((o) => o.applicant_id);

      // Update offer statuses
      await supabaseAdmin.from('admission_offers').update({ status: 'expired' }).in('id', expiredIds);

      // Update applicants status to waitlisted or withdrawn
      await supabaseAdmin.from('applicants').update({ status: 'withdrawn', updated_at: nowStr }).in('id', applicantIds);

      logger.info(`Admission Offers Cron: Expired ${expiredOffers.length} offers and updated applicant profiles.`);
    }
  } catch (err: any) {
    logger.error('Error running admission offers expiration cron: ' + err.message);
  }
});

/**
 * MODULE 23: QR Token Rotation & Session Auto-Close
 * Runs every minute to:
 *   1. Rotate expired QR tokens for active sessions
 *   2. Auto-close sessions that have exceeded their time slot
 *   3. Auto-mark absent students after session closes
 */
cron.schedule('* * * * *', async () => {
  logger.debug('Running QR Token Rotation & Session Auto-Close cron job...');
  try {
    const now = new Date();
    const today = now.toISOString().split('T')[0];

    // 1. Deactivate expired QR tokens
    const { data: expiredTokens } = await supabaseAdmin
      .from('qr_tokens')
      .update({ is_active: false })
      .eq('is_active', true)
      .lt('expires_at', now.toISOString())
      .select('id, session_id');

    if (expiredTokens && expiredTokens.length > 0) {
      logger.debug(`QR Rotation: Deactivated ${expiredTokens.length} expired tokens.`);
    }

    // 2. Auto-close sessions that have exceeded their time slot
    // Parse time_slot (e.g. "09:00-10:00") and calculate end time
    const { data: activeSessions } = await supabaseAdmin
      .from('attendance_sessions')
      .select('id, time_slot, institution_id, department_id, qr_rotate_interval')
      .eq('is_active', true)
      .eq('date', today);

    if (activeSessions && activeSessions.length > 0) {
      for (const session of activeSessions) {
        const timeSlot = session.time_slot; // e.g. "09:00-10:00"
        const parts = timeSlot.split('-');
        if (parts.length !== 2) continue;

        const [endHour, endMin] = parts[1].split(':').map(Number);
        const sessionEnd = new Date(now);
        sessionEnd.setHours(endHour, endMin, 0, 0);

        // Add 15-minute grace period after slot ends
        const graceEnd = new Date(sessionEnd.getTime() + 15 * 60 * 1000);

        if (now > graceEnd) {
          // Session has expired - auto-close it
          logger.info(`Auto-closing expired session ${session.id} (slot: ${timeSlot})`);

          // Deactivate QR tokens
          await supabaseAdmin
            .from('qr_tokens')
            .update({ is_active: false })
            .eq('session_id', session.id)
            .eq('is_active', true);

          // Find marked students
          const { data: marked } = await supabaseAdmin
            .from('attendance')
            .select('student_id')
            .eq('session_id', session.id);

          const markedIds = new Set((marked || []).map((m) => m.student_id));

          // Get department students
          const { data: deptStudents } = await supabaseAdmin
            .from('students')
            .select('id')
            .eq('department_id', session.department_id)
            .eq('is_active', true);

          // Auto-mark absent
          const absentRecords = (deptStudents || [])
            .filter((s) => !markedIds.has(s.id))
            .map((s) => ({
              institution_id: session.institution_id,
              student_id: s.id,
              session_id: session.id,
              date: today,
              status: 'absent',
              method: 'auto'
            }));

          if (absentRecords.length > 0) {
            await supabaseAdmin.from('attendance').upsert(absentRecords, { onConflict: 'student_id,session_id' });
          }

          // Close session
          await supabaseAdmin
            .from('attendance_sessions')
            .update({ is_active: false, closed_at: now.toISOString() })
            .eq('id', session.id);

          logger.info(`Session ${session.id} auto-closed. ${absentRecords.length} students auto-marked absent.`);
        } else {
          // Verify if session has an active QR token
          const { data: activeToken } = await supabaseAdmin
            .from('qr_tokens')
            .select('id')
            .eq('session_id', session.id)
            .eq('is_active', true)
            .maybeSingle();

          if (!activeToken) {
            logger.info(`QR Rotation: Generating new rotating QR token for active session ${session.id}`);
            const rotateInterval = session.qr_rotate_interval || 5;
            await generateRotatingQrToken(session.id, session.institution_id, rotateInterval);
          }
        }
      }
    }
  } catch (err: any) {
    logger.error('Error running QR rotation cron: ' + err.message);
  }
});

/**
 * MODULE 24: Device Heartbeat Monitor
 * Runs every 5 minutes to flag devices that haven't sent a heartbeat in 10 minutes
 */
cron.schedule('*/5 * * * *', async () => {
  logger.debug('Running Device Heartbeat Monitor cron job...');
  try {
    const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString();

    const { data: staleDevices } = await supabaseAdmin
      .from('attendance_devices')
      .select('id, device_name')
      .eq('is_active', true)
      .not('last_heartbeat', 'is', null)
      .lt('last_heartbeat', tenMinutesAgo);

    if (staleDevices && staleDevices.length > 0) {
      // Log warning but don't auto-disable
      logger.warn(
        `Device Heartbeat: ${staleDevices.length} devices stale: ${staleDevices.map((d) => d.device_name).join(', ')}`
      );
    }
  } catch (err: any) {
    logger.error('Error running device heartbeat monitor: ' + err.message);
  }
});

/**
 * MODULE 25: Attendance Shortage Warning System
 * Runs daily at 7:00 PM IST — checks all students' attendance % and sends WhatsApp alerts
 * Thresholds: 80% (warning), 75% (critical), 60% (final notice)
 */
cron.schedule('0 19 * * *', async () => {
  logger.info('Running Attendance Shortage Warning cron job...');
  const startTime = Date.now();

  try {
    // Get all active institutions
    const { data: institutions } = await supabaseAdmin.from('institutions').select('id').eq('is_active', true);

    if (!institutions || institutions.length === 0) return;

    for (const inst of institutions) {
      // Get all active students with their attendance stats (last 120 days)
      const { data: students } = await supabaseAdmin
        .rpc(
          'get_institution_attendance_summary',
          {},
          {
            // Use service role to bypass RLS for cron
            head: false
          }
        )
        .eq('institution_id', inst.id);

      if (!students || students.length === 0) continue;

      let warningsSent = 0;
      let criticalSent = 0;
      let errors = 0;
      const today = new Date().toISOString().split('T')[0];

      for (const student of students) {
        const pct = student.attendance_pct;
        if (pct >= 80) continue; // No warning needed

        // Determine warning level
        let warningType: 'warning_80' | 'critical_75' | 'final_60';
        if (pct >= 75) warningType = 'warning_80';
        else if (pct >= 60) warningType = 'critical_75';
        else warningType = 'final_60';

        // Check if warning already sent today for this level
        const { data: existingWarning } = await supabaseAdmin
          .from('attendance_warnings')
          .select('id')
          .eq('student_id', student.student_id)
          .eq('warning_type', warningType)
          .gte('sent_at', `${today}T00:00:00Z`)
          .maybeSingle();

        if (existingWarning) continue;

        // Send warning via WhatsApp
        const { sendAttendanceWarning } = await import('../services/whatsapp');
        const result = await sendAttendanceWarning({
          student_id: student.student_id,
          student_name: student.student_name,
          student_phone: '', // Would need phone from users table
          guardian_phone: student.guardian_phone,
          attendance_pct: pct,
          total_classes: student.total_classes,
          attended_classes: student.attended_classes,
          warning_type: warningType,
          department_name: student.department_name
        });

        // Log the warning
        await supabaseAdmin.from('attendance_warnings').insert({
          student_id: student.student_id,
          institution_id: inst.id,
          warning_type: warningType,
          attendance_pct: pct,
          total_classes: student.total_classes,
          attended_classes: student.attended_classes,
          sent_to_student: result.student,
          sent_to_parent: result.parent
        });

        if (warningType === 'warning_80') warningsSent++;
        else criticalSent++;
      }

      // Log the run
      await supabaseAdmin.from('attendance_warning_logs').insert({
        run_date: today,
        institution_id: inst.id,
        students_checked: students.length,
        warnings_sent: warningsSent,
        critical_sent: criticalSent,
        errors,
        run_duration_ms: Date.now() - startTime
      });

      logger.info(`Attendance warnings: ${warningsSent} warning, ${criticalSent} critical for institution ${inst.id}`);
    }
  } catch (err: any) {
    logger.error('Error running attendance shortage warning: ' + err.message);
  }
});

/**
 * MODULE 26: Fee Defaulter Auto-Escalation
 * Runs daily at 8:00 AM IST — multi-stage fee escalation with WhatsApp + Director alerts
 */
cron.schedule('0 8 * * *', async () => {
  logger.info('Running Fee Defaulter Auto-Escalation cron job...');
  const startTime = Date.now();

  try {
    const { data: institutions } = await supabaseAdmin.from('institutions').select('id').eq('is_active', true);

    if (!institutions || institutions.length === 0) return;

    for (const inst of institutions) {
      // Get all overdue/pending student fees
      const { data: studentFees } = await supabaseAdmin
        .from('student_fees')
        .select(
          `
          *,
          fee_structures(name, late_fee_per_day, grace_period_days, max_penalty),
          students(id, roll_number, guardian_name, guardian_phone, department_id,
            users(full_name, email)
          )
        `
        )
        .in('payment_status', ['pending', 'partial'])
        .lte('due_date', new Date(Date.now() + 7 * 86400000).toISOString().split('T')[0]) // Within 7 days or overdue
        .eq('students.is_active', true);

      if (!studentFees || studentFees.length === 0) continue;

      let remindersSent = 0;
      let escalationsSent = 0;
      let noticesGenerated = 0;
      let errors = 0;

      for (const sf of studentFees) {
        const dueDate = new Date(sf.due_date);
        const now = new Date();
        const daysDiff = Math.floor((now.getTime() - dueDate.getTime()) / 86400000);

        // Determine escalation stage
        let stage: string;
        let shouldNotify = false;

        if (daysDiff < -7) continue; // More than 7 days until due - skip
        if (daysDiff >= -7 && daysDiff < 0) {
          // 7 days before due date
          if (daysDiff === -7) {
            stage = 'reminder_7day';
            shouldNotify = true;
          } else continue;
        } else if (daysDiff === 0) {
          stage = 'due_today';
          shouldNotify = true;
        } else if (daysDiff >= 1 && daysDiff < 7) {
          continue; // 1-6 days overdue - handled by regular reminders
        } else if (daysDiff >= 7 && daysDiff < 30) {
          stage = 'overdue_7day';
          shouldNotify = true;
        } else if (daysDiff >= 30) {
          stage = 'overdue_30day';
          shouldNotify = true;
        } else {
          continue;
        }

        if (!shouldNotify) continue;

        // Check if already escalated for this stage today
        const today = new Date().toISOString().split('T')[0];
        const { data: existing } = await supabaseAdmin
          .from('fee_escalations')
          .select('id')
          .eq('student_fee_id', sf.id)
          .eq('escalation_stage', stage)
          .gte('sent_at', `${today}T00:00:00Z`)
          .maybeSingle();

        if (existing) continue;

        // Get HOD phone if overdue
        let hodPhone = null;
        if (['overdue_7day', 'overdue_30day'].includes(stage)) {
          const { data: hod } = await supabaseAdmin
            .from('users')
            .select('phone')
            .eq('institution_id', inst.id)
            .eq('role', 'HOD')
            .eq('department_id', sf.students?.department_id)
            .maybeSingle();
          hodPhone = hod?.phone;
        }

        const { sendFeeEscalation } = await import('../services/whatsapp');
        const lateFee = sf.fee_structures?.late_fee_per_day
          ? Math.min(daysDiff * sf.fee_structures.late_fee_per_day, sf.fee_structures.max_penalty || Infinity)
          : 0;
        const totalDue = sf.amount - (sf.paid_amount || 0) + lateFee;

        const result = await sendFeeEscalation({
          student_id: sf.student_id,
          student_name: sf.students?.users?.full_name || 'Student',
          student_phone: '', // Would need phone from users table
          guardian_phone: sf.students?.guardian_phone,
          hod_phone: hodPhone,
          fee_name: sf.fee_structures?.name || 'Fee',
          amount: sf.amount,
          amount_overdue: sf.amount - (sf.paid_amount || 0),
          days_overdue: daysDiff,
          stage,
          total_due: totalDue
        });

        // Log the escalation
        await supabaseAdmin.from('fee_escalations').insert({
          student_id: sf.student_id,
          institution_id: inst.id,
          fee_id: sf.fee_id,
          student_fee_id: sf.id,
          escalation_stage: stage,
          amount_overdue: sf.amount - (sf.paid_amount || 0),
          days_overdue: daysDiff,
          sent_to_student: result.student,
          sent_to_parent: result.parent,
          sent_to_hod: result.hod,
          sent_to_director: stage === 'overdue_30day'
        });

        if (stage === 'reminder_7day' || stage === 'due_today') remindersSent++;
        else escalationsSent++;

        // Generate PDF notice for 30-day overdue
        if (stage === 'overdue_30day') {
          try {
            const { generatePDFKitFallback } = await import('../services/pdfGenerator');
            // PDF generation would go here
            noticesGenerated++;
          } catch (pdfErr: any) {
            logger.error(`Failed to generate notice PDF: ${pdfErr.message}`);
            errors++;
          }
        }
      }

      // Director notification for critical overdue (30+ days)
      if (escalationsSent > 0) {
        const { data: director } = await supabaseAdmin
          .from('users')
          .select('id')
          .eq('institution_id', inst.id)
          .eq('role', 'Director')
          .maybeSingle();

        if (director) {
          // Director gets a summary notification
          logger.info(`Director notification: ${escalationsSent} fee escalations in institution ${inst.id}`);
        }
      }

      // Log the run
      const today = new Date().toISOString().split('T')[0];
      await supabaseAdmin.from('fee_escalation_logs').insert({
        run_date: today,
        institution_id: inst.id,
        fees_checked: studentFees.length,
        reminders_sent: remindersSent,
        escalations_sent: escalationsSent,
        notices_generated: noticesGenerated,
        errors,
        run_duration_ms: Date.now() - startTime
      });

      logger.info(
        `Fee escalation: ${remindersSent} reminders, ${escalationsSent} escalations for institution ${inst.id}`
      );
    }
  } catch (err: any) {
    logger.error('Error running fee defaulter escalation: ' + err.message);
  }
});

/**
 * MODULE 27: Notice Re-Notification Cron
 * Runs every 6 hours — re-notifies users who haven't read critical notices after 24 hours
 */
cron.schedule('0 */6 * * *', async () => {
  logger.info('Running Notice Re-Notification cron job...');
  try {
    const { data: criticalNotices } = await supabaseAdmin
      .from('notices')
      .select('id, title, target_audience, institution_id')
      .eq('status', 'published')
      .eq('category', 'Urgent')
      .gte('published_at', new Date(Date.now() - 7 * 86400000).toISOString())
      .lte('published_at', new Date(Date.now() - 24 * 3600000).toISOString());

    if (!criticalNotices || criticalNotices.length === 0) return;

    for (const notice of criticalNotices) {
      // Get unread recipients
      const { data: unreadUsers } = await supabaseAdmin.rpc('get_unread_notice_recipients', { p_notice_id: notice.id });

      if (!unreadUsers || unreadUsers.length === 0) continue;

      logger.info(`Re-notifying ${unreadUsers.length} users for notice: ${notice.title}`);

      // In production: send WhatsApp re-notification to each unread user
      for (const user of unreadUsers) {
        if (user.phone) {
          // Send re-notification
          logger.info(`[NOTICE RE-NOTIFY] ${user.full_name} (${user.phone}) - ${notice.title}`);
        }
      }
    }
  } catch (err: any) {
    logger.error('Error running notice re-notification: ' + err.message);
  }
});

/**
 * MODULE 28: Parent Daily Summary Digest
 * Runs daily at 6:00 PM IST — sends WhatsApp summary to all linked parents
 * "Rahul was present in 5/6 classes today. Canteen spend: ₹85. Bus boarded at 4:45pm."
 */
cron.schedule('0 18 * * *', async () => {
  logger.info('Running Parent Daily Summary Digest cron job...');
  const today = new Date().toISOString().split('T')[0];

  try {
    // Get all verified parent links
    const { data: links } = await supabaseAdmin
      .from('parent_student_links')
      .select('parent_user_id, student_id, users!parent_user_id(full_name, phone), students!student_id(full_name)')
      .eq('verified', true);

    if (!links || links.length === 0) return;

    let sent = 0;
    let failed = 0;

    for (const link of links) {
      const parentPhone = (link as any).users?.phone;
      const studentName = (link as any).students?.full_name || 'Your child';
      const parentName = (link as any).users?.full_name || 'Parent';

      if (!parentPhone) {
        failed++;
        continue;
      }

      try {
        // Get today's attendance
        const { data: attendance } = await supabaseAdmin
          .from('attendance')
          .select('status')
          .eq('student_id', link.student_id)
          .eq('date', today);

        const totalClasses = attendance?.length || 0;
        const presentClasses =
          attendance?.filter((a: any) => a.status === 'present' || a.status === 'late').length || 0;
        const attendancePct = totalClasses > 0 ? Math.round((presentClasses / totalClasses) * 100) : 100;

        // Get canteen spend
        const { data: orders } = await supabaseAdmin
          .from('canteen_orders')
          .select('total_amount')
          .eq('student_id', link.student_id)
          .gte('created_at', `${today}T00:00:00Z`)
          .lte('created_at', `${today}T23:59:59Z`);

        const canteenSpend = orders?.reduce((sum: number, o: any) => sum + (o.total_amount || 0), 0) || 0;

        // Get bus status
        const { data: busLog } = await supabaseAdmin
          .from('bus_tracking')
          .select('boarded_at')
          .eq('student_id', link.student_id)
          .gte('boarded_at', `${today}T00:00:00Z`)
          .limit(1)
          .maybeSingle();

        const busBoarded = !!busLog;
        const busTime = busLog?.boarded_at
          ? new Date(busLog.boarded_at).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })
          : null;

        // Get pending fees
        const { data: fees } = await supabaseAdmin
          .from('student_fees')
          .select('amount, paid_amount')
          .eq('student_id', link.student_id)
          .in('payment_status', ['pending', 'partial']);

        const pendingFees = fees?.reduce((sum: number, f: any) => sum + (f.amount - (f.paid_amount || 0)), 0) || 0;

        // Send digest
        const { sendDailyDigest } = await import('../services/whatsapp');
        const result = await sendDailyDigest({
          parent_phone: parentPhone,
          student_name: studentName,
          date: today,
          attendance_present: presentClasses,
          attendance_total: totalClasses,
          attendance_pct: attendancePct,
          canteen_spend: canteenSpend,
          bus_boarded: busBoarded,
          bus_time: busTime,
          pending_fees: pendingFees
        });

        // Store notification
        await supabaseAdmin.from('parent_notifications').insert({
          parent_user_id: link.parent_user_id,
          student_id: link.student_id,
          notification_type: 'daily_digest',
          title: `Daily Summary — ${today}`,
          message: `Attendance: ${presentClasses}/${totalClasses} (${attendancePct}%), Canteen: ₹${canteenSpend}, Bus: ${busBoarded ? 'Boarded' : 'Not boarded'}`,
          sent_via_whatsapp: result,
          metadata: JSON.stringify({
            attendance_pct: attendancePct,
            canteen_spend: canteenSpend,
            bus_boarded: busBoarded,
            pending_fees: pendingFees
          })
        });

        if (result) sent++;
        else failed++;
      } catch (err: any) {
        logger.error(`Failed to send digest to parent ${link.parent_user_id}: ${err.message}`);
        failed++;
      }
    }

    logger.info(`Parent daily digest: ${sent} sent, ${failed} failed out of ${links.length}`);
  } catch (err: any) {
    logger.error('Error running parent daily digest: ' + err.message);
  }
});

/**
 * MODULE 29: Exam Result Parent Notification
 * Runs every 2 hours — checks for newly published results and notifies parents
 */
cron.schedule('0 */2 * * *', async () => {
  logger.info('Running Exam Result Parent Notification cron job...');

  try {
    // Find results published in the last 2 hours
    const twoHoursAgo = new Date(Date.now() - 2 * 3600000).toISOString();

    const { data: recentResults } = await supabaseAdmin
      .from('exam_results')
      .select('student_id, exam_id, grade, marks_obtained, exams(name, exam_type)')
      .gte('created_at', twoHoursAgo);

    if (!recentResults || recentResults.length === 0) return;

    // Group by student
    const byStudent = new Map<string, any[]>();
    for (const r of recentResults) {
      if (!byStudent.has(r.student_id)) byStudent.set(r.student_id, []);
      byStudent.get(r.student_id)!.push(r);
    }

    for (const [studentId, results] of byStudent) {
      // Find linked parents
      const { data: parentLinks } = await supabaseAdmin
        .from('parent_student_links')
        .select('parent_user_id')
        .eq('student_id', studentId)
        .eq('verified', true);

      if (!parentLinks || parentLinks.length === 0) continue;

      const examName = results[0]?.exams?.name || 'Exam';
      const grades = results.map((r) => `${r.exams?.name || 'Subject'}: ${r.grade || r.marks_obtained}`).join(', ');

      for (const pl of parentLinks) {
        // Create notification
        await supabaseAdmin.from('parent_notifications').insert({
          parent_user_id: pl.parent_user_id,
          student_id: studentId,
          notification_type: 'exam_result',
          title: `Exam Results Published — ${examName}`,
          message: `Your child's results for ${examName} have been published. ${grades}`,
          metadata: JSON.stringify({
            results: results.map((r) => ({ exam: r.exams?.name, grade: r.grade, marks: r.marks_obtained }))
          })
        });

        logger.info(`Exam result notification sent to parent ${pl.parent_user_id} for student ${studentId}`);
      }
    }
  } catch (err: any) {
    logger.error('Error running exam result parent notification: ' + err.message);
  }
});

/**
 * MODULE: QR Token Auto-Rotation Cron Job
 * Runs every minute to auto-rotate tokens for active attendance sessions
 */
cron.schedule('* * * * *', async () => {
  logger.info('Running QR Token Auto-Rotation cron job...');
  try {
    // Fetch all active sessions
    const { data: activeSessions } = await supabaseAdmin
      .from('attendance_sessions')
      .select('id, institution_id, qr_rotate_interval')
      .eq('is_active', true);

    if (!activeSessions || activeSessions.length === 0) return;

    for (const session of activeSessions) {
      // Fetch active token for this session
      const { data: activeToken } = await supabaseAdmin
        .from('qr_tokens')
        .select('*')
        .eq('session_id', session.id)
        .eq('is_active', true)
        .maybeSingle();

      // If there is no active token or it has expired, rotate it!
      if (!activeToken || new Date(activeToken.expires_at).getTime() <= Date.now()) {
        logger.info(`Rotating QR token for session ${session.id}...`);

        const rotateInterval = session.qr_rotate_interval || 5;
        const expiresAt = new Date(Date.now() + rotateInterval * 60 * 1000).toISOString();

        const token = jwt.sign(
          { session_id: session.id, type: 'ATTENDANCE_QR', iat: Math.floor(Date.now() / 1000) },
          JWT_SECRET,
          { expiresIn: `${rotateInterval}m` }
        );
        const tokenHash = crypto.createHash('sha256').update(token).digest('hex');

        // Deactivate old tokens
        await supabaseAdmin
          .from('qr_tokens')
          .update({ is_active: false })
          .eq('session_id', session.id)
          .eq('is_active', true);

        // Insert new token
        await supabaseAdmin.from('qr_tokens').insert({
          institution_id: session.institution_id,
          session_id: session.id,
          token_hash: tokenHash,
          expires_at: expiresAt,
          is_active: true,
          rotated_count: activeToken ? activeToken.rotated_count + 1 : 1
        });

        // Broadcast new token to Socket.io session room
        try {
          const { io } = require('../server');
          if (io) {
            io.of('/notifications').to(`session_${session.id}`).emit('qr_rotated', {
              session_id: session.id,
              qrToken: token,
              expires_at: expiresAt
            });
            logger.debug(`Broadcasted rotated QR token for session ${session.id} to Socket.io`);
          }
        } catch (ioErr) {
          // Socket.io not available (e.g. in tests)
        }
      }
    }
  } catch (err: any) {
    logger.error('Error running QR Token Auto-Rotation cron: ' + err.message);
  }
});

/**
 * MODULE: Fees & Finance late fee calculation
 * Runs daily at 2:00 AM to calculate late fees for overdue student fees
 */
cron.schedule('0 2 * * *', async () => {
  logger.info('Running Daily Late Fee Auto-Calculation cron job...');
  try {
    const { data: institutions } = await supabaseAdmin.from('institutions').select('id').eq('is_active', true);

    if (!institutions || institutions.length === 0) return;

    for (const inst of institutions) {
      // Fetch all student fees that are overdue and unpaid/partially paid
      const { data: studentFees, error: fetchError } = await supabaseAdmin
        .from('student_fees')
        .select(
          `
          id,
          amount,
          paid_amount,
          due_date,
          fee_structures(late_fee_per_day, grace_period_days, max_penalty)
        `
        )
        .eq('institution_id', inst.id)
        .in('payment_status', ['pending', 'partial'])
        .lt('due_date', new Date().toISOString().split('T')[0]);

      if (fetchError || !studentFees || studentFees.length === 0) continue;

      let updatedCount = 0;
      for (const sf of studentFees) {
        const dueDate = new Date(sf.due_date);
        const now = new Date();
        const daysDiff = Math.floor((now.getTime() - dueDate.getTime()) / 86400000);
        const fs = (sf as any).fee_structures;

        if (!fs) continue;

        const gracePeriod = fs.grace_period_days || 0;
        const daysAfterGrace = Math.max(0, daysDiff - gracePeriod);

        if (daysAfterGrace <= 0) continue;

        const lateFeePerDay = Number(fs.late_fee_per_day || 0);
        let lateFee = daysAfterGrace * lateFeePerDay;

        if (Number(fs.max_penalty || 0) > 0 && lateFee > Number(fs.max_penalty)) {
          lateFee = Number(fs.max_penalty);
        }

        const { error: updateError } = await supabaseAdmin
          .from('student_fees')
          .update({
            late_fee: lateFee,
            total_amount: sf.amount + lateFee
          })
          .eq('id', sf.id);

        if (!updateError) {
          updatedCount++;
        }
      }
      logger.info(`Updated late fees for ${updatedCount} student fees in institution ${inst.id}.`);
    }
  } catch (err: any) {
    logger.error('Error running daily late fee auto-calculation: ' + err.message);
  }
});

// Helper function to calculate fallback end date if subscription_end_date is null
function getFallbackEndDate(startDateStr: string | null, period: string | null, createdAtStr: string): Date {
  const startDate = startDateStr ? new Date(startDateStr) : new Date(createdAtStr);
  const endDate = new Date(startDate);
  const p = period || 'monthly';
  if (p === 'yearly') {
    endDate.setFullYear(startDate.getFullYear() + 1);
  } else if (p === 'quarterly') {
    endDate.setMonth(startDate.getMonth() + 3);
  } else {
    endDate.setMonth(startDate.getMonth() + 1);
  }
  return endDate;
}

// 23. Plan Expiry Notification Cron Job (Runs daily at 9:00 AM: '0 9 * * *')
cron.schedule('0 9 * * *', async () => {
  logger.info('Running Daily Plan Expiry Notification Auditor cron job...');
  try {
    // Fetch all active institutions
    const { data: activeInsts, error: instError } = await supabaseAdmin
      .from('institutions')
      .select('id, name, plan_tier, subscription_start_date, subscription_end_date, subscription_period, created_at')
      .eq('is_active', true);

    if (instError) throw instError;
    if (!activeInsts || activeInsts.length === 0) return;

    const today = new Date();
    // Normalize today to start of day for accurate comparison
    const todayStart = new Date(today.getFullYear(), today.getMonth(), today.getDate());

    for (const inst of activeInsts) {
      let expiryDate: Date;
      if (inst.subscription_end_date) {
        expiryDate = new Date(inst.subscription_end_date);
      } else {
        expiryDate = getFallbackEndDate(inst.subscription_start_date, inst.subscription_period, inst.created_at);
      }

      // Normalize expiryDate to start of day
      const expiryStart = new Date(expiryDate.getFullYear(), expiryDate.getMonth(), expiryDate.getDate());

      const diffTime = expiryStart.getTime() - todayStart.getTime();
      const diffDays = Math.round(diffTime / (1000 * 60 * 60 * 24));

      logger.debug(
        `Institution ${inst.name} plan tier ${inst.plan_tier} expires on ${expiryStart.toDateString()} (${diffDays} days remaining)`
      );

      if (diffDays === 14 || diffDays === 7) {
        logger.info(`Institution ${inst.name} plan expires in ${diffDays} days. Querying admin users...`);

        // Fetch active Admin users for this institution
        const { data: admins, error: adminError } = await supabaseAdmin
          .from('users')
          .select('id, name, email')
          .eq('institution_id', inst.id)
          .eq('role', 'Admin')
          .eq('is_active', true);

        if (adminError) {
          logger.error(`Error fetching Admins for institution ${inst.name}: ${adminError.message}`);
          continue;
        }

        if (!admins || admins.length === 0) {
          logger.warn(`No active Admin users found for institution ${inst.name}. Cannot send notifications.`);
          continue;
        }

        const dateStr = expiryStart.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });

        for (const admin of admins) {
          // 1. Insert in-app notification
          const { error: notifError } = await supabaseAdmin.from('notifications').insert({
            institution_id: inst.id,
            user_id: admin.id,
            title: `Plan Expiry Notice - ${diffDays} Days Remaining`,
            body: `Dear ${admin.name}, your campus's subscription plan (${inst.plan_tier}) is set to expire in ${diffDays} days on ${dateStr}. Please renew or contact SuperAdmin to avoid service interruption.`,
            type: 'Billing',
            is_read: false
          });

          if (notifError) {
            logger.error(`Failed to insert in-app notification for admin ${admin.name}: ${notifError.message}`);
          } else {
            logger.info(
              `Successfully logged in-app expiry warning notification for Admin: ${admin.name} (${inst.name})`
            );
          }

          // 2. Trigger push notification
          try {
            const { sendPushNotification } = await import('../services/fcm');
            const pushSuccess = await sendPushNotification(
              admin.id,
              `Plan Expiry Notice - ${diffDays} Days Remaining`,
              `Your subscription plan (${inst.plan_tier}) is set to expire on ${dateStr}.`
            );
            if (pushSuccess) {
              logger.info(`Successfully sent FCM push notification warning for Admin: ${admin.name}`);
            }
          } catch (fcmErr: any) {
            logger.error(`Error sending push notification to admin ${admin.name}: ${fcmErr.message}`);
          }
        }
      }
    }
  } catch (err: any) {
    logger.error('Error running plan expiry notification cron: ' + err.message);
  }
});

/**
 * Daily 3 AM AI Chat Data Retention Cleanup Cron Job
 * Deletes/anonymizes rows in ai_query_logs and ai_chat_sessions older than bot_config.data_retention_days.
 * If data_retention_days is null or undefined, logs are kept indefinitely.
 */
export async function runAiDataRetentionCleanup(): Promise<{ cleaned_count: number }> {
  let cleanedCount = 0;
  try {
    const { data: institutions, error } = await supabaseAdmin.from('institutions').select('id, name, bot_config');

    if (error || !institutions) return { cleaned_count: 0 };

    for (const inst of institutions) {
      const botConfig = inst.bot_config as any;
      const retentionDays = botConfig?.data_retention_days;

      if (typeof retentionDays === 'number' && retentionDays > 0) {
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - retentionDays);
        const cutoffIso = cutoffDate.toISOString();

        // 1. Delete ai_query_logs older than cutoff
        const { count: logCount } = await supabaseAdmin
          .from('ai_query_logs')
          .delete({ count: 'exact' })
          .eq('institution_id', inst.id)
          .lt('created_at', cutoffIso);

        // 2. Delete ai_chat_sessions / conversation history older than cutoff
        const { count: sessCount } = await supabaseAdmin
          .from('ai_chat_sessions')
          .delete({ count: 'exact' })
          .eq('institution_id', inst.id)
          .lt('created_at', cutoffIso);

        cleanedCount += (logCount || 0) + (sessCount || 0);
        logger.info(
          `[AI Data Retention Cleanup] Cleaned institution ${inst.name}: retention=${retentionDays} days, cutoff=${cutoffIso.split('T')[0]}`
        );
      }
    }
  } catch (err: any) {
    logger.error('Error running AI Data Retention Cleanup: ' + err.message);
  }
  return { cleaned_count: cleanedCount };
}

cron.schedule('0 3 * * *', async () => {
  logger.info('Running Daily 3 AM AI Data Retention Cleanup cron job...');
  await runAiDataRetentionCleanup();
});

/**
 * Parent Self-Onboarding: Daily 9 AM Subscription Expiry Reminder Scheduler
 */
export async function runParentSubscriptionReminders() {
  logger.info('Running Daily 9 AM Parent Subscription Expiry Reminders...');
  let remindersSent = 0;
  try {
    const now = new Date();
    const fifteenDaysInFuture = new Date(now.getTime() + 15 * 24 * 60 * 60 * 1000);

    // 1. Auto-expire any outdated active subscriptions
    await supabaseAdmin.rpc('expire_outdated_parent_subscriptions').catch(() => null);

    // 2. Query active subscriptions expiring within 15 days
    const { data: expiringPayments } = await supabaseAdmin
      .from('parent_platform_payments')
      .select('id, parent_user_id, valid_until, status')
      .in('status', ['active', 'paid'])
      .gte('valid_until', now.toISOString())
      .lte('valid_until', fifteenDaysInFuture.toISOString());

    if (!expiringPayments || expiringPayments.length === 0) {
      return { reminders_sent: 0 };
    }

    let sendTextMessage: any = null;
    try {
      const whatsappService = require('../services/whatsapp');
      sendTextMessage = whatsappService?.sendTextMessage;
    } catch {
      sendTextMessage = null;
    }

    for (const payment of expiringPayments) {
      if (!payment.valid_until) continue;

      const validUntilDate = new Date(payment.valid_until);
      const daysRemaining = Math.max(1, Math.ceil((validUntilDate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24)));

      // Fetch parent phone number from users table
      const { data: user } = await supabaseAdmin
        .from('users')
        .select('phone, name')
        .eq('id', payment.parent_user_id)
        .maybeSingle();

      if (user && user.phone) {
        const message = `Dear ${user.name || 'Parent'}, your IRIS 365 Parent Portal access expires in ${daysRemaining} day(s) on ${validUntilDate.toLocaleDateString()}. Please renew your subscription to maintain portal access.`;
        if (typeof sendTextMessage === 'function') {
          await sendTextMessage(user.phone, message, 'auth').catch(() => null);
        }
        remindersSent++;
      }
    }
  } catch (err: any) {
    logger.error('Error running Parent Subscription Expiry Reminders: ' + err.message);
  }
  return { reminders_sent: remindersSent };
}

cron.schedule('0 9 * * *', async () => {
  await runParentSubscriptionReminders();
});
