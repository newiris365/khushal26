import { Router } from 'express';
import {
  getChildToday,
  getChildDailyReport,
  sendParentMessage,
  getParentMessages,
  getConversationThreads,
  getPTMTeachers,
  getPTMSlots,
  bookPTM,
  getParentBookings,
  cancelPTMBooking,
  getParentChildren,
  getParentComplaints,
  createParentComplaint,
  reschedulePTM
} from '../controllers/parent';
import { authMiddleware, requireRole } from '../middleware/auth';
import { supabaseAdmin } from '../config/supabase';

const router = Router();

router.use(authMiddleware);

// Middleware to block unverified parent links
async function requireVerifiedParent(req: any, res: any, next: any) {
  if (req.user?.role === 'Parent') {
    // Allow children fetching and child linking
    if (req.path === '/children' || req.path === '/link' || req.path.startsWith('/link/')) {
      return next();
    }

    const { data: verifiedLinks } = await supabaseAdmin
      .from('parent_student_links')
      .select('id')
      .or(`parent_user_id.eq.${req.user.id},parent_id.eq.${req.user.id}`)
      .limit(1);

    if (!verifiedLinks || verifiedLinks.length === 0) {
      return res.status(403).json({
        success: false,
        code: 'UNVERIFIED_PARENT',
        error: 'Access denied. Parent-student link is pending verification.'
      });
    }
  }
  next();
}

router.use(requireVerifiedParent);

router.get('/children', requireRole(['Parent']), getParentChildren);
router.get('/child/:id/today', getChildToday);
router.get('/child/:id/daily-report/:date', getChildDailyReport);

router.post('/messages', requireRole(['Parent', 'Staff', 'Admin', 'SuperAdmin']), sendParentMessage);
router.get('/messages/threads', requireRole(['Parent', 'Staff', 'Admin', 'SuperAdmin']), getConversationThreads);
router.get('/messages/:teacherId', requireRole(['Parent', 'Staff', 'Admin', 'SuperAdmin']), getParentMessages);

// PTM
router.get('/ptm/teachers', requireRole(['Parent']), getPTMTeachers);
router.get('/ptm/slots/:teacherId', requireRole(['Parent', 'Staff', 'Admin', 'SuperAdmin']), getPTMSlots);
router.post('/ptm/book', requireRole(['Parent']), bookPTM);
router.put('/ptm/:id', requireRole(['Parent']), reschedulePTM);
router.get('/ptm/bookings', requireRole(['Parent']), getParentBookings);
router.post('/ptm/cancel/:id', requireRole(['Parent']), cancelPTMBooking);

// Complaints
router.get('/complaints', requireRole(['Parent']), getParentComplaints);
router.post('/complaints', requireRole(['Parent']), createParentComplaint);

export default router;
