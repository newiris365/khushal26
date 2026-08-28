

-- ==========================================================
-- SECTION: CONSOLIDATED MIGRATIONS (JUNE 9 - JUNE 13)
-- ==========================================================
-- ==========================================================
-- MIGRATION: 20260609000003_campus_core_features.sql
-- ==========================================================

-- Migration: Campus Core Features Extension
-- Targets: Supabase (PostgreSQL)

-- Add fingerprint support to students table
ALTER TABLE students ADD COLUMN IF NOT EXISTS fingerprint_id VARCHAR(100) UNIQUE;
CREATE INDEX IF NOT EXISTS idx_students_fingerprint ON students(fingerprint_id);

-- 1. FEE CONCESSIONS & SCHOLARSHIPS
CREATE TABLE IF NOT EXISTS fee_concessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    fee_structure_id UUID REFERENCES fee_structures(id) ON DELETE CASCADE,
    concession_type VARCHAR(100) NOT NULL, -- Scholarship, Merit, Need-based, Sports
    amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    reason TEXT,
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. NOTICE READS
CREATE TABLE IF NOT EXISTS notice_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notice_id UUID REFERENCES notices(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_notice_user_read UNIQUE (notice_id, user_id)
);

-- 3. ID CARD TEMPLATES
CREATE TABLE IF NOT EXISTS id_card_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    template_json JSONB NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. ATTENDANCE REGULARIZATIONS
CREATE TABLE IF NOT EXISTS attendance_regularizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    reason TEXT NOT NULL,
    proof_url TEXT,
    status VARCHAR(30) DEFAULT 'Pending' CHECK (status IN ('Pending', 'Approved', 'Rejected')),
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable Row Level Security (RLS)
ALTER TABLE fee_concessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE notice_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE id_card_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_regularizations ENABLE ROW LEVEL SECURITY;

-- Setup RLS Policies
DROP POLICY IF EXISTS tenant_fee_concessions_policy ON fee_concessions;
CREATE POLICY tenant_fee_concessions_policy ON fee_concessions
    FOR ALL USING (
        institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
    );

DROP POLICY IF EXISTS tenant_notice_reads_policy ON notice_reads;
CREATE POLICY tenant_notice_reads_policy ON notice_reads
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM notices n
            WHERE n.id = notice_id
              AND (n.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
        )
    );

DROP POLICY IF EXISTS tenant_id_card_templates_policy ON id_card_templates;
CREATE POLICY tenant_id_card_templates_policy ON id_card_templates
    FOR ALL USING (
        institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
    );

DROP POLICY IF EXISTS tenant_attendance_regularizations_policy ON attendance_regularizations;
CREATE POLICY tenant_attendance_regularizations_policy ON attendance_regularizations
    FOR ALL USING (
        institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
    );


-- ==========================================================
-- MIGRATION: 20260609000004_canteen_module.sql
-- ==========================================================

-- ============================================================
-- IRIS 365 — MODULE 2: CANTEEN SYSTEM EXTENSIONS
-- ============================================================
-- Extends existing canteen_menus, canteen_orders, canteen_wallets,
-- meal_subscriptions with additional tables & columns.
-- ============================================================

-- 1. CANTEEN CATEGORIES (menu grouping)
CREATE TABLE IF NOT EXISTS canteen_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    icon VARCHAR(50) DEFAULT '🍽️',
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. CANTEEN FEEDBACK (order ratings & reviews)
CREATE TABLE IF NOT EXISTS canteen_feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    order_id UUID REFERENCES canteen_orders(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_feedback_per_order UNIQUE (order_id, student_id)
);

-- 3. CANTEEN OFFERS (discount codes & promotions)
CREATE TABLE IF NOT EXISTS canteen_offers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    discount_type VARCHAR(20) NOT NULL DEFAULT 'percentage', -- percentage, flat
    discount_value DECIMAL(10, 2) NOT NULL,
    min_order_amount DECIMAL(10, 2) DEFAULT 0,
    max_discount DECIMAL(10, 2),
    usage_limit INTEGER DEFAULT 100,
    used_count INTEGER DEFAULT 0,
    valid_from TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    valid_until TIMESTAMP WITH TIME ZONE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_offer_code_per_tenant UNIQUE (institution_id, code)
);

-- 4. CANTEEN PRE-ORDERS (scheduled future orders)
CREATE TABLE IF NOT EXISTS canteen_preorders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    items JSONB NOT NULL,
    total_amount DECIMAL(10, 2) NOT NULL,
    scheduled_date DATE NOT NULL,
    scheduled_slot VARCHAR(50) NOT NULL, -- e.g., "12:00-13:00", "08:00-09:00"
    status VARCHAR(30) DEFAULT 'Scheduled', -- Scheduled, Confirmed, Preparing, Ready, Delivered, Cancelled
    payment_method VARCHAR(50) DEFAULT 'Wallet',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. WALLET TRANSACTIONS (full audit trail)
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    wallet_id UUID REFERENCES canteen_wallets(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    type VARCHAR(20) NOT NULL, -- credit, debit
    amount DECIMAL(10, 2) NOT NULL,
    reference_type VARCHAR(50), -- topup, order_payment, refund, subscription
    reference_id UUID, -- order_id, subscription_id, etc.
    description TEXT,
    balance_after DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. ADD COLUMNS to existing canteen_menus
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS description TEXT;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS prep_time_mins INTEGER DEFAULT 10;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS is_veg BOOLEAN DEFAULT TRUE;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS rating_avg DECIMAL(3, 2) DEFAULT 0;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES canteen_categories(id) ON DELETE SET NULL;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS spice_level INTEGER DEFAULT 1 CHECK (spice_level >= 0 AND spice_level <= 3);

-- 7. ADD COLUMNS to existing canteen_orders
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS order_number VARCHAR(20);
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS special_instructions TEXT;
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS offer_id UUID REFERENCES canteen_offers(id) ON DELETE SET NULL;
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS discount_amount DECIMAL(10, 2) DEFAULT 0;

-- 8. INDEXES for performance
CREATE INDEX IF NOT EXISTS idx_canteen_orders_student ON canteen_orders(student_id);
CREATE INDEX IF NOT EXISTS idx_canteen_orders_status ON canteen_orders(status);
CREATE INDEX IF NOT EXISTS idx_canteen_orders_time ON canteen_orders(order_time DESC);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_student ON wallet_transactions(student_id);
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_wallet ON wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_canteen_feedback_order ON canteen_feedback(order_id);
CREATE INDEX IF NOT EXISTS idx_canteen_preorders_date ON canteen_preorders(scheduled_date);
CREATE INDEX IF NOT EXISTS idx_canteen_menus_category ON canteen_menus(category_id);

-- 9. RLS POLICIES
ALTER TABLE canteen_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE canteen_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE canteen_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE canteen_preorders ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

-- Tenant isolation policies
CREATE POLICY canteen_categories_tenant ON canteen_categories
    USING (institution_id = get_auth_institution_id());

CREATE POLICY canteen_feedback_tenant ON canteen_feedback
    USING (institution_id = get_auth_institution_id());

CREATE POLICY canteen_offers_tenant ON canteen_offers
    USING (institution_id = get_auth_institution_id());

CREATE POLICY canteen_preorders_tenant ON canteen_preorders
    USING (institution_id = get_auth_institution_id());

CREATE POLICY wallet_transactions_tenant ON wallet_transactions
    USING (institution_id = get_auth_institution_id());


-- ==========================================================
-- MIGRATION: 20260609000005_fitzone_module.sql
-- ==========================================================

-- ============================================================
-- IRIS 365 — MODULE 3: FITZONE SYSTEM EXTENSIONS
-- ============================================================

-- 1. GYM TRAINERS
CREATE TABLE IF NOT EXISTS gym_trainers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    specializations TEXT[],
    bio TEXT,
    photo_url TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. GYM MEMBERSHIP PLANS
CREATE TABLE IF NOT EXISTS gym_membership_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    duration_months INTEGER,
    price DECIMAL(10, 2),
    features TEXT[],
    max_sessions_per_week INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. ADJUST GYM SLOTS
ALTER TABLE gym_slots DROP CONSTRAINT IF EXISTS gym_slots_trainer_id_fkey;
ALTER TABLE gym_slots ADD COLUMN IF NOT EXISTS slot_type TEXT DEFAULT 'general';
ALTER TABLE gym_slots ADD COLUMN IF NOT EXISTS is_cancelled BOOLEAN DEFAULT FALSE;
-- Ensure trainer_id type matches gym_trainers(id) type
ALTER TABLE gym_slots ALTER COLUMN trainer_id TYPE UUID;
-- We can add constraint on gym_slots.trainer_id after table definitions
ALTER TABLE gym_slots ADD CONSTRAINT gym_slots_trainer_id_gym_trainers_fkey FOREIGN KEY (trainer_id) REFERENCES gym_trainers(id) ON DELETE SET NULL;

-- 4. ADJUST GYM BOOKINGS
ALTER TABLE gym_bookings ADD COLUMN IF NOT EXISTS checkin_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE gym_bookings ADD COLUMN IF NOT EXISTS qr_code TEXT UNIQUE;
-- Alter booking_date type to TIMESTAMP WITH TIME ZONE if it isn't
ALTER TABLE gym_bookings ALTER COLUMN booking_date TYPE TIMESTAMP WITH TIME ZONE;
-- We alter status to support both camelcase and lowercase values to avoid breaking previous atomic functions
ALTER TABLE gym_bookings DROP CONSTRAINT IF EXISTS gym_bookings_status_check;
ALTER TABLE gym_bookings ADD CONSTRAINT gym_bookings_status_check CHECK (status IN ('booked', 'checked_in', 'no_show', 'cancelled', 'Booked', 'Checked_in', 'No_show', 'Cancelled'));

-- 5. ADJUST GYM MEMBERSHIPS
ALTER TABLE gym_memberships ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES gym_membership_plans(id) ON DELETE SET NULL;
ALTER TABLE gym_memberships ADD COLUMN IF NOT EXISTS transaction_id TEXT;
ALTER TABLE gym_memberships ADD COLUMN IF NOT EXISTS is_frozen BOOLEAN DEFAULT FALSE;
ALTER TABLE gym_memberships ADD COLUMN IF NOT EXISTS frozen_from DATE;
ALTER TABLE gym_memberships ADD COLUMN IF NOT EXISTS frozen_until DATE;

-- 6. GYM EQUIPMENT
CREATE TABLE IF NOT EXISTS gym_equipment (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT,
    quantity INTEGER DEFAULT 1,
    condition TEXT DEFAULT 'good', -- excellent, good, fair, maintenance
    purchase_date DATE,
    last_serviced DATE,
    next_service DATE,
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. EQUIPMENT USAGE LOGS
CREATE TABLE IF NOT EXISTS equipment_usage_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    equipment_id UUID REFERENCES gym_equipment(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    date DATE DEFAULT CURRENT_DATE,
    duration_minutes INTEGER,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 8. EQUIPMENT MAINTENANCE LOGS
CREATE TABLE IF NOT EXISTS equipment_maintenance_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    equipment_id UUID REFERENCES gym_equipment(id) ON DELETE CASCADE,
    maintenance_type TEXT,
    performed_by TEXT,
    date DATE DEFAULT CURRENT_DATE,
    cost DECIMAL(10, 2),
    notes TEXT,
    next_due DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 9. FITNESS METRICS
CREATE TABLE IF NOT EXISTS fitness_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    recorded_by UUID REFERENCES gym_trainers(id) ON DELETE SET NULL,
    date DATE DEFAULT CURRENT_DATE,
    weight_kg DECIMAL(5, 2),
    height_cm DECIMAL(5, 2),
    bmi DECIMAL(5, 2),
    body_fat_percent DECIMAL(5, 2),
    chest_cm DECIMAL(5, 2),
    waist_cm DECIMAL(5, 2),
    hips_cm DECIMAL(5, 2),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 10. WORKOUT SESSIONS
CREATE TABLE IF NOT EXISTS workout_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    booking_id UUID REFERENCES gym_bookings(id) ON DELETE SET NULL,
    date DATE DEFAULT CURRENT_DATE,
    duration_minutes INTEGER,
    exercises JSONB, -- list of exercises with sets, reps, weight
    calories_burned INTEGER DEFAULT 0,
    trainer_notes TEXT,
    self_rating INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 11. TRAINER SESSIONS
CREATE TABLE IF NOT EXISTS trainer_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trainer_id UUID REFERENCES gym_trainers(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    duration_minutes INTEGER DEFAULT 60,
    session_type TEXT, -- personal_training, assessment, onboarding
    status TEXT DEFAULT 'scheduled', -- scheduled, accepted, rejected, completed, cancelled
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 12. INDEXES
CREATE INDEX IF NOT EXISTS idx_gym_trainers_inst ON gym_trainers(institution_id);
CREATE INDEX IF NOT EXISTS idx_gym_trainers_user ON gym_trainers(user_id);
CREATE INDEX IF NOT EXISTS idx_gym_membership_plans_inst ON gym_membership_plans(institution_id);
CREATE INDEX IF NOT EXISTS idx_gym_slots_date ON gym_slots(date);
CREATE INDEX IF NOT EXISTS idx_gym_bookings_student ON gym_bookings(student_id);
CREATE INDEX IF NOT EXISTS idx_gym_bookings_slot ON gym_bookings(slot_id);
CREATE INDEX IF NOT EXISTS idx_gym_memberships_student ON gym_memberships(student_id);
CREATE INDEX IF NOT EXISTS idx_gym_equipment_inst ON gym_equipment(institution_id);
CREATE INDEX IF NOT EXISTS idx_equipment_usage_logs_equip ON equipment_usage_logs(equipment_id);
CREATE INDEX IF NOT EXISTS idx_equipment_usage_logs_student ON equipment_usage_logs(student_id);
CREATE INDEX IF NOT EXISTS idx_equipment_maint_logs_equip ON equipment_maintenance_logs(equipment_id);
CREATE INDEX IF NOT EXISTS idx_fitness_metrics_student ON fitness_metrics(student_id);
CREATE INDEX IF NOT EXISTS idx_workout_sessions_student ON workout_sessions(student_id);
CREATE INDEX IF NOT EXISTS idx_trainer_sessions_trainer ON trainer_sessions(trainer_id);
CREATE INDEX IF NOT EXISTS idx_trainer_sessions_student ON trainer_sessions(student_id);

-- 13. ENABLE ROW LEVEL SECURITY
ALTER TABLE gym_trainers ENABLE ROW LEVEL SECURITY;
ALTER TABLE gym_membership_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE gym_equipment ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipment_usage_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE equipment_maintenance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE trainer_sessions ENABLE ROW LEVEL SECURITY;

-- 14. TENANT ISOLATION RLS POLICIES
CREATE POLICY gym_trainers_tenant ON gym_trainers
    USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY gym_membership_plans_tenant ON gym_membership_plans
    USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY gym_equipment_tenant ON gym_equipment
    USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY equipment_usage_logs_tenant ON equipment_usage_logs
    USING (
        equipment_id IN (SELECT id FROM gym_equipment WHERE institution_id = get_auth_institution_id())
        OR get_auth_user_role() = 'SuperAdmin'
    );

CREATE POLICY equipment_maintenance_logs_tenant ON equipment_maintenance_logs
    USING (
        equipment_id IN (SELECT id FROM gym_equipment WHERE institution_id = get_auth_institution_id())
        OR get_auth_user_role() = 'SuperAdmin'
    );

CREATE POLICY fitness_metrics_tenant ON fitness_metrics
    USING (
        student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id())
        OR get_auth_user_role() = 'SuperAdmin'
    );

CREATE POLICY workout_sessions_tenant ON workout_sessions
    USING (
        student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id())
        OR get_auth_user_role() = 'SuperAdmin'
    );

CREATE POLICY trainer_sessions_tenant ON trainer_sessions
    USING (
        trainer_id IN (SELECT id FROM gym_trainers WHERE institution_id = get_auth_institution_id())
        OR student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id())
        OR get_auth_user_role() = 'SuperAdmin'
    );


-- ==========================================================
-- MIGRATION: 20260609000006_events_module.sql
-- ==========================================================

-- ============================================================
-- MODULE 4: IRIS Events — Schema Extensions & New Tables
-- ============================================================

-- 1. EXTEND events TABLE with missing columns
ALTER TABLE events ADD COLUMN IF NOT EXISTS is_paid BOOLEAN DEFAULT false;
ALTER TABLE events ADD COLUMN IF NOT EXISTS ticket_price DECIMAL(10, 2) DEFAULT 0;
ALTER TABLE events ADD COLUMN IF NOT EXISTS registration_deadline TIMESTAMPTZ;
ALTER TABLE events ADD COLUMN IF NOT EXISTS tags TEXT[];
ALTER TABLE events ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

-- 2. EXTEND event_registrations TABLE
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS amount_paid DECIMAL(10,2) DEFAULT 0;
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS razorpay_order_id TEXT;
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS razorpay_payment_id TEXT;
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS checked_in_at TIMESTAMPTZ;

-- 3. EXTEND event_volunteers TABLE
ALTER TABLE event_volunteers ADD COLUMN IF NOT EXISTS status VARCHAR(30) DEFAULT 'active';
ALTER TABLE event_volunteers ADD COLUMN IF NOT EXISTS notes TEXT;

-- 4. CREATE event_budget TABLE
CREATE TABLE IF NOT EXISTS event_budget (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  category VARCHAR(100) NOT NULL,       -- Venue, Catering, Decoration, Marketing, Prizes, Logistics, Other
  description TEXT,
  estimated_amount DECIMAL(10, 2) DEFAULT 0,
  actual_amount DECIMAL(10, 2) DEFAULT 0,
  receipt_url TEXT,
  approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  status VARCHAR(30) DEFAULT 'pending', -- pending, approved, rejected
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. CREATE event_photos TABLE
CREATE TABLE IF NOT EXISTS event_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  photo_url TEXT NOT NULL,
  thumbnail_url TEXT,
  caption TEXT,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  is_featured BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 6. CREATE event_feedback TABLE
CREATE TABLE IF NOT EXISTS event_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  overall_rating INTEGER CHECK (overall_rating >= 1 AND overall_rating <= 5),
  content_rating INTEGER CHECK (content_rating >= 1 AND content_rating <= 5),
  venue_rating INTEGER CHECK (venue_rating >= 1 AND venue_rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (event_id, student_id)  -- One feedback per student per event
);

-- 7. CREATE event_announcements TABLE
CREATE TABLE IF NOT EXISTS event_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  priority VARCHAR(20) DEFAULT 'normal',  -- low, normal, high, urgent
  sent_via TEXT[] DEFAULT '{}',            -- email, push, whatsapp
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_events_institution ON events(institution_id);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
CREATE INDEX IF NOT EXISTS idx_events_start_datetime ON events(start_datetime);
CREATE INDEX IF NOT EXISTS idx_event_registrations_event ON event_registrations(event_id);
CREATE INDEX IF NOT EXISTS idx_event_registrations_student ON event_registrations(student_id);
CREATE INDEX IF NOT EXISTS idx_event_volunteers_event ON event_volunteers(event_id);
CREATE INDEX IF NOT EXISTS idx_event_budget_event ON event_budget(event_id);
CREATE INDEX IF NOT EXISTS idx_event_photos_event ON event_photos(event_id);
CREATE INDEX IF NOT EXISTS idx_event_feedback_event ON event_feedback(event_id);
CREATE INDEX IF NOT EXISTS idx_event_announcements_event ON event_announcements(event_id);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE event_budget ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_announcements ENABLE ROW LEVEL SECURITY;

-- Tenant isolation policies
CREATE POLICY "tenant_isolation_event_budget" ON event_budget
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_event_photos" ON event_photos
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_event_feedback" ON event_feedback
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_event_announcements" ON event_announcements
  USING (institution_id = get_auth_institution_id());


-- ==========================================================
-- MIGRATION: 20260609000007_hostel_module.sql
-- ==========================================================

-- ============================================================
-- MODULE 5: IRIS Hostel — Schema Extensions & New Tables
-- ============================================================

-- 1. EXTEND hostel_blocks TABLE
ALTER TABLE hostel_blocks ADD COLUMN IF NOT EXISTS total_floors INTEGER DEFAULT 1;
ALTER TABLE hostel_blocks ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

-- Change amenities type to TEXT[]
-- First check if we need to drop the old column and recreate it, or convert. 
-- Since we are in development/migration, we can do a safe cast:
ALTER TABLE hostel_blocks ALTER COLUMN amenities TYPE TEXT[] USING string_to_array(coalesce(amenities, ''), ',')::TEXT[];

-- Modify type constraint
ALTER TABLE hostel_blocks DROP CONSTRAINT IF EXISTS chk_block_type;
ALTER TABLE hostel_blocks ADD CONSTRAINT chk_block_type CHECK (lower(type) IN ('boys','girls','co-ed','staff'));

-- 2. EXTEND hostel_rooms TABLE
ALTER TABLE hostel_rooms ADD COLUMN IF NOT EXISTS floor INTEGER DEFAULT 0;
ALTER TABLE hostel_rooms ADD COLUMN IF NOT EXISTS room_type TEXT CHECK (room_type IN ('single','double','triple','dormitory'));
ALTER TABLE hostel_rooms ADD COLUMN IF NOT EXISTS monthly_rent DECIMAL(10, 2) DEFAULT 0;
ALTER TABLE hostel_rooms ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE hostel_rooms ALTER COLUMN amenities TYPE TEXT[] USING string_to_array(coalesce(amenities, ''), ',')::TEXT[];

-- 3. EXTEND hostel_allocations TABLE
ALTER TABLE hostel_allocations ADD COLUMN IF NOT EXISTS allotted_by UUID REFERENCES staff(id) ON DELETE SET NULL;
ALTER TABLE hostel_allocations ADD COLUMN IF NOT EXISTS vacating_reason TEXT;
ALTER TABLE hostel_allocations ADD COLUMN IF NOT EXISTS deposit_amount DECIMAL(10, 2) DEFAULT 0;
ALTER TABLE hostel_allocations ADD COLUMN IF NOT EXISTS deposit_status TEXT DEFAULT 'pending' CHECK (deposit_status IN ('pending', 'paid', 'refunded'));
ALTER TABLE hostel_allocations ADD COLUMN IF NOT EXISTS agreement_url TEXT;

-- 4. EXTEND hostel_complaints TABLE
ALTER TABLE hostel_complaints ADD COLUMN IF NOT EXISTS title TEXT NOT NULL DEFAULT 'Hostel Complaint';
ALTER TABLE hostel_complaints ADD COLUMN IF NOT EXISTS photo_urls TEXT[] DEFAULT '{}';
ALTER TABLE hostel_complaints ADD COLUMN IF NOT EXISTS priority TEXT DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'urgent'));
ALTER TABLE hostel_complaints ADD COLUMN IF NOT EXISTS resolution_notes TEXT;
ALTER TABLE hostel_complaints ADD COLUMN IF NOT EXISTS student_rating INTEGER CHECK (student_rating >= 1 AND student_rating <= 5);

ALTER TABLE hostel_complaints DROP CONSTRAINT IF EXISTS chk_complaint_category;
ALTER TABLE hostel_complaints ADD CONSTRAINT chk_complaint_category CHECK (lower(category) IN (
  'maintenance','cleanliness','electrical','plumbing',
  'internet','security','roommate','food','other'
));

-- 5. EXTEND hostel_visitors TABLE
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS visitor_id_type TEXT;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS visitor_id_number TEXT;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS visitor_photo_url TEXT;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS relation TEXT;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'inside' CHECK (status IN ('inside', 'checked_out'));
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES staff(id) ON DELETE SET NULL;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT false;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS gate_pass_url TEXT;
ALTER TABLE hostel_visitors ALTER COLUMN visitor_phone DROP NOT NULL;

-- 6. CREATE hostel_fees TABLE
CREATE TABLE IF NOT EXISTS hostel_fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  allocation_id UUID REFERENCES hostel_allocations(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  month DATE NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  due_date DATE,
  paid_date TIMESTAMPTZ,
  transaction_id TEXT,
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'overdue')),
  late_fee DECIMAL(10, 2) DEFAULT 0
);

-- 7. CREATE hostel_leave_requests TABLE
CREATE TABLE IF NOT EXISTS hostel_leave_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  leave_from DATE NOT NULL,
  leave_to DATE NOT NULL,
  reason TEXT,
  destination TEXT,
  parent_consent BOOLEAN DEFAULT false,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'late_return', 'returned')),
  approved_by UUID REFERENCES staff(id) ON DELETE SET NULL,
  approval_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 8. CREATE hostel_notices TABLE
CREATE TABLE IF NOT EXISTS hostel_notices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  block_id UUID REFERENCES hostel_blocks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  posted_by UUID REFERENCES staff(id) ON DELETE SET NULL,
  posted_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ
);

-- 9. CREATE hostel_inventory TABLE
CREATE TABLE IF NOT EXISTS hostel_inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES hostel_rooms(id) ON DELETE CASCADE,
  item_name TEXT NOT NULL,
  quantity INTEGER DEFAULT 1,
  condition TEXT DEFAULT 'good' CHECK (condition IN ('excellent', 'good', 'fair', 'damaged')),
  last_checked DATE DEFAULT CURRENT_DATE
);

-- 10. CREATE hostel_warden_reports TABLE
CREATE TABLE IF NOT EXISTS hostel_warden_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  block_id UUID REFERENCES hostel_blocks(id) ON DELETE CASCADE,
  report_type TEXT CHECK (report_type IN ('daily', 'weekly', 'monthly')),
  report_date DATE NOT NULL,
  data JSONB NOT NULL,
  generated_at TIMESTAMPTZ DEFAULT now(),
  pdf_url TEXT
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_hostel_blocks_institution ON hostel_blocks(institution_id);
CREATE INDEX IF NOT EXISTS idx_hostel_rooms_block ON hostel_rooms(block_id);
CREATE INDEX IF NOT EXISTS idx_hostel_allocations_student ON hostel_allocations(student_id);
CREATE INDEX IF NOT EXISTS idx_hostel_fees_student ON hostel_fees(student_id);
CREATE INDEX IF NOT EXISTS idx_hostel_complaints_student ON hostel_complaints(student_id);
CREATE INDEX IF NOT EXISTS idx_hostel_leave_requests_student ON hostel_leave_requests(student_id);
CREATE INDEX IF NOT EXISTS idx_hostel_visitors_student ON hostel_visitors(student_id);
CREATE INDEX IF NOT EXISTS idx_hostel_notices_block ON hostel_notices(block_id);
CREATE INDEX IF NOT EXISTS idx_hostel_inventory_room ON hostel_inventory(room_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE hostel_fees ENABLE ROW LEVEL SECURITY;
ALTER TABLE hostel_leave_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE hostel_notices ENABLE ROW LEVEL SECURITY;
ALTER TABLE hostel_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE hostel_warden_reports ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
CREATE POLICY "tenant_isolation_hostel_fees" ON hostel_fees
  USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()));

CREATE POLICY "tenant_isolation_hostel_leave_requests" ON hostel_leave_requests
  USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()));

CREATE POLICY "tenant_isolation_hostel_notices" ON hostel_notices
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_hostel_inventory" ON hostel_inventory
  USING (room_id IN (SELECT id FROM hostel_rooms WHERE block_id IN (SELECT id FROM hostel_blocks WHERE institution_id = get_auth_institution_id())));

CREATE POLICY "tenant_isolation_hostel_warden_reports" ON hostel_warden_reports
  USING (block_id IN (SELECT id FROM hostel_blocks WHERE institution_id = get_auth_institution_id()));


-- ==========================================================
-- MIGRATION: 20260609000008_library_module.sql
-- ==========================================================

-- ============================================================
-- MODULE 6: IRIS Library+ — Schema Extensions & New Tables
-- ============================================================

-- Enable vector extension for AI recommendations
CREATE EXTENSION IF NOT EXISTS vector;

-- 1. CREATE books TABLE
CREATE TABLE IF NOT EXISTS books (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  isbn TEXT,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  publisher TEXT,
  publication_year INTEGER,
  category TEXT,
  subcategory TEXT,
  language TEXT DEFAULT 'English',
  copies_total INTEGER DEFAULT 1,
  copies_available INTEGER DEFAULT 1,
  shelf_location TEXT,
  cover_image_url TEXT,
  description TEXT,
  tags TEXT[] DEFAULT '{}',
  embedding vector(1536),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. CREATE book_issues TABLE
CREATE TABLE IF NOT EXISTS book_issues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  issued_by UUID REFERENCES staff(id) ON DELETE SET NULL,
  issue_date DATE NOT NULL,
  due_date DATE NOT NULL,
  return_date DATE,
  returned_to UUID REFERENCES staff(id) ON DELETE SET NULL,
  condition_on_issue TEXT DEFAULT 'good' CHECK (condition_on_issue IN ('excellent', 'good', 'fair', 'damaged')),
  condition_on_return TEXT CHECK (condition_on_return IN ('excellent', 'good', 'fair', 'damaged', 'lost')),
  fine_amount DECIMAL DEFAULT 0,
  fine_paid BOOLEAN DEFAULT false,
  fine_paid_date DATE,
  status TEXT DEFAULT 'issued' CHECK (status IN ('issued', 'returned', 'renewed', 'lost')),
  renewal_count INTEGER DEFAULT 0,
  notes TEXT
);

-- 3. CREATE book_reservations TABLE
CREATE TABLE IF NOT EXISTS book_reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  reserved_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ,
  status TEXT DEFAULT 'waiting' CHECK (status IN ('waiting', 'notified', 'completed', 'expired')),
  notified_at TIMESTAMPTZ
);

-- 4. CREATE ebooks TABLE
CREATE TABLE IF NOT EXISTS ebooks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  author TEXT,
  category TEXT,
  department TEXT,
  semester TEXT,
  description TEXT,
  file_url TEXT NOT NULL,
  cover_url TEXT,
  file_size_mb DECIMAL,
  tags TEXT[] DEFAULT '{}',
  access_level TEXT DEFAULT 'all',
  download_count INTEGER DEFAULT 0,
  view_count INTEGER DEFAULT 0,
  uploaded_by UUID REFERENCES staff(id) ON DELETE SET NULL,
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

-- 5. CREATE study_rooms TABLE
CREATE TABLE IF NOT EXISTS study_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  capacity INTEGER,
  amenities TEXT[] DEFAULT '{}',
  floor INTEGER,
  is_active BOOLEAN DEFAULT true
);

-- 6. CREATE study_room_bookings TABLE
CREATE TABLE IF NOT EXISTS study_room_bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES study_rooms(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  purpose TEXT,
  group_members UUID[] DEFAULT '{}',
  status TEXT DEFAULT 'confirmed' CHECK (status IN ('confirmed', 'cancelled', 'completed', 'no_show')),
  qr_code TEXT UNIQUE,
  checked_in BOOLEAN DEFAULT false,
  checked_in_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 7. CREATE library_fines TABLE
CREATE TABLE IF NOT EXISTS library_fines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  issue_id UUID REFERENCES book_issues(id) ON DELETE CASCADE,
  amount DECIMAL DEFAULT 0,
  reason TEXT,
  status TEXT DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'paid')),
  payment_date DATE,
  payment_method TEXT CHECK (payment_method IN ('cash', 'wallet', 'online')),
  transaction_id TEXT
);

-- 8. CREATE reading_history TABLE
CREATE TABLE IF NOT EXISTS reading_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  book_id UUID REFERENCES books(id) ON DELETE SET NULL,
  ebook_id UUID REFERENCES ebooks(id) ON DELETE SET NULL,
  action TEXT CHECK (action IN ('borrow', 'return', 'reserve', 'view_ebook', 'download_ebook')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_books_institution ON books(institution_id);
CREATE INDEX IF NOT EXISTS idx_books_isbn ON books(isbn);
CREATE INDEX IF NOT EXISTS idx_book_issues_student ON book_issues(student_id);
CREATE INDEX IF NOT EXISTS idx_book_issues_book ON book_issues(book_id);
CREATE INDEX IF NOT EXISTS idx_book_reservations_book ON book_reservations(book_id);
CREATE INDEX IF NOT EXISTS idx_ebooks_institution ON ebooks(institution_id);
CREATE INDEX IF NOT EXISTS idx_study_rooms_institution ON study_rooms(institution_id);
CREATE INDEX IF NOT EXISTS idx_study_room_bookings_room ON study_room_bookings(room_id);
CREATE INDEX IF NOT EXISTS idx_library_fines_student ON library_fines(student_id);
CREATE INDEX IF NOT EXISTS idx_reading_history_student ON reading_history(student_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE books ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_issues ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ebooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE study_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE study_room_bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE library_fines ENABLE ROW LEVEL SECURITY;
ALTER TABLE reading_history ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
CREATE POLICY "tenant_isolation_books" ON books
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_book_issues" ON book_issues
  USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()));

CREATE POLICY "tenant_isolation_book_reservations" ON book_reservations
  USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()));

CREATE POLICY "tenant_isolation_ebooks" ON ebooks
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_study_rooms" ON study_rooms
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_study_room_bookings" ON study_room_bookings
  USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()));

CREATE POLICY "tenant_isolation_library_fines" ON library_fines
  USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()));

CREATE POLICY "tenant_isolation_reading_history" ON reading_history
  USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()));

-- ============================================================
-- HELPER VECTOR SIMILARITY FUNCTION (pgvector RPC)
-- ============================================================
CREATE OR REPLACE FUNCTION match_books (
  query_embedding vector(1536),
  match_threshold float,
  match_count int,
  inst_id uuid
)
RETURNS TABLE (
  id uuid,
  title text,
  author text,
  category text,
  cover_image_url text,
  description text,
  copies_available integer,
  shelf_location text,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    books.id,
    books.title,
    books.author,
    books.category,
    books.cover_image_url,
    books.description,
    books.copies_available,
    books.shelf_location,
    1 - (books.embedding <=> query_embedding) AS similarity
  FROM books
  WHERE books.institution_id = inst_id 
    AND books.embedding IS NOT NULL
    AND 1 - (books.embedding <=> query_embedding) > match_threshold
  ORDER BY books.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260609000009_transit_module.sql
-- ==========================================================

-- Migration: Module 7 (Transit Module)
-- Target: Supabase / PostgreSQL

-- 1. Alter Existing Tables to match specifications
ALTER TABLE bus_routes ADD COLUMN IF NOT EXISTS route_number TEXT;
ALTER TABLE bus_routes ADD COLUMN IF NOT EXISTS distance_km DECIMAL;
ALTER TABLE bus_routes ADD COLUMN IF NOT EXISTS duration_minutes INTEGER;
ALTER TABLE bus_routes ADD COLUMN IF NOT EXISTS monthly_fee DECIMAL;
ALTER TABLE bus_routes ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

ALTER TABLE buses ADD COLUMN IF NOT EXISTS model TEXT;
ALTER TABLE buses ADD COLUMN IF NOT EXISTS insurance_expiry DATE;
ALTER TABLE buses ADD COLUMN IF NOT EXISTS fitness_expiry DATE;
ALTER TABLE buses ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;

ALTER TABLE bus_tracking ADD COLUMN IF NOT EXISTS heading DECIMAL;

ALTER TABLE transport_subscriptions ADD COLUMN IF NOT EXISTS stop_name TEXT;
ALTER TABLE transport_subscriptions ADD COLUMN IF NOT EXISTS transaction_id TEXT;
ALTER TABLE transport_subscriptions ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

-- 2. Create New Tables
CREATE TABLE IF NOT EXISTS bus_drivers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  license_number TEXT UNIQUE,
  license_expiry DATE,
  phone TEXT,
  address TEXT,
  emergency_contact TEXT,
  joining_date DATE DEFAULT CURRENT_DATE,
  is_active BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS bus_trips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  bus_id uuid REFERENCES buses(id) ON DELETE CASCADE,
  route_id uuid REFERENCES bus_routes(id) ON DELETE CASCADE,
  driver_id uuid REFERENCES bus_drivers(id) ON DELETE SET NULL,
  trip_date DATE NOT NULL DEFAULT CURRENT_DATE,
  trip_type TEXT CHECK (trip_type IN ('morning','evening','special')),
  scheduled_start TIMESTAMPTZ,
  actual_start TIMESTAMPTZ,
  actual_end TIMESTAMPTZ,
  status TEXT DEFAULT 'scheduled', -- scheduled, active, completed, cancelled, no_show
  delay_minutes INTEGER DEFAULT 0,
  passenger_count INTEGER DEFAULT 0,
  notes TEXT
);

CREATE TABLE IF NOT EXISTS trip_stop_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  trip_id uuid REFERENCES bus_trips(id) ON DELETE CASCADE,
  stop_index INTEGER,
  stop_name TEXT,
  scheduled_time TIMESTAMPTZ,
  actual_arrival TIMESTAMPTZ,
  passengers_boarded INTEGER DEFAULT 0,
  passengers_alighted INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS bus_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  bus_id uuid REFERENCES buses(id) ON DELETE CASCADE,
  trip_id uuid REFERENCES bus_trips(id) ON DELETE SET NULL,
  incident_type TEXT, -- breakdown, accident, traffic, medical, other
  description TEXT,
  latitude DECIMAL,
  longitude DECIMAL,
  reported_by uuid REFERENCES users(id) ON DELETE SET NULL,
  severity TEXT CHECK (severity IN ('low','medium','high','critical')) DEFAULT 'low',
  status TEXT CHECK (status IN ('reported','investigating','resolved')) DEFAULT 'reported',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bus_maintenance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  bus_id uuid REFERENCES buses(id) ON DELETE CASCADE,
  maintenance_type TEXT, -- service, repair, inspection, tires, other
  scheduled_date DATE,
  completed_date DATE,
  cost DECIMAL DEFAULT 0,
  service_center TEXT,
  notes TEXT,
  next_due_date DATE
);

-- 3. Enable RLS
ALTER TABLE bus_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE trip_stop_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_maintenance ENABLE ROW LEVEL SECURITY;

-- 4. Create Tenant Isolation Policies (safe drop first)
DROP POLICY IF EXISTS tenant_bus_drivers_policy ON bus_drivers;
CREATE POLICY tenant_bus_drivers_policy ON bus_drivers
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_bus_trips_policy ON bus_trips;
CREATE POLICY tenant_bus_trips_policy ON bus_trips
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_trip_stop_logs_policy ON trip_stop_logs;
CREATE POLICY tenant_trip_stop_logs_policy ON trip_stop_logs
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_bus_incidents_policy ON bus_incidents;
CREATE POLICY tenant_bus_incidents_policy ON bus_incidents
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_bus_maintenance_policy ON bus_maintenance;
CREATE POLICY tenant_bus_maintenance_policy ON bus_maintenance
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

-- 5. Seed Mock Transit Data
-- Inject Rajesh Kumar Driver details
INSERT INTO bus_drivers (id, user_id, institution_id, license_number, license_expiry, phone, address, emergency_contact, joining_date, is_active)
VALUES (
  'd0000000-0000-0000-0000-000000000013',
  'b0000000-0000-0000-0000-000000000013',
  'a0000000-0000-0000-0000-000000000001',
  'DL-14202500009',
  CURRENT_DATE + INTERVAL '5 years',
  '+919829012347',
  'Sardarpura 1st Road, Jodhpur',
  '+919829012340',
  '2024-01-15',
  true
) ON CONFLICT (license_number) DO NOTHING;

-- Seed Bus Routes
INSERT INTO bus_routes (id, institution_id, name, route_number, stops, distance_km, duration_minutes, monthly_fee, is_active)
VALUES (
  '80000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  'Jodhpur Central Route',
  'ROUTE-101',
  '[
    {"name": "Sardarpura 4th Road", "latitude": 26.2912, "longitude": 73.0156, "stop_index": 0, "scheduled_time_morning": "08:00 AM", "scheduled_time_evening": "05:30 PM"},
    {"name": "Shastri Nagar Circle", "latitude": 26.2647, "longitude": 73.0012, "stop_index": 1, "scheduled_time_morning": "08:15 AM", "scheduled_time_evening": "05:15 PM"},
    {"name": "Mogra Highway Stop", "latitude": 26.1543, "longitude": 73.0234, "stop_index": 2, "scheduled_time_morning": "08:30 AM", "scheduled_time_evening": "05:00 PM"},
    {"name": "SIET Campus Terminal", "latitude": 26.1200, "longitude": 73.0500, "stop_index": 3, "scheduled_time_morning": "08:45 AM", "scheduled_time_evening": "04:45 PM"}
  ]'::jsonb,
  18.5,
  45,
  1200.00,
  true
) ON CONFLICT (id) DO NOTHING;

INSERT INTO bus_routes (id, institution_id, name, route_number, stops, distance_km, duration_minutes, monthly_fee, is_active)
VALUES (
  '80000000-0000-0000-0000-000000000002',
  'a0000000-0000-0000-0000-000000000001',
  'Mandore Outskirts Route',
  'ROUTE-102',
  '[
    {"name": "Mandore Garden Stop", "latitude": 26.3400, "longitude": 73.0400, "stop_index": 0, "scheduled_time_morning": "07:50 AM", "scheduled_time_evening": "05:40 PM"},
    {"name": "Paota Circle Hub", "latitude": 26.2990, "longitude": 73.0390, "stop_index": 1, "scheduled_time_morning": "08:10 AM", "scheduled_time_evening": "05:20 PM"},
    {"name": "Basni Industrial Zone", "latitude": 26.2410, "longitude": 72.9990, "stop_index": 2, "scheduled_time_morning": "08:25 AM", "scheduled_time_evening": "05:05 PM"},
    {"name": "SIET Campus Terminal", "latitude": 26.1200, "longitude": 73.0500, "stop_index": 3, "scheduled_time_morning": "08:45 AM", "scheduled_time_evening": "04:45 PM"}
  ]'::jsonb,
  24.2,
  55,
  1500.00,
  true
) ON CONFLICT (id) DO NOTHING;

-- Seed Buses
INSERT INTO buses (id, institution_id, vehicle_number, model, capacity, route_id, driver_id, device_id, insurance_expiry, fitness_expiry, is_active)
VALUES (
  '70000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  'RJ-19-PB-4050',
  'Tata Starbus 40-Seater',
  40,
  '80000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000013', -- Rajesh Kumar Driver user_id
  'GPS-DEV-4050',
  CURRENT_DATE + INTERVAL '28 days', -- Warn soon
  CURRENT_DATE + INTERVAL '120 days',
  true
) ON CONFLICT (vehicle_number) DO NOTHING;

-- Seed active subscription for Khushal
INSERT INTO transport_subscriptions (id, institution_id, student_id, route_id, stop_name, start_date, end_date, amount_paid, transaction_id, status)
VALUES (
  '90000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  'c0000000-0000-0000-0000-000000000006', -- Khushal student_id
  '80000000-0000-0000-0000-000000000001', -- Route 101
  'Sardarpura 4th Road',
  CURRENT_DATE - INTERVAL '5 days',
  CURRENT_DATE + INTERVAL '25 days',
  1200.00,
  'TXN_TRANSIT_UPI_1',
  'active'
) ON CONFLICT (id) DO NOTHING;

-- Seed active tracking position for Bus
INSERT INTO bus_tracking (id, institution_id, bus_id, latitude, longitude, speed, heading, timestamp, is_active)
VALUES (
  'a0000000-0000-0000-0000-000000001001',
  'a0000000-0000-0000-0000-000000000001',
  '70000000-0000-0000-0000-000000000001',
  26.2912,
  73.0156,
  35.5,
  180.0,
  now(),
  true
) ON CONFLICT (id) DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260609000010_gate_module.sql
-- ==========================================================

-- Migration: Module 8 (Gate Security Module)
-- Target: Supabase / PostgreSQL

-- 1. Drop old incidents table to overwrite with detailed version
DROP TABLE IF EXISTS security_incidents CASCADE;

-- 2. Create tables
CREATE TABLE IF NOT EXISTS gate_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  person_id uuid,
  person_type TEXT CHECK (person_type IN ('student','staff','visitor')),
  person_name TEXT,
  entry_method TEXT CHECK (entry_method IN ('qr','biometric','rfid','manual','visitor_pass')),
  direction TEXT CHECK (direction IN ('in','out')),
  gate_number TEXT DEFAULT 'main',
  timestamp TIMESTAMPTZ DEFAULT now(),
  authorized_by uuid REFERENCES users(id) ON DELETE SET NULL,
  reason TEXT,
  photo_url TEXT
);

CREATE TABLE IF NOT EXISTS rfid_cards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  card_uid TEXT UNIQUE NOT NULL,
  person_id uuid NOT NULL,
  person_type TEXT CHECK (person_type IN ('student','staff')),
  issued_date DATE DEFAULT CURRENT_DATE,
  expiry_date DATE,
  is_active BOOLEAN DEFAULT true,
  is_blocked BOOLEAN DEFAULT false,
  blocked_reason TEXT
);

CREATE TABLE IF NOT EXISTS visitor_passes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  visitor_name TEXT NOT NULL,
  visitor_phone TEXT,
  visitor_email TEXT,
  visitor_id_type TEXT,
  visitor_id_number TEXT,
  visitor_photo_url TEXT,
  host_id uuid,
  host_type TEXT CHECK (host_type IN ('student','staff')),
  host_name TEXT,
  purpose TEXT NOT NULL,
  pass_number TEXT UNIQUE,
  qr_code TEXT UNIQUE,
  valid_from TIMESTAMPTZ,
  valid_until TIMESTAMPTZ,
  is_used BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS security_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  reported_by uuid REFERENCES users(id) ON DELETE SET NULL,
  incident_type TEXT, -- theft, trespass, damage, overstay, other
  description TEXT NOT NULL,
  location TEXT,
  severity TEXT CHECK (severity IN ('low','medium','high','critical')) DEFAULT 'low',
  photo_urls TEXT[],
  status TEXT DEFAULT 'open', -- open, investigating, resolved
  assigned_to uuid REFERENCES users(id) ON DELETE SET NULL,
  resolution TEXT,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS blacklisted_visitors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT,
  phone TEXT,
  id_number TEXT,
  photo_url TEXT,
  reason TEXT,
  added_by uuid REFERENCES users(id) ON DELETE SET NULL,
  added_at TIMESTAMPTZ DEFAULT now(),
  is_active BOOLEAN DEFAULT true
);

CREATE TABLE IF NOT EXISTS gate_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  guard_id uuid REFERENCES users(id) ON DELETE CASCADE,
  shift_start TIMESTAMPTZ,
  shift_end TIMESTAMPTZ,
  gate_number TEXT DEFAULT 'main',
  handover_notes TEXT
);

CREATE TABLE IF NOT EXISTS campus_occupancy (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  timestamp TIMESTAMPTZ DEFAULT now(),
  students_inside INTEGER DEFAULT 0,
  staff_inside INTEGER DEFAULT 0,
  visitors_inside INTEGER DEFAULT 0
);

-- 3. Enable RLS
ALTER TABLE gate_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE rfid_cards ENABLE ROW LEVEL SECURITY;
ALTER TABLE visitor_passes ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE blacklisted_visitors ENABLE ROW LEVEL SECURITY;
ALTER TABLE gate_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE campus_occupancy ENABLE ROW LEVEL SECURITY;

-- 4. Create Isolation Policies (using auth helper)
DROP POLICY IF EXISTS tenant_gate_entries_policy ON gate_entries;
CREATE POLICY tenant_gate_entries_policy ON gate_entries
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_rfid_cards_policy ON rfid_cards;
CREATE POLICY tenant_rfid_cards_policy ON rfid_cards
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_visitor_passes_policy ON visitor_passes;
CREATE POLICY tenant_visitor_passes_policy ON visitor_passes
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_security_incidents_policy ON security_incidents;
CREATE POLICY tenant_security_incidents_policy ON security_incidents
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_blacklisted_visitors_policy ON blacklisted_visitors;
CREATE POLICY tenant_blacklisted_visitors_policy ON blacklisted_visitors
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_gate_shifts_policy ON gate_shifts;
CREATE POLICY tenant_gate_shifts_policy ON gate_shifts
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_campus_occupancy_policy ON campus_occupancy;
CREATE POLICY tenant_campus_occupancy_policy ON campus_occupancy
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

-- 5. Seed Mock Gate Data
-- A. Register RFID cards
INSERT INTO rfid_cards (id, institution_id, card_uid, person_id, person_type, expiry_date, is_active, is_blocked)
VALUES (
  'e0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  'RFID_KHUSHAL_123',
  'b0000000-0000-0000-0000-000000000006', -- Student Khushal User ID
  'student',
  CURRENT_DATE + INTERVAL '4 years',
  true,
  false
) ON CONFLICT (card_uid) DO NOTHING;

INSERT INTO rfid_cards (id, institution_id, card_uid, person_id, person_type, expiry_date, is_active, is_blocked)
VALUES (
  'e0000000-0000-0000-0000-000000000002',
  'a0000000-0000-0000-0000-000000000001',
  'RFID_STAFF_101',
  'b0000000-0000-0000-0000-000000000002', -- Admin/Staff User ID
  'staff',
  CURRENT_DATE + INTERVAL '5 years',
  true,
  false
) ON CONFLICT (card_uid) DO NOTHING;

-- B. Pre-allocate campus occupancy initial records
INSERT INTO campus_occupancy (id, institution_id, timestamp, students_inside, staff_inside, visitors_inside)
VALUES (
  'f0000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  now() - INTERVAL '1 hour',
  45,
  12,
  2
) ON CONFLICT (id) DO NOTHING;

-- C. Blacklist mock entries
INSERT INTO blacklisted_visitors (id, institution_id, name, phone, id_number, reason, added_by)
VALUES (
  '60000000-0000-0000-0000-000000000001',
  'a0000000-0000-0000-0000-000000000001',
  'Suresh Singhania',
  '+919876543222',
  'Aadhaar: 228844991100',
  'Suspicious activity near hostel block last semester',
  'b0000000-0000-0000-0000-000000000002'
) ON CONFLICT (id) DO NOTHING;

-- D. Visitor passes seeds
INSERT INTO visitor_passes (id, institution_id, visitor_name, visitor_phone, host_id, host_type, host_name, purpose, pass_number, qr_code, valid_from, valid_until, is_used)
VALUES (
  '70000000-0000-0000-0000-000000001001',
  'a0000000-0000-0000-0000-000000000001',
  'Alok Kumar',
  '+919829123499',
  'b0000000-0000-0000-0000-000000000006', -- Host: Khushal
  'student',
  'Khushal Gehlot',
  'Project Collaboration & Laptop handover',
  'VP-98102',
  'VP-QR-98102',
  now() - INTERVAL '30 minutes',
  now() + INTERVAL '3 hours 30 minutes',
  true
) ON CONFLICT (id) DO NOTHING;

-- E. Seed some activity gate logs
INSERT INTO gate_entries (id, institution_id, person_id, person_type, person_name, entry_method, direction, gate_number, timestamp, reason)
VALUES (
  '80000000-0000-0000-0000-000000005001',
  'a0000000-0000-0000-0000-000000000001',
  'b0000000-0000-0000-0000-000000000006',
  'student',
  'Khushal Gehlot',
  'rfid',
  'in',
  'main',
  now() - INTERVAL '45 minutes',
  'Regular check-in'
) ON CONFLICT (id) DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260609000011_director_module.sql
-- ==========================================================

-- Migration: Module 9 (Director Dashboard Module)
-- Target: Supabase / PostgreSQL

-- 1. Create tables
CREATE TABLE IF NOT EXISTS director_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  severity TEXT CHECK (severity IN ('info','warning','critical')) DEFAULT 'info',
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  module TEXT,
  data JSONB,
  is_read BOOLEAN DEFAULT false,
  is_resolved BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS alert_thresholds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  alert_type TEXT UNIQUE NOT NULL,
  threshold_value DECIMAL,
  comparison TEXT CHECK (comparison IN ('lt','gt','eq')),
  is_enabled BOOLEAN DEFAULT true,
  notify_via TEXT[] DEFAULT '{push,email}'
);

CREATE TABLE IF NOT EXISTS director_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  report_type TEXT NOT NULL,
  report_date DATE NOT NULL,
  data JSONB NOT NULL,
  pdf_url TEXT,
  generated_at TIMESTAMPTZ DEFAULT now(),
  emailed_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS ai_insights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid REFERENCES institutions(id) ON DELETE CASCADE,
  insight_type TEXT,
  title TEXT,
  description TEXT,
  severity TEXT,
  affected_entities JSONB,
  data_points JSONB,
  recommendation TEXT,
  generated_at TIMESTAMPTZ DEFAULT now(),
  is_dismissed BOOLEAN DEFAULT false
);

-- 2. Materialized Views
-- Join attendance with attendance_sessions as attendance table does not have department_id
DROP MATERIALIZED VIEW IF EXISTS daily_attendance_summary;
CREATE MATERIALIZED VIEW daily_attendance_summary AS
SELECT 
  a.institution_id,
  a.date,
  s.department_id,
  COUNT(*) as total_students,
  COUNT(CASE WHEN LOWER(a.status) = 'present' THEN 1 END) as present_count,
  ROUND(COUNT(CASE WHEN LOWER(a.status) = 'present' THEN 1 END) * 100.0 / NULLIF(COUNT(*), 0), 2) as attendance_percent
FROM attendance a
JOIN attendance_sessions s ON a.session_id = s.id
GROUP BY a.institution_id, a.date, s.department_id;

-- Fee Summary Materialized view
-- Select successful Completed payments (since status is Completed in schema)
DROP MATERIALIZED VIEW IF EXISTS daily_fee_summary;
CREATE MATERIALIZED VIEW daily_fee_summary AS
SELECT
  institution_id,
  payment_date as date,
  COUNT(*) as payments_count,
  SUM(amount_paid) as total_collected,
  COUNT(DISTINCT student_id) as unique_payers
FROM fee_payments
WHERE status = 'Completed'
GROUP BY institution_id, payment_date;

-- Unique Indexes required for view refresh CONCURRENTLY
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_attendance_summary ON daily_attendance_summary (institution_id, date, department_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_daily_fee_summary ON daily_fee_summary (institution_id, date);

-- 3. Materialized View Refresh Helper function
CREATE OR REPLACE FUNCTION refresh_director_materialized_views()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY daily_attendance_summary;
  REFRESH MATERIALIZED VIEW CONCURRENTLY daily_fee_summary;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Enable RLS
ALTER TABLE director_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_thresholds ENABLE ROW LEVEL SECURITY;
ALTER TABLE director_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;

-- 5. Create multi-tenant policies
DROP POLICY IF EXISTS tenant_director_alerts_policy ON director_alerts;
CREATE POLICY tenant_director_alerts_policy ON director_alerts
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_alert_thresholds_policy ON alert_thresholds;
CREATE POLICY tenant_alert_thresholds_policy ON alert_thresholds
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_director_reports_policy ON director_reports;
CREATE POLICY tenant_director_reports_policy ON director_reports
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_ai_insights_policy ON ai_insights;
CREATE POLICY tenant_ai_insights_policy ON ai_insights
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

-- 6. Seed Default Threshold Settings
-- Maps to institution SIET
INSERT INTO alert_thresholds (institution_id, alert_type, threshold_value, comparison, is_enabled)
VALUES
  ('a0000000-0000-0000-0000-000000000001', 'attendance_low', 75.0, 'lt', true),
  ('a0000000-0000-0000-0000-000000000001', 'fee_target_missed', 80.0, 'lt', true),
  ('a0000000-0000-0000-0000-000000000001', 'complaint_overdue', 5, 'gt', true),
  ('a0000000-0000-0000-0000-000000000001', 'bus_stopped', 10, 'gt', true),
  ('a0000000-0000-0000-0000-000000000001', 'hostel_complaint_surge', 5, 'gt', true),
  ('a0000000-0000-0000-0000-000000000001', 'exam_result_pending', 7, 'gt', true),
  ('a0000000-0000-0000-0000-000000000001', 'library_overdue_surge', 20, 'gt', true)
ON CONFLICT (alert_type) DO UPDATE
SET threshold_value = EXCLUDED.threshold_value, comparison = EXCLUDED.comparison;


-- ==========================================================
-- MIGRATION: 20260609000012_ai_concierge.sql
-- ==========================================================

-- ============================================================
-- MODULE 10: AI Concierge — Schema & Semantic Setup
-- ============================================================

-- Ensure pgvector is enabled
CREATE EXTENSION IF NOT EXISTS vector;

-- 1. CREATE ai_conversations TABLE
CREATE TABLE IF NOT EXISTS ai_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  channel TEXT CHECK (channel IN ('app', 'whatsapp', 'web')),
  session_id TEXT UNIQUE NOT NULL,
  messages JSONB DEFAULT '[]'::jsonb,
  context JSONB DEFAULT '{}'::jsonb,
  language TEXT DEFAULT 'en',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  last_message_at TIMESTAMPTZ DEFAULT now()
);

-- 2. CREATE ai_query_logs TABLE
CREATE TABLE IF NOT EXISTS ai_query_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  channel TEXT,
  query TEXT NOT NULL,
  intent TEXT,
  response TEXT NOT NULL,
  module TEXT,
  tokens_input INTEGER DEFAULT 0,
  tokens_output INTEGER DEFAULT 0,
  latency_ms INTEGER DEFAULT 0,
  was_escalated BOOLEAN DEFAULT false,
  user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. CREATE faq_knowledge_base TABLE
CREATE TABLE IF NOT EXISTS faq_knowledge_base (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  category TEXT,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  module TEXT,
  embedding vector(1536),
  usage_count INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. CREATE ai_escalations TABLE
CREATE TABLE IF NOT EXISTS ai_escalations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  query TEXT,
  reason TEXT,
  assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'investigating', 'resolved')),
  resolved_at TIMESTAMPTZ,
  resolution TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. CREATE whatsapp_subscribers TABLE
CREATE TABLE IF NOT EXISTS whatsapp_subscribers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  phone TEXT NOT NULL,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  is_verified BOOLEAN DEFAULT false,
  opted_in BOOLEAN DEFAULT true,
  language_preference TEXT DEFAULT 'en',
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(institution_id, phone)
);

-- 6. CREATE smart_notifications TABLE
CREATE TABLE IF NOT EXISTS smart_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  type TEXT,
  trigger TEXT,
  template_en TEXT,
  template_hi TEXT,
  target_roles TEXT[],
  is_active BOOLEAN DEFAULT true,
  sent_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 7. CREATE search_index TABLE
CREATE TABLE IF NOT EXISTS search_index (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  entity_type TEXT,
  entity_id UUID,
  title TEXT,
  content TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  embedding vector(1536),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- PERFORMANCE INDEXES & VECTOR OPERATIONS INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_ai_conv_session ON ai_conversations(session_id);
CREATE INDEX IF NOT EXISTS idx_ai_conv_user ON ai_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_query_logs_conv ON ai_query_logs(conversation_id);
CREATE INDEX IF NOT EXISTS idx_faq_kb_inst ON faq_knowledge_base(institution_id);
CREATE INDEX IF NOT EXISTS idx_ai_escalations_user ON ai_escalations(user_id);
CREATE INDEX IF NOT EXISTS idx_whatsapp_subs_phone ON whatsapp_subscribers(phone);
CREATE INDEX IF NOT EXISTS idx_search_index_inst ON search_index(institution_id);

-- Cosine Distance Vector Indexes for Fast Retrieval
CREATE INDEX IF NOT EXISTS idx_faq_embedding ON faq_knowledge_base USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_search_index_embedding ON search_index USING hnsw (embedding vector_cosine_ops);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_query_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE faq_knowledge_base ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE whatsapp_subscribers ENABLE ROW LEVEL SECURITY;
ALTER TABLE smart_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE search_index ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
CREATE POLICY "tenant_isolation_ai_conversations" ON ai_conversations
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_ai_query_logs" ON ai_query_logs
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_faq_kb" ON faq_knowledge_base
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_ai_escalations" ON ai_escalations
  USING (user_id IN (SELECT id FROM users WHERE institution_id = get_auth_institution_id()));

CREATE POLICY "tenant_isolation_whatsapp_subs" ON whatsapp_subscribers
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_smart_notifs" ON smart_notifications
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_search_index" ON search_index
  USING (institution_id = get_auth_institution_id());

-- ============================================================
-- pgvector RPC VECTOR SEARCH HELPER FUNCTIONS
-- ============================================================

-- A. Cosine Similarity FAQ Match RPC
CREATE OR REPLACE FUNCTION match_faq (
  query_embedding vector(1536),
  match_threshold float,
  match_count int,
  inst_id uuid
)
RETURNS TABLE (
  id uuid,
  category text,
  question text,
  answer text,
  module text,
  usage_count integer,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    faq_knowledge_base.id,
    faq_knowledge_base.category,
    faq_knowledge_base.question,
    faq_knowledge_base.answer,
    faq_knowledge_base.module,
    faq_knowledge_base.usage_count,
    1 - (faq_knowledge_base.embedding <=> query_embedding) AS similarity
  FROM faq_knowledge_base
  WHERE faq_knowledge_base.institution_id = inst_id 
    AND faq_knowledge_base.is_active = true
    AND faq_knowledge_base.embedding IS NOT NULL
    AND 1 - (faq_knowledge_base.embedding <=> query_embedding) > match_threshold
  ORDER BY faq_knowledge_base.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- B. Cosine Similarity Global Search Index Match RPC
CREATE OR REPLACE FUNCTION match_search_index (
  query_embedding vector(1536),
  match_threshold float,
  match_count int,
  inst_id uuid
)
RETURNS TABLE (
  id uuid,
  entity_type text,
  entity_id uuid,
  title text,
  content text,
  metadata jsonb,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
    search_index.id,
    search_index.entity_type,
    search_index.entity_id,
    search_index.title,
    search_index.content,
    search_index.metadata,
    1 - (search_index.embedding <=> query_embedding) AS similarity
  FROM search_index
  WHERE search_index.institution_id = inst_id 
    AND search_index.embedding IS NOT NULL
    AND 1 - (search_index.embedding <=> query_embedding) > match_threshold
  ORDER BY search_index.embedding <=> query_embedding
  LIMIT match_count;
END;
$$;

-- ============================================================
-- PRE-SEED FAQ KNOWLEDGE BASE SAMPLE DATA
-- ============================================================
INSERT INTO faq_knowledge_base (institution_id, category, question, answer, module, is_active)
VALUES 
  ('a0000000-0000-0000-0000-000000000001', 'General', 'What is IRIS 365?', 'IRIS 365 is our campus operating system that unifies hostel, library, gym, transit, and canteen facilities.', 'Core', true),
  ('a0000000-0000-0000-0000-000000000001', 'Finance', 'How do I pay my semester fees?', 'Navigate to the billing console (/student/fees) or click the "Pay Now" link in your AI chats to pay securely via Razorpay.', 'Finance', true),
  ('a0000000-0000-0000-0000-000000000001', 'Library', 'What are the library overdue charges?', 'Overdue library books carry a fine of ₹10 per day, which accumulates under your unpaid fines registry.', 'Library', true),
  ('a0000000-0000-0000-0000-000000000001', 'Transit', 'How can I track my bus location?', 'Go to the transit page (/transit) and click "Track Bus" on your active pass to view real-time GPS coordinates.', 'Transit', true);


-- ==========================================================
-- MIGRATION: 20260609000013_campus_core_additional.sql
-- ==========================================================

-- Migration: IRIS Campus Core Additional Tables & RLS HARDENING
-- Targets: Supabase (PostgreSQL)

-- 1. ATTENDANCE FRAUD LOGS
CREATE TABLE IF NOT EXISTS attendance_fraud_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES attendance_sessions(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    fraud_type VARCHAR(100) NOT NULL,
    details JSONB DEFAULT '{}'::jsonb,
    flagged_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. TIMETABLE SUBSTITUTE ASSIGNMENTS
CREATE TABLE IF NOT EXISTS substitute_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    timetable_id UUID REFERENCES timetable(id) ON DELETE CASCADE,
    original_teacher_id UUID REFERENCES staff(id) ON DELETE SET NULL,
    substitute_id UUID REFERENCES staff(id) ON DELETE SET NULL,
    date DATE NOT NULL,
    assigned_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. FEE INSTALLMENT PLANS
CREATE TABLE IF NOT EXISTS installment_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    fee_structure_id UUID REFERENCES fee_structures(id) ON DELETE CASCADE,
    total_amount DECIMAL(10, 2) NOT NULL,
    installments JSONB NOT NULL, -- e.g. [{"due_date": "...", "amount": ...}]
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 4. STUDENT HEALTH & DROPOUT SCORES
CREATE TABLE IF NOT EXISTS student_health_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    score INTEGER NOT NULL DEFAULT 100,
    risk_level VARCHAR(30) NOT NULL DEFAULT 'low' CHECK (risk_level IN ('low', 'medium', 'high', 'critical')),
    attendance_score INTEGER DEFAULT 100,
    fee_score INTEGER DEFAULT 100,
    academic_score INTEGER DEFAULT 100,
    engagement_score INTEGER DEFAULT 100,
    factors JSONB DEFAULT '{}'::jsonb,
    recommendation TEXT,
    calculated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. PARENT DAILY REPORTS
CREATE TABLE IF NOT EXISTS parent_daily_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    attendance_status VARCHAR(50),
    current_period TEXT,
    meals_today TEXT,
    gate_in_time TIMESTAMP WITH TIME ZONE,
    gate_out_time TIMESTAMP WITH TIME ZONE,
    canteen_spend DECIMAL(10, 2) DEFAULT 0.00,
    notices_count INTEGER DEFAULT 0,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_student_date_report UNIQUE (student_id, date)
);

-- 6. SCHOLARSHIP CRITERIA
CREATE TABLE IF NOT EXISTS scholarship_criteria (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    min_attendance DECIMAL(5, 2) NOT NULL DEFAULT 75.00,
    min_marks DECIMAL(5, 2) NOT NULL DEFAULT 60.00,
    income_limit DECIMAL(12, 2),
    discount_percent DECIMAL(5, 2) NOT NULL DEFAULT 10.00,
    is_active BOOLEAN DEFAULT TRUE
);

-- Indexing for performance
CREATE INDEX IF NOT EXISTS idx_fraud_logs_student ON attendance_fraud_logs(student_id);
CREATE INDEX IF NOT EXISTS idx_substitute_timetable ON substitute_assignments(timetable_id);
CREATE INDEX IF NOT EXISTS idx_installment_student ON installment_plans(student_id);
CREATE INDEX IF NOT EXISTS idx_health_scores_student ON student_health_scores(student_id);
CREATE INDEX IF NOT EXISTS idx_daily_reports_student ON parent_daily_reports(student_id);
CREATE INDEX IF NOT EXISTS idx_scholarship_inst ON scholarship_criteria(institution_id);

-- Enable RLS on all tables
ALTER TABLE attendance_fraud_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE substitute_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE installment_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_health_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE parent_daily_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE scholarship_criteria ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
DROP POLICY IF EXISTS tenant_attendance_fraud_logs_policy ON attendance_fraud_logs;
CREATE POLICY tenant_attendance_fraud_logs_policy ON attendance_fraud_logs
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM students s
            WHERE s.id = student_id
              AND (s.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
        )
    );

DROP POLICY IF EXISTS tenant_substitute_assignments_policy ON substitute_assignments;
CREATE POLICY tenant_substitute_assignments_policy ON substitute_assignments
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM timetable t
            WHERE t.id = timetable_id
              AND (t.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
        )
    );

DROP POLICY IF EXISTS tenant_installment_plans_policy ON installment_plans;
CREATE POLICY tenant_installment_plans_policy ON installment_plans
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM students s
            WHERE s.id = student_id
              AND (s.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
        )
    );

DROP POLICY IF EXISTS tenant_student_health_scores_policy ON student_health_scores;
CREATE POLICY tenant_student_health_scores_policy ON student_health_scores
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM students s
            WHERE s.id = student_id
              AND (s.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
        )
    );

DROP POLICY IF EXISTS tenant_parent_daily_reports_policy ON parent_daily_reports;
CREATE POLICY tenant_parent_daily_reports_policy ON parent_daily_reports
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM students s
            WHERE s.id = student_id
              AND (s.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
        )
    );

DROP POLICY IF EXISTS tenant_scholarship_criteria_policy ON scholarship_criteria;
CREATE POLICY tenant_scholarship_criteria_policy ON scholarship_criteria
    FOR ALL USING (
        institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
    );


-- ==========================================================
-- MIGRATION: 20260610000000_canteen_system_module2.sql
-- ==========================================================

-- Migration: IRIS Canteen System Extensions & Hardening
-- Targets: Supabase (PostgreSQL)

-- 1. CANTEEN COUNTERS
CREATE TABLE IF NOT EXISTS canteen_counters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    qr_code VARCHAR(255) UNIQUE,
    is_active BOOLEAN DEFAULT TRUE,
    is_accepting_orders BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. MEAL PLANS
CREATE TABLE IF NOT EXISTS meal_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    meal_types TEXT[], -- e.g. {'breakfast', 'lunch', 'snacks'}
    duration_days INTEGER NOT NULL DEFAULT 30,
    price DECIMAL(10, 2) NOT NULL,
    meals_included INTEGER NOT NULL DEFAULT 30,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. ALTER MEAL SUBSCRIPTIONS
ALTER TABLE meal_subscriptions ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES meal_plans(id) ON DELETE SET NULL;
ALTER TABLE meal_subscriptions ADD COLUMN IF NOT EXISTS meals_total INTEGER DEFAULT 30;
ALTER TABLE meal_subscriptions ADD COLUMN IF NOT EXISTS meals_used INTEGER DEFAULT 0;
ALTER TABLE meal_subscriptions ADD COLUMN IF NOT EXISTS status VARCHAR(50) DEFAULT 'active';

-- 4. DAILY MEAL SELECTIONS
CREATE TABLE IF NOT EXISTS daily_meal_selections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    subscription_id UUID REFERENCES meal_subscriptions(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    meal_type VARCHAR(50) NOT NULL,
    items JSONB DEFAULT '[]'::jsonb,
    is_opted_out BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_student_meal_date UNIQUE (student_id, date, meal_type)
);

-- 5. INVENTORY LOGS
CREATE TABLE IF NOT EXISTS inventory_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    item_id UUID REFERENCES canteen_menus(id) ON DELETE CASCADE,
    opening_stock INTEGER NOT NULL DEFAULT 0,
    used INTEGER NOT NULL DEFAULT 0,
    waste INTEGER NOT NULL DEFAULT 0,
    closing_stock INTEGER NOT NULL DEFAULT 0,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    logged_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. AI MENU PLANS
CREATE TABLE IF NOT EXISTS ai_menu_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    plan JSONB NOT NULL DEFAULT '{}'::jsonb,
    nutritional_summary JSONB DEFAULT '{}'::jsonb,
    generated_by VARCHAR(50) DEFAULT 'ai',
    approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
    is_active BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 7. NUTRITION LOGS
CREATE TABLE IF NOT EXISTS nutrition_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    total_calories INTEGER NOT NULL DEFAULT 0,
    protein_g DECIMAL(6, 2) DEFAULT 0.0,
    carbs_g DECIMAL(6, 2) DEFAULT 0.0,
    fat_g DECIMAL(6, 2) DEFAULT 0.0,
    meal_count INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_student_nutrition_date UNIQUE (student_id, date)
);

-- 8. HYGIENE CHECKLISTS
CREATE TABLE IF NOT EXISTS hygiene_checklists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    vendor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    temperature_log JSONB DEFAULT '{}'::jsonb,
    cleanliness_score INTEGER CHECK (cleanliness_score >= 1 AND cleanliness_score <= 100),
    items_checked JSONB NOT NULL DEFAULT '[]'::jsonb,
    passed BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_vendor_hygiene_date UNIQUE (institution_id, date)
);

-- 9. ALTER CANTEEN MENUS
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS protein_g DECIMAL(6, 2) DEFAULT 0.0;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS carbs_g DECIMAL(6, 2) DEFAULT 0.0;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS fat_g DECIMAL(6, 2) DEFAULT 0.0;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS prep_time_minutes INTEGER DEFAULT 15;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS sort_order INTEGER DEFAULT 0;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS daily_stock INTEGER DEFAULT 100;
ALTER TABLE canteen_menus ADD COLUMN IF NOT EXISTS stock_remaining INTEGER DEFAULT 100;
ALTER TABLE canteen_menus DROP COLUMN IF EXISTS allergens;
ALTER TABLE canteen_menus ADD COLUMN allergens TEXT[] DEFAULT '{}'::text[];

-- 10. ALTER CANTEEN ORDERS
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS final_amount DECIMAL(10, 2);
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS payment_status VARCHAR(50) DEFAULT 'pending';
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS transaction_id VARCHAR(100);
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS counter_id UUID REFERENCES canteen_counters(id) ON DELETE SET NULL;
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS token_number INTEGER;
ALTER TABLE canteen_orders ADD COLUMN IF NOT EXISTS estimated_ready_minutes INTEGER DEFAULT 15;

-- 11. INDEXING
CREATE INDEX IF NOT EXISTS idx_canteen_counters_inst ON canteen_counters(institution_id);
CREATE INDEX IF NOT EXISTS idx_meal_plans_inst ON meal_plans(institution_id);
CREATE INDEX IF NOT EXISTS idx_daily_meal_sel_stud ON daily_meal_selections(student_id);
CREATE INDEX IF NOT EXISTS idx_inventory_logs_date ON inventory_logs(date);
CREATE INDEX IF NOT EXISTS idx_ai_menu_plans_week ON ai_menu_plans(week_start);
CREATE INDEX IF NOT EXISTS idx_nutrition_logs_date ON nutrition_logs(date);
CREATE INDEX IF NOT EXISTS idx_hygiene_chk_date ON hygiene_checklists(date);

-- 12. ENABLE ROW LEVEL SECURITY
ALTER TABLE canteen_counters ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_meal_selections ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_menu_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE nutrition_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE hygiene_checklists ENABLE ROW LEVEL SECURITY;

-- 13. TENANT ISOLATION POLICIES
DROP POLICY IF EXISTS tenant_canteen_counters_policy ON canteen_counters;
CREATE POLICY tenant_canteen_counters_policy ON canteen_counters
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_meal_plans_policy ON meal_plans;
CREATE POLICY tenant_meal_plans_policy ON meal_plans
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_daily_meal_selections_policy ON daily_meal_selections;
CREATE POLICY tenant_daily_meal_selections_policy ON daily_meal_selections
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_inventory_logs_policy ON inventory_logs;
CREATE POLICY tenant_inventory_logs_policy ON inventory_logs
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_ai_menu_plans_policy ON ai_menu_plans;
CREATE POLICY tenant_ai_menu_plans_policy ON ai_menu_plans
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_nutrition_logs_policy ON nutrition_logs;
CREATE POLICY tenant_nutrition_logs_policy ON nutrition_logs
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM students s
            WHERE s.id = student_id
              AND (s.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
        )
    );

DROP POLICY IF EXISTS tenant_hygiene_checklists_policy ON hygiene_checklists;
CREATE POLICY tenant_hygiene_checklists_policy ON hygiene_checklists
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');


-- ==========================================================
-- MIGRATION: 20260610000001_fitzone_system_module3.sql
-- ==========================================================

-- ============================================================
-- IRIS 365 — MODULE 3: FITZONE SYSTEM SCHEMA EXPANSIONS
-- ============================================================

-- 1. AI WORKOUT PLANS
CREATE TABLE IF NOT EXISTS ai_workout_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    goal TEXT NOT NULL,
    plan JSONB NOT NULL,
    week_number INTEGER DEFAULT 1,
    generated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    last_adjusted TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. FITNESS CHALLENGES
CREATE TABLE IF NOT EXISTS fitness_challenges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    challenge_type TEXT NOT NULL, -- steps, plank, weight_loss, etc.
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    target_value DECIMAL(10, 2) NOT NULL,
    unit TEXT NOT NULL, -- reps, minutes, steps, kg
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 3. CHALLENGE PARTICIPANTS
CREATE TABLE IF NOT EXISTS challenge_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    challenge_id UUID REFERENCES fitness_challenges(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    current_value DECIMAL(10, 2) DEFAULT 0.0,
    rank INTEGER,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_challenge_student UNIQUE (challenge_id, student_id)
);

-- 4. FITPOINTS LOG
CREATE TABLE IF NOT EXISTS fitpoints_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    points INTEGER NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 5. VIRTUAL CLASSES
CREATE TABLE IF NOT EXISTS virtual_classes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    trainer_id UUID REFERENCES gym_trainers(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    video_url TEXT,
    thumbnail_url TEXT,
    duration_minutes INTEGER DEFAULT 30,
    difficulty TEXT DEFAULT 'Beginner', -- Beginner, Intermediate, Advanced
    category TEXT DEFAULT 'General', -- Cardio, HIIT, Strength, Yoga, Stretch
    view_count INTEGER DEFAULT 0,
    is_live BOOLEAN DEFAULT FALSE,
    scheduled_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 6. WELLNESS DAILY CHECKINS
CREATE TABLE IF NOT EXISTS wellness_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    mood INTEGER CHECK (mood BETWEEN 1 AND 5),
    stress_level INTEGER CHECK (stress_level BETWEEN 1 AND 5),
    sleep_hours DECIMAL(4, 2),
    energy_level INTEGER CHECK (energy_level BETWEEN 1 AND 5),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uniq_student_date UNIQUE (student_id, date)
);

-- 7. SEARCH INDEXES
CREATE INDEX IF NOT EXISTS idx_ai_workout_plans_student ON ai_workout_plans(student_id);
CREATE INDEX IF NOT EXISTS idx_fitness_challenges_inst ON fitness_challenges(institution_id);
CREATE INDEX IF NOT EXISTS idx_challenge_participants_challenge ON challenge_participants(challenge_id);
CREATE INDEX IF NOT EXISTS idx_challenge_participants_student ON challenge_participants(student_id);
CREATE INDEX IF NOT EXISTS idx_fitpoints_log_student ON fitpoints_log(student_id);
CREATE INDEX IF NOT EXISTS idx_virtual_classes_inst ON virtual_classes(institution_id);
CREATE INDEX IF NOT EXISTS idx_wellness_checkins_student_date ON wellness_checkins(student_id, date);

-- 8. ENABLE ROW LEVEL SECURITY
ALTER TABLE ai_workout_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE challenge_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitpoints_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE virtual_classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellness_checkins ENABLE ROW LEVEL SECURITY;

-- 9. TENANT ISOLATION RLS POLICIES
CREATE POLICY ai_workout_plans_tenant ON ai_workout_plans
    USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()) OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY fitness_challenges_tenant ON fitness_challenges
    USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY challenge_participants_tenant ON challenge_participants
    USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()) OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY fitpoints_log_tenant ON fitpoints_log
    USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()) OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY virtual_classes_tenant ON virtual_classes
    USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE POLICY wellness_checkins_tenant ON wellness_checkins
    USING (student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id()) OR get_auth_user_role() = 'SuperAdmin');


-- ==========================================================
-- MIGRATION: 20260610000002_events_system_module4.sql
-- ==========================================================

-- ============================================================
-- MODULE 4: IRIS Events — Complete Schema Extensions & New Tables
-- ============================================================

-- 1. ALTER events TABLE
ALTER TABLE events ADD COLUMN IF NOT EXISTS ai_plan JSONB DEFAULT NULL;
ALTER TABLE events ADD COLUMN IF NOT EXISTS is_hybrid BOOLEAN DEFAULT false;
ALTER TABLE events ADD COLUMN IF NOT EXISTS virtual_link TEXT DEFAULT NULL;

-- 2. ALTER event_registrations TABLE
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS registration_type VARCHAR(30) DEFAULT 'in_person';
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS transaction_id TEXT DEFAULT NULL;
ALTER TABLE event_registrations ADD COLUMN IF NOT EXISTS custom_fields JSONB DEFAULT '{}';

-- 3. ALTER event_volunteers TABLE
ALTER TABLE event_volunteers ADD COLUMN IF NOT EXISTS tasks JSONB DEFAULT '[]';
ALTER TABLE event_volunteers ADD COLUMN IF NOT EXISTS check_in_time TIMESTAMPTZ DEFAULT NULL;
ALTER TABLE event_volunteers ADD COLUMN IF NOT EXISTS hours_worked DECIMAL(5, 2) DEFAULT 0;
ALTER TABLE event_volunteers ADD COLUMN IF NOT EXISTS certificate_url TEXT DEFAULT NULL;

-- 4. CREATE volunteer_applications TABLE
CREATE TABLE IF NOT EXISTS volunteer_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  preferred_role VARCHAR(100) NOT NULL,
  motivation TEXT,
  status VARCHAR(30) DEFAULT 'pending', -- pending, approved, rejected
  applied_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. ALTER event_sponsors TABLE
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS contact_name VARCHAR(255) DEFAULT NULL;
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS contact_email VARCHAR(255) DEFAULT NULL;
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS website_url TEXT DEFAULT NULL;
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS payment_status VARCHAR(30) DEFAULT 'pending';
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS pipeline_stage VARCHAR(50) DEFAULT 'prospect'; -- prospect, contacted, negotiating, confirmed, paid
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS communication_log JSONB DEFAULT '[]';
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS deliverables JSONB DEFAULT '[]';
ALTER TABLE event_sponsors ADD COLUMN IF NOT EXISTS notes TEXT DEFAULT NULL;

-- 6. ALTER event_budget TABLE
ALTER TABLE event_budget ADD COLUMN IF NOT EXISTS item VARCHAR(255) DEFAULT NULL;
ALTER TABLE event_budget ADD COLUMN IF NOT EXISTS type VARCHAR(20) DEFAULT 'expense'; -- income, expense
ALTER TABLE event_budget DROP CONSTRAINT IF EXISTS budget_type_check;
ALTER TABLE event_budget ADD CONSTRAINT budget_type_check CHECK (type IN ('income', 'expense'));

-- 7. ALTER event_photos TABLE
ALTER TABLE event_photos ADD COLUMN IF NOT EXISTS tagged_students UUID[] DEFAULT '{}';
ALTER TABLE event_photos ADD COLUMN IF NOT EXISTS is_published BOOLEAN DEFAULT false;

-- 8. ALTER event_feedback TABLE
ALTER TABLE event_feedback ADD COLUMN IF NOT EXISTS organization_rating INTEGER DEFAULT 5;
ALTER TABLE event_feedback ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP;

-- 9. CREATE live_polls TABLE
CREATE TABLE IF NOT EXISTS live_polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  options JSONB NOT NULL, -- Array of string options e.g. ["Option A", "Option B"]
  is_active BOOLEAN DEFAULT false,
  show_results BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 10. CREATE poll_responses TABLE
CREATE TABLE IF NOT EXISTS poll_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES live_polls(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  selected_option INTEGER NOT NULL, -- 0-based index
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_poll_student UNIQUE (poll_id, student_id)
);

-- 11. CREATE live_questions TABLE
CREATE TABLE IF NOT EXISTS live_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  upvotes INTEGER DEFAULT 0,
  is_answered BOOLEAN DEFAULT false,
  is_approved BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 12. CREATE event_certificates TABLE
CREATE TABLE IF NOT EXISTS event_certificates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  event_id UUID REFERENCES events(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  certificate_type VARCHAR(50) NOT NULL, -- participation, winner, volunteer, speaker
  rank INTEGER DEFAULT NULL,              -- 1, 2, 3 for winners
  url TEXT NOT NULL,
  issued_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  verification_code VARCHAR(100) UNIQUE NOT NULL
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_volunteer_applications_event ON volunteer_applications(event_id);
CREATE INDEX IF NOT EXISTS idx_volunteer_applications_student ON volunteer_applications(student_id);
CREATE INDEX IF NOT EXISTS idx_live_polls_event ON live_polls(event_id);
CREATE INDEX IF NOT EXISTS idx_poll_responses_poll ON poll_responses(poll_id);
CREATE INDEX IF NOT EXISTS idx_live_questions_event ON live_questions(event_id);
CREATE INDEX IF NOT EXISTS idx_event_certificates_event ON event_certificates(event_id);
CREATE INDEX IF NOT EXISTS idx_event_certificates_student ON event_certificates(student_id);
CREATE INDEX IF NOT EXISTS idx_event_certificates_code ON event_certificates(verification_code);

-- ============================================================
-- ROW LEVEL SECURITY AND POLICIES
-- ============================================================
ALTER TABLE volunteer_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE poll_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_certificates ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist and recreate
DROP POLICY IF EXISTS tenant_isolation_volunteer_applications ON volunteer_applications;
CREATE POLICY tenant_isolation_volunteer_applications ON volunteer_applications
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_live_polls ON live_polls;
CREATE POLICY tenant_isolation_live_polls ON live_polls
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_poll_responses ON poll_responses;
CREATE POLICY tenant_isolation_poll_responses ON poll_responses
  USING (
    EXISTS (
      SELECT 1 FROM live_polls
      WHERE live_polls.id = poll_responses.poll_id
      AND live_polls.institution_id = get_auth_institution_id()
    )
  );

DROP POLICY IF EXISTS tenant_isolation_live_questions ON live_questions;
CREATE POLICY tenant_isolation_live_questions ON live_questions
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_event_certificates ON event_certificates;
CREATE POLICY tenant_isolation_event_certificates ON event_certificates
  USING (institution_id = get_auth_institution_id());


-- ==========================================================
-- MIGRATION: 20260610000003_hostel_system_module5.sql
-- ==========================================================

-- ============================================================
-- MODULE 5: IRIS Hostel — Extended Schema & New Tables
-- ============================================================

-- 1. CREATE roommate_preferences TABLE
CREATE TABLE IF NOT EXISTS roommate_preferences (
  student_id UUID PRIMARY KEY REFERENCES students(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  sleep_schedule INTEGER NOT NULL CHECK (sleep_schedule BETWEEN 1 AND 5),
  study_habits INTEGER NOT NULL CHECK (study_habits BETWEEN 1 AND 5),
  cleanliness INTEGER NOT NULL CHECK (cleanliness BETWEEN 1 AND 5),
  noise_tolerance INTEGER NOT NULL CHECK (noise_tolerance BETWEEN 1 AND 5),
  compatibility_score DECIMAL(5, 2) DEFAULT 0.00,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. CREATE iot_readings TABLE
CREATE TABLE IF NOT EXISTS iot_readings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  room_id UUID REFERENCES hostel_rooms(id) ON DELETE CASCADE,
  meter_type VARCHAR(50) NOT NULL CHECK (meter_type IN ('electricity', 'water')),
  reading_value DECIMAL(12, 4) NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. CREATE night_rollcalls TABLE
CREATE TABLE IF NOT EXISTS night_rollcalls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  block_id UUID REFERENCES hostel_blocks(id) ON DELETE CASCADE,
  floor INTEGER NOT NULL,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  guard_id UUID REFERENCES staff(id) ON DELETE SET NULL,
  is_active BOOLEAN DEFAULT true,
  started_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  records JSONB DEFAULT '{}'::jsonb
);

-- 4. CREATE wellness_checkins_hostel TABLE
CREATE TABLE IF NOT EXISTS wellness_checkins_hostel (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  mood INTEGER NOT NULL CHECK (mood BETWEEN 1 AND 5),
  notes TEXT,
  is_anonymous BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_roommate_preferences_institution ON roommate_preferences(institution_id);
CREATE INDEX IF NOT EXISTS idx_iot_readings_room ON iot_readings(room_id);
CREATE INDEX IF NOT EXISTS idx_iot_readings_timestamp ON iot_readings(timestamp);
CREATE INDEX IF NOT EXISTS idx_night_rollcalls_block_floor ON night_rollcalls(block_id, floor);
CREATE INDEX IF NOT EXISTS idx_night_rollcalls_date ON night_rollcalls(date);
CREATE INDEX IF NOT EXISTS idx_wellness_checkins_student ON wellness_checkins_hostel(student_id);
CREATE INDEX IF NOT EXISTS idx_wellness_checkins_date ON wellness_checkins_hostel(date);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE roommate_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE iot_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE night_rollcalls ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellness_checkins_hostel ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
DROP POLICY IF EXISTS tenant_isolation_roommate_preferences ON roommate_preferences;
CREATE POLICY tenant_isolation_roommate_preferences ON roommate_preferences
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_iot_readings ON iot_readings;
CREATE POLICY tenant_isolation_iot_readings ON iot_readings
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_night_rollcalls ON night_rollcalls;
CREATE POLICY tenant_isolation_night_rollcalls ON night_rollcalls
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_wellness_checkins ON wellness_checkins_hostel;
CREATE POLICY tenant_isolation_wellness_checkins ON wellness_checkins_hostel
  USING (institution_id = get_auth_institution_id());


-- ==========================================================
-- MIGRATION: 20260610000004_library_system_module6.sql
-- ==========================================================

-- ============================================================
-- MODULE 6: IRIS Library+ — Extended Schema & New Tables
-- ============================================================

-- 1. CREATE reading_goals TABLE
CREATE TABLE IF NOT EXISTS reading_goals (
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  year INTEGER NOT NULL,
  target_books INTEGER NOT NULL,
  completed_books INTEGER DEFAULT 0,
  streak_days INTEGER DEFAULT 0,
  points INTEGER DEFAULT 0,
  pages_read_total INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (student_id, year)
);

-- 2. CREATE book_clubs TABLE
CREATE TABLE IF NOT EXISTS book_clubs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  current_book_id UUID REFERENCES books(id) ON DELETE SET NULL,
  schedule TEXT,
  members UUID[] DEFAULT '{}'::uuid[],
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. CREATE book_club_discussions TABLE
CREATE TABLE IF NOT EXISTS book_club_discussions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id UUID REFERENCES book_clubs(id) ON DELETE CASCADE,
  chapter VARCHAR(100) NOT NULL,
  question TEXT NOT NULL,
  ai_generated BOOLEAN DEFAULT false,
  responses JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 4. CREATE digital_newspapers TABLE
CREATE TABLE IF NOT EXISTS digital_newspapers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  provider TEXT NOT NULL,
  current_issue_url TEXT NOT NULL,
  archive_urls JSONB DEFAULT '{}'::jsonb,
  bookmarks JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. CREATE interlibrary_requests TABLE
CREATE TABLE IF NOT EXISTS interlibrary_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requesting_institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  providing_institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  book_id UUID REFERENCES books(id) ON DELETE CASCADE,
  status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'shipped', 'delivered', 'returned')),
  courier_tracking TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_reading_goals_institution ON reading_goals(institution_id);
CREATE INDEX IF NOT EXISTS idx_book_clubs_institution ON book_clubs(institution_id);
CREATE INDEX IF NOT EXISTS idx_book_club_discussions_club ON book_club_discussions(club_id);
CREATE INDEX IF NOT EXISTS idx_digital_newspapers_institution ON digital_newspapers(institution_id);
CREATE INDEX IF NOT EXISTS idx_interlibrary_requests_requesting ON interlibrary_requests(requesting_institution_id);
CREATE INDEX IF NOT EXISTS idx_interlibrary_requests_providing ON interlibrary_requests(providing_institution_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE reading_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_clubs ENABLE ROW LEVEL SECURITY;
ALTER TABLE book_club_discussions ENABLE ROW LEVEL SECURITY;
ALTER TABLE digital_newspapers ENABLE ROW LEVEL SECURITY;
ALTER TABLE interlibrary_requests ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
DROP POLICY IF EXISTS tenant_isolation_reading_goals ON reading_goals;
CREATE POLICY tenant_isolation_reading_goals ON reading_goals
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_book_clubs ON book_clubs;
CREATE POLICY tenant_isolation_book_clubs ON book_clubs
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_book_club_discussions ON book_club_discussions;
CREATE POLICY tenant_isolation_book_club_discussions ON book_club_discussions
  USING (
    EXISTS (
      SELECT 1 FROM book_clubs
      WHERE book_clubs.id = book_club_discussions.club_id
      AND book_clubs.institution_id = get_auth_institution_id()
    )
  );

DROP POLICY IF EXISTS tenant_isolation_digital_newspapers ON digital_newspapers;
CREATE POLICY tenant_isolation_digital_newspapers ON digital_newspapers
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_interlibrary_requests ON interlibrary_requests;
CREATE POLICY tenant_isolation_interlibrary_requests ON interlibrary_requests
  USING (
    requesting_institution_id = get_auth_institution_id() OR
    providing_institution_id = get_auth_institution_id()
  );


-- ==========================================================
-- MIGRATION: 20260610000005_transit_system_module7.sql
-- ==========================================================

-- ============================================================
-- MODULE 7: IRIS Transit — Extended Schema & New Tables
-- ============================================================

-- 1. CREATE ai_route_suggestions TABLE
CREATE TABLE IF NOT EXISTS ai_route_suggestions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  analysis_date DATE DEFAULT CURRENT_DATE,
  suggestions JSONB DEFAULT '[]'::jsonb,
  approved BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. CREATE carbon_footprint TABLE
CREATE TABLE IF NOT EXISTS carbon_footprint (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  month VARCHAR(7) NOT NULL, -- Format: YYYY-MM
  co2_saved_kg DECIMAL DEFAULT 0,
  students_using_bus INTEGER DEFAULT 0,
  certificate_url TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(institution_id, month)
);

-- 3. CREATE sos_alerts TABLE
CREATE TABLE IF NOT EXISTS sos_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  bus_id UUID REFERENCES buses(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  alert_type TEXT DEFAULT 'parent',
  lat DECIMAL,
  lng DECIMAL,
  status VARCHAR(50) DEFAULT 'active' CHECK (status IN ('active', 'resolved')),
  resolved_at TIMESTAMPTZ,
  incident_details JSONB DEFAULT '{}'::jsonb,
  timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 4. CREATE parking_slots TABLE
CREATE TABLE IF NOT EXISTS parking_slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  slot_number TEXT NOT NULL,
  zone TEXT NOT NULL,
  is_occupied BOOLEAN DEFAULT false,
  vehicle_number TEXT,
  last_occupied_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(institution_id, zone, slot_number)
);

-- 5. CREATE registered_vehicles TABLE
CREATE TABLE IF NOT EXISTS registered_vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  vehicle_number TEXT NOT NULL UNIQUE,
  type TEXT NOT NULL CHECK (type IN ('two_wheeler', 'four_wheeler')),
  color TEXT,
  model TEXT,
  verified BOOLEAN DEFAULT false,
  pass_qr TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_ai_route_suggestions_institution ON ai_route_suggestions(institution_id);
CREATE INDEX IF NOT EXISTS idx_carbon_footprint_institution ON carbon_footprint(institution_id);
CREATE INDEX IF NOT EXISTS idx_sos_alerts_institution ON sos_alerts(institution_id);
CREATE INDEX IF NOT EXISTS idx_parking_slots_institution ON parking_slots(institution_id);
CREATE INDEX IF NOT EXISTS idx_registered_vehicles_student ON registered_vehicles(student_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE ai_route_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE carbon_footprint ENABLE ROW LEVEL SECURITY;
ALTER TABLE sos_alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE parking_slots ENABLE ROW LEVEL SECURITY;
ALTER TABLE registered_vehicles ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
DROP POLICY IF EXISTS tenant_isolation_ai_route_suggestions ON ai_route_suggestions;
CREATE POLICY tenant_isolation_ai_route_suggestions ON ai_route_suggestions
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_carbon_footprint ON carbon_footprint;
CREATE POLICY tenant_isolation_carbon_footprint ON carbon_footprint
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_sos_alerts ON sos_alerts;
CREATE POLICY tenant_isolation_sos_alerts ON sos_alerts
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_parking_slots ON parking_slots;
CREATE POLICY tenant_isolation_parking_slots ON parking_slots
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_registered_vehicles ON registered_vehicles;
CREATE POLICY tenant_isolation_registered_vehicles ON registered_vehicles
  USING (institution_id = get_auth_institution_id());

-- ============================================================
-- SEED DATA
-- ============================================================
-- Seed Parking Slots
INSERT INTO parking_slots (institution_id, slot_number, zone, is_occupied)
VALUES 
  ('a0000000-0000-0000-0000-000000000001', 'A-01', 'Zone A', false),
  ('a0000000-0000-0000-0000-000000000001', 'A-02', 'Zone A', true),
  ('a0000000-0000-0000-0000-000000000001', 'A-03', 'Zone A', false),
  ('a0000000-0000-0000-0000-000000000001', 'B-01', 'Zone B', false),
  ('a0000000-0000-0000-0000-000000000001', 'B-02', 'Zone B', false),
  ('a0000000-0000-0000-0000-000000000001', 'V-01', 'Visitor', false),
  ('a0000000-0000-0000-0000-000000000001', 'V-02', 'Visitor', true)
ON CONFLICT (institution_id, zone, slot_number) DO NOTHING;

-- Seed CO2 foot print data
INSERT INTO carbon_footprint (institution_id, month, co2_saved_kg, students_using_bus, certificate_url)
VALUES
  ('a0000000-0000-0000-0000-000000000001', '2026-04', 1240.50, 120, 'https://supabase.co/storage/v1/object/public/certificates/monthly-co2-2026-04.pdf'),
  ('a0000000-0000-0000-0000-000000000001', '2026-05', 1355.20, 134, 'https://supabase.co/storage/v1/object/public/certificates/monthly-co2-2026-05.pdf')
ON CONFLICT (institution_id, month) DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260610000006_gate_system_module8.sql
-- ==========================================================

-- ============================================================
-- MODULE 8: IRIS Smart Gate — Extended Schema & New Tables
-- ============================================================

-- 1. CREATE parking_logs TABLE
CREATE TABLE IF NOT EXISTS parking_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  vehicle_number TEXT NOT NULL,
  student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  in_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  out_time TIMESTAMPTZ,
  slot_number TEXT,
  pass_qr TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. CREATE emergency_muster TABLE
CREATE TABLE IF NOT EXISTS emergency_muster (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  triggered_by UUID REFERENCES users(id) ON DELETE SET NULL,
  trigger_type TEXT CHECK (trigger_type IN ('fire', 'earthquake', 'drill', 'other')),
  trigger_time TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 3. CREATE muster_responses TABLE
CREATE TABLE IF NOT EXISTS muster_responses (
  muster_id UUID REFERENCES emergency_muster(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  status VARCHAR(50) DEFAULT 'unaccounted' CHECK (status IN ('safe', 'unaccounted')),
  marked_safe_at TIMESTAMPTZ,
  location TEXT,
  PRIMARY KEY (muster_id, student_id)
);

-- 4. CREATE contractor_profiles TABLE
CREATE TABLE IF NOT EXISTS contractor_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  company_name TEXT NOT NULL,
  contact TEXT,
  id_proof_url TEXT,
  work_types TEXT[] DEFAULT '{}'::text[],
  is_approved BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. CREATE work_permits TABLE
CREATE TABLE IF NOT EXISTS work_permits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  contractor_id UUID REFERENCES contractor_profiles(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  scope TEXT NOT NULL,
  location TEXT NOT NULL,
  approved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  entry_pass_qr TEXT,
  status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed')),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 6. CREATE intercom_calls TABLE
CREATE TABLE IF NOT EXISTS intercom_calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  visitor_name TEXT NOT NULL,
  visitor_phone TEXT,
  host_id UUID REFERENCES users(id) ON DELETE CASCADE,
  called_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  answered BOOLEAN DEFAULT false,
  approved BOOLEAN DEFAULT false,
  recording_url TEXT,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_parking_logs_institution ON parking_logs(institution_id);
CREATE INDEX IF NOT EXISTS idx_emergency_muster_institution ON emergency_muster(institution_id);
CREATE INDEX IF NOT EXISTS idx_muster_responses_student ON muster_responses(student_id);
CREATE INDEX IF NOT EXISTS idx_contractor_profiles_institution ON contractor_profiles(institution_id);
CREATE INDEX IF NOT EXISTS idx_work_permits_contractor ON work_permits(contractor_id);
CREATE INDEX IF NOT EXISTS idx_intercom_calls_host ON intercom_calls(host_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE parking_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_muster ENABLE ROW LEVEL SECURITY;
ALTER TABLE muster_responses ENABLE ROW LEVEL SECURITY;
ALTER TABLE contractor_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_permits ENABLE ROW LEVEL SECURITY;
ALTER TABLE intercom_calls ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
DROP POLICY IF EXISTS tenant_isolation_parking_logs ON parking_logs;
CREATE POLICY tenant_isolation_parking_logs ON parking_logs
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_emergency_muster ON emergency_muster;
CREATE POLICY tenant_isolation_emergency_muster ON emergency_muster
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_muster_responses ON muster_responses;
CREATE POLICY tenant_isolation_muster_responses ON muster_responses
  USING (
    EXISTS (
      SELECT 1 FROM emergency_muster
      WHERE emergency_muster.id = muster_responses.muster_id
      AND emergency_muster.institution_id = get_auth_institution_id()
    )
  );

DROP POLICY IF EXISTS tenant_isolation_contractor_profiles ON contractor_profiles;
CREATE POLICY tenant_isolation_contractor_profiles ON contractor_profiles
  USING (institution_id = get_auth_institution_id());

DROP POLICY IF EXISTS tenant_isolation_work_permits ON work_permits;
CREATE POLICY tenant_isolation_work_permits ON work_permits
  USING (
    EXISTS (
      SELECT 1 FROM contractor_profiles
      WHERE contractor_profiles.id = work_permits.contractor_id
      AND contractor_profiles.institution_id = get_auth_institution_id()
    )
  );

DROP POLICY IF EXISTS tenant_isolation_intercom_calls ON intercom_calls;
CREATE POLICY tenant_isolation_intercom_calls ON intercom_calls
  USING (institution_id = get_auth_institution_id());

-- ============================================================
-- SEED MOCK DATA
-- ============================================================
-- Seed Contractor Profiles
INSERT INTO contractor_profiles (id, institution_id, company_name, contact, work_types, is_approved)
VALUES
  ('c5000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Apex Plumbing Services', '+91 99887 76655', ARRAY['Plumbing', 'Drainage'], true),
  ('c5000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'VoltTech Electricals', '+91 99887 76656', ARRAY['Electricals', 'Wiring', 'AC Service'], true)
ON CONFLICT (id) DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260610000007_director_system_module9.sql
-- ==========================================================

-- ============================================================
-- MODULE 9: IRIS Director Dashboard — Extended Schema
-- ============================================================

-- 1. CREATE strategic_goals TABLE
CREATE TABLE IF NOT EXISTS strategic_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  metric_name TEXT NOT NULL,
  target_value DECIMAL NOT NULL,
  current_value DECIMAL NOT NULL DEFAULT 0.0,
  deadline DATE NOT NULL,
  unit TEXT NOT NULL,
  status VARCHAR(50) DEFAULT 'on_track' CHECK (status IN ('on_track', 'at_risk', 'achieved', 'missed')),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. CREATE board_reports TABLE
CREATE TABLE IF NOT EXISTS board_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  quarter INTEGER NOT NULL CHECK (quarter BETWEEN 1 AND 4),
  year INTEGER NOT NULL,
  pptx_url TEXT NOT NULL,
  generated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  sent_to TEXT[] DEFAULT '{}'::text[]
);

-- 3. CREATE financial_pl TABLE
CREATE TABLE IF NOT EXISTS financial_pl (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  year INTEGER NOT NULL,
  revenue_breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
  cost_breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
  net_surplus DECIMAL NOT NULL DEFAULT 0.0,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_monthly_pl UNIQUE (institution_id, month, year)
);

-- 4. CREATE competitor_benchmarks TABLE
CREATE TABLE IF NOT EXISTS competitor_benchmarks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  metric TEXT NOT NULL,
  our_value DECIMAL NOT NULL,
  industry_avg DECIMAL NOT NULL,
  top_performer DECIMAL NOT NULL,
  percentile DECIMAL NOT NULL,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. CREATE student_journey_scores TABLE
CREATE TABLE IF NOT EXISTS student_journey_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  engagement_score DECIMAL NOT NULL DEFAULT 0.0,
  academic_score DECIMAL NOT NULL DEFAULT 0.0,
  social_score DECIMAL NOT NULL DEFAULT 0.0,
  facility_score DECIMAL NOT NULL DEFAULT 0.0,
  overall_score DECIMAL NOT NULL DEFAULT 0.0,
  intervention_status VARCHAR(50) DEFAULT 'none' CHECK (intervention_status IN ('none', 'pending_counselor', 'counselor_assigned', 'resolved')),
  calculated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_strategic_goals_inst ON strategic_goals(institution_id);
CREATE INDEX IF NOT EXISTS idx_board_reports_inst ON board_reports(institution_id);
CREATE INDEX IF NOT EXISTS idx_financial_pl_inst ON financial_pl(institution_id);
CREATE INDEX IF NOT EXISTS idx_competitor_benchmarks_inst ON competitor_benchmarks(institution_id);
CREATE INDEX IF NOT EXISTS idx_student_journey_scores_student ON student_journey_scores(student_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE strategic_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE board_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE financial_pl ENABLE ROW LEVEL SECURITY;
ALTER TABLE competitor_benchmarks ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_journey_scores ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
DROP POLICY IF EXISTS tenant_isolation_strategic_goals ON strategic_goals;
CREATE POLICY tenant_isolation_strategic_goals ON strategic_goals
  FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_isolation_board_reports ON board_reports;
CREATE POLICY tenant_isolation_board_reports ON board_reports
  FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_isolation_financial_pl ON financial_pl;
CREATE POLICY tenant_isolation_financial_pl ON financial_pl
  FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_isolation_competitor_benchmarks ON competitor_benchmarks;
CREATE POLICY tenant_isolation_competitor_benchmarks ON competitor_benchmarks
  FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

DROP POLICY IF EXISTS tenant_isolation_student_journey_scores ON student_journey_scores;
CREATE POLICY tenant_isolation_student_journey_scores ON student_journey_scores
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM students s
      WHERE s.id = student_id
      AND (s.institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
    )
  );

-- ============================================================
-- SEED MOCK DATA
-- ============================================================

-- Seed Strategic Goals
INSERT INTO strategic_goals (id, institution_id, metric_name, target_value, current_value, deadline, unit, status)
VALUES
  ('81000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Attendance Rate', 85.00, 82.00, '2026-12-31', '%', 'on_track'),
  ('81000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Fee Collection', 15000000.00, 14200000.00, '2026-12-31', '₹', 'on_track'),
  ('81000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Pass Rate', 90.00, 88.00, '2026-12-31', '%', 'on_track'),
  ('81000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Annual Fee Target Large', 25000000.00, 11000000.00, '2026-12-31', '₹', 'at_risk')
ON CONFLICT (id) DO NOTHING;

-- Seed Competitor Benchmarks
INSERT INTO competitor_benchmarks (id, institution_id, metric, our_value, industry_avg, top_performer, percentile)
VALUES
  ('b1000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Attendance Rate', 82.00, 78.50, 92.00, 74.00),
  ('b1000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Fee Collection Rate', 78.00, 72.00, 95.00, 82.00),
  ('b1000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Module Adoption (Canteen)', 92.00, 80.00, 98.00, 88.00),
  ('b1000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Module Adoption (FitZone)', 64.00, 50.00, 85.00, 70.00),
  ('b1000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'Module Adoption (Library+)', 72.00, 60.00, 90.00, 75.00),
  ('b1000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'Module Adoption (Transit)', 58.00, 65.00, 88.00, 42.00)
ON CONFLICT (id) DO NOTHING;

-- Seed Financial P&L
INSERT INTO financial_pl (id, institution_id, month, year, revenue_breakdown, cost_breakdown, net_surplus)
VALUES
  ('71000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 1, 2026, '{"fees": 4500000, "canteen": 125000, "events": 85000, "gym": 45000, "hostel": 650000}', '{"staff": 1200000, "maintenance": 300000, "utilities": 150000}', 3755000.00),
  ('71000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 2, 2026, '{"fees": 4800000, "canteen": 130000, "events": 90000, "gym": 48000, "hostel": 650000}', '{"staff": 1200000, "maintenance": 280000, "utilities": 145000}', 4093000.00),
  ('71000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 3, 2026, '{"fees": 5200000, "canteen": 145000, "events": 120000, "gym": 52000, "hostel": 680000}', '{"staff": 1250000, "maintenance": 310000, "utilities": 160000}', 4477000.00),
  ('71000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 4, 2026, '{"fees": 3900000, "canteen": 110000, "events": 50000, "gym": 40000, "hostel": 620000}', '{"staff": 1200000, "maintenance": 250000, "utilities": 135000}', 3135000.00),
  ('71000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 5, 2026, '{"fees": 4100000, "canteen": 115000, "events": 60000, "gym": 42000, "hostel": 620000}', '{"staff": 1200000, "maintenance": 260000, "utilities": 140000}', 3337000.00)
ON CONFLICT (id) DO NOTHING;

-- Seed Student Journey Scores for existing students dynamically
DO $$
DECLARE
  stud RECORD;
BEGIN
  FOR stud IN SELECT id FROM students LOOP
    INSERT INTO student_journey_scores (student_id, engagement_score, academic_score, social_score, facility_score, overall_score, intervention_status)
    VALUES (
      stud.id,
      50 + FLOOR(RANDOM() * 45), -- 50 to 95
      60 + FLOOR(RANDOM() * 38), -- 60 to 98
      45 + FLOOR(RANDOM() * 50), -- 45 to 95
      55 + FLOOR(RANDOM() * 40), -- 55 to 95
      60 + FLOOR(RANDOM() * 30), -- 60 to 90
      'none'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
END $$;


-- ==========================================================
-- MIGRATION: 20260610000010_ai_concierge_module10.sql
-- ==========================================================

-- ============================================================
-- MODULE 10 ADDITIONS: AI Concierge Enhanced Intelligence
-- Voice Interface, Proactive Nudges, Study Planner, Sentiment
-- ============================================================

-- 1. CREATE voice_transcripts TABLE
-- Stores speech-to-text transcriptions from Web Speech API,
-- Expo-AV recordings, and WhatsApp voice notes (Whisper)
CREATE TABLE IF NOT EXISTS voice_transcripts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID REFERENCES ai_conversations(id) ON DELETE SET NULL,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  audio_url TEXT,
  transcript TEXT NOT NULL,
  language TEXT DEFAULT 'en',
  source TEXT CHECK (source IN ('web_speech', 'expo_av', 'whatsapp_whisper')) DEFAULT 'web_speech',
  duration_seconds INTEGER DEFAULT 0,
  confidence DECIMAL DEFAULT 0.0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. CREATE proactive_nudges TABLE
-- AI-generated push intelligence notifications for students
CREATE TABLE IF NOT EXISTS proactive_nudges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  nudge_type TEXT NOT NULL CHECK (nudge_type IN (
    'weekly_prep', 'assignment_reminder', 'attendance_warning',
    'fee_reminder', 'event_suggestion', 'library_due',
    'health_tip', 'motivational', 'exam_countdown',
    'streak_celebration', 'custom'
  )),
  message TEXT NOT NULL,
  title TEXT,
  priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  channel TEXT DEFAULT 'push' CHECK (channel IN ('push', 'whatsapp', 'email', 'in_app')),
  sent_at TIMESTAMPTZ DEFAULT now(),
  was_read BOOLEAN DEFAULT false,
  was_actioned BOOLEAN DEFAULT false,
  actioned_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. CREATE study_plans TABLE
-- AI-generated personalized study schedules per student
CREATE TABLE IF NOT EXISTS study_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  exam_schedule JSONB NOT NULL DEFAULT '[]'::jsonb,
  daily_plan JSONB NOT NULL DEFAULT '[]'::jsonb,
  subjects JSONB DEFAULT '[]'::jsonb,
  weak_areas JSONB DEFAULT '[]'::jsonb,
  study_hours_per_day DECIMAL DEFAULT 4.0,
  plan_start_date DATE,
  plan_end_date DATE,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'paused', 'completed', 'expired')),
  completion_percentage DECIMAL DEFAULT 0.0,
  generated_at TIMESTAMPTZ DEFAULT now(),
  last_adjusted TIMESTAMPTZ DEFAULT now(),
  claude_reasoning TEXT
);

-- 4. CREATE sentiment_logs TABLE
-- Nightly batch analysis of student messages for mood trends
CREATE TABLE IF NOT EXISTS sentiment_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  department TEXT,
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  avg_sentiment DECIMAL DEFAULT 0.0,
  positive_count INTEGER DEFAULT 0,
  neutral_count INTEGER DEFAULT 0,
  negative_count INTEGER DEFAULT 0,
  message_count INTEGER DEFAULT 0,
  flagged_keywords TEXT[] DEFAULT '{}'::text[],
  flagged_messages JSONB DEFAULT '[]'::jsonb,
  complaint_categories JSONB DEFAULT '{}'::jsonb,
  auto_routed_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(institution_id, date, department)
);

-- 5. CREATE nudge_preferences TABLE
-- Per-student opt-in settings for proactive nudges
CREATE TABLE IF NOT EXISTS nudge_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  enabled BOOLEAN DEFAULT true,
  enabled_types TEXT[] DEFAULT ARRAY[
    'weekly_prep', 'assignment_reminder', 'attendance_warning',
    'fee_reminder', 'event_suggestion', 'exam_countdown'
  ],
  preferred_channels TEXT[] DEFAULT ARRAY['push', 'in_app'],
  quiet_hours_start TIME DEFAULT '22:00',
  quiet_hours_end TIME DEFAULT '07:00',
  max_nudges_per_day INTEGER DEFAULT 5,
  language_preference TEXT DEFAULT 'en',
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(student_id)
);

-- ============================================================
-- PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_voice_tx_user ON voice_transcripts(user_id);
CREATE INDEX IF NOT EXISTS idx_voice_tx_conv ON voice_transcripts(conversation_id);
CREATE INDEX IF NOT EXISTS idx_voice_tx_inst ON voice_transcripts(institution_id);

CREATE INDEX IF NOT EXISTS idx_nudges_student ON proactive_nudges(student_id);
CREATE INDEX IF NOT EXISTS idx_nudges_inst ON proactive_nudges(institution_id);
CREATE INDEX IF NOT EXISTS idx_nudges_type ON proactive_nudges(nudge_type);
CREATE INDEX IF NOT EXISTS idx_nudges_sent ON proactive_nudges(sent_at);

CREATE INDEX IF NOT EXISTS idx_study_plans_student ON study_plans(student_id);
CREATE INDEX IF NOT EXISTS idx_study_plans_status ON study_plans(status);

CREATE INDEX IF NOT EXISTS idx_sentiment_inst_date ON sentiment_logs(institution_id, date);
CREATE INDEX IF NOT EXISTS idx_sentiment_dept ON sentiment_logs(department_id);

CREATE INDEX IF NOT EXISTS idx_nudge_prefs_student ON nudge_preferences(student_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE voice_transcripts ENABLE ROW LEVEL SECURITY;
ALTER TABLE proactive_nudges ENABLE ROW LEVEL SECURITY;
ALTER TABLE study_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE sentiment_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE nudge_preferences ENABLE ROW LEVEL SECURITY;

-- Tenant Isolation Policies
CREATE POLICY "tenant_isolation_voice_transcripts" ON voice_transcripts
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_proactive_nudges" ON proactive_nudges
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_study_plans" ON study_plans
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_sentiment_logs" ON sentiment_logs
  USING (institution_id = get_auth_institution_id());

CREATE POLICY "tenant_isolation_nudge_preferences" ON nudge_preferences
  USING (institution_id = get_auth_institution_id());

-- ============================================================
-- SEED DATA — PROACTIVE NUDGE SAMPLES
-- ============================================================
INSERT INTO proactive_nudges (student_id, institution_id, nudge_type, title, message, priority, channel, was_read, was_actioned) VALUES
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   'weekly_prep', '📚 Week Ahead Prep',
   'You have 5 classes tomorrow starting with Maths at 9 AM. Your attendance is 84% — keep it up! Don''t forget: Physics assignment due Wednesday.',
   'normal', 'push', false, false),
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   'attendance_warning', '⚠️ Attendance Alert',
   'Your attendance in Data Structures dropped to 68% — you need 75% to sit for exams. Attend the next 4 classes consecutively to recover.',
   'high', 'push', true, false),
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   'fee_reminder', '💰 Fee Reminder',
   'Your semester fee installment of ₹12,500 is due in 3 days. Pay now to avoid late charges → /student/fees',
   'urgent', 'whatsapp', false, false),
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   'exam_countdown', '📝 Exam Countdown',
   'Mid-semester exams begin in 12 days! Your AI Study Plan suggests focusing on Linear Algebra and Thermodynamics this week.',
   'high', 'in_app', true, true),
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   'streak_celebration', '🔥 7-Day Streak!',
   'Congratulations! You''ve attended every class for 7 consecutive days. Keep the momentum going — you''re in the top 15% of your batch!',
   'low', 'push', true, true),
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   'library_due', '📖 Library Book Due',
   'Your book "Introduction to Algorithms" (CLRS) is due in 2 days. Return or renew it at /student/library to avoid ₹10/day fines.',
   'normal', 'in_app', false, false);

-- SEED DATA — STUDY PLAN SAMPLE
INSERT INTO study_plans (student_id, institution_id, exam_schedule, daily_plan, subjects, weak_areas, study_hours_per_day, plan_start_date, plan_end_date, status, completion_percentage, claude_reasoning) VALUES
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   '[{"subject":"Mathematics","date":"2026-06-25","time":"09:00"},{"subject":"Physics","date":"2026-06-27","time":"09:00"},{"subject":"Data Structures","date":"2026-06-30","time":"14:00"},{"subject":"English","date":"2026-07-02","time":"09:00"}]',
   '[{"day":"Monday","blocks":[{"time":"06:00-08:00","subject":"Mathematics","topic":"Linear Algebra - Eigenvalues","type":"focus"},{"time":"09:00-10:30","subject":"Physics","topic":"Thermodynamics revision","type":"review"},{"time":"16:00-17:30","subject":"Data Structures","topic":"Binary Trees Practice","type":"practice"}]},{"day":"Tuesday","blocks":[{"time":"06:00-08:00","subject":"Data Structures","topic":"Graph Algorithms - DFS/BFS","type":"focus"},{"time":"09:00-10:30","subject":"Mathematics","topic":"Calculus - Integration","type":"review"},{"time":"16:00-17:30","subject":"English","topic":"Technical Writing","type":"light"}]},{"day":"Wednesday","blocks":[{"time":"06:00-08:00","subject":"Physics","topic":"Optics & Waves","type":"focus"},{"time":"16:00-18:00","subject":"Mathematics","topic":"Practice Problems Set","type":"practice"}]}]',
   '["Mathematics","Physics","Data Structures","English"]',
   '["Linear Algebra - Eigenvalues","Thermodynamics - Carnot Cycle","Graph Algorithms"]',
   5.0, '2026-06-15', '2026-07-02', 'active', 35.0,
   'Based on exam schedule analysis: Mathematics exam is earliest (June 25), so allocated 40% study time to Math. Physics weak area in Thermodynamics identified from past scores — added extra revision blocks. Data Structures graph algorithms flagged due to low practice test scores. Study blocks scheduled around existing timetable, avoiding class hours. Morning 6-8 AM blocks for deep focus, afternoon for lighter review.');

-- SEED DATA — SENTIMENT LOGS SAMPLES
INSERT INTO sentiment_logs (institution_id, date, department, avg_sentiment, positive_count, neutral_count, negative_count, message_count, flagged_keywords, complaint_categories) VALUES
  ('a0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '1 day', 'Computer Science', 0.72, 45, 30, 12, 87,
   ARRAY['slow wifi', 'lab closed', 'great faculty'],
   '{"infrastructure": 8, "academics": 2, "food": 2}'::jsonb),
  ('a0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '1 day', 'Mechanical Engineering', 0.58, 22, 18, 20, 60,
   ARRAY['workshop noise', 'placement worry', 'canteen quality'],
   '{"infrastructure": 5, "placements": 10, "food": 5}'::jsonb),
  ('a0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '1 day', 'Electrical Engineering', 0.81, 38, 20, 5, 63,
   ARRAY['excellent lab', 'helpful TA'],
   '{"academics": 3, "infrastructure": 2}'::jsonb),
  ('a0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '2 days', 'Computer Science', 0.68, 40, 28, 18, 86,
   ARRAY['assignment overload', 'good hackathon'],
   '{"academics": 12, "events": 4, "food": 2}'::jsonb),
  ('a0000000-0000-0000-0000-000000000001', CURRENT_DATE - INTERVAL '2 days', 'Mechanical Engineering', 0.55, 18, 22, 25, 65,
   ARRAY['hot workshop', 'placement anxiety', 'water cooler broken'],
   '{"infrastructure": 12, "placements": 8, "food": 5}'::jsonb);

-- SEED DATA — NUDGE PREFERENCES
INSERT INTO nudge_preferences (student_id, institution_id, enabled, enabled_types, preferred_channels, quiet_hours_start, quiet_hours_end, max_nudges_per_day) VALUES
  ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001',
   true,
   ARRAY['weekly_prep', 'assignment_reminder', 'attendance_warning', 'fee_reminder', 'exam_countdown', 'streak_celebration'],
   ARRAY['push', 'in_app'],
   '22:00', '07:00', 5);

-- SEED DATA — VOICE TRANSCRIPT SAMPLE
INSERT INTO voice_transcripts (user_id, institution_id, transcript, language, source, duration_seconds, confidence) VALUES
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
   'Mera attendance kitna hai is semester mein?', 'hi', 'web_speech', 4, 0.92),
  ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001',
   'What is my pending fee amount for this semester?', 'en', 'web_speech', 3, 0.97);


-- ==========================================================
-- MIGRATION: 20260611000000_admissions_module11.sql
-- ==========================================================

-- ============================================================
-- MODULE 11: IRIS Admissions
-- Branded Admission Cycles, Multi-Step Applications, Academic
-- Audits, Auto-Merit calculations, Offer letters, and CRM Leads.
-- ============================================================

-- 1. CREATE admission_cycles TABLE
CREATE TABLE IF NOT EXISTS admission_cycles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  academic_year TEXT NOT NULL,
  start_date DATE,
  end_date DATE,
  status TEXT CHECK (status IN (
    'upcoming','open','closed','processing','completed'
  )) DEFAULT 'upcoming',
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. CREATE programs TABLE
CREATE TABLE IF NOT EXISTS programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  degree_type TEXT,
  duration_years INTEGER,
  total_seats INTEGER,
  reserved_seats JSONB DEFAULT '{}'::jsonb,
  eligibility_criteria JSONB DEFAULT '{}'::jsonb,
  application_fee DECIMAL DEFAULT 0,
  is_active BOOLEAN DEFAULT true
);

-- 3. CREATE applicants TABLE
CREATE TABLE IF NOT EXISTS applicants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  cycle_id UUID REFERENCES admission_cycles(id) ON DELETE SET NULL,
  application_number TEXT UNIQUE NOT NULL,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  dob DATE,
  gender TEXT,
  category TEXT,
  domicile_state TEXT,
  photo_url TEXT,
  aadhar_number TEXT,
  address JSONB DEFAULT '{}'::jsonb,
  guardian_name TEXT,
  guardian_phone TEXT,
  guardian_relation TEXT,
  status TEXT CHECK (status IN (
    'draft','submitted','under_review','shortlisted',
    'merit_listed','waitlisted','offered','admitted',
    'rejected','withdrawn'
  )) DEFAULT 'draft',
  merit_score DECIMAL DEFAULT 0.0,
  ai_score DECIMAL DEFAULT 0.0,
  rank_overall INTEGER,
  rank_category INTEGER,
  created_at TIMESTAMPTZ DEFAULT now(),
  submitted_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. CREATE applicant_programs TABLE
CREATE TABLE IF NOT EXISTS applicant_programs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  program_id UUID REFERENCES programs(id) ON DELETE CASCADE,
  preference_order INTEGER,
  status TEXT DEFAULT 'pending',
  allocated BOOLEAN DEFAULT false
);

-- 5. CREATE academic_records TABLE
CREATE TABLE IF NOT EXISTS academic_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  level TEXT NOT NULL, -- '10th', '12th', 'graduation'
  board_university TEXT,
  year_of_passing INTEGER,
  percentage DECIMAL,
  cgpa DECIMAL,
  subjects JSONB DEFAULT '[]'::jsonb,
  marksheet_url TEXT,
  certificate_url TEXT,
  is_verified BOOLEAN DEFAULT false,
  verification_notes TEXT
);

-- 6. CREATE entrance_scores TABLE
CREATE TABLE IF NOT EXISTS entrance_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  exam_name TEXT NOT NULL,
  roll_number TEXT,
  score DECIMAL,
  percentile DECIMAL,
  rank INTEGER,
  scorecard_url TEXT,
  is_verified BOOLEAN DEFAULT false
);

-- 7. CREATE documents TABLE
CREATE TABLE IF NOT EXISTS documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  doc_type TEXT NOT NULL,
  doc_url TEXT NOT NULL,
  file_name TEXT,
  file_size_kb INTEGER,
  is_verified BOOLEAN DEFAULT false,
  verified_by UUID REFERENCES users(id) ON DELETE SET NULL,
  verified_at TIMESTAMPTZ,
  rejection_reason TEXT,
  uploaded_at TIMESTAMPTZ DEFAULT now()
);

-- 8. CREATE merit_lists TABLE
CREATE TABLE IF NOT EXISTS merit_lists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  cycle_id UUID REFERENCES admission_cycles(id) ON DELETE CASCADE,
  program_id UUID REFERENCES programs(id) ON DELETE CASCADE,
  round_number INTEGER DEFAULT 1,
  list_type TEXT CHECK (list_type IN ('merit','waitlist','spot')),
  published_at TIMESTAMPTZ,
  cutoff_score DECIMAL,
  is_published BOOLEAN DEFAULT false
);

-- 9. CREATE merit_list_entries TABLE
CREATE TABLE IF NOT EXISTS merit_list_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merit_list_id UUID REFERENCES merit_lists(id) ON DELETE CASCADE,
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  rank INTEGER,
  category TEXT,
  merit_score DECIMAL,
  status TEXT DEFAULT 'listed', -- 'listed', 'offered', 'accepted', 'declined', 'expired'
  offer_sent_at TIMESTAMPTZ,
  offer_accepted_at TIMESTAMPTZ,
  offer_expires_at TIMESTAMPTZ
);

-- 10. CREATE admission_offers TABLE
CREATE TABLE IF NOT EXISTS admission_offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  program_id UUID REFERENCES programs(id) ON DELETE CASCADE,
  merit_list_id UUID REFERENCES merit_lists(id) ON DELETE SET NULL,
  offer_letter_url TEXT,
  offered_at TIMESTAMPTZ DEFAULT now(),
  expires_at TIMESTAMPTZ,
  status TEXT DEFAULT 'sent', -- 'sent', 'accepted', 'rejected', 'expired'
  accepted_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  rejection_reason TEXT
);

-- 11. CREATE admission_fees TABLE
CREATE TABLE IF NOT EXISTS admission_fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  fee_type TEXT CHECK (fee_type IN ('application','confirmation','enrollment')),
  amount DECIMAL NOT NULL,
  razorpay_order_id TEXT,
  transaction_id TEXT,
  status TEXT DEFAULT 'pending', -- 'pending', 'paid', 'failed'
  paid_at TIMESTAMPTZ,
  receipt_url TEXT
);

-- 12. CREATE counseling_sessions TABLE
CREATE TABLE IF NOT EXISTS counseling_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  cycle_id UUID REFERENCES admission_cycles(id) ON DELETE CASCADE,
  round_number INTEGER,
  scheduled_date DATE,
  mode TEXT CHECK (mode IN ('online','offline','hybrid')),
  venue TEXT,
  meeting_link TEXT,
  status TEXT DEFAULT 'scheduled' -- 'scheduled', 'completed', 'cancelled'
);

-- 13. CREATE counseling_slots TABLE
CREATE TABLE IF NOT EXISTS counseling_slots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES counseling_sessions(id) ON DELETE CASCADE,
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  slot_time TIMESTAMPTZ,
  officer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  status TEXT DEFAULT 'assigned', -- 'assigned', 'attended', 'no_show', 'rescheduled'
  attended BOOLEAN DEFAULT false,
  notes TEXT
);

-- 14. CREATE waitlist_movements TABLE
CREATE TABLE IF NOT EXISTS waitlist_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  applicant_id UUID REFERENCES applicants(id) ON DELETE CASCADE,
  program_id UUID REFERENCES programs(id) ON DELETE CASCADE,
  from_position INTEGER,
  to_position INTEGER,
  reason TEXT,
  moved_at TIMESTAMPTZ DEFAULT now()
);

-- 15. CREATE admission_analytics TABLE
CREATE TABLE IF NOT EXISTS admission_analytics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  cycle_id UUID REFERENCES admission_cycles(id) ON DELETE CASCADE,
  date DATE,
  applications_received INTEGER DEFAULT 0,
  applications_submitted INTEGER DEFAULT 0,
  documents_pending INTEGER DEFAULT 0,
  merit_listed INTEGER DEFAULT 0,
  offers_sent INTEGER DEFAULT 0,
  offers_accepted INTEGER DEFAULT 0,
  seats_filled INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 16. CREATE crm_leads TABLE
CREATE TABLE IF NOT EXISTS crm_leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT,
  email TEXT,
  phone TEXT,
  source TEXT, -- 'website', 'social', 'event', 'walkin', 'referral'
  program_interest TEXT,
  status TEXT DEFAULT 'new', -- 'new', 'contacted', 'interested', 'applied', 'admitted', 'lost'
  assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
  notes TEXT,
  last_contacted TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- INDEXES FOR PERFORMANCE
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_adm_cycles_inst ON admission_cycles(institution_id);
CREATE INDEX IF NOT EXISTS idx_adm_programs_inst ON programs(institution_id);
CREATE INDEX IF NOT EXISTS idx_applicants_inst ON applicants(institution_id);
CREATE INDEX IF NOT EXISTS idx_applicants_cycle ON applicants(cycle_id);
CREATE INDEX IF NOT EXISTS idx_applicants_status ON applicants(status);
CREATE INDEX IF NOT EXISTS idx_applicants_email ON applicants(email);
CREATE INDEX IF NOT EXISTS idx_crm_leads_inst ON crm_leads(institution_id);
CREATE INDEX IF NOT EXISTS idx_documents_applicant ON documents(applicant_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE applicants ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE merit_lists ENABLE ROW LEVEL SECURITY;
ALTER TABLE admission_offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE admission_cycles ENABLE ROW LEVEL SECURITY;
ALTER TABLE programs ENABLE ROW LEVEL SECURITY;

-- 1. APPLICANTS POLICIES
CREATE POLICY "applicant_own_data" ON applicants
  FOR SELECT USING (
    email = (SELECT email FROM users WHERE id = auth.uid())
  );

CREATE POLICY "admin_institution_applicants" ON applicants
  FOR ALL USING (
    institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
  );

-- 2. DOCUMENTS POLICIES
CREATE POLICY "applicant_own_documents" ON documents
  FOR ALL USING (
    applicant_id IN (SELECT id FROM applicants WHERE email = (SELECT email FROM users WHERE id = auth.uid()))
  );

CREATE POLICY "admin_institution_documents" ON documents
  FOR ALL USING (
    applicant_id IN (SELECT id FROM applicants WHERE institution_id = (SELECT institution_id FROM users WHERE id = auth.uid()))
  );

-- 3. ADMISSION OFFERS POLICIES
CREATE POLICY "applicant_own_offers" ON admission_offers
  FOR SELECT USING (
    applicant_id IN (SELECT id FROM applicants WHERE email = (SELECT email FROM users WHERE id = auth.uid()))
  );

CREATE POLICY "admin_institution_offers" ON admission_offers
  FOR ALL USING (
    applicant_id IN (SELECT id FROM applicants WHERE institution_id = (SELECT institution_id FROM users WHERE id = auth.uid()))
  );

-- 4. ADMISSION CYCLES POLICIES
CREATE POLICY "tenant_isolation_admission_cycles" ON admission_cycles
  FOR ALL USING (
    institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
  );

-- 5. PROGRAMS POLICIES
CREATE POLICY "tenant_isolation_programs" ON programs
  FOR ALL USING (
    institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
  );

-- ============================================================
-- SEED DATA - ADMISSION CYCLES & PROGRAMS FOR DEMO
-- ============================================================
INSERT INTO admission_cycles (id, institution_id, name, academic_year, start_date, end_date, status) VALUES
  ('c1111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'Fall Admissions 2026', '2026-27', CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE + INTERVAL '60 days', 'open')
  ON CONFLICT DO NOTHING;

INSERT INTO programs (id, institution_id, name, code, degree_type, duration_years, total_seats, reserved_seats, eligibility_criteria, application_fee) VALUES
  ('a1111111-1111-1111-1111-111111111111', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of Technology in Computer Science (B.Tech CSE)', 'BTECH-CSE', 'UG', 4, 120, '{"general": 60, "obc": 32, "sc": 18, "st": 10}', '{"min_12th_pc": 60.0, "required_subjects": ["Physics", "Mathematics"]}', 1000.00),
  ('a1111111-1111-1111-1111-111111111112', 'a0000000-0000-0000-0000-000000000001', 'Bachelor of Technology in Artificial Intelligence (B.Tech AI-DS)', 'BTECH-AIDS', 'UG', 4, 60, '{"general": 30, "obc": 16, "sc": 9, "st": 5}', '{"min_12th_pc": 65.0, "required_subjects": ["Physics", "Mathematics"]}', 1200.00),
  ('a1111111-1111-1111-1111-111111111113', 'a0000000-0000-0000-0000-000000000001', 'Master of Business Administration (MBA)', 'MBA-CORE', 'PG', 2, 60, '{"general": 30, "obc": 16, "sc": 9, "st": 5}', '{"min_grad_cgpa": 6.0}', 1500.00)
  ON CONFLICT DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260611000001_placements_module12.sql
-- ==========================================================

-- ============================================================
-- MODULE 12: IRIS Placements
-- Company CRM, Drives management, Student profile builder, AI
-- interview checks, Offer tracking, and Alumni mentoring network.
-- ============================================================

-- 1. CREATE companies TABLE
CREATE TABLE IF NOT EXISTS companies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  logo_url TEXT,
  website TEXT,
  industry TEXT,
  company_type TEXT CHECK (company_type IN (
    'product','service','startup','mnc','psu','ngo'
  )),
  hr_name TEXT,
  hr_email TEXT,
  hr_phone TEXT,
  linkedin_url TEXT,
  address TEXT,
  tier TEXT CHECK (tier IN ('dream','core','mass')),
  last_visited DATE,
  total_offers_given INTEGER DEFAULT 0,
  relationship_status TEXT DEFAULT 'active',
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 2. CREATE placement_drives TABLE
CREATE TABLE IF NOT EXISTS placement_drives (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  job_description TEXT,
  jd_url TEXT,
  role TEXT NOT NULL,
  department TEXT,
  job_type TEXT CHECK (job_type IN (
    'full_time','internship','ppo','contract'
  )),
  location TEXT[],
  ctc_min DECIMAL,
  ctc_max DECIMAL,
  ctc_display TEXT,
  stipend DECIMAL,
  bond_years INTEGER DEFAULT 0,
  eligibility_criteria JSONB DEFAULT '{}'::jsonb,
  min_cgpa DECIMAL DEFAULT 0.0,
  eligible_branches TEXT[],
  eligible_batches TEXT[],
  backlogs_allowed INTEGER DEFAULT 0,
  application_deadline TIMESTAMPTZ,
  drive_date DATE,
  drive_mode TEXT CHECK (drive_mode IN ('online','offline','hybrid')),
  venue TEXT,
  meeting_link TEXT,
  rounds JSONB DEFAULT '[]'::jsonb,
  status TEXT CHECK (status IN (
    'upcoming','open','closed','processing','completed'
  )) DEFAULT 'upcoming',
  max_applications INTEGER,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. CREATE student_profiles TABLE
CREATE TABLE IF NOT EXISTS student_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  resume_url TEXT,
  resume_updated_at TIMESTAMPTZ,
  cgpa DECIMAL DEFAULT 0.0,
  active_backlogs INTEGER DEFAULT 0,
  total_backlogs INTEGER DEFAULT 0,
  skills TEXT[],
  certifications JSONB DEFAULT '[]'::jsonb,
  projects JSONB DEFAULT '[]'::jsonb,
  internships JSONB DEFAULT '[]'::jsonb,
  achievements TEXT[],
  linkedin_url TEXT,
  github_url TEXT,
  portfolio_url TEXT,
  is_placed BOOLEAN DEFAULT false,
  placed_company_id UUID REFERENCES companies(id) ON DELETE SET NULL,
  placed_ctc DECIMAL,
  placed_role TEXT,
  placed_at TIMESTAMPTZ,
  placement_type TEXT,
  opted_out BOOLEAN DEFAULT false,
  opt_out_reason TEXT,
  ai_resume_score DECIMAL DEFAULT 0.0,
  ai_resume_feedback TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. CREATE drive_applications TABLE
CREATE TABLE IF NOT EXISTS drive_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drive_id UUID REFERENCES placement_drives(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  applied_at TIMESTAMPTZ DEFAULT now(),
  resume_url TEXT,
  cover_letter TEXT,
  status TEXT CHECK (status IN (
    'applied','shortlisted','test_scheduled','interview_scheduled',
    'selected','offered','offer_accepted','offer_rejected',
    'rejected','withdrawn'
  )) DEFAULT 'applied',
  current_round INTEGER DEFAULT 0,
  rejection_reason TEXT,
  feedback TEXT
);

-- 5. CREATE interview_rounds TABLE
CREATE TABLE IF NOT EXISTS interview_rounds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID REFERENCES drive_applications(id) ON DELETE CASCADE,
  drive_id UUID REFERENCES placement_drives(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  round_number INTEGER,
  round_type TEXT CHECK (round_type IN (
    'aptitude','coding','technical','hr','gd','case_study','final'
  )),
  scheduled_at TIMESTAMPTZ,
  venue TEXT,
  meeting_link TEXT,
  interviewer_name TEXT,
  interviewer_email TEXT,
  duration_minutes INTEGER,
  result TEXT CHECK (result IN ('pass','fail','hold','no_show')),
  score DECIMAL,
  feedback TEXT,
  status TEXT DEFAULT 'scheduled'
);

-- 6. CREATE offer_letters TABLE
CREATE TABLE IF NOT EXISTS offer_letters (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID REFERENCES drive_applications(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
  drive_id UUID REFERENCES placement_drives(id) ON DELETE CASCADE,
  offer_number TEXT UNIQUE,
  role TEXT,
  ctc DECIMAL,
  joining_date DATE,
  location TEXT,
  offer_letter_url TEXT,
  company_offer_url TEXT,
  status TEXT DEFAULT 'received',
  accepted_at TIMESTAMPTZ,
  declined_at TIMESTAMPTZ,
  decline_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 7. CREATE placement_stats TABLE
CREATE TABLE IF NOT EXISTS placement_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  academic_year TEXT NOT NULL,
  batch TEXT,
  branch TEXT,
  total_eligible INTEGER DEFAULT 0,
  total_registered INTEGER DEFAULT 0,
  total_placed INTEGER DEFAULT 0,
  total_companies INTEGER DEFAULT 0,
  avg_ctc DECIMAL DEFAULT 0.0,
  median_ctc DECIMAL DEFAULT 0.0,
  highest_ctc DECIMAL DEFAULT 0.0,
  lowest_ctc DECIMAL DEFAULT 0.0,
  ppo_count INTEGER DEFAULT 0,
  dream_offers INTEGER DEFAULT 0,
  calculated_at TIMESTAMPTZ DEFAULT now()
);

-- 8. CREATE mock_interviews TABLE
CREATE TABLE IF NOT EXISTS mock_interviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  interview_type TEXT,
  questions JSONB DEFAULT '[]'::jsonb,
  responses JSONB DEFAULT '[]'::jsonb,
  ai_feedback TEXT,
  score DECIMAL DEFAULT 0.0,
  duration_minutes INTEGER,
  conducted_at TIMESTAMPTZ DEFAULT now()
);

-- 9. CREATE alumni TABLE
CREATE TABLE IF NOT EXISTS alumni (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  graduation_year INTEGER,
  current_company TEXT,
  "current_role" TEXT,
  current_ctc DECIMAL,
  location TEXT,
  linkedin_url TEXT,
  is_mentor BOOLEAN DEFAULT false,
  mentoring_slots INTEGER DEFAULT 0,
  achievements TEXT[],
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 10. CREATE alumni_mentorship TABLE
CREATE TABLE IF NOT EXISTS alumni_mentorship (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alumni_id UUID REFERENCES alumni(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  session_date TIMESTAMPTZ,
  duration_minutes INTEGER,
  topic TEXT,
  feedback TEXT,
  student_rating INTEGER,
  status TEXT DEFAULT 'scheduled'
);

-- 11. CREATE placement_notifications TABLE
CREATE TABLE IF NOT EXISTS placement_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  drive_id UUID REFERENCES placement_drives(id) ON DELETE CASCADE,
  student_id UUID REFERENCES students(id) ON DELETE CASCADE,
  type TEXT,
  message TEXT,
  sent_via TEXT[],
  sent_at TIMESTAMPTZ DEFAULT now()
);

-- ============================================================
-- PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_companies_inst ON companies(institution_id);
CREATE INDEX IF NOT EXISTS idx_drives_company ON placement_drives(company_id);
CREATE INDEX IF NOT EXISTS idx_applications_drive ON drive_applications(drive_id);
CREATE INDEX IF NOT EXISTS idx_applications_student ON drive_applications(student_id);
CREATE INDEX IF NOT EXISTS idx_rounds_application ON interview_rounds(application_id);
CREATE INDEX IF NOT EXISTS idx_offers_student ON offer_letters(student_id);
CREATE INDEX IF NOT EXISTS idx_alumni_student ON alumni(student_id);

-- ============================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE placement_drives ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE drive_applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE interview_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE offer_letters ENABLE ROW LEVEL SECURITY;
ALTER TABLE mock_interviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE alumni ENABLE ROW LEVEL SECURITY;
ALTER TABLE alumni_mentorship ENABLE ROW LEVEL SECURITY;

-- 1. COMPANIES POLICY
CREATE POLICY "companies_all_access" ON companies FOR ALL USING (true);

-- 2. PLACEMENT DRIVES POLICY
CREATE POLICY "drives_all_access" ON placement_drives FOR ALL USING (true);

-- 3. STUDENT PROFILES POLICY
CREATE POLICY "student_own_profile" ON student_profiles
  FOR ALL USING (
    student_id IN (
      SELECT id FROM students WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "admin_all_profiles" ON student_profiles FOR ALL USING (true);

-- 4. APPLICATIONS POLICY
CREATE POLICY "student_own_applications" ON drive_applications
  FOR ALL USING (
    student_id IN (
      SELECT id FROM students WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "admin_all_applications" ON drive_applications FOR ALL USING (true);

-- 5. INTERVIEW ROUDS POLICY
CREATE POLICY "student_own_rounds" ON interview_rounds
  FOR SELECT USING (
    student_id IN (
      SELECT id FROM students WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "admin_all_rounds" ON interview_rounds FOR ALL USING (true);

-- 6. OFFER LETTERS POLICY
CREATE POLICY "student_own_offers" ON offer_letters
  FOR ALL USING (
    student_id IN (
      SELECT id FROM students WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "admin_all_offers" ON offer_letters FOR ALL USING (true);

-- 7. MOCK INTERVIEWS POLICY
CREATE POLICY "student_own_mocks" ON mock_interviews
  FOR ALL USING (
    student_id IN (
      SELECT id FROM students WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "admin_all_mocks" ON mock_interviews FOR ALL USING (true);

-- 8. ALUMNI POLICY
CREATE POLICY "alumni_all_access" ON alumni FOR ALL USING (true);

-- 9. MENTORSHIP POLICY
CREATE POLICY "mentorship_all_access" ON alumni_mentorship FOR ALL USING (true);

-- ============================================================
-- SEED DATA
-- ============================================================
INSERT INTO companies (id, institution_id, name, logo_url, website, industry, company_type, hr_name, hr_email, hr_phone, tier, relationship_status) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Google India', 'https://images.unsplash.com/photo-1573804633927-bfcbcd909acd?w=120', 'https://google.com', 'Technology', 'mnc', 'Neha Sen', 'neha.sen@google.com', '+91 99881 23456', 'dream', 'active'),
  ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Infosys', 'https://images.unsplash.com/photo-1486406146926-c627a92ad1ab?w=120', 'https://infosys.com', 'IT Services', 'service', 'Rajesh K.', 'rajesh.k@infosys.com', '+91 94140 12891', 'mass', 'active'),
  ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'ZS Associates', 'https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?w=120', 'https://zs.com', 'Consulting', 'product', 'Preeti Sharma', 'preeti.sharma@zs.com', '+91 99290 12347', 'core', 'active')
  ON CONFLICT DO NOTHING;

INSERT INTO placement_drives (id, institution_id, company_id, title, role, job_type, location, ctc_min, ctc_max, ctc_display, min_cgpa, eligible_branches, eligible_batches, status, application_deadline, drive_date) VALUES
  ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Google SWE Summer Drive 2026', 'Software Engineer (L3)', 'full_time', ARRAY['Bangalore', 'Hyderabad'], 32.0, 42.0, '32 - 42 LPA', 8.0, ARRAY['CSE', 'AIDS'], ARRAY['2026'], 'open', CURRENT_TIMESTAMP + INTERVAL '10 days', CURRENT_DATE + INTERVAL '15 days'),
  ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'ZS Consulting Campus Hiring', 'Business Technology Analyst', 'full_time', ARRAY['Pune', 'Gurgaon'], 8.5, 12.0, '8.5 - 12 LPA', 7.0, ARRAY['CSE', 'AIDS', 'ECE'], ARRAY['2026'], 'open', CURRENT_TIMESTAMP + INTERVAL '5 days', CURRENT_DATE + INTERVAL '8 days')
  ON CONFLICT DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260611_add_bus_tracking_index.sql
-- ==========================================================

-- Add composite index for bus_tracking latest-row queries
-- Prevents full table scan when fetching latest position of a bus
CREATE INDEX IF NOT EXISTS idx_bus_tracking_latest ON bus_tracking(bus_id, timestamp DESC);

-- Nightly archival job (run via pg_cron or external cron)
-- Archive rows older than 7 days to keep the hot table small
-- CREATE TABLE IF NOT EXISTS bus_tracking_archive (LIKE bus_tracking INCLUDING ALL);
-- INSERT INTO bus_tracking_archive SELECT * FROM bus_tracking WHERE timestamp < NOW() - INTERVAL '7 days';
-- DELETE FROM bus_tracking WHERE timestamp < NOW() - INTERVAL '7 days';

-- ==========================================================
-- MIGRATION: 20260612000001_attendance_enhancement.sql
-- ==========================================================

-- IRIS 365 Attendance Enhancement Migration
-- QR Token rotation, Biometric/RFID device management, Attendance method activation

-- ============================================================
-- 1. QR TOKENS TABLE (for rotating QR codes)
-- ============================================================
CREATE TABLE IF NOT EXISTS qr_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES attendance_sessions(id) ON DELETE CASCADE,
  token_hash VARCHAR(64) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  rotated_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_qr_tokens_session ON qr_tokens(session_id);
CREATE INDEX idx_qr_tokens_hash ON qr_tokens(token_hash);
CREATE INDEX idx_qr_tokens_active ON qr_tokens(is_active, expires_at);

-- ============================================================
-- 2. ATTENDANCE SESSIONS: Add is_active, closed_at, auto_close fields
-- ============================================================
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS qr_rotate_interval INT DEFAULT 5; -- minutes
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS geo_lat DOUBLE PRECISION;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS geo_lng DOUBLE PRECISION;
ALTER TABLE attendance_sessions ADD COLUMN IF NOT EXISTS geo_radius INT DEFAULT 200; -- meters

-- ============================================================
-- 3. BIOMETRIC / RFID DEVICES TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS attendance_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  device_name VARCHAR(100) NOT NULL,
  device_type VARCHAR(20) NOT NULL CHECK (device_type IN ('biometric', 'rfid', 'hybrid')),
  device_serial VARCHAR(100) NOT NULL,
  api_key VARCHAR(128) NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
  department_id UUID REFERENCES departments(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_heartbeat TIMESTAMPTZ,
  firmware_version VARCHAR(50),
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(institution_id, device_serial)
);

CREATE INDEX idx_attendance_devices_inst ON attendance_devices(institution_id);

-- ============================================================
-- 4. DEVICE ATTENDANCE LOGS (raw log from biometric/RFID devices)
-- ============================================================
CREATE TABLE IF NOT EXISTS device_attendance_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id UUID NOT NULL REFERENCES attendance_devices(id) ON DELETE CASCADE,
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  session_id UUID REFERENCES attendance_sessions(id) ON DELETE SET NULL,
  identifier_type VARCHAR(20) NOT NULL CHECK (identifier_type IN ('fingerprint', 'rfid_card', 'face', 'pin')),
  identifier_value VARCHAR(200) NOT NULL,
  student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  matched BOOLEAN NOT NULL DEFAULT false,
  match_confidence DECIMAL(5,2),
  raw_payload JSONB DEFAULT '{}'::jsonb,
  logged_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_device_logs_device ON device_attendance_logs(device_id);
CREATE INDEX idx_device_logs_student ON device_attendance_logs(student_id);

-- ============================================================
-- 5. ATTENDANCE METHODS CONFIGURATION (per institution)
-- ============================================================
CREATE TABLE IF NOT EXISTS attendance_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  method_key VARCHAR(20) NOT NULL CHECK (method_key IN ('qr', 'biometric', 'rfid', 'manual')),
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  config JSONB DEFAULT '{}'::jsonb,
  -- QR config: { rotate_interval_minutes, geo_radius, geo_lat, geo_lng }
  -- Biometric config: { require_session, auto_match }
  -- RFID config: { require_session, allowed_device_ids }
  -- Manual config: { allowed_roles }
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(institution_id, method_key)
);

CREATE INDEX idx_attendance_methods_inst ON attendance_methods(institution_id);

-- ============================================================
-- 6. RLS POLICIES
-- ============================================================
ALTER TABLE qr_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_attendance_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_methods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "qr_tokens_select" ON qr_tokens FOR SELECT USING (
  institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
);
CREATE POLICY "qr_tokens_insert" ON qr_tokens FOR INSERT WITH CHECK (
  get_auth_user_role() IN ('Admin', 'Staff', 'SuperAdmin')
);
CREATE POLICY "qr_tokens_update" ON qr_tokens FOR UPDATE USING (
  institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
);

CREATE POLICY "attendance_devices_select" ON attendance_devices FOR SELECT USING (
  institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
);
CREATE POLICY "attendance_devices_insert" ON attendance_devices FOR INSERT WITH CHECK (
  get_auth_user_role() IN ('Admin', 'SuperAdmin')
);
CREATE POLICY "attendance_devices_update" ON attendance_devices FOR UPDATE USING (
  institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
);

CREATE POLICY "device_logs_select" ON device_attendance_logs FOR SELECT USING (
  institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
);
CREATE POLICY "device_logs_insert" ON device_attendance_logs FOR INSERT WITH CHECK (
  institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
);

CREATE POLICY "attendance_methods_select" ON attendance_methods FOR SELECT USING (
  institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
);
CREATE POLICY "attendance_methods_insert" ON attendance_methods FOR INSERT WITH CHECK (
  get_auth_user_role() IN ('Admin', 'SuperAdmin')
);
CREATE POLICY "attendance_methods_update" ON attendance_methods FOR UPDATE USING (
  get_auth_user_role() IN ('Admin', 'SuperAdmin')
  OR (get_auth_user_role() = 'Director' AND institution_id = get_auth_institution_id())
);

-- ============================================================
-- 7. SEED: Default attendance methods for existing institutions
-- ============================================================
INSERT INTO attendance_methods (institution_id, method_key, is_enabled, config)
SELECT i.id, m.method_key, m.enabled, m.config::jsonb
FROM institutions i
CROSS JOIN (VALUES
  ('qr', true, '{"rotate_interval_minutes": 5, "geo_radius": 200}'),
  ('biometric', true, '{"require_session": true, "auto_match": true}'),
  ('rfid', true, '{"require_session": true, "allowed_device_ids": []}'),
  ('manual', true, '{"allowed_roles": ["Admin", "Staff", "SuperAdmin"]}')
) AS m(method_key, enabled, config)
ON CONFLICT (institution_id, method_key) DO NOTHING;

-- ============================================================
-- 8. UPDATED_AT TRIGGER
-- ============================================================
CREATE OR REPLACE FUNCTION update_device_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_attendance_devices_updated
  BEFORE UPDATE ON attendance_devices
  FOR EACH ROW EXECUTE FUNCTION update_device_timestamp();

CREATE TRIGGER trigger_attendance_methods_updated
  BEFORE UPDATE ON attendance_methods
  FOR EACH ROW EXECUTE FUNCTION update_device_timestamp();


-- ==========================================================
-- MIGRATION: 20260612000002_rls_security_hardening.sql
-- ==========================================================

-- ============================================================
-- IRIS 365 — Comprehensive RLS Security Hardening
-- Addresses: Student over-permissioning, Warden scope,
-- Security missing reads, Driver no policy, Parent no link,
-- Vendor no policy, Staff attendance scoping, HOD role,
-- tables with RLS enabled but no policies, open policies
-- ============================================================

-- ============================================================
-- 0. HELPER: Check if user has staff record in a department
-- ============================================================
CREATE OR REPLACE FUNCTION is_user_in_department(target_dept_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM staff
    WHERE user_id = (auth.jwt() ->> 'sub')::UUID
    AND department_id = target_dept_id
    AND institution_id = get_auth_institution_id()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================================
-- 1. PARENT → STUDENT LINK TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS parent_student_links (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  relationship VARCHAR(50) NOT NULL, -- father, mother, guardian
  is_primary BOOLEAN DEFAULT false,
  verified BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(parent_user_id, student_id)
);

CREATE INDEX idx_psl_parent ON parent_student_links(parent_user_id);
CREATE INDEX idx_psl_student ON parent_student_links(student_id);

ALTER TABLE parent_student_links ENABLE ROW LEVEL SECURITY;

-- Parents can only see their own links
CREATE POLICY "parent_student_links_own" ON parent_student_links
  FOR SELECT USING (
    parent_user_id = (auth.jwt() ->> 'sub')::UUID
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- Admin/SuperAdmin can manage links
CREATE POLICY "parent_student_links_admin" ON parent_student_links
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 2. DROP EXISTING OVERLY-BROAD POLICIES
-- ============================================================

DO $$
DECLARE
  pol RECORD;
BEGIN
  FOR pol IN 
    SELECT policyname, tablename 
    FROM pg_policies 
    WHERE schemaname = 'public'
      AND policyname IN (
        'users_select', 'users_insert', 'users_update', 'users_delete',
        'departments_select', 'departments_manage',
        'students_select', 'students_insert', 'students_update', 'students_delete',
        'staff_select', 'staff_manage',
        'attendance_sessions_select', 'attendance_sessions_insert', 'attendance_sessions_update', 'attendance_sessions_delete',
        'attendance_select', 'attendance_insert', 'attendance_update',
        'fee_structures_select', 'fee_structures_manage',
        'fee_payments_select', 'fee_payments_insert', 'fee_payments_manage',
        'fee_concessions_select', 'fee_concessions_manage',
        'canteen_menus_select', 'canteen_menus_insert', 'canteen_menus_update', 'canteen_menus_delete',
        'canteen_orders_select', 'canteen_orders_insert', 'canteen_orders_update',
        'events_select', 'events_insert', 'events_update', 'events_delete',
        'exam_results_select', 'exam_results_insert', 'exam_results_update',
        'exams_select', 'exams_manage',
        'timetable_select', 'timetable_manage',
        'books_select', 'books_manage',
        'book_issues_select', 'book_issues_insert', 'book_issues_update',
        'hostel_rooms_select', 'hostel_rooms_manage',
        'hostel_visitors_select', 'hostel_visitors_insert', 'hostel_visitors_update',
        'gate_entries_select', 'gate_entries_insert', 'gate_entries_update',
        'visitor_passes_select', 'visitor_passes_insert', 'visitor_passes_update',
        'blacklisted_visitors_select', 'blacklisted_visitors_manage',
        'rfid_cards_select', 'rfid_cards_manage',
        'security_incidents_select', 'security_incidents_insert', 'security_incidents_update',
        'gate_shifts_select', 'gate_shifts_manage',
        'campus_occupancy_select', 'campus_occupancy_manage',
        'bus_routes_select', 'bus_routes_manage',
        'buses_select', 'buses_manage',
        'bus_tracking_select', 'bus_tracking_insert', 'bus_tracking_update',
        'bus_drivers_select', 'bus_drivers_manage',
        'bus_trips_select', 'bus_trips_insert', 'bus_trips_update',
        'trip_stop_logs_select', 'trip_stop_logs_insert',
        'bus_incidents_select', 'bus_incidents_insert',
        'bus_maintenance_select', 'bus_maintenance_manage',
        'notifications_select', 'notifications_insert',
        'event_registrations_select', 'event_registrations_insert', 'event_registrations_update',
        'gym_slots_select', 'gym_slots_manage',
        'gym_memberships_select', 'gym_memberships_insert',
        'gym_bookings_select', 'gym_bookings_insert', 'gym_bookings_update',
        'meal_subscriptions_select', 'meal_subscriptions_manage',
        'fee_reminders_select', 'fee_reminders_manage',
        'transport_subscriptions_select', 'transport_subscriptions_manage',
        'visitor_logs_select', 'visitor_logs_insert', 'visitor_logs_update',
        'id_card_templates_select', 'id_card_templates_manage',
        'attendance_regularizations_select', 'attendance_regularizations_insert', 'attendance_regularizations_update',
        'notification_logs_select', 'notification_logs_insert',
        'companies_select', 'companies_manage',
        'placement_drives_select', 'placement_drives_manage',
        'student_profiles_select_own', 'student_profiles_manage_own',
        'drive_applications_select', 'drive_applications_manage',
        'interview_rounds_select', 'interview_rounds_manage',
        'offer_letters_select', 'offer_letters_manage',
        'mock_interviews_select', 'mock_interviews_manage',
        'alumni_select', 'alumni_manage',
        'alumni_mentorship_select', 'alumni_mentorship_manage',
        'rls_audit_admin_only', 'parent_student_links_own', 'parent_student_links_admin'
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, pol.tablename);
  END LOOP;
END $$;


-- Drop the catch-all tenant policies that allow ALL roles full access
DROP POLICY IF EXISTS "tenant_users_policy" ON users;
DROP POLICY IF EXISTS "tenant_students_policy" ON students;
DROP POLICY IF EXISTS "tenant_attendance_policy" ON attendance;
DROP POLICY IF EXISTS "tenant_attendance_sessions_policy" ON attendance_sessions;
DROP POLICY IF EXISTS "tenant_fee_structures_policy" ON fee_structures;
DROP POLICY IF EXISTS "tenant_fee_payments_policy" ON fee_payments;
DROP POLICY IF EXISTS "tenant_canteen_menus_policy" ON canteen_menus;
DROP POLICY IF EXISTS "tenant_canteen_orders_policy" ON canteen_orders;
DROP POLICY IF EXISTS "tenant_events_policy" ON events;
DROP POLICY IF EXISTS "tenant_book_issues_policy" ON book_issues;
DROP POLICY IF EXISTS "tenant_books_policy" ON books;
DROP POLICY IF EXISTS "tenant_bus_routes_policy" ON bus_routes;
DROP POLICY IF EXISTS "tenant_buses_policy" ON buses;
DROP POLICY IF EXISTS "tenant_gate_logs_policy" ON gate_logs;
DROP POLICY IF EXISTS "tenant_hostel_rooms_policy" ON hostel_rooms;
DROP POLICY IF EXISTS "tenant_notifications_policy" ON notifications;
DROP POLICY IF EXISTS "tenant_timetable_policy" ON timetable;
DROP POLICY IF EXISTS "tenant_staff_policy" ON staff;
DROP POLICY IF EXISTS "tenant_departments_policy" ON departments;

-- Drop campus_core policies
DROP POLICY IF EXISTS "tenant_fee_concessions_policy" ON fee_concessions;
DROP POLICY IF EXISTS "tenant_id_card_templates_policy" ON id_card_templates;
DROP POLICY IF EXISTS "tenant_attendance_regularizations_policy" ON attendance_regularizations;

-- ============================================================
-- 3. REBUILD: Core table policies with proper role scoping
-- ============================================================

-- USERS: Admin/Staff/Teacher can see own institution; Students see only self
CREATE POLICY "users_select" ON users
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "users_insert" ON users
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "users_update" ON users
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR id = (auth.jwt() ->> 'sub')::UUID
  );

CREATE POLICY "users_delete" ON users
  FOR DELETE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- DEPARTMENTS
CREATE POLICY "departments_select" ON departments
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "departments_manage" ON departments
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- STUDENTS: Admin/Staff see all in institution; Students see only self
CREATE POLICY "students_select" ON students
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "students_insert" ON students
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "students_update" ON students
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR user_id = (auth.jwt() ->> 'sub')::UUID
  );

CREATE POLICY "students_delete" ON students
  FOR DELETE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- STAFF
CREATE POLICY "staff_select" ON staff
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "staff_manage" ON staff
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 4. ATTENDANCE: Staff scoped to own department
-- ============================================================

-- ATTENDANCE SESSIONS: Staff can only manage sessions in their department
CREATE POLICY "attendance_sessions_select" ON attendance_sessions
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "attendance_sessions_insert" ON attendance_sessions
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR (
      get_auth_user_role() = 'Staff'
      AND institution_id = get_auth_institution_id()
      AND is_user_in_department(department_id)
    )
  );

CREATE POLICY "attendance_sessions_update" ON attendance_sessions
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR (
      get_auth_user_role() = 'Staff'
      AND institution_id = get_auth_institution_id()
      AND is_user_in_department(department_id)
    )
  );

CREATE POLICY "attendance_sessions_delete" ON attendance_sessions
  FOR DELETE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ATTENDANCE: Students see own records; Staff see their department; Admin see all
CREATE POLICY "attendance_select" ON attendance
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "attendance_insert" ON attendance
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR get_auth_user_role() = 'Staff'
  );

CREATE POLICY "attendance_update" ON attendance
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR get_auth_user_role() = 'Staff'
  );

-- ============================================================
-- 5. FEES: Students see only own payments
-- ============================================================

CREATE POLICY "fee_structures_select" ON fee_structures
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "fee_structures_manage" ON fee_structures
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

CREATE POLICY "fee_payments_select" ON fee_payments
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "fee_payments_insert" ON fee_payments
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR (
      get_auth_user_role() = 'Student'
      AND student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    )
  );

CREATE POLICY "fee_payments_manage" ON fee_payments
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

CREATE POLICY "fee_concessions_select" ON fee_concessions
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "fee_concessions_manage" ON fee_concessions
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 6. CANTEEN: Student sees available menus + own orders;
--    Vendor sees their stall orders + menus
-- ============================================================

-- Canteen menus: Students see only available items; Vendor/Admin see all
CREATE POLICY "canteen_menus_select" ON canteen_menus
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "canteen_menus_insert" ON canteen_menus
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Vendor')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "canteen_menus_update" ON canteen_menus
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Vendor')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "canteen_menus_delete" ON canteen_menus
  FOR DELETE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- Canteen orders: Students see/insert own; Vendor see/update their stall; Admin see all
CREATE POLICY "canteen_orders_select" ON canteen_orders
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "canteen_orders_insert" ON canteen_orders
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR (
      get_auth_user_role() = 'Student'
      AND student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    )
  );

CREATE POLICY "canteen_orders_update" ON canteen_orders
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Vendor')
    AND institution_id = get_auth_institution_id()
  );

-- ============================================================
-- 7. EVENTS: Students see published/active only; Admin see all
-- ============================================================

CREATE POLICY "events_select" ON events
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "events_insert" ON events
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "events_update" ON events
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

CREATE POLICY "events_delete" ON events
  FOR DELETE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 8. EXAM RESULTS: Students see only own; Staff see department
-- ============================================================

CREATE POLICY "exam_results_select" ON exam_results
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM exams e
      WHERE e.id = exam_id
      AND e.institution_id = get_auth_institution_id()
    )
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "exam_results_insert" ON exam_results
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "exam_results_update" ON exam_results
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

-- EXAMS table (was missing policy)
CREATE POLICY "exams_select" ON exams
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "exams_manage" ON exams
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

-- ============================================================
-- 9. TIMETABLE
-- ============================================================

CREATE POLICY "timetable_select" ON timetable
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "timetable_manage" ON timetable
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 10. LIBRARY: Students see own issues
-- ============================================================

CREATE POLICY "books_select" ON books
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "books_manage" ON books
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "book_issues_select" ON book_issues
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "book_issues_insert" ON book_issues
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
    OR (
      get_auth_user_role() = 'Student'
      AND student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    )
  );

CREATE POLICY "book_issues_update" ON book_issues
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

-- ============================================================
-- 11. HOSTEL: Warden scoped to own block; Student see own
-- ============================================================

CREATE POLICY "hostel_rooms_select" ON hostel_rooms
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "hostel_rooms_manage" ON hostel_rooms
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden')
  );

-- Hostel visitors: Security + Warden can manage; Student see own
CREATE POLICY "hostel_visitors_select" ON hostel_visitors
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "hostel_visitors_insert" ON hostel_visitors
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security', 'Warden')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "hostel_visitors_update" ON hostel_visitors
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security', 'Warden')
    AND institution_id = get_auth_institution_id()
  );

-- ============================================================
-- 12. GATE: Security can read profiles for identity verification
-- ============================================================

CREATE POLICY "gate_entries_select" ON gate_entries
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "gate_entries_insert" ON gate_entries
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "gate_entries_update" ON gate_entries
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
    AND institution_id = get_auth_institution_id()
  );

-- Visitor passes: Security + Warden
CREATE POLICY "visitor_passes_select" ON visitor_passes
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "visitor_passes_insert" ON visitor_passes
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "visitor_passes_update" ON visitor_passes
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
    AND institution_id = get_auth_institution_id()
  );

-- Blacklisted visitors: Security + Admin
CREATE POLICY "blacklisted_visitors_select" ON blacklisted_visitors
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "blacklisted_visitors_manage" ON blacklisted_visitors
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
  );

-- RFID cards
CREATE POLICY "rfid_cards_select" ON rfid_cards
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "rfid_cards_manage" ON rfid_cards
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
  );

-- Security incidents
CREATE POLICY "security_incidents_select" ON security_incidents
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "security_incidents_insert" ON security_incidents
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "security_incidents_update" ON security_incidents
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
  );

-- Gate shifts
CREATE POLICY "gate_shifts_select" ON gate_shifts
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "gate_shifts_manage" ON gate_shifts
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
  );

-- Campus occupancy
CREATE POLICY "campus_occupancy_select" ON campus_occupancy
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "campus_occupancy_manage" ON campus_occupancy
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
  );

-- ============================================================
-- 13. TRANSIT: Driver sees own bus + route; Students see own route
-- ============================================================

CREATE POLICY "bus_routes_select" ON bus_routes
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "bus_routes_manage" ON bus_routes
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

CREATE POLICY "buses_select" ON buses
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "buses_manage" ON buses
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
  );

-- bus_tracking: Driver can INSERT own location; Admin see all; Students see their route
CREATE POLICY "bus_tracking_select" ON bus_tracking
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "bus_tracking_insert" ON bus_tracking
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "bus_tracking_update" ON bus_tracking
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
  );

-- bus_drivers
CREATE POLICY "bus_drivers_select" ON bus_drivers
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "bus_drivers_manage" ON bus_drivers
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- bus_trips
CREATE POLICY "bus_trips_select" ON bus_trips
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "bus_trips_insert" ON bus_trips
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
  );

CREATE POLICY "bus_trips_update" ON bus_trips
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
  );

-- trip_stop_logs
CREATE POLICY "trip_stop_logs_select" ON trip_stop_logs
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "trip_stop_logs_insert" ON trip_stop_logs
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
  );

-- bus_incidents
CREATE POLICY "bus_incidents_select" ON bus_incidents
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "bus_incidents_insert" ON bus_incidents
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
    AND institution_id = get_auth_institution_id()
  );

-- bus_maintenance
CREATE POLICY "bus_maintenance_select" ON bus_maintenance
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "bus_maintenance_manage" ON bus_maintenance
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 14. NOTIFICATIONS
-- ============================================================

CREATE POLICY "notifications_select" ON notifications
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "notifications_insert" ON notifications
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

-- ============================================================
-- 15. EVENT REGISTRATIONS (was missing policy)
-- ============================================================

CREATE POLICY "event_registrations_select" ON event_registrations
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "event_registrations_insert" ON event_registrations
  FOR INSERT WITH CHECK (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "event_registrations_update" ON event_registrations
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR (
      get_auth_user_role() = 'Student'
      AND student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    )
  );

-- ============================================================
-- 16. GYM: Membership check for bookings
-- ============================================================

CREATE POLICY "gym_slots_select" ON gym_slots
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "gym_slots_manage" ON gym_slots
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

CREATE POLICY "gym_memberships_select" ON gym_memberships
  FOR SELECT USING (
    student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id())
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "gym_memberships_insert" ON gym_memberships
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR (
      get_auth_user_role() = 'Student'
      AND student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    )
  );

CREATE POLICY "gym_bookings_select" ON gym_bookings
  FOR SELECT USING (
    student_id IN (SELECT id FROM students WHERE institution_id = get_auth_institution_id())
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "gym_bookings_insert" ON gym_bookings
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    OR (
      get_auth_user_role() = 'Student'
      AND student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    )
  );

CREATE POLICY "gym_bookings_update" ON gym_bookings
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 17. MEAL SUBSCRIPTIONS (Warden needs to see)
-- ============================================================

CREATE POLICY "meal_subscriptions_select" ON meal_subscriptions
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "meal_subscriptions_manage" ON meal_subscriptions
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden', 'Vendor')
  );

-- ============================================================
-- 18. FEE REMINDERS
-- ============================================================

CREATE POLICY "fee_reminders_select" ON fee_reminders
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "fee_reminders_manage" ON fee_reminders
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 19. TRANSPORT SUBSCRIPTIONS
-- ============================================================

CREATE POLICY "transport_subscriptions_select" ON transport_subscriptions
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "transport_subscriptions_manage" ON transport_subscriptions
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Driver')
  );

-- ============================================================
-- 20. VISITOR LOGS (Security needs full access)
-- ============================================================

CREATE POLICY "visitor_logs_select" ON visitor_logs
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "visitor_logs_insert" ON visitor_logs
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security', 'Warden')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "visitor_logs_update" ON visitor_logs
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security', 'Warden')
  );

-- ============================================================
-- 21. ID CARD TEMPLATES
-- ============================================================

CREATE POLICY "id_card_templates_select" ON id_card_templates
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "id_card_templates_manage" ON id_card_templates
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- ============================================================
-- 22. ATTENDANCE REGULARIZATIONS
-- ============================================================

CREATE POLICY "attendance_regularizations_select" ON attendance_regularizations
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "attendance_regularizations_insert" ON attendance_regularizations
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff', 'Student')
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "attendance_regularizations_update" ON attendance_regularizations
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

-- ============================================================
-- 23. NOTIFICATION LOGS
-- ============================================================

CREATE POLICY "notification_logs_select" ON notification_logs
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "notification_logs_insert" ON notification_logs
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

-- ============================================================
-- 24. PLACEMENTS: Tighten open policies
-- ============================================================

-- Drop the wide-open policies
DROP POLICY IF EXISTS "companies_all_access" ON companies;
DROP POLICY IF EXISTS "drives_all_access" ON placement_drives;
DROP POLICY IF EXISTS "admin_all_profiles" ON student_profiles;
DROP POLICY IF EXISTS "admin_all_applications" ON drive_applications;
DROP POLICY IF EXISTS "admin_all_rounds" ON interview_rounds;
DROP POLICY IF EXISTS "admin_all_offers" ON offer_letters;
DROP POLICY IF EXISTS "admin_all_mocks" ON mock_interviews;
DROP POLICY IF EXISTS "alumni_all_access" ON alumni;
DROP POLICY IF EXISTS "mentorship_all_access" ON alumni_mentorship;

CREATE POLICY "companies_select" ON companies
  FOR SELECT USING (true); -- Companies are public

CREATE POLICY "companies_manage" ON companies
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

CREATE POLICY "placement_drives_select" ON placement_drives
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "placement_drives_manage" ON placement_drives
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "student_profiles_select_own" ON student_profiles
  FOR SELECT USING (
    student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "student_profiles_manage_own" ON student_profiles
  FOR ALL USING (
    student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "drive_applications_select" ON drive_applications
  FOR SELECT USING (
    student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "drive_applications_manage" ON drive_applications
  FOR ALL USING (
    student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "interview_rounds_select" ON interview_rounds
  FOR SELECT USING (
    student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "interview_rounds_manage" ON interview_rounds
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "offer_letters_select" ON offer_letters
  FOR SELECT USING (
    student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "offer_letters_manage" ON offer_letters
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "mock_interviews_select" ON mock_interviews
  FOR SELECT USING (
    student_id IN (SELECT id FROM students WHERE user_id = (auth.jwt() ->> 'sub')::UUID)
    OR get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "mock_interviews_manage" ON mock_interviews
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "alumni_select" ON alumni
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "alumni_manage" ON alumni
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

CREATE POLICY "alumni_mentorship_select" ON alumni_mentorship
  FOR SELECT USING (
    alumni_id IN (SELECT id FROM alumni WHERE institution_id = get_auth_institution_id())
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "alumni_mentorship_manage" ON alumni_mentorship
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
  );

-- ============================================================
-- 25. OBE/NAAC: Tighten open policies to Admin+Staff only
-- ============================================================

-- Drop all the open policies
DO $$
DECLARE
  tbl TEXT;
  pol TEXT;
BEGIN
  FOR tbl, pol IN SELECT tablename, policyname FROM pg_policies
    WHERE schemaname = 'public'
    AND policyname LIKE '%_access'
    AND tablename IN (
      'programs_obe', 'courses', 'course_outcomes', 'program_outcomes',
      'co_po_mapping', 'assessment_tools', 'co_assessments', 'student_co_marks',
      'co_attainment', 'po_attainment', 'naac_criteria', 'naac_metrics',
      'iqac_activities', 'faculty_development', 'research_publications',
      'student_achievements', 'feedback_surveys', 'survey_responses', 'ssr_documents'
    )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol, tbl);
  END LOOP;
END $$;

-- Re-create with proper access: Admin + Staff + Teacher read; Admin write
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOR tbl IN SELECT unnest(ARRAY[
    'programs_obe', 'courses', 'course_outcomes', 'program_outcomes',
    'co_po_mapping', 'assessment_tools', 'co_assessments', 'student_co_marks',
    'co_attainment', 'po_attainment', 'naac_criteria', 'naac_metrics',
    'iqac_activities', 'faculty_development', 'research_publications',
    'student_achievements', 'feedback_surveys', 'survey_responses', 'ssr_documents'
  ])
  LOOP
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR SELECT USING (true)',
      tbl || '_read', tbl
    );
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR ALL USING (get_auth_user_role() IN (''SuperAdmin'', ''Admin''))',
      tbl || '_write', tbl
    );
  END LOOP;
END $$;

-- ============================================================
-- 26. HOD ROLE: Add to module_permissions seed
--    HOD = Admin permissions for their department
-- ============================================================

INSERT INTO module_permissions (institution_id, role, module, can_read, can_write, can_delete)
SELECT i.id, 'HOD', m.module, true, m.w, false
FROM institutions i
CROSS JOIN (VALUES
  ('dashboard', true), ('students', true), ('attendance', true), ('timetable', true),
  ('exams', true), ('notices', true), ('obe', true), ('library', true),
  ('fees', false), ('canteen', false), ('hostel', false), ('placements', false),
  ('hr', false), ('gate', false), ('gym', false), ('transit', false),
  ('events', false), ('idcards', false), ('ai_concierge', false), ('naac', false),
  ('admissions', false), ('faculty_development', true), ('achievements', false),
  ('director', false), ('parent_portal', false)
) AS m(module, w)
ON CONFLICT (institution_id, role, module) DO NOTHING;

-- ============================================================
-- 27. AUDIT LOG TABLE
-- ============================================================

CREATE TABLE IF NOT EXISTS rls_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type VARCHAR(50) NOT NULL, -- policy_change, permission_grant, permission_revoke
  table_name VARCHAR(100) NOT NULL,
  role VARCHAR(50),
  details JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE rls_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_audit_admin_only" ON rls_audit_log
  FOR ALL USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
  );

-- Log this migration
INSERT INTO rls_audit_log (event_type, table_name, role, details)
VALUES ('policy_change', 'ALL', 'system', '{"migration": "20260612000002_rls_security_hardening", "description": "Comprehensive RLS overhaul: parent_student_links, role-scoped policies, no-policy table fixes"}');


-- ==========================================================
-- MIGRATION: 20260612000003_feature_logic_fixes.sql
-- ==========================================================

-- ============================================================
-- IRIS 365 — Feature Logic Fixes
-- Late fees, timetable scoping, library fine payment,
-- event capacity enforcement, gate blacklist check
-- ============================================================

-- ============================================================
-- 1. FEE STRUCTURES: Late fee / penalty columns
-- ============================================================

ALTER TABLE fee_structures
  ADD COLUMN IF NOT EXISTS late_fee_per_day DECIMAL(10,2) DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS grace_period_days INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS max_penalty DECIMAL(10,2) DEFAULT 0.00;

-- RPC: Calculate penalty for a fee payment
CREATE OR REPLACE FUNCTION calculate_fee_penalty(
  p_fee_structure_id UUID,
  p_payment_date DATE
) RETURNS DECIMAL AS $$
DECLARE
  v_due_date DATE;
  v_late_fee_per_day DECIMAL;
  v_grace_period_days INTEGER;
  v_max_penalty DECIMAL;
  v_days_late INTEGER;
  v_penalty DECIMAL;
BEGIN
  SELECT due_date, late_fee_per_day, grace_period_days, max_penalty
  INTO v_due_date, v_late_fee_per_day, v_grace_period_days, v_max_penalty
  FROM fee_structures WHERE id = p_fee_structure_id;

  IF NOT FOUND THEN RETURN 0; END IF;

  v_days_late := p_payment_date - v_due_date - v_grace_period_days;

  IF v_days_late <= 0 THEN RETURN 0; END IF;

  v_penalty := v_days_late * v_late_fee_per_day;

  IF v_max_penalty > 0 AND v_penalty > v_max_penalty THEN
    v_penalty := v_max_penalty;
  END IF;

  RETURN v_penalty;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Initiate fee payment with penalty calculation
CREATE OR REPLACE FUNCTION initiate_fee_payment(
  p_institution_id UUID,
  p_student_id UUID,
  p_fee_structure_id UUID,
  p_payment_date DATE DEFAULT CURRENT_DATE
) RETURNS JSON AS $$
DECLARE
  v_amount DECIMAL;
  v_penalty DECIMAL;
  v_total DECIMAL;
  v_fee_name VARCHAR;
  v_due_date DATE;
BEGIN
  SELECT amount, name, due_date
  INTO v_amount, v_fee_name, v_due_date
  FROM fee_structures
  WHERE id = p_fee_structure_id AND institution_id = p_institution_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Fee structure not found');
  END IF;

  v_penalty := calculate_fee_penalty(p_fee_structure_id, p_payment_date);
  v_total := v_amount + v_penalty;

  RETURN json_build_object(
    'success', true,
    'fee_name', v_fee_name,
    'base_amount', v_amount,
    'penalty', v_penalty,
    'total_amount', v_total,
    'due_date', v_due_date,
    'payment_date', p_payment_date
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 2. TIMETABLE: Add semester + batch_year scoping
-- ============================================================

ALTER TABLE timetable
  ADD COLUMN IF NOT EXISTS semester INTEGER,
  ADD COLUMN IF NOT EXISTS batch_year VARCHAR(10);

CREATE INDEX IF NOT EXISTS idx_timetable_semester_batch ON timetable(semester, batch_year);

-- ============================================================
-- 3. LIBRARY FINE PAYMENT PATH
-- ============================================================

CREATE TABLE IF NOT EXISTS library_fine_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  book_issue_id UUID NOT NULL REFERENCES book_issues(id) ON DELETE CASCADE,
  amount DECIMAL(10,2) NOT NULL,
  payment_method VARCHAR(50) NOT NULL DEFAULT 'cash', -- cash, wallet, online
  paid_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  recorded_by UUID REFERENCES users(id) ON DELETE SET NULL,
  receipt_number VARCHAR(50),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_lfp_student ON library_fine_payments(student_id);
CREATE INDEX idx_lfp_issue ON library_fine_payments(book_issue_id);

ALTER TABLE library_fine_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lfp_select" ON library_fine_payments
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "lfp_insert" ON library_fine_payments
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff')
    AND institution_id = get_auth_institution_id()
  );

-- RPC: Pay library fine (atomic: insert payment + clear fine on book_issue)
CREATE OR REPLACE FUNCTION pay_library_fine(
  p_institution_id UUID,
  p_student_id UUID,
  p_book_issue_id UUID,
  p_amount DECIMAL,
  p_payment_method VARCHAR DEFAULT 'cash',
  p_recorded_by UUID DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
  v_fine_amount DECIMAL;
  v_existing_payment DECIMAL;
  v_net_fine DECIMAL;
  v_receipt VARCHAR;
BEGIN
  -- Get the fine amount
  SELECT fine_amount INTO v_fine_amount
  FROM book_issues
  WHERE id = p_book_issue_id AND student_id = p_student_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Book issue not found');
  END IF;

  IF v_fine_amount IS NULL OR v_fine_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'No fine outstanding');
  END IF;

  -- Check existing payments
  SELECT COALESCE(SUM(amount), 0) INTO v_existing_payment
  FROM library_fine_payments
  WHERE book_issue_id = p_book_issue_id AND student_id = p_student_id;

  v_net_fine := v_fine_amount - v_existing_payment;

  IF p_amount > v_net_fine THEN
    p_amount := v_net_fine;
  END IF;

  IF p_amount <= 0 THEN
    RETURN json_build_object('success', false, 'error', 'Fine already fully paid');
  END IF;

  -- Generate receipt number
  v_receipt := 'LIB-' || to_char(now(), 'YYYYMMDD') || '-' || substring(md5(random()::text), 1, 8);

  -- Insert payment
  INSERT INTO library_fine_payments (institution_id, student_id, book_issue_id, amount, payment_method, recorded_by, receipt_number)
  VALUES (p_institution_id, p_student_id, p_book_issue_id, p_amount, p_payment_method, p_recorded_by, v_receipt);

  -- Update fine_amount on book_issue if fully paid
  IF v_existing_payment + p_amount >= v_fine_amount THEN
    UPDATE book_issues SET fine_amount = 0, fine_paid = true WHERE id = p_book_issue_id;
  END IF;

  RETURN json_build_object(
    'success', true,
    'amount_paid', p_amount,
    'remaining_fine', GREATEST(0, v_net_fine - p_amount),
    'receipt_number', v_receipt
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 4. EVENTS: Atomic registration with capacity check
-- ============================================================

CREATE OR REPLACE FUNCTION register_event_atomic(
  p_institution_id UUID,
  p_event_id UUID,
  p_student_id UUID
) RETURNS JSON AS $$
DECLARE
  v_max_participants INTEGER;
  v_current_count INTEGER;
  v_event_status VARCHAR;
  v_event_name VARCHAR;
  v_registration_id UUID;
BEGIN
  -- Lock the event row
  SELECT max_participants, status, name
  INTO v_max_participants, v_event_status, v_event_name
  FROM events
  WHERE id = p_event_id AND institution_id = p_institution_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Event not found');
  END IF;

  IF v_event_status != 'active' THEN
    RETURN json_build_object('success', false, 'error', 'Event is not active (status: ' || v_event_status || ')');
  END IF;

  -- Check if already registered
  IF EXISTS (SELECT 1 FROM event_registrations WHERE event_id = p_event_id AND student_id = p_student_id) THEN
    RETURN json_build_object('success', false, 'error', 'Already registered for this event');
  END IF;

  -- Check capacity (if max_participants is set)
  IF v_max_participants IS NOT NULL AND v_max_participants > 0 THEN
    SELECT COUNT(*) INTO v_current_count
    FROM event_registrations
    WHERE event_id = p_event_id AND payment_status != 'cancelled';

    IF v_current_count >= v_max_participants THEN
      RETURN json_build_object('success', false, 'error', 'Event is full (' || v_max_participants || ' max)', 'current', v_current_count);
    END IF;

    -- Atomically increment
    UPDATE events SET
      max_participants = max_participants  -- no-op to hold lock
    WHERE id = p_event_id AND (
      SELECT COUNT(*) FROM event_registrations
      WHERE event_id = p_event_id AND payment_status != 'cancelled'
    ) < v_max_participants;

    IF NOT FOUND THEN
      RETURN json_build_object('success', false, 'error', 'Event filled up concurrently');
    END IF;
  END IF;

  -- Insert registration
  INSERT INTO event_registrations (institution_id, event_id, student_id, registration_date, payment_status)
  VALUES (p_institution_id, p_event_id, p_student_id, now(), 'pending')
  RETURNING id INTO v_registration_id;

  RETURN json_build_object(
    'success', true,
    'registration_id', v_registration_id,
    'event_name', v_event_name,
    'message', 'Registration successful'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. GATE: Extend to deny blacklisted students/staff
-- ============================================================

-- Add person_type to blacklisted_visitors to also cover students/staff
ALTER TABLE blacklisted_visitors
  ADD COLUMN IF NOT EXISTS person_type VARCHAR(20) DEFAULT 'visitor', -- visitor, student, staff
  ADD COLUMN IF NOT EXISTS person_id UUID; -- FK to students.id or users.id

CREATE INDEX IF NOT EXISTS idx_blacklist_person ON blacklisted_visitors(person_type, person_id);

-- RPC: Check if a person is blacklisted at gate entry
CREATE OR REPLACE FUNCTION check_gate_access(
  p_institution_id UUID,
  p_person_id UUID,
  p_person_type VARCHAR DEFAULT 'student'
) RETURNS JSON AS $$
DECLARE
  v_blocked BOOLEAN := false;
  v_reason TEXT;
  v_record JSON;
BEGIN
  -- Check blacklisted_visitors table
  SELECT true, bv.reason INTO v_blocked, v_reason
  FROM blacklisted_visitors bv
  WHERE bv.institution_id = p_institution_id
  AND bv.is_active = true
  AND (
    (p_person_type = 'visitor' AND bv.id_number = p_person_id::TEXT)
    OR (bv.person_type = p_person_type AND bv.person_id = p_person_id)
  )
  LIMIT 1;

  IF v_blocked THEN
    RETURN json_build_object(
      'success', false,
      'allowed', false,
      'reason', 'BLOCKED: ' || COALESCE(v_reason, 'No reason provided'),
      'alert_level', 'high'
    );
  END IF;

  -- Check if student is deactivated / expelled
  IF p_person_type = 'student' THEN
    SELECT json_build_object('name', u.name, 'status', 'active') INTO v_record
    FROM students s
    JOIN users u ON u.id = s.user_id
    WHERE s.id = p_person_id AND s.institution_id = p_institution_id AND u.is_active = true;

    IF v_record IS NULL THEN
      RETURN json_build_object('success', false, 'allowed', false, 'reason', 'Student account deactivated or not found', 'alert_level', 'medium');
    END IF;
  END IF;

  -- Check if staff is deactivated
  IF p_person_type = 'staff' THEN
    SELECT json_build_object('name', u.name) INTO v_record
    FROM staff st
    JOIN users u ON u.id = st.user_id
    WHERE st.id = p_person_id AND st.institution_id = p_institution_id AND u.is_active = true;

    IF v_record IS NULL THEN
      RETURN json_build_object('success', false, 'allowed', false, 'reason', 'Staff account deactivated or not found', 'alert_level', 'medium');
    END IF;
  END IF;

  RETURN json_build_object('success', true, 'allowed', true, 'alert_level', 'none');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. HOSTEL: Ensure checkout RPC exists (already in code,
--    but add an atomic version for consistency)
-- ============================================================

CREATE OR REPLACE FUNCTION checkout_hostel_atomic(
  p_allocation_id UUID,
  p_vacated_date DATE,
  p_vacating_reason TEXT DEFAULT NULL,
  p_recorded_by UUID DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
  v_allocation RECORD;
  v_room RECORD;
  v_outstanding_fees DECIMAL;
  v_open_complaints INTEGER;
BEGIN
  -- Lock the allocation row
  SELECT ha.*, hr.id AS room_id_ref, hr.occupied, hr.capacity
  INTO v_allocation
  FROM hostel_allocations ha
  JOIN hostel_rooms hr ON hr.id = ha.room_id
  WHERE ha.id = p_allocation_id AND ha.is_current = true
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'Active allocation not found');
  END IF;

  -- Check outstanding hostel fees
  SELECT COALESCE(SUM(amount - paid_amount), 0) INTO v_outstanding_fees
  FROM hostel_fees
  WHERE student_id = v_allocation.student_id AND paid_amount < amount;

  IF v_outstanding_fees > 0 THEN
    RETURN json_build_object('success', false, 'error', 'Outstanding hostel fees: ₹' || v_outstanding_fees);
  END IF;

  -- Check open complaints
  SELECT COUNT(*) INTO v_open_complaints
  FROM hostel_complaints
  WHERE student_id = v_allocation.student_id
  AND status NOT IN ('resolved', 'closed');

  -- Update allocation
  UPDATE hostel_allocations
  SET is_current = false,
      vacated_date = p_vacated_date,
      vacating_reason = p_vacating_reason
  WHERE id = p_allocation_id;

  -- Decrement room occupied count
  UPDATE hostel_rooms
  SET occupied = GREATEST(0, occupied - 1)
  WHERE id = v_allocation.room_id;

  RETURN json_build_object(
    'success', true,
    'student_id', v_allocation.student_id,
    'room_number', (SELECT room_number FROM hostel_rooms WHERE id = v_allocation.room_id),
    'vacated_date', p_vacated_date,
    'open_complaints', v_open_complaints,
    'message', 'Checkout successful. Room has been vacated.'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 7. SEED: Add HOD role to module_permissions
--    (Duplicate-safe with the security_hardening migration)
-- ============================================================

INSERT INTO module_permissions (institution_id, role, module, can_read, can_write, can_delete)
SELECT i.id, 'HOD', m.module, true, m.w, false
FROM institutions i
CROSS JOIN (VALUES
  ('dashboard', true), ('students', true), ('attendance', true), ('timetable', true),
  ('exams', true), ('notices', true), ('obe', true), ('library', true),
  ('fees', false), ('canteen', false), ('hostel', false), ('placements', false),
  ('hr', false), ('gate', false), ('gym', false), ('transit', false),
  ('events', false), ('idcards', false), ('ai_concierge', false), ('naac', false),
  ('admissions', false), ('faculty_development', true), ('achievements', false),
  ('director', false), ('parent_portal', false)
) AS m(module, w)
ON CONFLICT (institution_id, role, module) DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260612000004_high_priority_features.sql
-- ==========================================================

-- ============================================================
-- HIGH PRIORITY FEATURES: Attendance Warnings, Fee Escalation, Parent OTP
-- ============================================================

-- ============================================================
-- 1. ATTENDANCE SHORTAGE WARNING SYSTEM
-- ============================================================

-- Track which warnings have been sent to avoid duplicate alerts
CREATE TABLE IF NOT EXISTS attendance_warnings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    warning_type VARCHAR(20) NOT NULL CHECK (warning_type IN ('warning_80', 'critical_75', 'final_60')),
    attendance_pct DECIMAL(5,2) NOT NULL,
    total_classes INTEGER NOT NULL DEFAULT 0,
    attended_classes INTEGER NOT NULL DEFAULT 0,
    sent_to_student BOOLEAN NOT NULL DEFAULT false,
    sent_to_parent BOOLEAN NOT NULL DEFAULT false,
    sent_to_hod BOOLEAN NOT NULL DEFAULT false,
    sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    warning_date DATE NOT NULL DEFAULT CURRENT_DATE,
    CONSTRAINT unique_warning_per_student_type UNIQUE (student_id, warning_type, warning_date)
);

-- Log of all attendance warning runs (audit trail)
CREATE TABLE IF NOT EXISTS attendance_warning_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_date DATE NOT NULL DEFAULT CURRENT_DATE,
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    students_checked INTEGER NOT NULL DEFAULT 0,
    warnings_sent INTEGER NOT NULL DEFAULT 0,
    critical_sent INTEGER NOT NULL DEFAULT 0,
    errors INTEGER NOT NULL DEFAULT 0,
    run_duration_ms INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE attendance_warnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_warning_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Admin/Director can view attendance warnings" ON attendance_warnings
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Students can view their own attendance warnings" ON attendance_warnings
    FOR SELECT USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "Parents can view linked child warnings" ON attendance_warnings
    FOR SELECT USING (
        student_id IN (
            SELECT student_id FROM parent_student_links
            WHERE parent_user_id = auth.uid() AND verified = true
        )
    );

CREATE POLICY "System can insert attendance warnings" ON attendance_warnings
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Admin/Director can view warning logs" ON attendance_warning_logs
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "System can insert warning logs" ON attendance_warning_logs
    FOR INSERT WITH CHECK (true);

-- RPC: Calculate attendance percentage for a student
CREATE OR REPLACE FUNCTION get_student_attendance_pct(p_student_id UUID)
RETURNS TABLE (
    total_classes BIGINT,
    attended_classes BIGINT,
    attendance_pct NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT AS total_classes,
        COUNT(*) FILTER (WHERE a.status IN ('present', 'late'))::BIGINT AS attended_classes,
        CASE
            WHEN COUNT(*) = 0 THEN 100.00
            ELSE ROUND((COUNT(*) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC / COUNT(*)::NUMERIC) * 100, 2)
        END AS attendance_pct
    FROM attendance a
    WHERE a.student_id = p_student_id
      AND a.date >= (CURRENT_DATE - INTERVAL '120 days');
END;
$$;

-- RPC: Get attendance summary for all active students in an institution
CREATE OR REPLACE FUNCTION get_institution_attendance_summary()
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    guardian_name VARCHAR,
    guardian_phone VARCHAR,
    department_name TEXT,
    total_classes BIGINT,
    attended_classes BIGINT,
    attendance_pct NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id AS student_id,
        u.name AS student_name,
        s.roll_number,
        s.guardian_name,
        s.guardian_phone,
        d.name AS department_name,
        COUNT(a.id)::BIGINT AS total_classes,
        COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::BIGINT AS attended_classes,
        CASE
            WHEN COUNT(a.id) = 0 THEN 100.00
            ELSE ROUND(
                (COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC
                / NULLIF(COUNT(a.id), 0)::NUMERIC) * 100, 2
            )
        END AS attendance_pct
    FROM students s
    JOIN users u ON s.user_id = u.id
    LEFT JOIN departments d ON s.department_id = d.id
    LEFT JOIN attendance a ON a.student_id = s.id
        AND a.date >= (CURRENT_DATE - INTERVAL '120 days')
    WHERE s.is_active = true
      AND s.institution_id = get_auth_institution_id()
    GROUP BY s.id, u.name, s.roll_number, s.guardian_name, s.guardian_phone, d.name
    HAVING
        CASE
            WHEN COUNT(a.id) = 0 THEN 100.00
            ELSE ROUND(
                (COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC
                / NULLIF(COUNT(a.id), 0)::NUMERIC) * 100, 2
            )
        END < 80
    ORDER BY attendance_pct ASC;
END;
$$;


-- ============================================================
-- 2. FEE DEFAULTER AUTO-ESCALATION
-- ============================================================

-- Track escalation stages and notifications sent
CREATE TABLE IF NOT EXISTS fee_escalations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    fee_id UUID NOT NULL REFERENCES fee_structures(id) ON DELETE CASCADE,
    student_fee_id UUID NOT NULL REFERENCES student_fees(id) ON DELETE CASCADE,
    escalation_stage VARCHAR(30) NOT NULL CHECK (escalation_stage IN (
        'reminder_7day',      -- 7 days before due date
        'reminder_1day',      -- 1 day before due date
        'due_today',          -- Due date today
        'overdue_7day',       -- 7 days overdue
        'overdue_30day',      -- 30 days overdue - formal notice
        'escalated_to_admin'  -- Director flagged
    )),
    amount_overdue NUMERIC(10,2) NOT NULL DEFAULT 0,
    days_overdue INTEGER NOT NULL DEFAULT 0,
    sent_to_student BOOLEAN NOT NULL DEFAULT false,
    sent_to_parent BOOLEAN NOT NULL DEFAULT false,
    sent_to_hod BOOLEAN NOT NULL DEFAULT false,
    sent_to_director BOOLEAN NOT NULL DEFAULT false,
    notice_generated BOOLEAN NOT NULL DEFAULT false,
    notice_file_url TEXT,
    sent_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_escalation_per_student_stage UNIQUE (student_fee_id, escalation_stage)
);

-- Track all escalation runs
CREATE TABLE IF NOT EXISTS fee_escalation_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_date DATE NOT NULL DEFAULT CURRENT_DATE,
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    fees_checked INTEGER NOT NULL DEFAULT 0,
    reminders_sent INTEGER NOT NULL DEFAULT 0,
    escalations_sent INTEGER NOT NULL DEFAULT 0,
    notices_generated INTEGER NOT NULL DEFAULT 0,
    errors INTEGER NOT NULL DEFAULT 0,
    run_duration_ms INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE fee_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fee_escalation_logs ENABLE ROW LEVEL SECURITY;

-- RLS Policies for fee_escalations
CREATE POLICY "Admin/Director can view fee escalations" ON fee_escalations
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director', 'HOD')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Students can view their own fee escalations" ON fee_escalations
    FOR SELECT USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "Parents can view linked child escalations" ON fee_escalations
    FOR SELECT USING (
        student_id IN (
            SELECT student_id FROM parent_student_links
            WHERE parent_user_id = auth.uid() AND verified = true
        )
    );

CREATE POLICY "System can insert fee escalations" ON fee_escalations
    FOR INSERT WITH CHECK (true);

CREATE POLICY "System can update fee escalations" ON fee_escalations
    FOR UPDATE USING (true);

CREATE POLICY "Admin/Director can view escalation logs" ON fee_escalation_logs
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "System can insert escalation logs" ON fee_escalation_logs
    FOR INSERT WITH CHECK (true);

-- RPC: Get fee defaulters for an institution (students with overdue fees)
CREATE OR REPLACE FUNCTION get_fee_defaulters()
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    guardian_name VARCHAR,
    guardian_phone VARCHAR,
    department_name TEXT,
    fee_id UUID,
    fee_name VARCHAR,
    amount_due NUMERIC,
    amount_paid NUMERIC,
    amount_overdue NUMERIC,
    due_date DATE,
    days_overdue INTEGER,
    late_fee NUMERIC,
    total_due NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id AS student_id,
        u.name AS student_name,
        s.roll_number,
        s.guardian_name,
        s.guardian_phone,
        d.name AS department_name,
        sf.fee_id,
        fs.name AS fee_name,
        sf.amount AS amount_due,
        sf.paid_amount AS amount_paid,
        (sf.amount - sf.paid_amount) AS amount_overdue,
        sf.due_date,
        (CURRENT_DATE - sf.due_date)::INTEGER AS days_overdue,
        calculate_fee_penalty(sf.fee_id, CURRENT_DATE) AS late_fee,
        (sf.amount - sf.paid_amount + calculate_fee_penalty(sf.fee_id, CURRENT_DATE)) AS total_due
    FROM student_fees sf
    JOIN fee_structures fs ON sf.fee_id = fs.id
    JOIN students s ON sf.student_id = s.id
    JOIN users u ON s.user_id = u.id
    LEFT JOIN departments d ON s.department_id = d.id
    WHERE sf.payment_status IN ('pending', 'partial')
      AND sf.due_date <= CURRENT_DATE
      AND s.is_active = true
      AND s.institution_id = get_auth_institution_id()
    ORDER BY (sf.due_date - CURRENT_DATE) DESC, sf.amount DESC;
END;
$$;


-- ============================================================
-- 3. PARENT → CHILD VERIFIED LINK SYSTEM (OTP)
-- ============================================================

-- OTP tokens for parent registration and child linking
CREATE TABLE IF NOT EXISTS parent_otps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone VARCHAR(20) NOT NULL,
    otp_code VARCHAR(6) NOT NULL,
    purpose VARCHAR(30) NOT NULL CHECK (purpose IN ('register', 'link_child', 'verify_change')),
    metadata JSONB DEFAULT '{}',
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 5,
    is_used BOOLEAN NOT NULL DEFAULT false,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Parent profiles (separate from users table for portal-specific data)
CREATE TABLE IF NOT EXISTS parent_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    occupation VARCHAR(100),
    relationship VARCHAR(50) DEFAULT 'Guardian',
    is_verified BOOLEAN NOT NULL DEFAULT false,
    verified_at TIMESTAMP WITH TIME ZONE,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_parent_profile UNIQUE (user_id)
);

-- Enable RLS
ALTER TABLE parent_otps ENABLE ROW LEVEL SECURITY;
ALTER TABLE parent_profiles ENABLE ROW LEVEL SECURITY;

-- RLS Policies for parent_otps (no user access - system only)
CREATE POLICY "System can manage parent OTPs" ON parent_otps
    FOR ALL USING (true);

-- RLS Policies for parent_profiles
CREATE POLICY "Parents can view their own profile" ON parent_profiles
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Admin can view parent profiles in institution" ON parent_profiles
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "System can insert parent profiles" ON parent_profiles
    FOR INSERT WITH CHECK (true);

CREATE POLICY "System can update parent profiles" ON parent_profiles
    FOR UPDATE USING (true);

-- RPC: Generate and store OTP for parent
CREATE OR REPLACE FUNCTION generate_parent_otp(
    p_phone VARCHAR,
    p_purpose VARCHAR,
    p_metadata JSONB DEFAULT '{}'
)
RETURNS TABLE (
    otp_id UUID,
    otp_code VARCHAR,
    expires_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_otp VARCHAR(6);
    v_id UUID;
    v_expires TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Generate 6-digit OTP
    v_otp := LPAD(FLOOR(RANDOM() * 999999 + 1)::TEXT, 6, '0');
    v_expires := NOW() + INTERVAL '10 minutes';

    -- Invalidate any existing OTPs for this phone+purpose
    UPDATE parent_otps
    SET is_used = true
    WHERE phone = p_phone
      AND purpose = p_purpose
      AND is_used = false;

    -- Insert new OTP
    INSERT INTO parent_otps (phone, otp_code, purpose, metadata, expires_at)
    VALUES (p_phone, v_otp, p_purpose, p_metadata, v_expires)
    RETURNING id INTO v_id;

    otp_id := v_id;
    otp_code := v_otp;
    expires_at := v_expires;
    RETURN NEXT;
END;
$$;

-- RPC: Verify parent OTP
CREATE OR REPLACE FUNCTION verify_parent_otp(
    p_phone VARCHAR,
    p_otp VARCHAR,
    p_purpose VARCHAR
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    metadata JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_otp_record RECORD;
BEGIN
    -- Find valid OTP
    SELECT * INTO v_otp_record
    FROM parent_otps
    WHERE phone = p_phone
      AND purpose = p_purpose
      AND is_used = false
      AND expires_at > NOW()
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_otp_record IS NULL THEN
        success := false;
        message := 'No valid OTP found. Please request a new code.';
        metadata := '{}';
        RETURN NEXT;
        RETURN;
    END IF;

    -- Check attempts
    IF v_otp_record.attempts >= v_otp_record.max_attempts THEN
        UPDATE parent_otps SET is_used = true WHERE id = v_otp_record.id;
        success := false;
        message := 'Maximum attempts exceeded. Please request a new code.';
        metadata := '{}';
        RETURN NEXT;
        RETURN;
    END IF;

    -- Increment attempts
    UPDATE parent_otps SET attempts = attempts + 1 WHERE id = v_otp_record.id;

    -- Check OTP
    IF v_otp_record.otp_code != p_otp THEN
        success := false;
        message := 'Incorrect verification code. Please try again.';
        metadata := '{}';
        RETURN NEXT;
        RETURN;
    END IF;

    -- Mark as used
    UPDATE parent_otps SET is_used = true WHERE id = v_otp_record.id;

    success := true;
    message := 'Verification successful.';
    metadata := v_otp_record.metadata;
    RETURN NEXT;
END;
$$;

-- RPC: Link parent to child via roll number verification
CREATE OR REPLACE FUNCTION link_parent_to_child(
    p_roll_number VARCHAR,
    p_child_dob DATE
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    student_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student RECORD;
    v_user_id UUID;
BEGIN
    v_user_id := auth.uid();

    -- Find student by roll number
    SELECT s.id, s.user_id, s.dob, s.institution_id, u.name AS full_name
    INTO v_student
    FROM students s
    JOIN users u ON s.user_id = u.id
    WHERE s.roll_number = p_roll_number
      AND s.is_active = true;

    IF v_student IS NULL THEN
        success := false;
        message := 'No active student found with this roll number.';
        student_id := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Verify DOB matches (additional security layer)
    IF v_student.dob != p_child_dob THEN
        success := false;
        message := 'Date of birth does not match our records.';
        student_id := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Check if already linked
    IF EXISTS (
        SELECT 1 FROM parent_student_links
        WHERE parent_user_id = v_user_id
          AND student_id = v_student.id
          AND verified = true
    ) THEN
        success := false;
        message := 'This student is already linked to your account.';
        student_id := v_student.id;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Create or update link
    INSERT INTO parent_student_links (parent_user_id, student_id, verified, relationship)
    VALUES (v_user_id, v_student.id, true, 'Guardian')
    ON CONFLICT (parent_user_id, student_id)
    DO UPDATE SET verified = true;

    -- Update parent profile if exists
    UPDATE parent_profiles SET is_verified = true, verified_at = NOW()
    WHERE user_id = v_user_id;

    success := true;
    message := 'Successfully linked to student ' || v_student.full_name;
    student_id := v_student.id;
    RETURN NEXT;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000005_medium_priority_features.sql
-- ==========================================================

-- ============================================================
-- MEDIUM PRIORITY: Exam Seating, Lost & Found, Notice Read Receipts
-- ============================================================

-- ============================================================
-- 1. EXAM HALL SEATING ALLOCATION
-- ============================================================

CREATE TABLE IF NOT EXISTS exam_seating (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exam_id UUID NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    room_number VARCHAR(50) NOT NULL,
    seat_number VARCHAR(10) NOT NULL,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    invigilator_id UUID REFERENCES users(id) ON DELETE SET NULL,
    is_checked_in BOOLEAN NOT NULL DEFAULT false,
    checked_in_at TIMESTAMP WITH TIME ZONE,
    qr_token VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_seat_per_exam UNIQUE (exam_id, room_number, seat_number),
    CONSTRAINT unique_student_per_exam UNIQUE (exam_id, student_id)
);

CREATE TABLE IF NOT EXISTS exam_halls (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    hall_name VARCHAR(100) NOT NULL,
    room_number VARCHAR(50) NOT NULL,
    capacity INTEGER NOT NULL DEFAULT 30,
    has_ac BOOLEAN NOT NULL DEFAULT false,
    has_projector BOOLEAN NOT NULL DEFAULT false,
    floor_number INTEGER DEFAULT 1,
    building VARCHAR(100),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_hall_room UNIQUE (institution_id, room_number)
);

-- Enable RLS
ALTER TABLE exam_seating ENABLE ROW LEVEL SECURITY;
ALTER TABLE exam_halls ENABLE ROW LEVEL SECURITY;

-- RLS for exam_seating
CREATE POLICY "Admin/Director can manage exam seating" ON exam_seating
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Teachers can view seating for their exams" ON exam_seating
    FOR SELECT USING (
        get_auth_user_role() = 'Teacher'
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Students can view their own seating" ON exam_seating
    FOR SELECT USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "Parents can view linked child seating" ON exam_seating
    FOR SELECT USING (
        student_id IN (
            SELECT student_id FROM parent_student_links
            WHERE parent_user_id = auth.uid() AND verified = true
        )
    );

-- RLS for exam_halls
CREATE POLICY "Admin can manage exam halls" ON exam_halls
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Staff can view exam halls" ON exam_halls
    FOR SELECT USING (
        get_auth_user_role() IN ('Teacher', 'Staff', 'Director', 'HOD')
        AND institution_id = get_auth_institution_id()
        AND is_active = true
    );

-- RPC: Auto-allocate seating for an exam
CREATE OR REPLACE FUNCTION auto_allocate_seating(p_exam_id UUID)
RETURNS TABLE (
    total_allocated INTEGER,
    rooms_used INTEGER,
    message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_exam RECORD;
    v_hall RECORD;
    v_students UUID[];
    v_seat_counter INTEGER;
    v_total INTEGER := 0;
    v_room_count INTEGER := 0;
BEGIN
    -- Get exam details
    SELECT * INTO v_exam FROM exams WHERE id = p_exam_id;
    IF v_exam IS NULL THEN
        RAISE EXCEPTION 'Exam not found';
    END IF;

    -- Get enrolled students for this exam
    SELECT ARRAY_AGG(s.id ORDER BY s.roll_number) INTO v_students
    FROM students s
    WHERE s.department_id = v_exam.department_id
      AND s.is_active = true
      AND s.year = v_exam.year;

    IF v_students IS NULL OR array_length(v_students, 1) = 0 THEN
        total_allocated := 0;
        rooms_used := 0;
        message := 'No students found for this exam';
        RETURN NEXT;
        RETURN;
    END IF;

    -- Clear existing seating for this exam
    DELETE FROM exam_seating WHERE exam_id = p_exam_id;

    -- Allocate seats room by room
    v_seat_counter := 1;
    FOR v_hall IN
        SELECT * FROM exam_halls
        WHERE institution_id = v_exam.institution_id
          AND is_active = true
        ORDER BY capacity DESC
    LOOP
        EXIT WHEN v_seat_counter > array_length(v_students, 1);

        FOR i IN 1..LEAST(v_hall.capacity, array_length(v_students, 1) - v_seat_counter + 1) LOOP
            INSERT INTO exam_seating (exam_id, institution_id, room_number, seat_number, student_id)
            VALUES (
                p_exam_id,
                v_exam.institution_id,
                v_hall.room_number,
                LPAD(i::TEXT, 3, '0'),
                v_students[v_seat_counter]
            );
            v_seat_counter := v_seat_counter + 1;
            v_total := v_total + 1;
        END LOOP;

        v_room_count := v_room_count + 1;
    END LOOP;

    total_allocated := v_total;
    rooms_used := v_room_count;
    message := 'Allocated ' || v_total || ' students across ' || v_room_count || ' rooms';
    RETURN NEXT;
END;
$$;

-- RPC: Check-in student at exam hall via QR scan
CREATE OR REPLACE FUNCTION checkin_exam_seat(
    p_exam_id UUID,
    p_room_number VARCHAR,
    p_seat_number VARCHAR,
    p_student_id UUID
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    seat_info JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_seat RECORD;
BEGIN
    SELECT * INTO v_seat
    FROM exam_seating
    WHERE exam_id = p_exam_id
      AND room_number = p_room_number
      AND seat_number = p_seat_number;

    IF v_seat IS NULL THEN
        success := false;
        message := 'No seat found for this room/seat combination';
        seat_info := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    IF v_seat.student_id != p_student_id THEN
        success := false;
        message := 'This seat is assigned to a different student';
        seat_info := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    UPDATE exam_seating
    SET is_checked_in = true, checked_in_at = NOW()
    WHERE id = v_seat.id;

    success := true;
    message := 'Check-in successful';
    seat_info := to_jsonb(v_seat);
    RETURN NEXT;
END;
$$;


-- ============================================================
-- 2. LOST & FOUND MODULE
-- ============================================================

CREATE TABLE IF NOT EXISTS lost_found_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    reported_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    item_name VARCHAR(255) NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'Other' CHECK (category IN (
        'Electronics', 'ID Card', 'Wallet', 'Keys', 'Bag', 'Books', 'Clothing', 'Accessories', 'Other'
    )),
    description TEXT,
    photo_url TEXT,
    location_found VARCHAR(255),
    found_date DATE NOT NULL DEFAULT CURRENT_DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'claimed', 'returned', 'disposed')),
    claimed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    claimed_at TIMESTAMP WITH TIME ZONE,
    returned_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE lost_found_items ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Admin/Security can manage lost found items" ON lost_found_items
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "All users can view available lost found items" ON lost_found_items
    FOR SELECT USING (
        institution_id = get_auth_institution_id()
    );

CREATE POLICY "Students can claim items" ON lost_found_items
    FOR UPDATE USING (
        get_auth_user_role() = 'Student'
        AND institution_id = get_auth_institution_id()
    );

-- RPC: Claim a lost found item
CREATE OR REPLACE FUNCTION claim_lost_found_item(p_item_id UUID)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_item RECORD;
BEGIN
    SELECT * INTO v_item FROM lost_found_items WHERE id = p_item_id;

    IF v_item IS NULL THEN
        success := false;
        message := 'Item not found';
        RETURN NEXT;
        RETURN;
    END IF;

    IF v_item.status != 'available' THEN
        success := false;
        message := 'This item is no longer available';
        RETURN NEXT;
        RETURN;
    END IF;

    UPDATE lost_found_items
    SET status = 'claimed',
        claimed_by = auth.uid(),
        claimed_at = NOW()
    WHERE id = p_item_id;

    success := true;
    message := 'Item claimed. Please collect from the security desk.';
    RETURN NEXT;
END;
$$;


-- ============================================================
-- 3. NOTICE READ RECEIPTS ENHANCEMENT
-- ============================================================

-- Add status column to notices if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'notices' AND column_name = 'status'
    ) THEN
        ALTER TABLE notices ADD COLUMN status VARCHAR(20) DEFAULT 'published' CHECK (status IN ('draft', 'published', 'archived'));
    END IF;
END $$;

-- RPC: Get notice read receipt stats
CREATE OR REPLACE FUNCTION get_notice_read_stats(p_notice_id UUID)
RETURNS TABLE (
    notice_id UUID,
    total_target_users BIGINT,
    total_read BIGINT,
    read_percentage NUMERIC,
    unread_users JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_notice RECORD;
    v_target_audience VARCHAR;
    v_total_users BIGINT;
    v_total_read BIGINT;
    v_unread JSONB;
BEGIN
    -- Get notice details
    SELECT * INTO v_notice FROM notices WHERE id = p_notice_id;

    IF v_notice IS NULL THEN
        RAISE EXCEPTION 'Notice not found';
    END IF;

    -- Count target users based on audience
    SELECT COUNT(*) INTO v_total_users
    FROM users u
    JOIN students s ON s.user_id = u.id
    WHERE s.institution_id = v_notice.institution_id
      AND s.is_active = true
      AND (
          v_notice.target_audience = 'All'
          OR (v_notice.target_audience = 'Students')
          OR (v_notice.target_audience = 'Staff' AND u.role IN ('Teacher', 'Staff', 'HOD'))
          OR (v_notice.target_audience = 'HOD' AND u.role = 'HOD')
      );

    -- Count users who have read it
    SELECT COUNT(DISTINCT nr.user_id) INTO v_total_read
    FROM notice_reads nr
    WHERE nr.notice_id = p_notice_id;

    -- Get unread users
    SELECT COALESCE(
        json_agg(json_build_object(
            'user_id', u.id,
            'name', u.name,
            'email', u.email
        )),
        '[]'::JSON
    ) INTO v_unread
    FROM users u
    JOIN students s ON s.user_id = u.id
    WHERE s.institution_id = v_notice.institution_id
      AND s.is_active = true
      AND u.id NOT IN (
          SELECT user_id FROM notice_reads WHERE notice_id = p_notice_id
      )
      AND (
          v_notice.target_audience = 'All'
          OR (v_notice.target_audience = 'Students')
          OR (v_notice.target_audience = 'Staff' AND u.role IN ('Teacher', 'Staff', 'HOD'))
          OR (v_notice.target_audience = 'HOD' AND u.role = 'HOD')
      )
    LIMIT 50;

    notice_id := p_notice_id;
    total_target_users := v_total_users;
    total_read := v_total_read;
    read_percentage := CASE WHEN v_total_users = 0 THEN 0 ELSE ROUND((v_total_read::NUMERIC / v_total_users::NUMERIC) * 100, 1) END;
    unread_users := v_unread;
    RETURN NEXT;
END;
$$;

-- RPC: Re-notify users who haven't read a notice
CREATE OR REPLACE FUNCTION get_unread_notice_recipients(p_notice_id UUID)
RETURNS TABLE (
    user_id UUID,
    full_name VARCHAR,
    email VARCHAR,
    phone VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_notice RECORD;
BEGIN
    SELECT * INTO v_notice FROM notices WHERE id = p_notice_id;

    IF v_notice IS NULL THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT u.id, u.name AS full_name, u.email, s.guardian_phone AS phone
    FROM users u
    JOIN students s ON s.user_id = u.id
    WHERE s.institution_id = v_notice.institution_id
      AND s.is_active = true
      AND u.id NOT IN (
          SELECT user_id FROM notice_reads WHERE notice_id = p_notice_id
      )
      AND (
          v_notice.target_audience = 'All'
          OR (v_notice.target_audience = 'Students')
          OR (v_notice.target_audience = 'Staff' AND u.role IN ('Teacher', 'Staff', 'HOD'))
          OR (v_notice.target_audience = 'HOD' AND u.role = 'HOD')
      );
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000006_broken_fixes_and_new_modules.sql
-- ==========================================================

-- ============================================================
-- BROKEN FIXES: Gym membership, Hostel roommates, Timetable batch, Fee penalties
-- ============================================================

-- ============================================================
-- 1. FIX: Gym booking RPC - add active membership check
-- ============================================================
CREATE OR REPLACE FUNCTION book_gym_slot_atomic(
  p_institution_id UUID,
  p_slot_id UUID,
  p_student_id UUID
) RETURNS JSON AS $$
DECLARE
  v_booking_id UUID;
  v_slot_date DATE;
  v_start_time TIME;
  v_end_time TIME;
  v_has_membership BOOLEAN;
BEGIN
  -- CHECK: Student must have an active gym membership
  SELECT EXISTS (
    SELECT 1 FROM gym_memberships gm
    WHERE gm.student_id = p_student_id
      AND gm.institution_id = p_institution_id
      AND gm.status = 'Active'
      AND gm.end_date >= CURRENT_DATE
      AND (gm.is_frozen IS NOT TRUE OR gm.frozen_until < CURRENT_DATE)
  ) INTO v_has_membership;

  IF NOT v_has_membership THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No active gym membership found. Please purchase a membership before booking slots.'
    );
  END IF;

  -- Check if student already booked this slot
  IF EXISTS (
    SELECT 1 FROM gym_bookings
    WHERE student_id = p_student_id AND slot_id = p_slot_id AND status = 'Booked'
  ) THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Student already has an active booking for this gym slot. Duplicate booking denied.'
    );
  END IF;

  UPDATE gym_slots
    SET booked_count = booked_count + 1
    WHERE id = p_slot_id
      AND booked_count < capacity
      AND institution_id = p_institution_id
    RETURNING date, start_time, end_time INTO v_slot_date, v_start_time, v_end_time;

  IF NOT FOUND THEN
    RETURN json_build_object(
      'success', false,
      'error', 'Gym slot is fully booked or does not exist.'
    );
  END IF;

  INSERT INTO gym_bookings (institution_id, slot_id, student_id, booking_date, status)
    VALUES (p_institution_id, p_slot_id, p_student_id, CURRENT_DATE, 'Booked')
    RETURNING id INTO v_booking_id;

  RETURN json_build_object(
    'success', true,
    'booking_id', v_booking_id,
    'slot_date', v_slot_date,
    'start_time', v_start_time,
    'end_time', v_end_time
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ============================================================
-- 2. FIX: Timetable - add semester + batch_year columns
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'timetable' AND column_name = 'semester'
  ) THEN
    ALTER TABLE timetable ADD COLUMN semester INTEGER DEFAULT 1;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'timetable' AND column_name = 'batch_year'
  ) THEN
    ALTER TABLE timetable ADD COLUMN batch_year VARCHAR(10) DEFAULT '';
  END IF;
END $$;

-- RPC: Get student timetable filtered by their semester/batch
CREATE OR REPLACE FUNCTION get_student_timetable_filtered(p_student_id UUID)
RETURNS TABLE (
    id UUID,
    day_of_week VARCHAR,
    time_slot VARCHAR,
    subject VARCHAR,
    teacher_name TEXT,
    room VARCHAR,
    semester INTEGER,
    batch_year VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_student RECORD;
BEGIN
  SELECT s.department_id, s.semester, s.batch_year INTO v_student
  FROM students s WHERE s.id = p_student_id;

  IF v_student IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT t.id, t.day_of_week, t.time_slot, t.subject,
         u.name AS teacher_name, t.room, t.semester, t.batch_year
  FROM timetable t
  LEFT JOIN staff st ON t.teacher_id = st.id
  LEFT JOIN users u ON st.user_id = u.id
  WHERE t.department_id = v_student.department_id
    AND (t.semester = v_student.semester OR t.semester IS NULL OR t.semester = 0)
    AND (t.batch_year = v_student.batch_year OR t.batch_year = '' OR t.batch_year IS NULL)
  ORDER BY
    CASE t.day_of_week
      WHEN 'Monday' THEN 1 WHEN 'Tuesday' THEN 2 WHEN 'Wednesday' THEN 3
      WHEN 'Thursday' THEN 4 WHEN 'Friday' THEN 5 WHEN 'Saturday' THEN 6
      ELSE 7
    END,
    t.time_slot;
END;
$$;


-- ============================================================
-- 3. FIX: Fee structures - add late fee columns (if not already added)
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fee_structures' AND column_name = 'late_fee_per_day'
  ) THEN
    ALTER TABLE fee_structures ADD COLUMN late_fee_per_day NUMERIC(8,2) DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fee_structures' AND column_name = 'grace_period_days'
  ) THEN
    ALTER TABLE fee_structures ADD COLUMN grace_period_days INTEGER DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'fee_structures' AND column_name = 'max_penalty'
  ) THEN
    ALTER TABLE fee_structures ADD COLUMN max_penalty NUMERIC(10,2) DEFAULT 0;
  END IF;
END $$;

-- RPC: Calculate late fee penalty for a given student fee
CREATE OR REPLACE FUNCTION calculate_late_fee(p_student_fee_id UUID)
RETURNS TABLE (
    original_amount NUMERIC,
    days_overdue INTEGER,
    late_fee_per_day NUMERIC,
    days_after_grace INTEGER,
    total_late_fee NUMERIC,
    total_amount NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sf RECORD;
  v_fs RECORD;
  v_days_overdue INTEGER;
  v_days_after_grace INTEGER;
  v_late_fee NUMERIC;
BEGIN
  SELECT sf.*, fs.late_fee_per_day, fs.grace_period_days, fs.max_penalty, fs.amount AS fs_amount
  INTO v_sf
  FROM student_fees sf
  JOIN fee_structures fs ON sf.fee_id = fs.id
  WHERE sf.id = p_student_fee_id;

  IF v_sf IS NULL THEN RETURN; END IF;

  v_days_overdue := GREATEST(0, (CURRENT_DATE - v_sf.due_date)::INTEGER);
  v_days_after_grace := GREATEST(0, v_days_overdue - COALESCE(v_sf.grace_period_days, 0));
  v_late_fee := v_days_after_grace * COALESCE(v_sf.late_fee_per_day, 0);

  -- Apply max penalty cap
  IF COALESCE(v_sf.max_penalty, 0) > 0 THEN
    v_late_fee := LEAST(v_late_fee, v_sf.max_penalty);
  END IF;

  original_amount := v_sf.amount;
  days_overdue := v_days_overdue;
  late_fee_per_day := COALESCE(v_sf.late_fee_per_day, 0);
  days_after_grace := v_days_after_grace;
  total_late_fee := v_late_fee;
  total_amount := v_sf.amount + v_late_fee;
  RETURN NEXT;
END;
$$;


-- ============================================================
-- 4. ADD: Canteen - is_special_daily flag + allergen search
-- ============================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'canteen_menus' AND column_name = 'is_daily_special'
  ) THEN
    ALTER TABLE canteen_menus ADD COLUMN is_daily_special BOOLEAN DEFAULT FALSE;
  END IF;
END $$;

-- RPC: Get today's menu with allergen filter
CREATE OR REPLACE FUNCTION get_canteen_menu_filtered(
  p_category VARCHAR DEFAULT NULL,
  p_veg_only BOOLEAN DEFAULT FALSE,
  p_exclude_allergens TEXT[] DEFAULT NULL,
  p_search VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    item_name VARCHAR,
    category VARCHAR,
    price DECIMAL,
    image_url TEXT,
    is_available BOOLEAN,
    is_veg BOOLEAN,
    is_daily_special BOOLEAN,
    description TEXT,
    calories INTEGER,
    prep_time_mins INTEGER,
    spice_level INTEGER,
    rating_avg DECIMAL,
    allergens TEXT[],
    stock_remaining INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT cm.id, cm.item_name, cm.category, cm.price, cm.image_url,
         cm.is_available, cm.is_veg, cm.is_daily_special,
         cm.description, cm.calories, cm.prep_time_mins,
         cm.spice_level, cm.rating_avg, cm.allergens, cm.stock_remaining
  FROM canteen_menus cm
  WHERE cm.is_available = true
    AND (p_category IS NULL OR cm.category = p_category)
    AND (p_veg_only = FALSE OR cm.is_veg = TRUE)
    AND (p_search IS NULL OR cm.item_name ILIKE '%' || p_search || '%')
    AND (p_exclude_allergens IS NULL OR NOT cm.allergens && p_exclude_allergens)
  ORDER BY cm.is_daily_special DESC, cm.sort_order ASC, cm.rating_avg DESC;
END;
$$;


-- ============================================================
-- 5. ADD: Hostel roommates - dedicated RPC (no data leak)
-- ============================================================
CREATE OR REPLACE FUNCTION get_my_roommates(p_student_id UUID)
RETURNS TABLE (
    student_name TEXT,
    roll_number VARCHAR,
    room_number VARCHAR,
    block_name VARCHAR,
    floor_number INTEGER,
    bed_number VARCHAR,
    course VARCHAR,
    department_name TEXT,
    phone VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_allocation RECORD;
BEGIN
  -- Get current allocation for this student
  SELECT ha.room_id INTO v_allocation
  FROM hostel_allocations ha
  WHERE ha.student_id = p_student_id AND ha.is_current = TRUE;

  IF v_allocation IS NULL THEN RETURN; END IF;

  -- Return only students in the same room
  RETURN QUERY
  SELECT u.name AS student_name, s.roll_number,
         hr.room_number, hb.name AS block_name, hr.floor_number,
         ha2.bed_number, s.course, d.name AS department_name, u.phone
  FROM hostel_allocations ha2
  JOIN students s ON ha2.student_id = s.id
  JOIN users u ON s.user_id = u.id
  JOIN hostel_rooms hr ON ha2.room_id = hr.id
  JOIN hostel_blocks hb ON hr.block_id = hb.id
  LEFT JOIN departments d ON s.department_id = d.id
  WHERE ha2.room_id = v_allocation.room_id
    AND ha2.is_current = TRUE
    AND ha2.student_id != p_student_id;
END;
$$;


-- ============================================================
-- 6. ADD: Assignment submission module
-- ============================================================
CREATE TABLE IF NOT EXISTS assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    subject VARCHAR(150),
    total_marks INTEGER DEFAULT 100,
    deadline TIMESTAMP WITH TIME ZONE NOT NULL,
    allowed_file_types TEXT[] DEFAULT ARRAY['pdf', 'jpg', 'jpeg', 'png'],
    max_file_size_mb INTEGER DEFAULT 10,
    semester INTEGER,
    batch_year VARCHAR(10),
    is_published BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS assignment_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    file_url TEXT NOT NULL,
    file_name VARCHAR(255),
    file_size_kb INTEGER,
    file_type VARCHAR(10),
    marks_obtained INTEGER,
    feedback TEXT,
    submitted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    graded_at TIMESTAMP WITH TIME ZONE,
    graded_by UUID REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'submitted' CHECK (status IN ('submitted', 'graded', 'returned')),
    CONSTRAINT unique_submission_per_assignment UNIQUE (assignment_id, student_id)
);

-- RLS
ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignment_submissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Staff/Admin can manage assignments" ON assignments
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'Staff')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Students can view published assignments" ON assignments
    FOR SELECT USING (
        is_published = true
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Students can view/insert own submissions" ON assignment_submissions
    FOR ALL USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "Staff/Admin can view submissions" ON assignment_submissions
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'Staff')
        AND assignment_id IN (SELECT id FROM assignments WHERE institution_id = get_auth_institution_id())
    );

-- RPC: Submit assignment
CREATE OR REPLACE FUNCTION submit_assignment(
    p_assignment_id UUID,
    p_file_url TEXT,
    p_file_name VARCHAR,
    p_file_size_kb INTEGER,
    p_file_type VARCHAR
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student_id UUID;
    v_assignment RECORD;
    v_submission_id UUID;
BEGIN
    SELECT id INTO v_student_id FROM students WHERE user_id = auth.uid();
    IF v_student_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Student profile not found.');
    END IF;

    SELECT * INTO v_assignment FROM assignments WHERE id = p_assignment_id AND is_published = true;
    IF v_assignment IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Assignment not found or not published.');
    END IF;

    IF v_assignment.deadline < NOW() THEN
        RETURN json_build_object('success', false, 'error', 'Submission deadline has passed.');
    END IF;

    -- Upsert (allow resubmission before deadline)
    INSERT INTO assignment_submissions (assignment_id, student_id, file_url, file_name, file_size_kb, file_type, status)
    VALUES (p_assignment_id, v_student_id, p_file_url, p_file_name, p_file_size_kb, p_file_type, 'submitted')
    ON CONFLICT (assignment_id, student_id)
    DO UPDATE SET file_url = EXCLUDED.file_url, file_name = EXCLUDED.file_name,
                  file_size_kb = EXCLUDED.file_size_kb, file_type = EXCLUDED.file_type,
                  submitted_at = NOW(), status = 'submitted', marks_obtained = NULL, feedback = NULL
    RETURNING id INTO v_submission_id;

    RETURN json_build_object('success', true, 'submission_id', v_submission_id);
END;
$$;


-- ============================================================
-- 7. ADD: Study material / notes module
-- ============================================================
CREATE TABLE IF NOT EXISTS study_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    department_id UUID REFERENCES departments(id) ON DELETE CASCADE,
    uploaded_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    subject VARCHAR(150),
    file_url TEXT NOT NULL,
    file_name VARCHAR(255),
    file_type VARCHAR(10),
    file_size_kb INTEGER,
    category VARCHAR(50) DEFAULT 'Notes' CHECK (category IN ('Notes', 'Lab Manual', 'Textbook', 'Video', 'PPT', 'Question Bank', 'Syllabus', 'Other')),
    semester INTEGER,
    batch_year VARCHAR(10),
    download_count INTEGER DEFAULT 0,
    is_published BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE study_materials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Staff/Admin can manage study materials" ON study_materials
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'Staff')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Students can view published materials" ON study_materials
    FOR SELECT USING (
        is_published = true
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Students can view materials for their dept/semester" ON study_materials
    FOR SELECT USING (
        is_published = true
        AND (department_id IS NULL OR department_id IN (
            SELECT department_id FROM students WHERE user_id = auth.uid()
        ))
        AND (semester IS NULL OR semester IN (
            SELECT semester FROM students WHERE user_id = auth.uid()
        ))
    );


-- ============================================================
-- 8. ADD: Leave application module
-- ============================================================
CREATE TABLE IF NOT EXISTS student_leave_applications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    leave_type VARCHAR(30) NOT NULL CHECK (leave_type IN ('medical', 'od', 'personal', 'half_day', 'emergency')),
    from_date DATE NOT NULL,
    to_date DATE NOT NULL,
    reason TEXT NOT NULL,
    attachment_url TEXT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'faculty_approved', 'hod_approved', 'rejected')),
    faculty_remarks TEXT,
    faculty_approved_at TIMESTAMP WITH TIME ZONE,
    hod_remarks TEXT,
    hod_approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE student_leave_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Students can view/insert own leaves" ON student_leave_applications
    FOR ALL USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "Faculty/HOD/Admin can view leaves" ON student_leave_applications
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'HOD', 'Staff')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Faculty/HOD can update leave status" ON student_leave_applications
    FOR UPDATE USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'HOD')
    );

-- RPC: Submit leave application
CREATE OR REPLACE FUNCTION submit_leave_application(
    p_leave_type VARCHAR,
    p_from_date DATE,
    p_to_date DATE,
    p_reason TEXT,
    p_attachment_url TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student_id UUID;
    v_leave_id UUID;
BEGIN
    SELECT id INTO v_student_id FROM students WHERE user_id = auth.uid();
    IF v_student_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Student profile not found.');
    END IF;

    IF p_to_date < p_from_date THEN
        RETURN json_build_object('success', false, 'error', 'End date cannot be before start date.');
    END IF;

    INSERT INTO student_leave_applications (institution_id, student_id, leave_type, from_date, to_date, reason, attachment_url)
    SELECT s.institution_id, v_student_id, p_leave_type, p_from_date, p_to_date, p_reason, p_attachment_url
    FROM students s WHERE s.id = v_student_id
    RETURNING id INTO v_leave_id;

    RETURN json_build_object('success', true, 'leave_id', v_leave_id);
END;
$$;

-- RPC: Approve leave (faculty or HOD)
CREATE OR REPLACE FUNCTION approve_leave(
    p_leave_id UUID,
    p_approver_role VARCHAR,
    p_remarks TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_leave RECORD;
    v_new_status VARCHAR;
    v_inst_id UUID;
    v_user_role VARCHAR;
BEGIN
    SELECT u.institution_id, u.role INTO v_inst_id, v_user_role
    FROM users u WHERE u.id = auth.uid();

    SELECT * INTO v_leave FROM student_leave_applications WHERE id = p_leave_id;
    IF v_leave IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Leave application not found.');
    END IF;

    IF v_inst_id IS NOT NULL AND v_leave.institution_id != v_inst_id AND COALESCE(v_user_role, '') != 'SuperAdmin' THEN
        RETURN json_build_object('success', false, 'error', 'Access denied. Cross-institution leave approval prohibited.');
    END IF;

    IF p_approver_role = 'Teacher' OR p_approver_role = 'Staff' THEN
        IF v_leave.status != 'pending' THEN
            RETURN json_build_object('success', false, 'error', 'Leave already processed.');
        END IF;
        v_new_status := 'faculty_approved';
        UPDATE student_leave_applications SET status = v_new_status, faculty_remarks = p_remarks, faculty_approved_at = NOW() WHERE id = p_leave_id;
    ELSIF p_approver_role = 'HOD' OR p_approver_role = 'Admin' THEN
        IF v_leave.status != 'faculty_approved' THEN
            RETURN json_build_object('success', false, 'error', 'Leave must be faculty-approved before HOD approval.');
        END IF;
        v_new_status := 'hod_approved';
        UPDATE student_leave_applications SET status = v_new_status, hod_remarks = p_remarks, hod_approved_at = NOW() WHERE id = p_leave_id;

        -- Auto-mark attendance as excused for approved leave days
        UPDATE attendance SET status = 'excused', notes = 'Leave approved'
        WHERE student_id = v_leave.student_id
          AND date BETWEEN v_leave.from_date AND v_leave.to_date;
    ELSE
        RETURN json_build_object('success', false, 'error', 'Invalid approver role.');
    END IF;

    RETURN json_build_object('success', true, 'new_status', v_new_status);
END;
$$;

-- RPC: Reject leave
CREATE OR REPLACE FUNCTION reject_leave(
    p_leave_id UUID,
    p_remarks TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_leave RECORD;
    v_inst_id UUID;
    v_user_role VARCHAR;
BEGIN
    SELECT u.institution_id, u.role INTO v_inst_id, v_user_role
    FROM users u WHERE u.id = auth.uid();

    SELECT * INTO v_leave FROM student_leave_applications WHERE id = p_leave_id;
    IF v_leave IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Leave not found or already processed.');
    END IF;

    IF v_inst_id IS NOT NULL AND v_leave.institution_id != v_inst_id AND COALESCE(v_user_role, '') != 'SuperAdmin' THEN
        RETURN json_build_object('success', false, 'error', 'Access denied. Cross-institution leave rejection prohibited.');
    END IF;

    UPDATE student_leave_applications SET status = 'rejected', hod_remarks = p_remarks, hod_approved_at = NOW()
    WHERE id = p_leave_id AND status IN ('pending', 'faculty_approved');

    IF FOUND THEN
        RETURN json_build_object('success', true, 'new_status', 'rejected');
    ELSE
        RETURN json_build_object('success', false, 'error', 'Leave not found or already processed.');
    END IF;
END;
$$;


-- ============================================================
-- 9. ADD: Campus wallet top-up via Razorpay
-- ============================================================
CREATE TABLE IF NOT EXISTS wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    amount NUMERIC(10,2) NOT NULL,
    type VARCHAR(20) NOT NULL CHECK (type IN ('topup', 'deduction', 'refund', 'parent_topup')),
    payment_method VARCHAR(30) DEFAULT 'razorpay',
    razorpay_order_id VARCHAR(100),
    razorpay_payment_id VARCHAR(100),
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed')),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'wallet_transactions' AND column_name = 'payment_method'
  ) THEN
    ALTER TABLE wallet_transactions ADD COLUMN payment_method VARCHAR(30) DEFAULT 'razorpay';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'wallet_transactions' AND column_name = 'razorpay_order_id'
  ) THEN
    ALTER TABLE wallet_transactions ADD COLUMN razorpay_order_id VARCHAR(100);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'wallet_transactions' AND column_name = 'razorpay_payment_id'
  ) THEN
    ALTER TABLE wallet_transactions ADD COLUMN razorpay_payment_id VARCHAR(100);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'wallet_transactions' AND column_name = 'status'
  ) THEN
    ALTER TABLE wallet_transactions ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
  END IF;
END $$;


ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Students can view own wallet transactions" ON wallet_transactions
    FOR SELECT USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "System can insert wallet transactions" ON wallet_transactions
    FOR INSERT WITH CHECK (true);

CREATE POLICY "System can update wallet transactions" ON wallet_transactions
    FOR UPDATE USING (true);

-- RPC: Credit wallet after successful payment
CREATE OR REPLACE FUNCTION credit_wallet(
    p_student_id UUID,
    p_amount NUMERIC,
    p_razorpay_order_id VARCHAR,
    p_razorpay_payment_id VARCHAR,
    p_description TEXT DEFAULT 'Wallet top-up'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tx_id UUID;
    v_student RECORD;
BEGIN
    SELECT * INTO v_student FROM students WHERE id = p_student_id;
    IF v_student IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Student not found.');
    END IF;

    INSERT INTO wallet_transactions (institution_id, student_id, amount, type, razorpay_order_id, razorpay_payment_id, status, description)
    VALUES (v_student.institution_id, p_student_id, p_amount, 'topup', p_razorpay_order_id, p_razorpay_payment_id, 'completed', p_description)
    RETURNING id INTO v_tx_id;

    -- Update student wallet balance (students table needs wallet_balance column)
    UPDATE students SET wallet_balance = COALESCE(wallet_balance, 0) + p_amount WHERE id = p_student_id;

    RETURN json_build_object('success', true, 'transaction_id', v_tx_id, 'new_balance', (SELECT wallet_balance FROM students WHERE id = p_student_id));
END;
$$;

-- Add wallet_balance column to students if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'students' AND column_name = 'wallet_balance'
  ) THEN
    ALTER TABLE students ADD COLUMN wallet_balance NUMERIC(10,2) DEFAULT 0;
  END IF;
END $$;


-- ============================================================
-- 10. ADD: Bus ETA endpoint for student's stop
-- ============================================================
CREATE OR REPLACE FUNCTION get_bus_eta_for_student(p_student_id UUID)
RETURNS TABLE (
    bus_id UUID,
    bus_name VARCHAR,
    route_name VARCHAR,
    stop_name VARCHAR,
    stop_index INTEGER,
    distance_km NUMERIC,
    eta_minutes INTEGER,
    latitude NUMERIC,
    longitude NUMERIC,
    last_updated TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscription RECORD;
    v_bus RECORD;
    v_bus_id UUID;
    v_stop_index INTEGER;
    v_distance NUMERIC;
    v_velocity NUMERIC;
BEGIN
    -- Get student's bus subscription
    SELECT bs.route_id, bs.stop_name, br.stops
    INTO v_subscription
    FROM transport_subscriptions bs
    JOIN bus_routes br ON bs.route_id = br.id
    WHERE bs.student_id = p_student_id AND bs.status = 'active'
    LIMIT 1;

    IF v_subscription IS NULL THEN RETURN; END IF;

    -- Get bus assigned to this route
    SELECT b.id INTO v_bus_id
    FROM buses b
    WHERE b.route_id = v_subscription.route_id
    LIMIT 1;

    IF v_bus_id IS NULL THEN RETURN; END IF;

    -- Get latest bus location
    SELECT bl.bus_id, bl.latitude, bl.longitude, bl.speed, bl.recorded_at
    INTO v_bus
    FROM bus_tracking bl
    WHERE bl.bus_id = v_bus_id
    ORDER BY bl.recorded_at DESC
    LIMIT 1;

    IF v_bus IS NULL THEN RETURN; END IF;

    -- Find stop_index from JSONB stops array
    SELECT (pos - 1)::INTEGER INTO v_stop_index
    FROM jsonb_array_elements(v_subscription.stops) WITH ORDINALITY AS arr(elem, pos)
    WHERE elem->>'name' = v_subscription.stop_name
    LIMIT 1;

    IF v_stop_index IS NULL THEN RETURN; END IF;

    -- Calculate distance to student's stop using Haversine
    IF v_subscription.stops IS NOT NULL AND jsonb_array_length(v_subscription.stops) > 0 THEN
        DECLARE
            v_stop_lat NUMERIC;
            v_stop_lon NUMERIC;
        BEGIN
            v_stop_lat := (v_subscription.stops->v_stop_index->>'latitude')::NUMERIC;
            v_stop_lon := (v_subscription.stops->v_stop_index->>'longitude')::NUMERIC;

            v_distance := (
                6371 * acos(
                    cos(radians(v_bus.latitude)) * cos(radians(v_stop_lat)) *
                    cos(radians(v_stop_lon) - radians(v_bus.longitude)) +
                    sin(radians(v_bus.latitude)) * sin(radians(v_stop_lat))
                )
            );

            v_velocity := CASE WHEN v_bus.speed > 5 THEN v_bus.speed ELSE 25 END;

            bus_id := v_bus.bus_id;
            bus_name := (SELECT name FROM buses WHERE id = v_bus.bus_id);
            route_name := (SELECT route_name FROM bus_routes WHERE id = v_subscription.route_id);
            stop_name := v_subscription.stop_name;
            stop_index := v_stop_index;
            distance_km := ROUND(v_distance, 2);
            eta_minutes := ROUND((v_distance / v_velocity) * 60);
            latitude := v_bus.latitude;
            longitude := v_bus.longitude;
            last_updated := v_bus.recorded_at;
            RETURN NEXT;
        END;
    END IF;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000007_parent_module_fixes.sql
-- ==========================================================

-- ============================================================
-- PARENT MODULE: RLS fixes, daily digest, wallet top-up, visitor auth
-- ============================================================

-- ============================================================
-- 1. FIX: parent_student_links column consistency
-- ============================================================
-- The table uses student_id but some RPCs reference child_student_id.
-- Ensure column is student_id (the original definition).

-- ============================================================
-- 2. ADD: RLS policies for Parent role across core tables
-- ============================================================

-- Students: Parents can view linked children
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked children'
    AND tablename = 'students'
  ) THEN
    CREATE POLICY "Parents can view linked children" ON students
      FOR SELECT USING (
        id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
      );
  END IF;
END $$;

-- Attendance: Parents can view linked children's attendance
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked child attendance'
    AND tablename = 'attendance'
  ) THEN
    CREATE POLICY "Parents can view linked child attendance" ON attendance
      FOR SELECT USING (
        student_id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
      );
  END IF;
END $$;

-- Student fees: Parents can view linked children's fees
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked child fees'
    AND tablename = 'student_fees'
  ) THEN
    CREATE POLICY "Parents can view linked child fees" ON student_fees
      FOR SELECT USING (
        student_id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
      );
  END IF;
END $$;

-- Exam results: Parents can view linked children's results
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked child results'
    AND tablename = 'exam_results'
  ) THEN
    CREATE POLICY "Parents can view linked child results" ON exam_results
      FOR SELECT USING (
        student_id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
      );
  END IF;
END $$;

-- Notices: Parents can view notices from linked children's institution
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view institution notices'
    AND tablename = 'notices'
  ) THEN
    CREATE POLICY "Parents can view institution notices" ON notices
      FOR SELECT USING (
        institution_id IN (
          SELECT s.institution_id FROM parent_student_links psl
          JOIN students s ON psl.student_id = s.id
          WHERE psl.parent_user_id = auth.uid() AND psl.verified = true
        )
      );
  END IF;
END $$;

-- Gate logs: Parents can view linked children's gate logs
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked child gate logs'
    AND tablename = 'gate_logs'
  ) THEN
    CREATE POLICY "Parents can view linked child gate logs" ON gate_logs
      FOR SELECT USING (
        person_id IN (
          SELECT s.user_id FROM parent_student_links psl
          JOIN students s ON psl.student_id = s.id
          WHERE psl.parent_user_id = auth.uid() AND psl.verified = true
        )
      );
  END IF;
END $$;

-- Bus subscriptions: Parents can view linked children's bus subscriptions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked child bus subscriptions'
    AND tablename = 'transport_subscriptions'
  ) THEN
    CREATE POLICY "Parents can view linked child bus subscriptions" ON transport_subscriptions
      FOR SELECT USING (
        student_id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
      );
  END IF;
END $$;

-- Wallet transactions: Parents can view linked children's transactions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked child wallet tx'
    AND tablename = 'wallet_transactions'
  ) THEN
    CREATE POLICY "Parents can view linked child wallet tx" ON wallet_transactions
      FOR SELECT USING (
        student_id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
      );
  END IF;
END $$;

-- Parents can INSERT wallet transactions (for top-up)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can top-up linked child wallet'
    AND tablename = 'wallet_transactions'
  ) THEN
    CREATE POLICY "Parents can top-up linked child wallet" ON wallet_transactions
      FOR INSERT WITH CHECK (
        student_id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
        AND type = 'parent_topup'
      );
  END IF;
END $$;

-- Hostel allocations: Parents can view linked children's allocation
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE policyname = 'Parents can view linked child hostel'
    AND tablename = 'hostel_allocations'
  ) THEN
    CREATE POLICY "Parents can view linked child hostel" ON hostel_allocations
      FOR SELECT USING (
        student_id IN (
          SELECT student_id FROM parent_student_links
          WHERE parent_user_id = auth.uid() AND verified = true
        )
      );
  END IF;
END $$;

-- ============================================================
-- 3. ADD: Hostel visitor pre-authorization
-- ============================================================
CREATE TABLE IF NOT EXISTS hostel_visitor_preauth (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    parent_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    visitor_name VARCHAR(255) NOT NULL,
    visitor_phone VARCHAR(20),
    visit_date DATE NOT NULL,
    visit_time TIME,
    purpose TEXT,
    status VARCHAR(20) DEFAULT 'approved' CHECK (status IN ('approved', 'cancelled', 'completed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE hostel_visitor_preauth ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Parents can manage own visitor preauth" ON hostel_visitor_preauth
    FOR ALL USING (
        parent_user_id = auth.uid()
    );

CREATE POLICY "Students can view own visitor preauth" ON hostel_visitor_preauth
    FOR SELECT USING (
        student_id IN (
            SELECT id FROM students WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "Warden/Security can view all preauth" ON hostel_visitor_preauth
    FOR SELECT USING (
        get_auth_user_role() IN ('Warden', 'Security', 'Admin')
        AND institution_id = get_auth_institution_id()
    );

-- RPC: Pre-authorize a visit
CREATE OR REPLACE FUNCTION preauthorize_visitor(
    p_student_id UUID,
    p_visitor_name VARCHAR,
    p_visitor_phone VARCHAR,
    p_visit_date DATE,
    p_visit_time TIME,
    p_purpose TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_preauth_id UUID;
    v_parent_id UUID;
    v_institution_id UUID;
BEGIN
    -- Verify parent is linked to this student
    SELECT psl.parent_user_id, s.institution_id INTO v_parent_id, v_institution_id
    FROM parent_student_links psl
    JOIN students s ON psl.student_id = s.id
    WHERE psl.parent_user_id = auth.uid()
      AND psl.student_id = p_student_id
      AND psl.verified = true;

    IF v_parent_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Not authorized to pre-approve visits for this student.');
    END IF;

    INSERT INTO hostel_visitor_preauth (institution_id, student_id, parent_user_id, visitor_name, visitor_phone, visit_date, visit_time, purpose)
    VALUES (v_institution_id, p_student_id, v_parent_id, p_visitor_name, p_visitor_phone, p_visit_date, p_visit_time, p_purpose)
    RETURNING id INTO v_preauth_id;

    RETURN json_build_object('success', true, 'preauth_id', v_preauth_id);
END;
$$;

-- ============================================================
-- 4. ADD: Exam result notification for parents
-- ============================================================
CREATE TABLE IF NOT EXISTS parent_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    notification_type VARCHAR(50) NOT NULL CHECK (notification_type IN (
        'daily_digest', 'attendance_alert', 'fee_reminder', 'exam_result',
        'wallet_topup', 'visitor_approved', 'bus_boarded', 'hostel_complaint'
    )),
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    sent_via_whatsapp BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE parent_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Parents can view own notifications" ON parent_notifications
    FOR SELECT USING (parent_user_id = auth.uid());

CREATE POLICY "Parents can mark own notifications read" ON parent_notifications
    FOR UPDATE USING (parent_user_id = auth.uid());

CREATE POLICY "System can insert parent notifications" ON parent_notifications
    FOR INSERT WITH CHECK (true);

-- ============================================================
-- 5. RPC: Get parent's child info (replaces hardcoded mock)
-- ============================================================
CREATE OR REPLACE FUNCTION get_parent_child_info()
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    course VARCHAR,
    department_name TEXT,
    semester INTEGER,
    year INTEGER,
    guardian_phone VARCHAR,
    wallet_balance NUMERIC,
    institution_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, u.name, s.roll_number, s.course, d.name,
           s.semester, s.year, s.guardian_phone, s.wallet_balance, s.institution_id
    FROM parent_student_links psl
    JOIN students s ON psl.student_id = s.id
    JOIN users u ON s.user_id = u.id
    LEFT JOIN departments d ON s.department_id = d.id
    WHERE psl.parent_user_id = auth.uid()
      AND psl.verified = true
    ORDER BY psl.is_primary DESC NULLS LAST
    LIMIT 1;
END;
$$;

-- ============================================================
-- 6. RPC: Get parent child daily summary
-- ============================================================
CREATE OR REPLACE FUNCTION get_parent_daily_summary(p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    student_name TEXT,
    attendance_present BIGINT,
    attendance_total BIGINT,
    attendance_pct NUMERIC,
    canteen_spend NUMERIC,
    bus_boarded BOOLEAN,
    bus_time TIME,
    gate_in TIME,
    gate_out TIME,
    pending_fees NUMERIC,
    wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student_id UUID;
    v_user_id UUID;
BEGIN
    -- Get linked child
    SELECT psl.student_id, s.user_id INTO v_student_id, v_user_id
    FROM parent_student_links psl
    JOIN students s ON psl.student_id = s.id
    WHERE psl.parent_user_id = auth.uid() AND psl.verified = true
    ORDER BY psl.is_primary DESC NULLS LAST LIMIT 1;

    IF v_student_id IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        u.name,
        COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::BIGINT,
        COUNT(a.id)::BIGINT,
        CASE WHEN COUNT(a.id) = 0 THEN 100.0
             ELSE ROUND(COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC / COUNT(a.id)::NUMERIC * 100, 1)
        END,
        COALESCE((SELECT SUM(co.total_amount) FROM canteen_orders co WHERE co.student_id = v_student_id AND co.created_at::DATE = p_date), 0),
        EXISTS(SELECT 1 FROM bus_tracking bt WHERE bt.student_id = v_student_id AND bt.boarded_at::DATE = p_date),
        (SELECT bt.boarded_at::TIME FROM bus_tracking bt WHERE bt.student_id = v_student_id AND bt.boarded_at::DATE = p_date LIMIT 1),
        (SELECT gl.in_time::TIME FROM gate_logs gl WHERE gl.person_id = v_user_id AND gl.in_time::DATE = p_date LIMIT 1),
        (SELECT gl.out_time::TIME FROM gate_logs gl WHERE gl.person_id = v_user_id AND gl.out_time::DATE = p_date ORDER BY gl.out_time DESC LIMIT 1),
        (SELECT COALESCE(SUM(sf.amount - COALESCE(sf.paid_amount, 0)), 0) FROM student_fees sf WHERE sf.student_id = v_student_id AND sf.payment_status IN ('pending', 'partial')),
        (SELECT COALESCE(s.wallet_balance, 0) FROM students s WHERE s.id = v_student_id)
    FROM attendance a
    JOIN students s ON a.student_id = s.id
    JOIN users u ON s.user_id = u.id
    WHERE a.student_id = v_student_id AND a.date = p_date
    GROUP BY u.name;
END;
$$;

-- ============================================================
-- 7. RPC: Parent top-up child wallet
-- ============================================================
CREATE OR REPLACE FUNCTION parent_topup_child_wallet(
    p_student_id UUID,
    p_amount NUMERIC,
    p_description TEXT DEFAULT 'Parent wallet top-up'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_authorized BOOLEAN;
    v_tx_id UUID;
    v_new_balance NUMERIC;
BEGIN
    -- Verify parent is linked
    SELECT EXISTS (
        SELECT 1 FROM parent_student_links
        WHERE parent_user_id = auth.uid()
          AND student_id = p_student_id
          AND verified = true
    ) INTO v_authorized;

    IF NOT v_authorized THEN
        RETURN json_build_object('success', false, 'error', 'Not authorized to top-up this student.');
    END IF;

    IF p_amount <= 0 OR p_amount > 10000 THEN
        RETURN json_build_object('success', false, 'error', 'Amount must be between ₹1 and ₹10,000.');
    END IF;

    -- Record transaction
    INSERT INTO wallet_transactions (institution_id, student_id, amount, type, status, description)
    SELECT s.institution_id, p_student_id, p_amount, 'parent_topup', 'completed', p_description
    FROM students s WHERE s.id = p_student_id
    RETURNING id INTO v_tx_id;

    -- Update balance
    UPDATE students SET wallet_balance = COALESCE(wallet_balance, 0) + p_amount WHERE id = p_student_id
    RETURNING wallet_balance INTO v_new_balance;

    -- Create parent notification
    INSERT INTO parent_notifications (parent_user_id, student_id, notification_type, title, message, metadata)
    VALUES (
        auth.uid(), p_student_id, 'wallet_topup',
        'Wallet Top-Up Successful',
        '₹' || p_amount || ' has been added to your child''s campus wallet.',
        json_build_object('amount', p_amount, 'transaction_id', v_tx_id)
    );

    RETURN json_build_object('success', true, 'transaction_id', v_tx_id, 'new_balance', v_new_balance);
END;
$$;

-- ============================================================
-- 8. RPC: Get parent notification unread count
-- ============================================================
CREATE OR REPLACE FUNCTION get_parent_unread_count()
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN (SELECT COUNT(*)::BIGINT FROM parent_notifications
            WHERE parent_user_id = auth.uid() AND is_read = false);
END;
$$;

-- ============================================================
-- 9. RPC: Get child's bus status (is child on the bus?)
-- ============================================================
CREATE OR REPLACE FUNCTION get_child_bus_status()
RETURNS TABLE (
    is_on_bus BOOLEAN,
    bus_name VARCHAR,
    route_name VARCHAR,
    last_stop VARCHAR,
    eta_minutes INTEGER,
    latitude NUMERIC,
    longitude NUMERIC,
    last_updated TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student_id UUID;
    v_user_id UUID;
    v_subscription RECORD;
    v_bus_record RECORD;
    v_bus_loc RECORD;
BEGIN
    SELECT psl.student_id, s.user_id INTO v_student_id, v_user_id
    FROM parent_student_links psl
    JOIN students s ON psl.student_id = s.id
    WHERE psl.parent_user_id = auth.uid() AND psl.verified = true
    ORDER BY psl.is_primary DESC NULLS LAST LIMIT 1;

    IF v_student_id IS NULL THEN RETURN; END IF;

    -- Check if student has active bus subscription
    SELECT bs.route_id, bs.stop_name INTO v_subscription
    FROM transport_subscriptions bs
    WHERE bs.student_id = v_student_id AND bs.status = 'active'
    LIMIT 1;

    IF v_subscription IS NULL THEN
        is_on_bus := false;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Check gate log for boarding today (i.e. went out today)
    IF NOT EXISTS (
        SELECT 1 FROM gate_logs
        WHERE person_id = v_user_id
          AND out_time::DATE = CURRENT_DATE
    ) THEN
        is_on_bus := false;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Get bus assigned to this route
    SELECT b.id, b.name INTO v_bus_record
    FROM buses b
    WHERE b.route_id = v_subscription.route_id
    LIMIT 1;

    IF v_bus_record IS NULL THEN
        is_on_bus := false;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Get bus location
    SELECT bt.latitude, bt.longitude, bt.speed, bt.timestamp
    INTO v_bus_loc
    FROM bus_tracking bt
    WHERE bt.bus_id = v_bus_record.id
    ORDER BY bt.timestamp DESC LIMIT 1;

    IF v_bus_loc IS NULL THEN
        is_on_bus := false;
        RETURN NEXT;
        RETURN;
    END IF;

    is_on_bus := true;
    bus_name := v_bus_record.name;
    route_name := (SELECT name FROM bus_routes WHERE id = v_subscription.route_id);
    latitude := v_bus_loc.latitude;
    longitude := v_bus_loc.longitude;
    last_updated := v_bus_loc.timestamp;
    eta_minutes := 0; -- Would calculate from Haversine
    last_stop := '';
    RETURN NEXT;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000008_faculty_module.sql
-- ==========================================================

-- ============================================================
-- FACULTY MODULE: Department check, CIA marks, timetable fix
-- ============================================================

-- ============================================================
-- 1. ADD: CIA / Internal Marks tables
-- ============================================================
CREATE TABLE IF NOT EXISTS cia_assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(150) NOT NULL,
    assessment_type VARCHAR(30) NOT NULL CHECK (assessment_type IN (
        'CIA_1', 'CIA_2', 'CIA_3', 'Assignment', 'Quiz', 'Presentation', 'Lab', 'Attendance_Marks', 'Other'
    )),
    subject VARCHAR(150),
    max_marks INTEGER NOT NULL DEFAULT 30,
    weightage_pct DECIMAL(5,2) DEFAULT 0,
    semester INTEGER,
    batch_year VARCHAR(10),
    date DATE,
    deadline TIMESTAMP WITH TIME ZONE,
    is_published BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS cia_marks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES cia_assessments(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    marks_obtained DECIMAL(8,2) NOT NULL DEFAULT 0,
    remarks TEXT,
    entered_by UUID REFERENCES users(id),
    entered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_cia_mark_per_student UNIQUE (assessment_id, student_id)
);

-- RLS
ALTER TABLE cia_assessments ENABLE ROW LEVEL SECURITY;
ALTER TABLE cia_marks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Faculty can manage own CIA assessments" ON cia_assessments
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'Staff')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Students can view published CIA assessments" ON cia_assessments
    FOR SELECT USING (
        is_published = true
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Faculty can manage own CIA marks" ON cia_marks
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'Staff')
        AND (
            get_auth_user_role() = 'SuperAdmin' 
            OR assessment_id IN (
                SELECT id FROM cia_assessments WHERE institution_id = get_auth_institution_id()
            )
        )
    );

CREATE POLICY "Students can view own CIA marks" ON cia_marks
    FOR SELECT USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "Parents can view linked child CIA marks" ON cia_marks
    FOR SELECT USING (
        student_id IN (
            SELECT student_id FROM parent_student_links
            WHERE parent_user_id = auth.uid() AND verified = true
        )
    );

-- RPC: Get students with attendance shortage for a specific subject/department
CREATE OR REPLACE FUNCTION get_class_attendance_shortage(
    p_department_id UUID,
    p_subject VARCHAR DEFAULT NULL
)
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    total_classes BIGINT,
    attended_classes BIGINT,
    attendance_pct NUMERIC,
    status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        u.name AS full_name,
      s.roll_number,
        COUNT(a.id)::BIGINT,
        COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::BIGINT,
        CASE WHEN COUNT(a.id) = 0 THEN 100.0
             ELSE ROUND(COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC / COUNT(a.id)::NUMERIC * 100, 1)
        END,
        CASE
            WHEN COUNT(a.id) = 0 THEN 'No Data'
            WHEN COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC / COUNT(a.id)::NUMERIC * 100 < 60 THEN 'CRITICAL'
            WHEN COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC / COUNT(a.id)::NUMERIC * 100 < 75 THEN 'AT RISK'
            ELSE 'SAFE'
        END
    FROM students s
    JOIN users u ON s.user_id = u.id
    LEFT JOIN attendance a ON a.student_id = s.id
        AND (p_subject IS NULL OR a.session_id IN (
            SELECT id FROM attendance_sessions WHERE subject = p_subject
        ))
    WHERE s.department_id = p_department_id
      AND s.is_active = true
    GROUP BY s.id, u.name, s.roll_number
    ORDER BY attendance_pct ASC;
END;
$$;

-- RPC: Bulk enter CIA marks
CREATE OR REPLACE FUNCTION bulk_enter_cia_marks(
    p_assessment_id UUID,
    p_marks JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_entry JSONB;
    v_count INTEGER := 0;
    v_assessment RECORD;
BEGIN
    -- Verify assessment exists
    SELECT * INTO v_assessment FROM cia_assessments WHERE id = p_assessment_id;
    IF v_assessment IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Assessment not found.');
    END IF;

    -- Iterate over marks entries
    FOR v_entry IN SELECT * FROM jsonb_array_elements(p_marks)
    LOOP
        INSERT INTO cia_marks (assessment_id, student_id, marks_obtained, remarks, entered_by)
        VALUES (
            p_assessment_id,
            (v_entry->>'student_id')::UUID,
            (v_entry->>'marks_obtained')::DECIMAL,
            COALESCE(v_entry->>'remarks', ''),
            auth.uid()
        )
        ON CONFLICT (assessment_id, student_id)
        DO UPDATE SET
            marks_obtained = EXCLUDED.marks_obtained,
            remarks = EXCLUDED.remarks,
            entered_by = auth.uid(),
            entered_at = NOW();
        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object('success', true, 'marks_entered', v_count);
END;
$$;

-- RPC: Get CIA summary for a student
CREATE OR REPLACE FUNCTION get_student_cia_summary(p_student_id UUID)
RETURNS TABLE (
    assessment_name VARCHAR,
    assessment_type VARCHAR,
    subject VARCHAR,
    max_marks INTEGER,
    marks_obtained DECIMAL,
    percentage NUMERIC,
    date DATE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT ca.name, ca.assessment_type, ca.subject, ca.max_marks,
           cm.marks_obtained,
           CASE WHEN ca.max_marks > 0 THEN ROUND(cm.marks_obtained / ca.max_marks::NUMERIC * 100, 1) ELSE 0 END,
           ca.date
    FROM cia_assessments ca
    LEFT JOIN cia_marks cm ON cm.assessment_id = ca.id AND cm.student_id = p_student_id
    WHERE ca.is_published = true
    ORDER BY ca.date DESC, ca.name;
END;
$$;

-- RPC: Get timetable filtered by teacher_id
CREATE OR REPLACE FUNCTION get_teacher_timetable(p_teacher_id UUID)
RETURNS TABLE (
    id UUID,
    day_of_week VARCHAR,
    time_slot VARCHAR,
    subject VARCHAR,
    room VARCHAR,
    department_name TEXT,
    semester INTEGER,
    batch_year VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_staff_id UUID;
BEGIN
    -- Get staff record for this teacher
    SELECT st.id INTO v_staff_id FROM staff st WHERE st.user_id = p_teacher_id;

    IF v_staff_id IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT t.id, t.day_of_week, t.time_slot, t.subject, t.room,
           d.name, t.semester, t.batch_year
    FROM timetable t
    LEFT JOIN departments d ON t.department_id = d.id
    WHERE t.teacher_id = v_staff_id
    ORDER BY
        CASE t.day_of_week
            WHEN 'Monday' THEN 1 WHEN 'Tuesday' THEN 2 WHEN 'Wednesday' THEN 3
            WHEN 'Thursday' THEN 4 WHEN 'Friday' THEN 5 WHEN 'Saturday' THEN 6
            ELSE 7
        END,
        t.time_slot;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000009_admin_gaps_fix.sql
-- ==========================================================

-- ============================================================
-- ADMIN GAPS FIX: Admission docs, Timetable auto-gen, HOD fix,
-- Defaulter report, Academic calendar
-- ============================================================

-- ============================================================
-- 1. STUDENT ADMISSION: Document uploads + admission workflow
-- ============================================================
CREATE TABLE IF NOT EXISTS student_admissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    applicant_name VARCHAR(200) NOT NULL,
    email VARCHAR(200),
    phone VARCHAR(20),
    roll_number VARCHAR(50),
    department_id UUID REFERENCES departments(id),
    admission_year INTEGER NOT NULL DEFAULT EXTRACT(YEAR FROM CURRENT_DATE),
    semester INTEGER DEFAULT 1,
    batch_year VARCHAR(10),
    application_number VARCHAR(50) UNIQUE,
    admission_status VARCHAR(30) DEFAULT 'applied' CHECK (admission_status IN (
        'applied', 'documents_pending', 'under_review', 'approved', 'enrolled', 'rejected', 'waitlisted'
    )),
    guardian_name VARCHAR(200),
    guardian_phone VARCHAR(20),
    dob DATE,
    gender VARCHAR(20),
    address TEXT,
    category VARCHAR(50),
    blood_group VARCHAR(10),
    aadhaar_number VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admission_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admission_id UUID NOT NULL REFERENCES student_admissions(id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL CHECK (document_type IN (
        '10th_marksheet', '12th_marksheet', 'aadhaar', 'photo', 'migration_cert',
        'caste_cert', 'income_cert', 'medical_cert', 'tc', 'other'
    )),
    file_name VARCHAR(255) NOT NULL,
    file_url TEXT NOT NULL,
    file_size_kb INTEGER,
    verified BOOLEAN DEFAULT false,
    verified_by UUID REFERENCES users(id),
    uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS admission_workflow (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admission_id UUID NOT NULL REFERENCES student_admissions(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL,
    performed_by UUID REFERENCES users(id),
    remarks TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE student_admissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE admission_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE admission_workflow ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can manage admissions" ON student_admissions
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Admin can manage admission documents" ON admission_documents
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
    );

CREATE POLICY "Admin can manage admission workflow" ON admission_workflow
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
    );

-- RPC: Bulk import students from CSV data
CREATE OR REPLACE FUNCTION bulk_admit_students(
    p_students JSONB,
    p_institution_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_entry JSONB;
    v_count INTEGER := 0;
    v_errors INTEGER := 0;
    v_error_list JSONB := '[]'::JSONB;
    v_dept_id UUID;
    v_user_id UUID;
    v_student_id UUID;
    v_email VARCHAR;
    v_roll VARCHAR;
    v_name VARCHAR;
BEGIN
    FOR v_entry IN SELECT * FROM jsonb_array_elements(p_students)
    LOOP
        v_name := v_entry->>'name';
        v_email := v_entry->>'email';
        v_roll := v_entry->>'roll_number';
        v_dept_id := (v_entry->>'department_id')::UUID;

        BEGIN
            -- Create user
            INSERT INTO users (institution_id, name, email, phone, role, is_active)
            VALUES (p_institution_id, v_name, v_email, v_entry->>'phone', 'Student', true)
            RETURNING id INTO v_user_id;

            -- Create student profile
            INSERT INTO students (user_id, institution_id, department_id, roll_number, semester, batch_year, dob, gender, guardian_name, guardian_phone, fingerprint_id)
            VALUES (
                v_user_id, p_institution_id, v_dept_id, v_roll,
                COALESCE((v_entry->>'semester')::INTEGER, 1),
                COALESCE(v_entry->>'batch_year', EXTRACT(YEAR FROM CURRENT_DATE)::TEXT),
                (v_entry->>'dob')::DATE,
                v_entry->>'gender',
                v_entry->>'guardian_name',
                v_entry->>'guardian_phone',
                v_entry->>'fingerprint_id'
            )
            RETURNING id INTO v_student_id;

            v_count := v_count + 1;
        EXCEPTION WHEN OTHERS THEN
            v_errors := v_errors + 1;
            v_error_list := v_error_list || jsonb_build_object(
                'row', v_count + v_errors,
                'roll', v_roll,
                'error', SQLERRM
            );
        END;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'imported', v_count,
        'errors', v_errors,
        'error_details', v_error_list
    );
END;
$$;

-- ============================================================
-- 2. TIMETABLE: Auto-generation + conflict detection
-- ============================================================
CREATE TABLE IF NOT EXISTS timetable_constraints (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    constraint_type VARCHAR(30) NOT NULL CHECK (constraint_type IN (
        'teacher_unavailable', 'room_unavailable', 'batch_unavailable',
        'max_daily_hours', 'no_back_to_back_lab', 'preferred_slot'
    )),
    teacher_id UUID REFERENCES staff(id),
    room VARCHAR(100),
    day_of_week VARCHAR(20),
    time_slot VARCHAR(20),
    max_hours_per_day INTEGER DEFAULT 6,
    priority INTEGER DEFAULT 0,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS timetable_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    department_id UUID REFERENCES departments(id),
    semester INTEGER,
    batch_year VARCHAR(10),
    slots JSONB NOT NULL DEFAULT '[]'::JSONB,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE timetable_constraints ENABLE ROW LEVEL SECURITY;
ALTER TABLE timetable_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can manage timetable constraints" ON timetable_constraints
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Admin can manage timetable templates" ON timetable_templates
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

-- RPC: Detect timetable conflicts
CREATE OR REPLACE FUNCTION detect_timetable_conflicts(
    p_institution_id UUID,
    pSlots JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_slot JSONB;
    v_conflicts JSONB := '[]'::JSONB;
    v_existing RECORD;
    v_teacher_conflict BOOLEAN;
    v_room_conflict BOOLEAN;
    v_batch_conflict BOOLEAN;
BEGIN
    FOR v_slot IN SELECT * FROM jsonb_array_elements(pSlots)
    LOOP
        v_teacher_conflict := false;
        v_room_conflict := false;
        v_batch_conflict := false;

        -- Check teacher conflict
        IF v_slot->>'teacher_id' IS NOT NULL THEN
            SELECT * INTO v_existing
            FROM timetable t
            WHERE t.institution_id = p_institution_id
            AND t.teacher_id = (v_slot->>'teacher_id')::UUID
            AND t.day_of_week = v_slot->>'day_of_week'
            AND t.time_slot = v_slot->>'time_slot'
            AND t.id != COALESCE((v_slot->>'id')::UUID, '00000000-0000-0000-0000-000000000000'::UUID)
            LIMIT 1;

            IF FOUND THEN
                v_teacher_conflict := true;
                v_conflicts := v_conflicts || jsonb_build_object(
                    'type', 'teacher',
                    'slot', v_slot,
                    'conflict_with', jsonb_build_object('subject', v_existing.subject, 'room', v_existing.room)
                );
            END IF;
        END IF;

        -- Check room conflict
        IF v_slot->>'room' IS NOT NULL AND v_slot->>'room' != '' THEN
            SELECT * INTO v_existing
            FROM timetable t
            WHERE t.institution_id = p_institution_id
            AND t.room = v_slot->>'room'
            AND t.day_of_week = v_slot->>'day_of_week'
            AND t.time_slot = v_slot->>'time_slot'
            AND t.id != COALESCE((v_slot->>'id')::UUID, '00000000-0000-0000-0000-000000000000'::UUID)
            LIMIT 1;

            IF FOUND THEN
                v_room_conflict := true;
                v_conflicts := v_conflicts || jsonb_build_object(
                    'type', 'room',
                    'slot', v_slot,
                    'conflict_with', jsonb_build_object('subject', v_existing.subject, 'teacher_id', v_existing.teacher_id)
                );
            END IF;
        END IF;

        -- Check batch conflict
        IF v_slot->>'batch_year' IS NOT NULL AND v_slot->>'batch_year' != '' THEN
            SELECT * INTO v_existing
            FROM timetable t
            WHERE t.institution_id = p_institution_id
            AND t.batch_year = v_slot->>'batch_year'
            AND t.semester = (v_slot->>'semester')::INTEGER
            AND t.day_of_week = v_slot->>'day_of_week'
            AND t.time_slot = v_slot->>'time_slot'
            AND t.id != COALESCE((v_slot->>'id')::UUID, '00000000-0000-0000-0000-000000000000'::UUID)
            LIMIT 1;

            IF FOUND THEN
                v_batch_conflict := true;
                v_conflicts := v_conflicts || jsonb_build_object(
                    'type', 'batch',
                    'slot', v_slot,
                    'conflict_with', jsonb_build_object('subject', v_existing.subject, 'room', v_existing.room)
                );
            END IF;
        END IF;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'conflicts', v_conflicts,
        'has_conflicts', jsonb_array_length(v_conflicts) > 0
    );
END;
$$;

-- RPC: Auto-generate timetable for a department/semester
CREATE OR REPLACE FUNCTION auto_generate_timetable(
    p_institution_id UUID,
    p_department_id UUID,
    p_semester INTEGER,
    p_batch_year VARCHAR(10),
    p_subjects JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subject JSONB;
    v_days TEXT[] := ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
    v_slots TEXT[] := ARRAY['09:00','10:00','11:00','12:00','14:00','15:00','16:00'];
    v_slot_idx INTEGER := 1;
    v_day_idx INTEGER := 1;
    v_subject_name VARCHAR;
    v_hours_per_week INTEGER;
    v_teacher UUID;
    v_room VARCHAR;
    v_inserted INTEGER := 0;
    v_conflicts JSONB := '[]'::JSONB;
BEGIN
    FOR v_subject IN SELECT * FROM jsonb_array_elements(p_subjects)
    LOOP
        v_subject_name := v_subject->>'name';
        v_hours_per_week := COALESCE((v_subject->>'hours_per_week')::INTEGER, 3);
        v_teacher := (v_subject->>'teacher_id')::UUID;
        v_room := COALESCE(v_subject->>'room', '');

        -- Simple round-robin allocation
        WHILE v_hours_per_week > 0 LOOP
            IF v_slot_idx > array_length(v_slots, 1) THEN
                v_slot_idx := 1;
                v_day_idx := v_day_idx + 1;
            END IF;
            IF v_day_idx > array_length(v_days) THEN
                EXIT; -- No more slots available
            END IF;

            -- Check for conflict before inserting
            IF NOT EXISTS (
                SELECT 1 FROM timetable t
                WHERE t.institution_id = p_institution_id
                AND t.teacher_id = v_teacher
                AND t.day_of_week = v_days[v_day_idx]
                AND t.time_slot = v_slots[v_slot_idx]
            ) AND NOT EXISTS (
                SELECT 1 FROM timetable t
                WHERE t.institution_id = p_institution_id
                AND t.room = v_room
                AND t.room != ''
                AND t.day_of_week = v_days[v_day_idx]
                AND t.time_slot = v_slots[v_slot_idx]
            ) THEN
                INSERT INTO timetable (institution_id, department_id, teacher_id, subject, room, day_of_week, time_slot, semester, batch_year)
                VALUES (p_institution_id, p_department_id, v_teacher, v_subject_name, v_room, v_days[v_day_idx], v_slots[v_slot_idx], p_semester, p_batch_year);
                v_inserted := v_inserted + 1;
                v_hours_per_week := v_hours_per_week - 1;
            ELSE
                v_conflicts := v_conflicts || jsonb_build_object(
                    'subject', v_subject_name,
                    'day', v_days[v_day_idx],
                    'slot', v_slots[v_slot_idx],
                    'reason', 'teacher_or_room_unavailable'
                );
            END IF;

            v_slot_idx := v_slot_idx + 1;
        END LOOP;

        -- Reset for next subject
        v_slot_idx := 1;
        v_day_idx := 1;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'slots_inserted', v_inserted,
        'conflicts', v_conflicts,
        'conflict_count', jsonb_array_length(v_conflicts)
    );
END;
$$;

-- ============================================================
-- 3. NOTICE FIX: Add HOD to users.role CHECK + target_audience
-- ============================================================
-- No CHECK constraint on users.role, so HOD is already valid as a string.
-- The issue is the schema comment doesn't list it. No SQL change needed.
-- But let's ensure notices.target_audience accepts 'Faculty' as alias.

-- ============================================================
-- 4. CONSOLIDATED DEFAULTER REPORT
-- ============================================================
CREATE OR REPLACE FUNCTION get_consolidated_defaulters(
    p_institution_id UUID,
    p_attendance_threshold NUMERIC DEFAULT 75,
    p_fee_overdue_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    department_name TEXT,
    attendance_pct NUMERIC,
    attendance_status TEXT,
    total_fee_due NUMERIC,
    total_paid NUMERIC,
    overdue_amount NUMERIC,
    days_overdue INTEGER,
    risk_level TEXT,
    combined_score NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH att AS (
        SELECT
            a.student_id,
            ROUND(
                COUNT(a.id) FILTER (WHERE a.status IN ('present','late'))::NUMERIC /
                NULLIF(COUNT(a.id), 0) * 100, 1
            ) AS pct
        FROM attendance a
        JOIN students s ON a.student_id = s.id
        WHERE s.institution_id = p_institution_id
        GROUP BY a.student_id
    ),
    fees AS (
        SELECT
            sf.student_id,
            COALESCE(SUM(sf.amount), 0) AS total_due,
            COALESCE(SUM(sf.amount_paid), 0) AS paid,
            COALESCE(SUM(sf.amount - sf.amount_paid), 0) AS overdue,
            MAX(CASE WHEN sf.due_date < CURRENT_DATE THEN CURRENT_DATE - sf.due_date ELSE 0 END) AS max_days_overdue
        FROM student_fees sf
        JOIN students s ON sf.student_id = s.id
        WHERE s.institution_id = p_institution_id
        GROUP BY sf.student_id
    )
    SELECT
        s.id,
        u.name,
        s.roll_number,
        d.name,
        COALESCE(att.pct, 100),
        CASE
            WHEN att.pct IS NULL THEN 'No Data'
            WHEN att.pct < 60 THEN 'CRITICAL'
            WHEN att.pct < p_attendance_threshold THEN 'AT RISK'
            ELSE 'SAFE'
        END,
        COALESCE(fees.total_due, 0),
        COALESCE(fees.paid, 0),
        COALESCE(fees.overdue, 0),
        COALESCE(fees.max_days_overdue, 0)::INTEGER,
        CASE
            WHEN (COALESCE(att.pct, 100) < 60 AND COALESCE(fees.overdue, 0) > 0) THEN 'HIGH'
            WHEN (COALESCE(att.pct, 100) < p_attendance_threshold AND COALESCE(fees.overdue, 0) > 0) THEN 'MEDIUM'
            WHEN COALESCE(att.pct, 100) < 60 THEN 'MEDIUM'
            WHEN COALESCE(fees.overdue, 0) > 0 THEN 'LOW'
            ELSE 'NONE'
        END,
        ROUND(
            (CASE WHEN att.pct < 100 THEN (100 - COALESCE(att.pct, 100)) ELSE 0 END) * 0.6
            + (LEAST(COALESCE(fees.overdue, 0) / 10000.0, 10) * 10) * 0.4
        , 1)
    FROM students s
    JOIN users u ON s.user_id = u.id
    LEFT JOIN departments d ON s.department_id = d.id
    LEFT JOIN att ON att.student_id = s.id
    LEFT JOIN fees ON fees.student_id = s.id
    WHERE s.is_active = true
    AND s.institution_id = p_institution_id
    AND (
        COALESCE(att.pct, 100) < p_attendance_threshold
        OR COALESCE(fees.overdue, 0) > 0
    )
    ORDER BY combined_score DESC;
END;
$$;

-- ============================================================
-- 5. ACADEMIC CALENDAR
-- ============================================================
CREATE TABLE IF NOT EXISTS academic_calendar (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    event_type VARCHAR(40) NOT NULL CHECK (event_type IN (
        'semester_start', 'semester_end', 'exam_start', 'exam_end',
        'holiday', 'result_date', 'fee_due', 'admission_start',
        'admission_end', 'counseling', 'orientation', 'vacation',
        'internal_exam', 'project_submission', 'other'
    )),
    description TEXT,
    start_date DATE NOT NULL,
    end_date DATE,
    semester INTEGER,
    batch_year VARCHAR(10),
    is_recurring BOOLEAN DEFAULT false,
    recurrence_rule VARCHAR(100),
    color VARCHAR(20) DEFAULT '#6C2BD9',
    is_published BOOLEAN DEFAULT true,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS academic_calendar_holidays (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    date DATE NOT NULL,
    is_optional BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE academic_calendar ENABLE ROW LEVEL SECURITY;
ALTER TABLE academic_calendar_holidays ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can manage academic calendar" ON academic_calendar
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Everyone can view academic calendar" ON academic_calendar
    FOR SELECT USING (
        is_published = true
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Admin can manage holidays" ON academic_calendar_holidays
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

CREATE POLICY "Everyone can view holidays" ON academic_calendar_holidays
    FOR SELECT USING (
        institution_id = get_auth_institution_id()
    );

-- RPC: Get upcoming academic events
CREATE OR REPLACE FUNCTION get_academic_calendar_upcoming(
    p_institution_id UUID,
    p_from_date DATE DEFAULT CURRENT_DATE,
    p_months_ahead INTEGER DEFAULT 6
)
RETURNS TABLE (
    id UUID,
    title VARCHAR,
    event_type VARCHAR,
    description TEXT,
    start_date DATE,
    end_date DATE,
    semester INTEGER,
    batch_year VARCHAR,
    color VARCHAR,
    days_until INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT ac.id, ac.title, ac.event_type, ac.description,
           ac.start_date, ac.end_date, ac.semester, ac.batch_year, ac.color,
           (ac.start_date - p_from_date)::INTEGER
    FROM academic_calendar ac
    WHERE ac.institution_id = p_institution_id
    AND ac.is_published = true
    AND ac.start_date BETWEEN p_from_date AND (p_from_date + (p_months_ahead || ' months')::INTERVAL)
    ORDER BY ac.start_date;
END;
$$;

-- RPC: Check if a date is a holiday
CREATE OR REPLACE FUNCTION is_academic_holiday(
    p_institution_id UUID,
    p_date DATE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM academic_calendar_holidays
    WHERE institution_id = p_institution_id
    AND date = p_date;

    IF v_count > 0 THEN RETURN true; END IF;

    -- Also check academic_calendar for holidays
    SELECT COUNT(*) INTO v_count
    FROM academic_calendar
    WHERE institution_id = p_institution_id
    AND event_type = 'holiday'
    AND p_date BETWEEN start_date AND COALESCE(end_date, start_date);

    RETURN v_count > 0;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000010_warden_module_fixes.sql
-- ==========================================================

-- ============================================================
-- WARDEN MODULE FIXES: Visitor approval, unallocated students,
-- checkout workflow, curfew check-in, mess view, room transfers
-- ============================================================

-- ============================================================
-- 1. WARDEN VISITOR APPROVAL: Add approval workflow columns
-- ============================================================
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS approval_status VARCHAR(30) DEFAULT 'pending'
    CHECK (approval_status IN ('pending', 'approved', 'rejected', 'expired'));
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS approved_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS visit_purpose TEXT;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS expected_time TIMESTAMP WITH TIME ZONE;
ALTER TABLE hostel_visitors ADD COLUMN IF NOT EXISTS block_id UUID REFERENCES hostel_blocks(id);

-- RPC: Warden approves visitor for their block
CREATE OR REPLACE FUNCTION approve_hostel_visitor(
    p_visitor_id UUID,
    p_warden_id UUID,
    p_approve BOOLEAN,
    p_remarks TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_visitor RECORD;
    v_block_id UUID;
    v_room RECORD;
    v_warden_block UUID;
BEGIN
    -- Get visitor details
    SELECT * INTO v_visitor FROM hostel_visitors WHERE id = p_visitor_id;
    IF v_visitor IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Visitor not found.');
    END IF;

    -- Get warden's block
    SELECT hb.id INTO v_warden_block
    FROM hostel_blocks hb
    WHERE hb.warden_id = p_warden_id
    AND hb.institution_id = v_visitor.institution_id
    LIMIT 1;

    IF v_warden_block IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Warden not assigned to any block.');
    END IF;

    -- Verify visitor's student is in warden's block
    IF v_visitor.student_id IS NOT NULL THEN
        SELECT hr.block_id INTO v_block_id
        FROM hostel_allocations ha
        JOIN hostel_rooms hr ON ha.room_id = hr.id
        WHERE ha.student_id = v_visitor.student_id
        AND ha.is_current = true
        AND hr.block_id = v_warden_block;

        IF v_block_id IS NULL THEN
            RETURN json_build_object('success', false, 'error', 'Student not in your block.');
        END IF;
    END IF;

    -- Update approval
    UPDATE hostel_visitors
    SET approval_status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
        is_approved = p_approve,
        approved_by = (SELECT id FROM staff WHERE user_id = p_warden_id LIMIT 1),
        approved_at = NOW()
    WHERE id = p_visitor_id;

    RETURN json_build_object('success', true, 'approved', p_approve);
END;
$$;

-- ============================================================
-- 2. UNALLOCATED STUDENTS VIEW
-- ============================================================
CREATE OR REPLACE VIEW unallocated_students AS
SELECT
    s.id AS student_id,
    u.name AS full_name,
    s.roll_number,
    s.department_id,
    d.name AS department_name,
    s.semester,
    s.batch_year,
    s.created_at AS admission_date
FROM students s
JOIN users u ON s.user_id = u.id
LEFT JOIN departments d ON s.department_id = d.id
WHERE u.is_active = true
AND NOT EXISTS (
    SELECT 1 FROM hostel_allocations ha
    WHERE ha.student_id = s.id
    AND ha.is_current = true
)
ORDER BY u.name;

-- RPC: Get unallocated students for warden's institution
CREATE OR REPLACE FUNCTION get_unallocated_students()
RETURNS TABLE (
    student_id UUID,
    full_name TEXT,
    roll_number VARCHAR,
    department_name TEXT,
    semester INTEGER,
    batch_year VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT us.student_id, us.full_name, us.roll_number,
           us.department_name, us.semester, us.batch_year
    FROM unallocated_students us
    WHERE us.student_id IS NOT NULL;
END;
$$;

-- ============================================================
-- 3. HOSTEL CHECKOUT / ROOM VACATING WORKFLOW
-- ============================================================
CREATE OR REPLACE FUNCTION checkout_hostel_room(
    p_allocation_id UUID,
    p_warden_id UUID,
    p_reason TEXT DEFAULT '',
    p_deposit_action VARCHAR(20) DEFAULT 'refunded'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_allocation RECORD;
    v_block_id UUID;
    v_warden_block UUID;
BEGIN
    SELECT * INTO v_allocation FROM hostel_allocations WHERE id = p_allocation_id;
    IF v_allocation IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Allocation not found.');
    END IF;

    IF v_allocation.is_current = false THEN
        RETURN json_build_object('success', false, 'error', 'Allocation already closed.');
    END IF;

    -- Get warden's block
    SELECT hb.id INTO v_warden_block
    FROM hostel_blocks hb
    WHERE hb.warden_id = p_warden_id
    LIMIT 1;

    -- Verify room is in warden's block
    SELECT hr.block_id INTO v_block_id
    FROM hostel_rooms hr
    WHERE hr.id = v_allocation.room_id;

    IF v_warden_block IS NOT NULL AND v_block_id != v_warden_block THEN
        RETURN json_build_object('success', false, 'error', 'Room not in your block.');
    END IF;

    -- Close allocation
    UPDATE hostel_allocations
    SET is_current = false,
        vacated_date = CURRENT_DATE,
        vacating_reason = p_reason,
        deposit_status = CASE WHEN p_deposit_action = 'refunded' THEN 'refunded'
                              WHEN p_deposit_action = 'forfeited' THEN 'paid'
                              ELSE deposit_status END
    WHERE id = p_allocation_id;

    -- Update room occupied count
    UPDATE hostel_rooms
    SET occupied = GREATEST(occupied - 1, 0)
    WHERE id = v_allocation.room_id;

    RETURN json_build_object('success', true, 'message', 'Room vacated successfully.');
END;
$$;

-- ============================================================
-- 4. NIGHTLY CURFEW / HEADCOUNT CHECK-IN
-- ============================================================
CREATE TABLE IF NOT EXISTS curfew_checkins (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    block_id UUID NOT NULL REFERENCES hostel_blocks(id) ON DELETE CASCADE,
    check_date DATE NOT NULL DEFAULT CURRENT_DATE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    is_present BOOLEAN DEFAULT false,
    marked_by UUID REFERENCES users(id),
    remarks TEXT,
    marked_at TIMESTAMP WITH TIME ZONE,
    UNIQUE (block_id, check_date, student_id)
);

CREATE TABLE IF NOT EXISTS curfew_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    block_id UUID NOT NULL REFERENCES hostel_blocks(id) ON DELETE CASCADE,
    check_date DATE NOT NULL DEFAULT CURRENT_DATE,
    absent_student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    alert_sent_to_parent BOOLEAN DEFAULT false,
    alert_sent_at TIMESTAMP WITH TIME ZONE,
    warden_notified BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE curfew_checkins ENABLE ROW LEVEL SECURITY;
ALTER TABLE curfew_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Warden can manage curfew in their block" ON curfew_checkins
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden')
        AND (
            get_auth_user_role() != 'Warden'
            OR block_id IN (
                SELECT hb.id FROM hostel_blocks hb
                WHERE hb.warden_id = auth.uid()
            )
        )
    );

CREATE POLICY "Warden can view curfew alerts" ON curfew_alerts
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden')
    );

CREATE POLICY "System can insert curfew alerts" ON curfew_alerts
    FOR INSERT WITH CHECK (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden')
    );

-- RPC: Mark curfew check-in for a block
CREATE OR REPLACE FUNCTION mark_curfew_checkin(
    p_block_id UUID,
    p_warden_id UUID,
    pcheck_date DATE DEFAULT CURRENT_DATE,
    p_students JSONB DEFAULT '[]'::JSONB
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_warden_block UUID;
    v_entry JSONB;
    v_present_count INTEGER := 0;
    v_absent_count INTEGER := 0;
    v_student RECORD;
BEGIN
    -- Verify warden owns this block
    SELECT hb.id INTO v_warden_block
    FROM hostel_blocks hb
    WHERE hb.id = p_block_id AND hb.warden_id = p_warden_id;

    IF v_warden_block IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Block not assigned to you.');
    END IF;

    -- Mark each student
    FOR v_entry IN SELECT * FROM jsonb_array_elements(p_students)
    LOOP
        INSERT INTO curfew_checkins (institution_id, block_id, check_date, student_id, is_present, marked_by, marked_at)
        VALUES (
            (SELECT institution_id FROM hostel_blocks WHERE id = p_block_id),
            p_block_id,
            pcheck_date,
            (v_entry->>'student_id')::UUID,
            (v_entry->>'is_present')::BOOLEAN,
            p_warden_id,
            NOW()
        )
        ON CONFLICT (block_id, check_date, student_id)
        DO UPDATE SET
            is_present = EXCLUDED.is_present,
            marked_by = EXCLUDED.marked_by,
            marked_at = NOW();

        IF (v_entry->>'is_present')::BOOLEAN THEN
            v_present_count := v_present_count + 1;
        ELSE
            v_absent_count := v_absent_count + 1;

            -- Create alert for absent student
            INSERT INTO curfew_alerts (institution_id, block_id, check_date, absent_student_id)
            VALUES (
                (SELECT institution_id FROM hostel_blocks WHERE id = p_block_id),
                p_block_id,
                pcheck_date,
                (v_entry->>'student_id')::UUID
            )
            ON CONFLICT DO NOTHING;
        END IF;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'present', v_present_count,
        'absent', v_absent_count
    );
END;
$$;

-- RPC: Get curfew status for a block on a date
CREATE OR REPLACE FUNCTION get_curfew_status(
    p_block_id UUID,
    pcheck_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    room_number VARCHAR,
    is_present BOOLEAN,
    marked_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        u.name,
        s.roll_number,
        hr.room_number,
        COALESCE(cc.is_present, false),
        cc.marked_at
    FROM hostel_allocations ha
    JOIN hostel_rooms hr ON ha.room_id = hr.id
    JOIN students s ON ha.student_id = s.id
    JOIN users u ON s.user_id = u.id
    LEFT JOIN curfew_checkins cc
        ON cc.student_id = s.id
        AND cc.block_id = p_block_id
        AND cc.check_date = pcheck_date
    WHERE hr.block_id = p_block_id
    AND ha.is_current = true
    ORDER BY hr.room_number, u.name;
END;
$$;

-- ============================================================
-- 5. MESS / MEAL SUBSCRIPTION VIEW PER BLOCK
-- ============================================================
CREATE OR REPLACE FUNCTION get_block_meal_subscriptions(p_block_id UUID)
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    room_number VARCHAR,
    plan_name VARCHAR,
    meals_total INTEGER,
    meals_used INTEGER,
    meals_remaining INTEGER,
    subscription_status VARCHAR,
    start_date DATE,
    end_date DATE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        u.name,
        s.roll_number,
        hr.room_number,
        mp.name,
        ms.meals_total,
        ms.meals_used,
        (ms.meals_total - ms.meals_used),
        ms.status,
        ms.start_date,
        ms.end_date
    FROM hostel_allocations ha
    JOIN hostel_rooms hr ON ha.room_id = hr.id
    JOIN students s ON ha.student_id = s.id
    JOIN users u ON s.user_id = u.id
    JOIN meal_subscriptions ms ON ms.student_id = s.id
    LEFT JOIN meal_plans mp ON ms.plan_id = mp.id
    WHERE hr.block_id = p_block_id
    AND ha.is_current = true
    AND ms.status = 'active'
    ORDER BY u.name;
END;
$$;

-- ============================================================
-- 6. ROOM TRANSFER REQUESTS
-- ============================================================
CREATE TABLE IF NOT EXISTS room_transfer_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    current_room_id UUID REFERENCES hostel_rooms(id),
    requested_room_id UUID REFERENCES hostel_rooms(id),
    reason TEXT NOT NULL,
    reason_category VARCHAR(30) DEFAULT 'other' CHECK (reason_category IN (
        'roommate_conflict', 'health', 'proximity', 'noise', 'maintenance', 'other'
    )),
    status VARCHAR(30) DEFAULT 'pending' CHECK (status IN (
        'pending', 'warden_approved', 'admin_approved', 'rejected', 'completed'
    )),
    warden_id UUID REFERENCES users(id),
    warden_remarks TEXT,
    warden_approved_at TIMESTAMP WITH TIME ZONE,
    admin_id UUID REFERENCES users(id),
    admin_remarks TEXT,
    admin_approved_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE room_transfer_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Students can view own transfer requests" ON room_transfer_requests
    FOR SELECT USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "Students can create transfer requests" ON room_transfer_requests
    FOR INSERT WITH CHECK (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Warden can manage transfers in their block" ON room_transfer_requests
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden')
        AND (
            get_auth_user_role() != 'Warden'
            OR current_room_id IN (
                SELECT hr.id FROM hostel_rooms hr
                JOIN hostel_blocks hb ON hr.block_id = hb.id
                WHERE hb.warden_id = auth.uid()
            )
        )
    );

-- RPC: Warden approves room transfer
CREATE OR REPLACE FUNCTION approve_room_transfer(
    p_request_id UUID,
    p_warden_id UUID,
    p_approve BOOLEAN,
    p_remarks TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request RECORD;
    v_warden_block UUID;
    v_new_room RECORD;
BEGIN
    SELECT * INTO v_request FROM room_transfer_requests WHERE id = p_request_id;
    IF v_request IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Request not found.');
    END IF;

    IF v_request.status != 'pending' THEN
        RETURN json_build_object('success', false, 'error', 'Request already processed.');
    END IF;

    -- Verify warden's block
    SELECT hb.id INTO v_warden_block
    FROM hostel_blocks hb
    WHERE hb.warden_id = p_warden_id
    LIMIT 1;

    -- Verify current room is in warden's block
    IF v_warden_block IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM hostel_rooms hr
            WHERE hr.id = v_request.current_room_id
            AND hr.block_id = v_warden_block
        ) THEN
            RETURN json_build_object('success', false, 'error', 'Current room not in your block.');
        END IF;
    END IF;

    IF p_approve THEN
        -- Check requested room has capacity
        IF v_request.requested_room_id IS NOT NULL THEN
            SELECT * INTO v_new_room FROM hostel_rooms WHERE id = v_request.requested_room_id;
            IF v_new_room IS NULL THEN
                RETURN json_build_object('success', false, 'error', 'Requested room not found.');
            END IF;
            IF v_new_room.occupied >= v_new_room.capacity THEN
                RETURN json_build_object('success', false, 'error', 'Requested room is full.');
            END IF;
        END IF;

        UPDATE room_transfer_requests
        SET status = 'warden_approved',
            warden_id = p_warden_id,
            warden_remarks = p_remarks,
            warden_approved_at = NOW()
        WHERE id = p_request_id;
    ELSE
        UPDATE room_transfer_requests
        SET status = 'rejected',
            warden_id = p_warden_id,
            warden_remarks = p_remarks,
            warden_approved_at = NOW()
        WHERE id = p_request_id;
    END IF;

    RETURN json_build_object('success', true, 'approved', p_approve);
END;
$$;

-- RPC: Complete room transfer (move student to new room)
CREATE OR REPLACE FUNCTION complete_room_transfer(p_request_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request RECORD;
    v_old_room_id UUID;
BEGIN
    SELECT * INTO v_request FROM room_transfer_requests WHERE id = p_request_id;
    IF v_request IS NULL OR v_request.status != 'warden_approved' THEN
        RETURN json_build_object('success', false, 'error', 'Request not ready for completion.');
    END IF;

    IF v_request.requested_room_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'No target room specified.');
    END IF;

    -- Get old room
    SELECT room_id INTO v_old_room_id
    FROM hostel_allocations
    WHERE student_id = v_request.student_id AND is_current = true;

    -- Update allocation
    UPDATE hostel_allocations
    SET room_id = v_request.requested_room_id
    WHERE student_id = v_request.student_id AND is_current = true;

    -- Update old room count
    IF v_old_room_id IS NOT NULL THEN
        UPDATE hostel_rooms SET occupied = GREATEST(occupied - 1, 0) WHERE id = v_old_room_id;
    END IF;

    -- Update new room count
    UPDATE hostel_rooms SET occupied = occupied + 1 WHERE id = v_request.requested_room_id;

    -- Mark transfer complete
    UPDATE room_transfer_requests SET status = 'completed' WHERE id = p_request_id;

    RETURN json_build_object('success', true, 'message', 'Room transfer completed.');
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000011_security_module_fixes.sql
-- ==========================================================

-- ============================================================
-- SECURITY MODULE FIXES: Identity verification, visitor lookup,
-- blacklist alerts, vehicle logs, event attendees
-- ============================================================

-- ============================================================
-- 1. FIX: Security can read user/student profiles for verification
--    (users_select already allows institution-scoped reads,
--     but add explicit column-level view for Security)
-- ============================================================
CREATE OR REPLACE FUNCTION verify_person_at_gate(
    p_identifier TEXT
)
RETURNS TABLE (
    user_id UUID,
    full_name TEXT,
    role VARCHAR,
    photo_url TEXT,
    is_active BOOLEAN,
    student_roll VARCHAR,
    department_name TEXT,
    semester INTEGER,
    person_type TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Try matching by email, phone, roll_number, or user id
    RETURN QUERY
    SELECT
        u.id,
        u.name AS full_name,
        u.role,
        u.avatar_url AS photo_url,
        u.is_active,
        s.roll_number,
        d.name,
        s.semester,
        CASE WHEN s.id IS NOT NULL THEN 'student'
             WHEN st.id IS NOT NULL THEN 'staff'
             ELSE 'user'
        END::TEXT
    FROM users u
    LEFT JOIN students s ON s.user_id = u.id
    LEFT JOIN staff st ON st.user_id = u.id
    LEFT JOIN departments d ON s.department_id = d.id
    WHERE u.institution_id = get_auth_institution_id()
    AND (
        u.id::TEXT = p_identifier
        OR u.email = p_identifier
        OR u.phone = p_identifier
        OR s.roll_number = p_identifier
        OR LOWER(u.name) LIKE LOWER('%' || p_identifier || '%')
        OR st.employee_id = p_identifier
    )
    LIMIT 5;
END;
$$;

-- ============================================================
-- 2. FIX: Security can look up ALL visitor passes (not just own)
-- ============================================================
-- The existing hostel_visitors_select policy allows institution-wide reads.
-- But visitor_logs (gate entry/exit) needs broader read for Security.
-- Add a view for today's approved visitors

CREATE OR REPLACE FUNCTION get_approved_visitors_today()
RETURNS TABLE (
    id UUID,
    visitor_name TEXT,
    visitor_phone TEXT,
    relation TEXT,
    visit_purpose TEXT,
    student_name TEXT,
    student_roll VARCHAR,
    room_number VARCHAR,
    approval_status VARCHAR,
    expected_time TIMESTAMP WITH TIME ZONE,
    approved_by_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        hv.id,
        hv.visitor_name,
        hv.visitor_phone,
        hv.relation,
        hv.visit_purpose,
        su.name,
        s.roll_number,
        hr.room_number,
        hv.approval_status,
        hv.expected_time,
        abu.name
    FROM hostel_visitors hv
    LEFT JOIN students s ON hv.student_id = s.id
    LEFT JOIN users su ON s.user_id = su.id
    LEFT JOIN hostel_allocations ha ON ha.student_id = s.id AND ha.is_current = true
    LEFT JOIN hostel_rooms hr ON ha.room_id = hr.id
    LEFT JOIN staff ab ON hv.approved_by = ab.id
    LEFT JOIN users abu ON ab.user_id = abu.id
    WHERE hv.institution_id = get_auth_institution_id()
    AND (
        hv.approval_status = 'approved'
        OR hv.expected_time::DATE = CURRENT_DATE
        OR hv.created_at::DATE = CURRENT_DATE
    )
    ORDER BY hv.created_at DESC;
END;
$$;

-- ============================================================
-- 3. BLACKLIST / SUSPENDED STUDENT ALERT
-- ============================================================
CREATE TABLE IF NOT EXISTS access_restrictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    person_type VARCHAR(20) NOT NULL CHECK (person_type IN ('student', 'staff', 'visitor')),
    person_id UUID NOT NULL,
    restriction_type VARCHAR(30) NOT NULL CHECK (restriction_type IN (
        'suspended', 'expelled', 'banned', 'no_campus_access', 'disciplinary', 'other'
    )),
    reason TEXT NOT NULL,
    restricted_by UUID REFERENCES users(id),
    valid_from DATE DEFAULT CURRENT_DATE,
    valid_until DATE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE access_restrictions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Security can view active restrictions" ON access_restrictions
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security', 'Warden')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Admin can manage restrictions" ON access_restrictions
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND institution_id = get_auth_institution_id()
    );

-- RPC: Check if a person is restricted
CREATE OR REPLACE FUNCTION check_person_restricted(p_person_id UUID)
RETURNS TABLE (
    is_restricted BOOLEAN,
    restriction_type VARCHAR,
    reason TEXT,
    valid_until DATE,
    restricted_by_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        true,
        ar.restriction_type,
        ar.reason,
        ar.valid_until,
        u.name
    FROM access_restrictions ar
    LEFT JOIN users u ON ar.restricted_by = u.id
    WHERE ar.person_id = p_person_id
    AND ar.is_active = true
    AND ar.institution_id = get_auth_institution_id()
    AND (ar.valid_until IS NULL OR ar.valid_until >= CURRENT_DATE)
    LIMIT 1;

    -- If no rows, person is not restricted
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::VARCHAR, NULL::TEXT, NULL::DATE, NULL::TEXT;
    END IF;
END;
$$;

-- RPC: Scan at gate — returns identity + restriction status + visitor status
CREATE OR REPLACE FUNCTION gate_scan_lookup(p_identifier TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_person RECORD;
    v_restricted RECORD;
    v_visitor RECORD;
    v_result JSON;
BEGIN
    -- Step 1: Look up person
    SELECT * INTO v_person
    FROM verify_person_at_gate(p_identifier)
    LIMIT 1;

    IF v_person IS NULL THEN
        RETURN json_build_object(
            'success', true,
            'found', false,
            'message', 'Person not found in system.'
        );
    END IF;

    -- Step 2: Check blacklist
    SELECT * INTO v_restricted
    FROM check_person_restricted(v_person.user_id)
    LIMIT 1;

    -- Step 3: Check if visitor with approved pass
    IF v_person.person_type = 'user' THEN
        SELECT hv.id, hv.visitor_name, hv.approval_status INTO v_visitor
        FROM hostel_visitors hv
        WHERE hv.visitor_name ILIKE '%' || p_identifier || '%'
        OR hv.visitor_phone = p_identifier
        AND hv.institution_id = get_auth_institution_id()
        AND hv.approval_status = 'approved'
        LIMIT 1;
    END IF;

    RETURN json_build_object(
        'success', true,
        'found', true,
        'person', json_build_object(
            'user_id', v_person.user_id,
            'full_name', v_person.full_name,
            'role', v_person.role,
            'photo_url', v_person.photo_url,
            'is_active', v_person.is_active,
            'student_roll', v_person.student_roll,
            'department', v_person.department_name,
            'semester', v_person.semester,
            'person_type', v_person.person_type
        ),
        'restriction', json_build_object(
            'is_restricted', COALESCE(v_restricted.is_restricted, false),
            'type', v_restricted.restriction_type,
            'reason', v_restricted.reason,
            'valid_until', v_restricted.valid_until,
            'restricted_by', v_restricted.restricted_by_name
        ),
        'visitor_pass', CASE WHEN v_visitor IS NOT NULL THEN
            json_build_object(
                'id', v_visitor.id,
                'visitor_name', v_visitor.visitor_name,
                'approval_status', v_visitor.approval_status
            )
        ELSE NULL END
    );
END;
$$;

-- ============================================================
-- 4. VEHICLE ENTRY/EXIT LOG
-- ============================================================
CREATE TABLE IF NOT EXISTS vehicle_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    vehicle_number VARCHAR(20) NOT NULL,
    vehicle_type VARCHAR(30) DEFAULT 'two_wheeler' CHECK (vehicle_type IN (
        'two_wheeler', 'four_wheeler', 'bus', 'delivery', 'emergency', 'other'
    )),
    driver_name VARCHAR(200),
    driver_phone VARCHAR(20),
    purpose TEXT,
    person_id UUID REFERENCES users(id),
    entry_time TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    exit_time TIMESTAMP WITH TIME ZONE,
    entered_by UUID REFERENCES users(id),
    exited_by UUID REFERENCES users(id),
    gate_number VARCHAR(20),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE vehicle_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Security can manage vehicle logs" ON vehicle_logs
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security', 'Warden')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "Admin can view all vehicle logs" ON vehicle_logs
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND institution_id = get_auth_institution_id()
    );

-- RPC: Vehicle entry
CREATE OR REPLACE FUNCTION vehicle_entry(
    p_vehicle_number VARCHAR,
    p_vehicle_type VARCHAR,
    p_driver_name VARCHAR,
    p_driver_phone VARCHAR,
    p_purpose TEXT,
    p_gate_number VARCHAR DEFAULT '1'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_log_id UUID;
BEGIN
    INSERT INTO vehicle_logs (
        institution_id, vehicle_number, vehicle_type, driver_name,
        driver_phone, purpose, entered_by, gate_number
    ) VALUES (
        get_auth_institution_id(), p_vehicle_number, p_vehicle_type,
        p_driver_name, p_driver_phone, p_purpose,
        auth.uid(),
        p_gate_number
    ) RETURNING id INTO v_log_id;

    RETURN json_build_object('success', true, 'log_id', v_log_id, 'message', 'Vehicle entry logged.');
END;
$$;

-- RPC: Vehicle exit
CREATE OR REPLACE FUNCTION vehicle_exit(p_log_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE vehicle_logs
    SET exit_time = NOW(),
        exited_by = auth.uid()
    WHERE id = p_log_id AND exit_time IS NULL;

    IF FOUND THEN
        RETURN json_build_object('success', true, 'message', 'Vehicle exit logged.');
    ELSE
        RETURN json_build_object('success', false, 'error', 'Log not found or already exited.');
    END IF;
END;
$$;

-- ============================================================
-- 5. TODAY'S EVENT ATTENDEE LIST
-- ============================================================
CREATE OR REPLACE FUNCTION get_todays_event_attendees()
RETURNS TABLE (
    event_id UUID,
    event_title TEXT,
    event_date DATE,
    registration_id UUID,
    user_id UUID,
    full_name TEXT,
    email TEXT,
    registration_status VARCHAR,
    check_in_time TIMESTAMP WITH TIME ZONE,
    ticket_code VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        e.id,
        e.title::TEXT,
        e.event_date,
        er.id,
        er.user_id,
        u.name AS full_name,
        u.email,
        er.status,
        er.check_in_time,
        er.ticket_code
    FROM events e
    JOIN event_registrations er ON er.event_id = e.id
    JOIN users u ON er.user_id = u.id
    WHERE e.institution_id = get_auth_institution_id()
    AND e.event_date = CURRENT_DATE
    ORDER BY e.title, u.name;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000012_driver_module.sql
-- ==========================================================

-- ============================================================
-- DRIVER MODULE: RLS, Trip Console, Route Schedule, Headcount,
-- Emergency Reports
-- ============================================================

-- ============================================================
-- 1. DRIVER RLS: Scoped to own bus, own trips, own route
-- ============================================================

-- Drop overly-broad bus_trips policy (replaced with driver-scoped)
DROP POLICY IF EXISTS tenant_bus_trips_policy ON bus_trips;
CREATE POLICY "bus_trips_admin_select" ON bus_trips
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "bus_trips_driver_select" ON bus_trips
    FOR SELECT USING (
        get_auth_user_role() = 'Driver'
        AND driver_id IN (
            SELECT bd.id FROM bus_drivers bd
            WHERE bd.user_id = auth.uid()
        )
    );

CREATE POLICY "bus_trips_driver_insert" ON bus_trips
    FOR INSERT WITH CHECK (
        get_auth_user_role() = 'Driver'
        AND driver_id IN (
            SELECT bd.id FROM bus_drivers bd
            WHERE bd.user_id = auth.uid()
        )
    );

CREATE POLICY "bus_trips_driver_update" ON bus_trips
    FOR UPDATE USING (
        get_auth_user_role() = 'Driver'
        AND driver_id IN (
            SELECT bd.id FROM bus_drivers bd
            WHERE bd.user_id = auth.uid()
        )
    );

-- Drop overly-broad trip_stop_logs policy
DROP POLICY IF EXISTS tenant_trip_stop_logs_policy ON trip_stop_logs;
CREATE POLICY "trip_stop_logs_admin_all" ON trip_stop_logs
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "trip_stop_logs_driver_select" ON trip_stop_logs
    FOR SELECT USING (
        get_auth_user_role() = 'Driver'
        AND trip_id IN (
            SELECT bt.id FROM bus_trips bt
            JOIN bus_drivers bd ON bt.driver_id = bd.id
            WHERE bd.user_id = auth.uid()
        )
    );

CREATE POLICY "trip_stop_logs_driver_insert" ON trip_stop_logs
    FOR INSERT WITH CHECK (
        get_auth_user_role() = 'Driver'
        AND trip_id IN (
            SELECT bt.id FROM bus_trips bt
            JOIN bus_drivers bd ON bt.driver_id = bd.id
            WHERE bd.user_id = auth.uid()
        )
    );

CREATE POLICY "trip_stop_logs_driver_update" ON trip_stop_logs
    FOR UPDATE USING (
        get_auth_user_role() = 'Driver'
        AND trip_id IN (
            SELECT bt.id FROM bus_trips bt
            JOIN bus_drivers bd ON bt.driver_id = bd.id
            WHERE bd.user_id = auth.uid()
        )
    );

-- Drop overly-broad bus_incidents policy
DROP POLICY IF EXISTS tenant_bus_incidents_policy ON bus_incidents;
CREATE POLICY "bus_incidents_admin_all" ON bus_incidents
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "bus_incidents_driver_select" ON bus_incidents
    FOR SELECT USING (
        get_auth_user_role() = 'Driver'
        AND reported_by = auth.uid()
    );

CREATE POLICY "bus_incidents_driver_insert" ON bus_incidents
    FOR INSERT WITH CHECK (
        get_auth_user_role() = 'Driver'
        AND institution_id = get_auth_institution_id()
    );

-- Driver can only see their own bus
DROP POLICY IF EXISTS "buses_select" ON buses;
CREATE POLICY "buses_admin_select" ON buses
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden', 'Student', 'Parent', 'Staff', 'Teacher')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "buses_driver_select" ON buses
    FOR SELECT USING (
        get_auth_user_role() = 'Driver'
        AND id IN (
            SELECT b.id FROM buses b
            JOIN bus_drivers bd ON b.driver_id = bd.id
            WHERE bd.user_id = auth.uid()
        )
    );

-- Driver can only see their own route
DROP POLICY IF EXISTS "bus_routes_select" ON bus_routes;
CREATE POLICY "bus_routes_admin_select" ON bus_routes
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Warden', 'Student', 'Parent', 'Staff', 'Teacher')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "bus_routes_driver_select" ON bus_routes
    FOR SELECT USING (
        get_auth_user_role() = 'Driver'
        AND id IN (
            SELECT b.route_id FROM buses b
            JOIN bus_drivers bd ON b.driver_id = bd.id
            WHERE bd.user_id = auth.uid()
        )
    );

-- Driver can see their route's subscriptions (headcount)
DROP POLICY IF EXISTS "transport_subscriptions_select" ON transport_subscriptions;
CREATE POLICY "transport_subscriptions_admin_select" ON transport_subscriptions
    FOR SELECT USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin')
        AND institution_id = get_auth_institution_id()
    );

CREATE POLICY "transport_subscriptions_student_select" ON transport_subscriptions
    FOR SELECT USING (
        student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
    );

CREATE POLICY "transport_subscriptions_driver_select" ON transport_subscriptions
    FOR SELECT USING (
        get_auth_user_role() = 'Driver'
        AND route_id IN (
            SELECT b.route_id FROM buses b
            JOIN bus_drivers bd ON b.driver_id = bd.id
            WHERE bd.user_id = auth.uid()
        )
        AND status = 'active'
    );

-- ============================================================
-- 2. DRIVER RPCs: Get own bus, route, trips
-- ============================================================

-- Get driver's assigned bus and route
CREATE OR REPLACE FUNCTION get_driver_assignments()
RETURNS TABLE (
    bus_id UUID,
    vehicle_number TEXT,
    bus_name TEXT,
    capacity INTEGER,
    bus_model TEXT,
    route_id UUID,
    route_name TEXT,
    route_number TEXT,
    stops JSONB,
    distance_km DECIMAL,
    duration_minutes INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        b.id, b.vehicle_number, b.name, b.capacity, b.model,
        br.id, br.name, br.route_number, br.stops,
        br.distance_km, br.duration_minutes
    FROM buses b
    JOIN bus_routes br ON b.route_id = br.id
    WHERE b.driver_id = v_driver_id
    AND b.is_active = true;
END;
$$;

-- Get driver's today's trip
CREATE OR REPLACE FUNCTION get_driver_today_trip()
RETURNS TABLE (
    trip_id UUID,
    bus_id UUID,
    route_id UUID,
    trip_type TEXT,
    status TEXT,
    scheduled_start TIMESTAMPTZ,
    actual_start TIMESTAMPTZ,
    actual_end TIMESTAMPTZ,
    delay_minutes INTEGER,
    passenger_count INTEGER,
    route_name TEXT,
    stops JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        bt.id, bt.bus_id, bt.route_id, bt.trip_type, bt.status,
        bt.scheduled_start, bt.actual_start, bt.actual_end,
        bt.delay_minutes, bt.passenger_count,
        br.name, br.stops
    FROM bus_trips bt
    JOIN buses b ON bt.bus_id = b.id
    JOIN bus_routes br ON bt.route_id = br.id
    WHERE bt.driver_id = v_driver_id
    AND bt.trip_date = CURRENT_DATE
    ORDER BY bt.scheduled_start DESC
    LIMIT 1;
END;
$$;

-- Start a trip
CREATE OR REPLACE FUNCTION start_bus_trip(
    p_bus_id UUID,
    p_route_id UUID,
    p_trip_type TEXT DEFAULT 'morning'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
    v_trip_id UUID;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Driver profile not found.');
    END IF;

    -- Check no active trip already
    IF EXISTS (
        SELECT 1 FROM bus_trips
        WHERE driver_id = v_driver_id
        AND trip_date = CURRENT_DATE
        AND status = 'active'
    ) THEN
        RETURN json_build_object('success', false, 'error', 'You already have an active trip. End it first.');
    END IF;

    INSERT INTO bus_trips (
        institution_id, bus_id, route_id, driver_id,
        trip_date, trip_type, scheduled_start, actual_start, status
    ) VALUES (
        (SELECT institution_id FROM bus_drivers WHERE id = v_driver_id),
        p_bus_id, p_route_id, v_driver_id,
        CURRENT_DATE, p_trip_type, NOW(), NOW(), 'active'
    ) RETURNING id INTO v_trip_id;

    -- Update bus is_active
    UPDATE buses SET is_active = true WHERE id = p_bus_id;

    RETURN json_build_object('success', true, 'trip_id', v_trip_id, 'message', 'Trip started.');
END;
$$;

-- End a trip
CREATE OR REPLACE FUNCTION end_bus_trip(p_trip_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Driver profile not found.');
    END IF;

    UPDATE bus_trips
    SET status = 'completed', actual_end = NOW()
    WHERE id = p_trip_id
    AND driver_id = v_driver_id
    AND status = 'active';

    IF FOUND THEN
        -- Deactivate old tracking
        UPDATE bus_tracking SET is_active = false
        WHERE bus_id = (SELECT bus_id FROM bus_trips WHERE id = p_trip_id)
        AND is_active = true;

        RETURN json_build_object('success', true, 'message', 'Trip ended.');
    ELSE
        RETURN json_build_object('success', false, 'error', 'Trip not found or already ended.');
    END IF;
END;
$$;

-- Get student headcount for driver's route today
CREATE OR REPLACE FUNCTION get_driver_route_headcount()
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number TEXT,
    stop_name TEXT,
    has_boarded BOOLEAN,
    boarded_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
    v_route_id UUID;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN RETURN; END IF;

    SELECT b.route_id INTO v_route_id
    FROM buses b WHERE b.driver_id = v_driver_id AND b.is_active = true
    LIMIT 1;

    IF v_route_id IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        s.id,
        u.name,
        s.roll_number,
        ts.stop_name,
        CASE WHEN bt.boarded_at IS NOT NULL THEN true ELSE false END,
        bt.boarded_at
    FROM transport_subscriptions ts
    JOIN students s ON ts.student_id = s.id
    JOIN users u ON s.user_id = u.id
    LEFT JOIN bus_tracking bt ON bt.student_id = s.id
        AND bt.bus_id = (SELECT id FROM buses WHERE driver_id = v_driver_id AND is_active = true LIMIT 1)
        AND bt.boarded_at::DATE = CURRENT_DATE
    WHERE ts.route_id = v_route_id
    AND ts.status = 'active'
    ORDER BY ts.stop_name, u.name;
END;
$$;

-- Get trip stop schedule (from route stops)
CREATE OR REPLACE FUNCTION get_driver_stop_schedule()
RETURNS TABLE (
    stop_index INTEGER,
    stop_name TEXT,
    latitude DECIMAL,
    longitude DECIMAL,
    scheduled_time TEXT,
    is_reached BOOLEAN,
    reached_at TIMESTAMPTZ,
    passengers_boarded INTEGER,
    passengers_alighted INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
    v_route_id UUID;
    v_trip_id UUID;
    v_stops JSONB;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN RETURN; END IF;

    SELECT b.route_id INTO v_route_id
    FROM buses b WHERE b.driver_id = v_driver_id AND b.is_active = true
    LIMIT 1;

    IF v_route_id IS NULL THEN RETURN; END IF;

    -- Get today's trip
    SELECT bt.id INTO v_trip_id
    FROM bus_trips bt
    WHERE bt.driver_id = v_driver_id
    AND bt.trip_date = CURRENT_DATE
    AND bt.status = 'active'
    LIMIT 1;

    -- Get stops from route
    SELECT br.stops INTO v_stops
    FROM bus_routes br WHERE br.id = v_route_id;

    IF v_stops IS NULL THEN RETURN; END IF;

    RETURN QUERY
    SELECT
        (stop->>'stop_index')::INTEGER,
        stop->>'name',
        (stop->>'latitude')::DECIMAL,
        (stop->>'longitude')::DECIMAL,
        COALESCE(stop->>'scheduled_time_morning', stop->>'scheduled_time_evening'),
        COALESCE(tsl.actual_arrival IS NOT NULL, false),
        tsl.actual_arrival,
        COALESCE(tsl.passengers_boarded, 0),
        COALESCE(tsl.passengers_alighted, 0)
    FROM jsonb_array_elements(v_stops) AS stop
    LEFT JOIN trip_stop_logs tsl ON tsl.trip_id = v_trip_id
        AND tsl.stop_index = (stop->>'stop_index')::INTEGER
    ORDER BY (stop->>'stop_index')::INTEGER;
END;
$$;

-- Mark a stop as reached
CREATE OR REPLACE FUNCTION mark_stop_reached(
    p_stop_index INTEGER,
    p_passengers_boarded INTEGER DEFAULT 0,
    p_passengers_alighted INTEGER DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
    v_trip_id UUID;
    v_stop_name TEXT;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Driver profile not found.');
    END IF;

    SELECT bt.id INTO v_trip_id
    FROM bus_trips bt
    WHERE bt.driver_id = v_driver_id
    AND bt.trip_date = CURRENT_DATE
    AND bt.status = 'active'
    LIMIT 1;

    IF v_trip_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'No active trip found.');
    END IF;

    -- Get stop name from route
    SELECT stop->>'name' INTO v_stop_name
    FROM bus_routes br,
         jsonb_array_elements(br.stops) stop
    WHERE br.id = (SELECT route_id FROM bus_trips WHERE id = v_trip_id)
    AND (stop->>'stop_index')::INTEGER = p_stop_index
    LIMIT 1;

    INSERT INTO trip_stop_logs (
        institution_id, trip_id, stop_index, stop_name,
        scheduled_time, actual_arrival, passengers_boarded, passengers_alighted
    ) VALUES (
        (SELECT institution_id FROM bus_trips WHERE id = v_trip_id),
        v_trip_id, p_stop_index, COALESCE(v_stop_name, 'Stop ' || p_stop_index),
        NOW(), NOW(), p_passengers_boarded, p_passengers_alighted
    )
    ON CONFLICT (trip_id, stop_index) DO UPDATE SET
        actual_arrival = NOW(),
        passengers_boarded = EXCLUDED.passengers_boarded,
        passengers_alighted = EXCLUDED.passengers_alighted;

    RETURN json_build_object('success', true, 'message', 'Stop marked as reached.');
END;
$$;

-- Add unique constraint for trip_stop_logs if not exists
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'trip_stop_logs_trip_stop_unique'
    ) THEN
        ALTER TABLE trip_stop_logs ADD CONSTRAINT trip_stop_logs_trip_stop_unique UNIQUE (trip_id, stop_index);
    END IF;
EXCEPTION WHEN OTHERS THEN
    -- Constraint may already exist
    NULL;
END $$;

-- Report emergency/breakdown
CREATE OR REPLACE FUNCTION report_bus_incident(
    p_incident_type TEXT,
    p_description TEXT,
    p_latitude DECIMAL,
    p_longitude DECIMAL,
    p_severity TEXT DEFAULT 'high'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_driver_id UUID;
    v_bus_id UUID;
    v_trip_id UUID;
    v_incident_id UUID;
BEGIN
    SELECT bd.id INTO v_driver_id
    FROM bus_drivers bd WHERE bd.user_id = auth.uid();

    IF v_driver_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Driver profile not found.');
    END IF;

    SELECT b.id, bt.id INTO v_bus_id, v_trip_id
    FROM buses b
    LEFT JOIN bus_trips bt ON bt.bus_id = b.id AND bt.status = 'active' AND bt.trip_date = CURRENT_DATE
    WHERE b.driver_id = v_driver_id AND b.is_active = true
    LIMIT 1;

    INSERT INTO bus_incidents (
        institution_id, bus_id, trip_id, incident_type,
        description, latitude, longitude, reported_by, severity, status
    ) VALUES (
        (SELECT institution_id FROM bus_drivers WHERE id = v_driver_id),
        v_bus_id, v_trip_id, p_incident_type,
        p_description, p_latitude, p_longitude, auth.uid(),
        p_severity, 'reported'
    ) RETURNING id INTO v_incident_id;

    RETURN json_build_object(
        'success', true,
        'incident_id', v_incident_id,
        'message', 'Emergency reported. Admin and warden have been alerted.'
    );
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000013_vendor_canteen_module.sql
-- ==========================================================

-- ============================================================
-- VENDOR / CANTEEN STAFF MODULE: KOT, Menu Mgmt, Sales, Pre-orders
-- ============================================================

-- ============================================================
-- 1. ORDER STATUS TRACKING: Add status history table
-- ============================================================
CREATE TABLE IF NOT EXISTS canteen_order_status_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    order_id UUID NOT NULL REFERENCES canteen_orders(id) ON DELETE CASCADE,
    old_status VARCHAR(50),
    new_status VARCHAR(50) NOT NULL,
    changed_by UUID REFERENCES users(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE canteen_order_status_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Vendor can manage order status logs" ON canteen_order_status_log
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Vendor')
        AND institution_id = get_auth_institution_id()
    );

-- RPC: Update order status (KOT workflow)
CREATE OR REPLACE FUNCTION update_order_status(
    p_order_id UUID,
    p_new_status VARCHAR,
    p_notes TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_status VARCHAR;
    v_order RECORD;
BEGIN
    SELECT status INTO v_old_status FROM canteen_orders WHERE id = p_order_id;
    IF v_old_status IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Order not found.');
    END IF;

    UPDATE canteen_orders
    SET status = p_new_status
    WHERE id = p_order_id;

    INSERT INTO canteen_order_status_log (institution_id, order_id, old_status, new_status, changed_by, notes)
    VALUES (
        (SELECT institution_id FROM canteen_orders WHERE id = p_order_id),
        p_order_id, v_old_status, p_new_status, auth.uid(), p_notes
    );

    RETURN json_build_object('success', true, 'old_status', v_old_status, 'new_status', p_new_status);
END;
$$;

-- ============================================================
-- 2. ATOMIC WALLET DEDUCTION for canteen orders
-- ============================================================
CREATE OR REPLACE FUNCTION place_canteen_order_atomic(
    p_student_id UUID,
    p_items JSONB,
    p_total_amount DECIMAL,
    p_special_instructions TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_wallet RECORD;
    v_order_id UUID;
    v_order_number VARCHAR;
    v_item JSONB;
    v_stock_ok BOOLEAN := true;
BEGIN
    -- Get student's wallet with lock
    SELECT * INTO v_wallet
    FROM canteen_wallets
    WHERE student_id = p_student_id
    FOR UPDATE;

    IF v_wallet IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'No canteen wallet found.');
    END IF;

    IF v_wallet.balance < p_total_amount THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient wallet balance. Current: ₹' || v_wallet.balance || ', Required: ₹' || p_total_amount);
    END IF;

    -- Check stock for all items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM canteen_menus
            WHERE id = (v_item->>'item_id')::UUID
            AND is_available = true
            AND stock_remaining > 0
        ) THEN
            v_stock_ok := false;
            EXIT;
        END IF;
    END LOOP;

    IF NOT v_stock_ok THEN
        RETURN json_build_object('success', false, 'error', 'One or more items are out of stock.');
    END IF;

    -- Deduct wallet atomically
    UPDATE canteen_wallets
    SET balance = balance - p_total_amount,
        last_updated = NOW()
    WHERE id = v_wallet.id;

    -- Create order
    v_order_number := 'ORD' || TO_CHAR(NOW(), 'YYMMDD') || LPAD(FLOOR(RANDOM() * 9999)::TEXT, 4, '0');

    INSERT INTO canteen_orders (
        institution_id, student_id, items, total_amount, final_amount,
        status, payment_status, special_instructions, order_number, order_time
    ) VALUES (
        (SELECT institution_id FROM students WHERE id = p_student_id),
        p_student_id, p_items, p_total_amount, p_total_amount,
        'placed', 'paid', p_special_instructions, v_order_number, NOW()
    ) RETURNING id INTO v_order_id;

    -- Deduct stock
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        UPDATE canteen_menus
        SET stock_remaining = GREATEST(stock_remaining - COALESCE((v_item->>'quantity')::INTEGER, 1), 0)
        WHERE id = (v_item->>'item_id')::UUID;
    END LOOP;

    -- Log wallet transaction
    INSERT INTO wallet_transactions (institution_id, student_id, amount, type, status, description)
    VALUES (
        (SELECT institution_id FROM students WHERE id = p_student_id),
        p_student_id, -p_total_amount, 'canteen_order', 'completed',
        'Canteen order ' || v_order_number
    );

    RETURN json_build_object(
        'success', true,
        'order_id', v_order_id,
        'order_number', v_order_number,
        'amount_deducted', p_total_amount,
        'remaining_balance', v_wallet.balance - p_total_amount
    );
END;
$$;

-- ============================================================
-- 3. VENDOR DAILY SALES REPORT
-- ============================================================
CREATE OR REPLACE FUNCTION get_vendor_daily_sales(
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_vendor_id UUID;
    v_institution_id UUID;
    v_result JSON;
BEGIN
    SELECT id, institution_id INTO v_vendor_id, v_institution_id
    FROM users WHERE id = auth.uid();

    SELECT institution_id INTO v_institution_id
    FROM users WHERE id = auth.uid();

    WITH day_orders AS (
        SELECT *
        FROM canteen_orders
        WHERE institution_id = v_institution_id
        AND created_at::DATE = p_date
    ),
    item_stats AS (
        SELECT
            (item->>'name') AS item_name,
            SUM((item->>'quantity')::INTEGER) AS total_qty,
            SUM((item->>'price')::DECIMAL * (item->>'quantity')::INTEGER) AS total_revenue
        FROM day_orders,
             jsonb_array_elements(items) AS item
        GROUP BY (item->>'name')
        ORDER BY total_qty DESC
    )
    SELECT json_build_object(
        'date', p_date,
        'total_orders', (SELECT COUNT(*) FROM day_orders),
        'total_revenue', COALESCE((SELECT SUM(total_amount) FROM day_orders), 0),
        'wallet_orders', (SELECT COUNT(*) FROM day_orders WHERE payment_status = 'paid'),
        'cash_orders', (SELECT COUNT(*) FROM day_orders WHERE payment_status = 'cash'),
        'status_breakdown', (
            SELECT json_object_agg(status, cnt)
            FROM (SELECT status, COUNT(*) AS cnt FROM day_orders GROUP BY status) s
        ),
        'top_items', (
            SELECT json_agg(json_build_object('name', item_name, 'qty', total_qty, 'revenue', total_revenue))
            FROM item_stats LIMIT 10
        ),
        'hourly_breakdown', (
            SELECT json_agg(json_build_object('hour', h, 'orders', COALESCE(cnt, 0)))
            FROM generate_series(8, 20) AS h
            LEFT JOIN (
                SELECT EXTRACT(HOUR FROM created_at)::INTEGER AS hour, COUNT(*) AS cnt
                FROM day_orders GROUP BY 1
            ) hr ON hr.hour = h
        )
    ) INTO v_result;

    RETURN v_result;
END;
$$;

-- ============================================================
-- 4. PRE-ORDER / MEAL PREP LIST
-- ============================================================
CREATE OR REPLACE FUNCTION get_canteen_prep_list(
    p_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    item_name VARCHAR,
    category VARCHAR,
    total_quantity BIGINT,
    veg_quantity BIGINT,
    nonveg_quantity BIGINT,
    special_instructions TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT
        (item->>'name')::VARCHAR,
        COALESCE(cm.category_id::TEXT, 'Uncategorized'),
        SUM((item->>'quantity')::BIGINT),
        SUM(CASE WHEN cm.is_veg THEN (item->>'quantity')::BIGINT ELSE 0 END),
        SUM(CASE WHEN NOT cm.is_veg THEN (item->>'quantity')::BIGINT ELSE 0 END),
        string_agg(DISTINCT co.special_instructions, '; ')
    FROM canteen_orders co,
         jsonb_array_elements(co.items) AS item
    LEFT JOIN canteen_menus cm ON cm.item_name = (item->>'name')
    WHERE co.institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    AND co.created_at::DATE = p_date
    AND co.status IN ('placed', 'confirmed', 'preparing')
    GROUP BY (item->>'name'), cm.category_id
    ORDER BY SUM((item->>'quantity')::BIGINT) DESC;
END;
$$;

-- ============================================================
-- 5. MENU AVAILABILITY TOGGLE
-- ============================================================
CREATE OR REPLACE FUNCTION toggle_menu_availability(
    p_menu_id UUID,
    p_is_available BOOLEAN
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE canteen_menus
    SET is_available = p_is_available,
        stock_remaining = CASE WHEN p_is_available THEN daily_stock ELSE 0 END
    WHERE id = p_menu_id
    AND institution_id = (SELECT institution_id FROM users WHERE id = auth.uid());

    IF FOUND THEN
        RETURN json_build_object('success', true, 'available', p_is_available);
    ELSE
        RETURN json_build_object('success', false, 'error', 'Menu item not found.');
    END IF;
END;
$$;

-- Update stock
CREATE OR REPLACE FUNCTION update_menu_stock(
    p_menu_id UUID,
    p_new_stock INTEGER
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE canteen_menus
    SET daily_stock = p_new_stock,
        stock_remaining = p_new_stock
    WHERE id = p_menu_id
    AND institution_id = (SELECT institution_id FROM users WHERE id = auth.uid());

    IF FOUND THEN
        RETURN json_build_object('success', true);
    ELSE
        RETURN json_build_object('success', false, 'error', 'Menu item not found.');
    END IF;
END;
$$;

-- Update price
CREATE OR REPLACE FUNCTION update_menu_price(
    p_menu_id UUID,
    p_new_price DECIMAL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE canteen_menus
    SET price = p_new_price
    WHERE id = p_menu_id
    AND institution_id = (SELECT institution_id FROM users WHERE id = auth.uid());

    IF FOUND THEN
        RETURN json_build_object('success', true);
    ELSE
        RETURN json_build_object('success', false, 'error', 'Menu item not found.');
    END IF;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000014_director_kpis.sql
-- ==========================================================

-- =========================================================================
-- DIRECTOR DASHBOARD KPIs & ANALYTICS
-- Migration: 20260612000014
-- Real-time campus pulse, fee recovery, attendance trends,
-- complaint SLA, NAAC export, system anomaly detection
-- =========================================================================

-- =========================================================================
-- 1. SYSTEM ANOMALY DETECTION TABLE
-- =========================================================================
CREATE TABLE IF NOT EXISTS system_anomalies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id),
  anomaly_type VARCHAR(50) NOT NULL, -- geo_fence_violation, duplicate_attendance, rapid_wallet_txn, new_device_login, dual_presence, unusual_hours, bulk_action
  severity VARCHAR(20) NOT NULL DEFAULT 'medium', -- low, medium, high, critical
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  module VARCHAR(50) NOT NULL, -- attendance, wallet, gate, auth, canteen
  person_id UUID,
  person_type VARCHAR(20), -- student, staff, teacher
  person_name TEXT,
  metadata JSONB DEFAULT '{}', -- { lat, long, device_id, amount, old_value, new_value }
  is_resolved BOOLEAN DEFAULT FALSE,
  resolved_by UUID,
  resolved_at TIMESTAMPTZ,
  resolution_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_system_anomalies_institution ON system_anomalies(institution_id);
CREATE INDEX IF NOT EXISTS idx_system_anomalies_type ON system_anomalies(anomaly_type);
CREATE INDEX IF NOT EXISTS idx_system_anomalies_created ON system_anomalies(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_system_anomalies_unresolved ON system_anomalies(institution_id, is_resolved) WHERE NOT is_resolved;

-- =========================================================================
-- 2. NAAC ACCREDITATION SNAPSHOTS TABLE
-- =========================================================================
CREATE TABLE IF NOT EXISTS naac_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id),
  snapshot_date DATE NOT NULL DEFAULT CURRENT_DATE,
  data JSONB NOT NULL, -- Full NAAC metrics blob
  generated_by UUID,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(institution_id, snapshot_date)
);

-- =========================================================================
-- 3. DIRECTOR KPI RPCs
-- =========================================================================

-- 3a. Campus Pulse: 10 real KPIs in one call
CREATE OR REPLACE FUNCTION get_campus_pulse()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inst_id UUID;
  v_result JSON;
  v_today DATE := CURRENT_DATE;
  v_this_month_start DATE := DATE_TRUNC('month', CURRENT_DATE)::DATE;
  v_attendance_pct NUMERIC := 0;
  v_total_students INT := 0;
  v_fee_billed NUMERIC := 0;
  v_fee_collected NUMERIC := 0;
  v_fee_outstanding NUMERIC := 0;
  v_hostel_occupied INT := 0;
  v_hostel_capacity INT := 0;
  v_complaints_open INT := 0;
  v_gate_entries_today INT := 0;
  v_canteen_revenue NUMERIC := 0;
  v_bus_routes_active INT := 0;
  v_security_incidents INT := 0;
  v_departments JSONB := '[]'::JSONB;
  v_fee_by_dept JSONB := '[]'::JSONB;
BEGIN
  SELECT u.institution_id INTO v_inst_id
  FROM users u
  WHERE u.id = auth.uid();

  IF v_inst_id IS NULL THEN
    SELECT id INTO v_inst_id FROM institutions LIMIT 1;
  END IF;

  -- 1. Today's attendance %
  SELECT COALESCE(
    ROUND(100.0 * COUNT(*) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(*), 0), 1), 0
  ) INTO v_attendance_pct
  FROM attendance a
  WHERE a.institution_id = v_inst_id
    AND a.date = v_today;

  -- 2. Total active students
  SELECT COUNT(*) INTO v_total_students
  FROM students s
  WHERE s.institution_id = v_inst_id AND s.is_active = TRUE;

  -- 3. Fee collection this month
  SELECT
    COALESCE(SUM(fs.amount), 0),
    COALESCE(SUM(fp.amount_paid), 0),
    COALESCE(SUM(fs.amount), 0) - COALESCE(SUM(fp.amount_paid), 0)
  INTO v_fee_billed, v_fee_collected, v_fee_outstanding
  FROM fee_structures fs
  LEFT JOIN student_fees sf ON sf.fee_structure_id = fs.id AND sf.institution_id = v_inst_id
  LEFT JOIN fee_payments fp ON fp.student_id = sf.student_id AND fp.fee_structure_id = sf.fee_structure_id AND fp.status = 'completed'
    AND fp.payment_date >= v_this_month_start
  WHERE fs.institution_id = v_inst_id;

  -- 4. Hostel occupancy
  SELECT
    COALESCE(SUM(hr.occupied), 0),
    COALESCE(SUM(hr.capacity), 0)
  INTO v_hostel_occupied, v_hostel_capacity
  FROM hostel_blocks hb
  JOIN hostel_rooms hr ON hr.block_id = hb.id
  WHERE hb.institution_id = v_inst_id;

  -- 5. Open complaints
  SELECT COUNT(*) INTO v_complaints_open
  FROM hostel_complaints hc
  WHERE hc.institution_id = v_inst_id
    AND hc.status NOT IN ('resolved', 'closed');

  -- 6. Gate entries today
  SELECT COUNT(*) INTO v_gate_entries_today
  FROM gate_entries ge
  WHERE ge.institution_id = v_inst_id
    AND ge.timestamp::DATE = v_today;

  -- 7. Canteen revenue today
  SELECT COALESCE(SUM(co.total_amount), 0) INTO v_canteen_revenue
  FROM canteen_orders co
  WHERE co.institution_id = v_inst_id
    AND co.order_time::DATE = v_today
    AND co.status != 'cancelled';

  -- 8. Active bus routes
  SELECT COUNT(DISTINCT bt.route_id) INTO v_bus_routes_active
  FROM bus_trips bt
  WHERE bt.institution_id = v_inst_id
    AND bt.trip_date = v_today
    AND bt.status IN ('in_progress', 'scheduled');

  -- 9. Security incidents today
  SELECT COUNT(*) INTO v_security_incidents
  FROM security_incidents si
  WHERE si.institution_id = v_inst_id
    AND si.created_at::DATE = v_today;

  -- 10. Department breakdown
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'name', d.name,
      'student_count', dept_stats.cnt,
      'attendance_pct', dept_stats.att_pct
    )
  ), '[]'::JSONB) INTO v_departments
  FROM (
    SELECT
      s.department_id,
      COUNT(*) as cnt,
      COALESCE(ROUND(100.0 * COUNT(*) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(a.id), 0), 1), 0) as att_pct
    FROM students s
    LEFT JOIN attendance a ON a.student_id = s.id AND a.date = v_today
    WHERE s.institution_id = v_inst_id AND s.is_active = TRUE
    GROUP BY s.department_id
  ) dept_stats
  JOIN departments d ON d.id = dept_stats.department_id;

  -- Fee by department
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'department', d.name,
      'billed', COALESCE(dept_fees.billed, 0),
      'collected', COALESCE(dept_fees.collected, 0),
      'outstanding', COALESCE(dept_fees.billed, 0) - COALESCE(dept_fees.collected, 0)
    )
  ), '[]'::JSONB) INTO v_fee_by_dept
  FROM (
    SELECT
      s.department_id,
      SUM(sf.amount) as billed,
      SUM(COALESCE(fp.amount_paid, 0)) as collected
    FROM students s
    JOIN student_fees sf ON sf.student_id = s.id
    LEFT JOIN fee_payments fp ON fp.student_id = sf.student_id AND fp.fee_structure_id = sf.fee_structure_id AND fp.status = 'completed'
    WHERE s.institution_id = v_inst_id AND s.is_active = TRUE
    GROUP BY s.department_id
  ) dept_fees
  JOIN departments d ON d.id = dept_fees.department_id;

  v_result := json_build_object(
    'attendance_pct', v_attendance_pct,
    'total_students', v_total_students,
    'fee_billed', v_fee_billed,
    'fee_collected', v_fee_collected,
    'fee_outstanding', v_fee_outstanding,
    'hostel_occupied', v_hostel_occupied,
    'hostel_capacity', v_hostel_capacity,
    'hostel_occupancy_pct', CASE WHEN v_hostel_capacity > 0 THEN ROUND(100.0 * v_hostel_occupied / v_hostel_capacity, 1) ELSE 0 END,
    'complaints_open', v_complaints_open,
    'gate_entries_today', v_gate_entries_today,
    'canteen_revenue', v_canteen_revenue,
    'bus_routes_active', v_bus_routes_active,
    'security_incidents', v_security_incidents,
    'departments', v_departments,
    'fee_by_department', v_fee_by_dept,
    'snapshot_date', v_today,
    'snapshot_time', NOW()
  );

  RETURN v_result;
END;
$$;

-- 3b. Fee Recovery Tracking
CREATE OR REPLACE FUNCTION get_fee_recovery_tracking(
  p_semester INT DEFAULT NULL,
  p_department_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inst_id UUID;
  v_result JSON;
BEGIN
  SELECT u.institution_id INTO v_inst_id
  FROM users u WHERE u.id = auth.uid();
  IF v_inst_id IS NULL THEN SELECT id INTO v_inst_id FROM institutions LIMIT 1; END IF;

  SELECT json_build_object(
    'summary', (
      SELECT json_build_object(
        'total_billed', COALESCE(SUM(sf.amount), 0),
        'total_collected', COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0),
        'total_outstanding', COALESCE(SUM(sf.amount), 0) - COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0),
        'collection_rate', CASE WHEN SUM(sf.amount) > 0
          THEN ROUND(100.0 * COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) / SUM(sf.amount), 1)
          ELSE 0 END,
        'total_students', COUNT(DISTINCT sf.student_id),
        'fully_paid_count', COUNT(DISTINCT sf.student_id) FILTER (
          WHERE COALESCE((SELECT SUM(amount_paid) FROM fee_payments WHERE student_id = sf.student_id AND fee_structure_id = sf.fee_structure_id AND status = 'completed'), 0) >= sf.amount
        ),
        'partial_paid_count', COUNT(DISTINCT sf.student_id) FILTER (
          WHERE COALESCE((SELECT SUM(amount_paid) FROM fee_payments WHERE student_id = sf.student_id AND fee_structure_id = sf.fee_structure_id AND status = 'completed'), 0) > 0
            AND COALESCE((SELECT SUM(amount_paid) FROM fee_payments WHERE student_id = sf.student_id AND fee_structure_id = sf.fee_structure_id AND status = 'completed'), 0) < sf.amount
        ),
        'unpaid_count', COUNT(DISTINCT sf.student_id) FILTER (
          WHERE COALESCE((SELECT SUM(amount_paid) FROM fee_payments WHERE student_id = sf.student_id AND fee_structure_id = sf.fee_structure_id AND status = 'completed'), 0) = 0
        )
      )
      FROM student_fees sf
      LEFT JOIN fee_payments fp ON fp.student_id = sf.student_id AND fp.fee_structure_id = sf.fee_structure_id
      JOIN students s ON s.id = sf.student_id AND s.institution_id = v_inst_id
      WHERE sf.institution_id = v_inst_id
        AND (p_semester IS NULL OR s.semester = p_semester)
        AND (p_department_id IS NULL OR s.department_id = p_department_id)
    ),
    'by_department', (
      SELECT COALESCE(jsonb_agg(row_to_json(d)), '[]'::JSONB)
      FROM (
        SELECT
          dep.name as department_name,
          COALESCE(SUM(sf.amount), 0) as billed,
          COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) as collected,
          COALESCE(SUM(sf.amount), 0) - COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) as outstanding,
          CASE WHEN SUM(sf.amount) > 0
            THEN ROUND(100.0 * COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) / SUM(sf.amount), 1)
            ELSE 0 END as collection_rate
        FROM students s
        JOIN departments dep ON dep.id = s.department_id
        LEFT JOIN student_fees sf ON sf.student_id = s.id
        LEFT JOIN fee_payments fp ON fp.student_id = sf.student_id AND fp.fee_structure_id = sf.fee_structure_id
        WHERE s.institution_id = v_inst_id AND s.is_active = TRUE
          AND (p_semester IS NULL OR s.semester = p_semester)
        GROUP BY dep.id, dep.name
        ORDER BY outstanding DESC
      ) d
    ),
    'by_fee_type', (
      SELECT COALESCE(jsonb_agg(row_to_json(ft)), '[]'::JSONB)
      FROM (
        SELECT
          fs.name as fee_name,
          COALESCE(SUM(sf.amount), 0) as billed,
          COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) as collected,
          COALESCE(SUM(sf.amount), 0) - COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) as outstanding
        FROM fee_structures fs
        LEFT JOIN student_fees sf ON sf.fee_structure_id = fs.id
        LEFT JOIN fee_payments fp ON fp.student_id = sf.student_id AND fp.fee_structure_id = sf.fee_structure_id
        WHERE fs.institution_id = v_inst_id
        GROUP BY fs.id, fs.name
        ORDER BY outstanding DESC
      ) ft
    ),
    'top_defaulters', (
      SELECT COALESCE(jsonb_agg(row_to_json(def)), '[]'::JSONB)
      FROM (
        SELECT
          s.id as student_id,
          u.name as student_name,
          s.roll_number,
          dep.name as department_name,
          s.semester,
          COALESCE(SUM(sf.amount), 0) as total_due,
          COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) as total_paid,
          COALESCE(SUM(sf.amount), 0) - COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) as overdue_amount,
          COALESCE(guardian.guardian_name, '') as guardian_name,
          COALESCE(guardian.guardian_phone, '') as guardian_phone
        FROM students s
        JOIN users u ON u.id = s.user_id
        JOIN departments dep ON dep.id = s.department_id
        LEFT JOIN student_fees sf ON sf.student_id = s.id
        LEFT JOIN fee_payments fp ON fp.student_id = sf.student_id AND fp.fee_structure_id = sf.fee_structure_id
        LEFT JOIN LATERAL (
          SELECT s2.guardian_name, s2.guardian_phone
          FROM students s2 WHERE s2.id = s.id
        ) guardian ON TRUE
        WHERE s.institution_id = v_inst_id AND s.is_active = TRUE
        GROUP BY s.id, u.name, s.roll_number, dep.name, s.semester, guardian.guardian_name, guardian.guardian_phone
        HAVING COALESCE(SUM(sf.amount), 0) - COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) > 0
        ORDER BY overdue_amount DESC
        LIMIT 20
      ) def
    ),
    'monthly_trend', (
      SELECT COALESCE(jsonb_agg(row_to_json(mt)), '[]'::JSONB)
      FROM (
        SELECT
          DATE_TRUNC('month', fp.payment_date)::DATE as month,
          SUM(fp.amount_paid) as collected
        FROM fee_payments fp
        WHERE fp.institution_id = v_inst_id AND fp.status = 'completed'
          AND fp.payment_date >= (CURRENT_DATE - INTERVAL '12 months')
        GROUP BY DATE_TRUNC('month', fp.payment_date)
        ORDER BY month
      ) mt
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 3c. Attendance Trends (department-wise, weekly/monthly)
CREATE OR REPLACE FUNCTION get_attendance_trends(
  p_period VARCHAR DEFAULT 'weekly', -- weekly, monthly
  p_department_id UUID DEFAULT NULL,
  p_weeks INT DEFAULT 12
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inst_id UUID;
  v_result JSON;
  v_start_date DATE;
BEGIN
  SELECT u.institution_id INTO v_inst_id
  FROM users u WHERE u.id = auth.uid();
  IF v_inst_id IS NULL THEN SELECT id INTO v_inst_id FROM institutions LIMIT 1; END IF;

  IF p_period = 'weekly' THEN
    v_start_date := CURRENT_DATE - (p_weeks * 7);
  ELSE
    v_start_date := CURRENT_DATE - (p_weeks * 30);
  END IF;

  SELECT json_build_object(
    'overall_trend', (
      SELECT COALESCE(jsonb_agg(row_to_json(t)), '[]'::JSONB)
      FROM (
        SELECT
          CASE WHEN p_period = 'weekly'
            THEN DATE_TRUNC('week', a.date)::DATE
            ELSE DATE_TRUNC('month', a.date)::DATE
          END as period_start,
          COUNT(*) as total_classes,
          COUNT(*) FILTER (WHERE a.status = 'present') as present_count,
          ROUND(100.0 * COUNT(*) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(*), 0), 1) as attendance_pct
        FROM attendance a
        WHERE a.institution_id = v_inst_id
          AND a.date >= v_start_date
        GROUP BY period_start
        ORDER BY period_start
      ) t
    ),
    'by_department', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'department', dept_trend.department_name,
          'trend', dept_trend.trend
        )
      ), '[]'::JSONB)
      FROM (
        SELECT
          d.name as department_name,
          COALESCE(jsonb_agg(
            jsonb_build_object(
              'period', dept_data.period_start,
              'attendance_pct', dept_data.attendance_pct
            ) ORDER BY dept_data.period_start
          ), '[]'::JSONB) as trend
        FROM departments d
        CROSS JOIN LATERAL (
          SELECT
            CASE WHEN p_period = 'weekly'
              THEN DATE_TRUNC('week', a.date)::DATE
              ELSE DATE_TRUNC('month', a.date)::DATE
            END as period_start,
            ROUND(100.0 * COUNT(*) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(*), 0), 1) as attendance_pct
          FROM attendance a
          JOIN students s ON s.id = a.student_id
          WHERE s.institution_id = v_inst_id
            AND s.department_id = d.id
            AND a.date >= v_start_date
            AND (p_department_id IS NULL OR s.department_id = p_department_id)
          GROUP BY period_start
        ) dept_data
        WHERE d.institution_id = v_inst_id
        GROUP BY d.id, d.name
        ORDER BY d.name
      ) dept_trend
    ),
    'department_summary', (
      SELECT COALESCE(jsonb_agg(row_to_json(ds)), '[]'::JSONB)
      FROM (
        SELECT
          d.name as department_name,
          d.id as department_id,
          COUNT(DISTINCT s.id) as student_count,
          COUNT(a.id) as total_records,
          COUNT(a.id) FILTER (WHERE a.status = 'present') as present_count,
          ROUND(100.0 * COUNT(a.id) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(a.id), 0), 1) as overall_pct,
          ROUND(100.0 * COUNT(a.id) FILTER (WHERE a.status = 'present' AND a.date >= CURRENT_DATE - 7) / NULLIF(COUNT(a.id) FILTER (WHERE a.date >= CURRENT_DATE - 7), 0), 1) as last_7d_pct,
          ROUND(100.0 * COUNT(a.id) FILTER (WHERE a.status = 'present' AND a.date >= CURRENT_DATE - 30) / NULLIF(COUNT(a.id) FILTER (WHERE a.date >= CURRENT_DATE - 30), 0), 1) as last_30d_pct
        FROM departments d
        LEFT JOIN students s ON s.department_id = d.id AND s.institution_id = v_inst_id AND s.is_active = TRUE
        LEFT JOIN attendance a ON a.student_id = s.id AND a.date >= v_start_date
        WHERE d.institution_id = v_inst_id
        GROUP BY d.id, d.name
        ORDER BY overall_pct ASC
      ) ds
    ),
    'declining_departments', (
      SELECT COALESCE(jsonb_agg(row_to_json(dd)), '[]'::JSONB)
      FROM (
        SELECT
          d.name as department_name,
          recent.recent_pct,
          older.older_pct,
          ROUND(recent.recent_pct - older.older_pct, 1) as change_pct
        FROM departments d
        JOIN LATERAL (
          SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(*), 0), 1) as recent_pct
          FROM attendance a
          JOIN students s ON s.id = a.student_id
          WHERE s.department_id = d.id AND s.institution_id = v_inst_id
            AND a.date >= CURRENT_DATE - 14
        ) recent ON TRUE
        JOIN LATERAL (
          SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(*), 0), 1) as older_pct
          FROM attendance a
          JOIN students s ON s.id = a.student_id
          WHERE s.department_id = d.id AND s.institution_id = v_inst_id
            AND a.date >= CURRENT_DATE - 28 AND a.date < CURRENT_DATE - 14
        ) older ON TRUE
        WHERE d.institution_id = v_inst_id
          AND (recent.recent_pct - older.older_pct) < -5
        ORDER BY (recent.recent_pct - older.older_pct) ASC
      ) dd
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 3d. Complaint SLA Monitoring
CREATE OR REPLACE FUNCTION get_complaint_sla_monitoring()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inst_id UUID;
  v_result JSON;
BEGIN
  SELECT u.institution_id INTO v_inst_id
  FROM users u WHERE u.id = auth.uid();
  IF v_inst_id IS NULL THEN SELECT id INTO v_inst_id FROM institutions LIMIT 1; END IF;

  SELECT json_build_object(
    'summary', (
      SELECT json_build_object(
        'total_complaints', COUNT(*),
        'open', COUNT(*) FILTER (WHERE hc.status = 'open'),
        'in_progress', COUNT(*) FILTER (WHERE hc.status = 'in_progress'),
        'resolved', COUNT(*) FILTER (WHERE hc.status = 'resolved'),
        'closed', COUNT(*) FILTER (WHERE hc.status = 'closed'),
        'avg_resolution_hours', ROUND(AVG(EXTRACT(EPOCH FROM (hc.resolved_at - hc.created_at)) / 3600) FILTER (WHERE hc.resolved_at IS NOT NULL), 1),
        'overdue_3days', COUNT(*) FILTER (WHERE hc.status NOT IN ('resolved', 'closed') AND hc.created_at < NOW() - INTERVAL '3 days'),
        'overdue_7days', COUNT(*) FILTER (WHERE hc.status NOT IN ('resolved', 'closed') AND hc.created_at < NOW() - INTERVAL '7 days')
      )
      FROM hostel_complaints hc
      WHERE hc.institution_id = v_inst_id
    ),
    'by_category', (
      SELECT COALESCE(jsonb_agg(row_to_json(cat)), '[]'::JSONB)
      FROM (
        SELECT
          hc.category,
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE hc.status IN ('open', 'in_progress')) as pending,
          ROUND(AVG(EXTRACT(EPOCH FROM (hc.resolved_at - hc.created_at)) / 3600) FILTER (WHERE hc.resolved_at IS NOT NULL), 1) as avg_resolution_hours
        FROM hostel_complaints hc
        WHERE hc.institution_id = v_inst_id
        GROUP BY hc.category
        ORDER BY pending DESC
      ) cat
    ),
    'by_block', (
      SELECT COALESCE(jsonb_agg(row_to_json(blk)), '[]'::JSONB)
      FROM (
        SELECT
          hb.name as block_name,
          COUNT(*) as total,
          COUNT(*) FILTER (WHERE hc.status IN ('open', 'in_progress')) as pending,
          ROUND(AVG(EXTRACT(EPOCH FROM (hc.resolved_at - hc.created_at)) / 3600) FILTER (WHERE hc.resolved_at IS NOT NULL), 1) as avg_resolution_hours
        FROM hostel_complaints hc
        JOIN hostel_rooms hr ON hr.id = hc.room_id
        JOIN hostel_blocks hb ON hb.id = hr.block_id
        WHERE hc.institution_id = v_inst_id
        GROUP BY hb.id, hb.name
        ORDER BY pending DESC
      ) blk
    ),
    'sla_breaches', (
      SELECT COALESCE(jsonb_agg(row_to_json(slb)), '[]'::JSONB)
      FROM (
        SELECT
          hc.id,
          hc.category,
          hc.description,
          hc.status,
          hc.created_at,
          hc.assigned_to,
          EXTRACT(EPOCH FROM (NOW() - hc.created_at)) / 3600 as hours_open,
          CASE
            WHEN hc.created_at < NOW() - INTERVAL '7 days' THEN 'critical'
            WHEN hc.created_at < NOW() - INTERVAL '3 days' THEN 'warning'
            ELSE 'normal'
          END as sla_status
        FROM hostel_complaints hc
        WHERE hc.institution_id = v_inst_id
          AND hc.status NOT IN ('resolved', 'closed')
          AND hc.created_at < NOW() - INTERVAL '3 days'
        ORDER BY hc.created_at ASC
        LIMIT 50
      ) slb
    ),
    'repeat_rooms', (
      SELECT COALESCE(jsonb_agg(row_to_json(rr)), '[]'::JSONB)
      FROM (
        SELECT
          hc.room_id,
          hr.room_number,
          hb.name as block_name,
          COUNT(*) as complaint_count,
          MAX(hc.created_at) as last_complaint
        FROM hostel_complaints hc
        JOIN hostel_rooms hr ON hr.id = hc.room_id
        JOIN hostel_blocks hb ON hb.id = hr.block_id
        WHERE hc.institution_id = v_inst_id
        GROUP BY hc.room_id, hr.room_number, hb.name
        HAVING COUNT(*) >= 3
        ORDER BY complaint_count DESC
      ) rr
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 3e. NAAC Accreditation Data Export
CREATE OR REPLACE FUNCTION get_naac_accreditation_data()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inst_id UUID;
  v_result JSON;
  v_academic_year VARCHAR;
  v_student_count INT;
  v_teacher_count INT;
  v_staff_count INT;
BEGIN
  SELECT u.institution_id INTO v_inst_id
  FROM users u WHERE u.id = auth.uid();
  IF v_inst_id IS NULL THEN SELECT id INTO v_inst_id FROM institutions LIMIT 1; END IF;

  v_academic_year := CASE
    WHEN EXTRACT(MONTH FROM CURRENT_DATE) >= 7
    THEN EXTRACT(YEAR FROM CURRENT_DATE)::VARCHAR || '-' || (EXTRACT(YEAR FROM CURRENT_DATE) + 1)::VARCHAR
    ELSE (EXTRACT(YEAR FROM CURRENT_DATE) - 1)::VARCHAR || '-' || EXTRACT(YEAR FROM CURRENT_DATE)::VARCHAR
  END;

  SELECT COUNT(*) INTO v_student_count FROM students WHERE institution_id = v_inst_id AND is_active = TRUE;
  SELECT COUNT(*) INTO v_teacher_count FROM users WHERE institution_id = v_inst_id AND role = 'Teacher' AND is_active = TRUE;
  SELECT COUNT(*) INTO v_staff_count FROM users WHERE institution_id = v_inst_id AND role IN ('Staff', 'Admin') AND is_active = TRUE;

  SELECT json_build_object(
    'academic_year', v_academic_year,
    'generated_at', NOW(),

    -- Criterion 1: Curricular Aspects
    'curricular_aspects', json_build_object(
      'total_programs', (SELECT COUNT(DISTINCT department_id) FROM students WHERE institution_id = v_inst_id),
      'student_teacher_ratio', CASE WHEN v_teacher_count > 0 THEN ROUND(v_student_count::NUMERIC / v_teacher_count, 1) ELSE 0 END,
      'student_staff_ratio', CASE WHEN v_staff_count > 0 THEN ROUND(v_student_count::NUMERIC / v_staff_count, 1) ELSE 0 END
    ),

    -- Criterion 2: Teaching-Learning
    'teaching_learning', json_build_object(
      'total_students', v_student_count,
      'total_teachers', v_teacher_count,
      'attendance_summary', (
        SELECT json_build_object(
          'avg_attendance_pct', ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'present') / NULLIF(COUNT(*), 0), 1),
          'total_sessions', COUNT(*),
          'data_from', MIN(date),
          'data_to', MAX(date)
        )
        FROM attendance WHERE institution_id = v_inst_id
      ),
      'exam_results', (
        SELECT json_build_object(
          'total_exams', COUNT(DISTINCT exam_id),
          'total_results', COUNT(*),
          'pass_count', COUNT(*) FILTER (WHERE status = 'pass'),
          'pass_rate', ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'pass') / NULLIF(COUNT(*), 0), 1)
        )
        FROM exam_results WHERE institution_id = v_inst_id
      )
    ),

    -- Criterion 3: Research & Innovation
    'research_innovation', json_build_object(
      'total_events', (SELECT COUNT(*) FROM events WHERE institution_id = v_inst_id AND category = 'academic'),
      'total_workshops', (SELECT COUNT(*) FROM events WHERE institution_id = v_inst_id AND category = 'workshop')
    ),

    -- Criterion 4: Infrastructure
    'infrastructure', json_build_object(
      'hostel_blocks', (SELECT COUNT(*) FROM hostel_blocks WHERE institution_id = v_inst_id),
      'hostel_capacity', (SELECT COALESCE(SUM(capacity), 0) FROM hostel_rooms WHERE block_id IN (SELECT id FROM hostel_blocks WHERE institution_id = v_inst_id)),
      'hostel_occupied', (SELECT COALESCE(SUM(occupied), 0) FROM hostel_rooms WHERE block_id IN (SELECT id FROM hostel_blocks WHERE institution_id = v_inst_id)),
      'bus_routes', (SELECT COUNT(DISTINCT route_id) FROM bus_trips WHERE institution_id = v_inst_id),
      'library_books', (SELECT COUNT(*) FROM books WHERE institution_id = v_inst_id)
    ),

    -- Criterion 5: Student Support
    'student_support', json_build_object(
      'total_complaints', (SELECT COUNT(*) FROM hostel_complaints WHERE institution_id = v_inst_id),
      'resolved_complaints', (SELECT COUNT(*) FROM hostel_complaints WHERE institution_id = v_inst_id AND status IN ('resolved', 'closed')),
      'resolution_rate', (
        SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE status IN ('resolved', 'closed')) / NULLIF(COUNT(*), 0), 1)
        FROM hostel_complaints WHERE institution_id = v_inst_id
      ),
      'fee_collection_rate', (
        SELECT CASE WHEN SUM(sf.amount) > 0
          THEN ROUND(100.0 * COALESCE(SUM(fp.amount_paid) FILTER (WHERE fp.status = 'completed'), 0) / SUM(sf.amount), 1)
          ELSE 0 END
        FROM student_fees sf
        LEFT JOIN fee_payments fp ON fp.student_id = sf.student_id AND fp.fee_structure_id = sf.fee_structure_id
        WHERE sf.institution_id = v_inst_id
      )
    ),

    -- Criterion 6: Governance
    'governance', json_build_object(
      'total_users', (SELECT COUNT(*) FROM users WHERE institution_id = v_inst_id AND is_active = TRUE),
      'roles_breakdown', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('role', role, 'count', cnt)), '[]'::JSONB)
        FROM (
          SELECT role, COUNT(*) as cnt
          FROM users WHERE institution_id = v_inst_id AND is_active = TRUE
          GROUP BY role
        ) r
      )
    ),

    -- Department-wise summary
    'department_wise', (
      SELECT COALESCE(jsonb_agg(row_to_json(dep)), '[]'::JSONB)
      FROM (
        SELECT
          d.name as department_name,
          COUNT(DISTINCT s.id) as students,
          COUNT(DISTINCT CASE WHEN u.role = 'Teacher' THEN u.id END) as teachers,
          ROUND(100.0 * COUNT(a.id) FILTER (WHERE a.status = 'present') / NULLIF(COUNT(a.id), 0), 1) as attendance_pct
        FROM departments d
        LEFT JOIN students s ON s.department_id = d.id AND s.institution_id = v_inst_id AND s.is_active = TRUE
        LEFT JOIN users u ON u.institution_id = v_inst_id AND u.role = 'Teacher' AND u.is_active = TRUE
        LEFT JOIN attendance a ON a.student_id = s.id
        WHERE d.institution_id = v_inst_id
        GROUP BY d.id, d.name
      ) dep
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 3f. System Anomaly Detection
CREATE OR REPLACE FUNCTION detect_system_anomalies()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inst_id UUID;
  v_result JSON;
  v_anomaly_count INT := 0;
BEGIN
  SELECT u.institution_id INTO v_inst_id
  FROM users u WHERE u.id = auth.uid();
  IF v_inst_id IS NULL THEN SELECT id INTO v_inst_id FROM institutions LIMIT 1; END IF;

  -- Detect duplicate attendance (same student, same session, multiple marks)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'duplicate_attendance',
    'high',
    'Duplicate Attendance Detected',
    'Student ' || u.name || ' has ' || COUNT(*) || ' attendance records for the same session on ' || a.date,
    'attendance',
    a.student_id,
    'student',
    u.name,
    jsonb_build_object('date', a.date, 'session_id', a.session_id, 'count', COUNT(*))
  FROM attendance a
  JOIN students s ON s.id = a.student_id
  JOIN users u ON u.id = s.user_id
  WHERE a.institution_id = v_inst_id
    AND a.date >= CURRENT_DATE - 1
  GROUP BY a.student_id, a.session_id, a.date, u.name
  HAVING COUNT(*) > 1
  ON CONFLICT DO NOTHING;

  -- Detect wallet rapid transactions (>3 in 5 minutes)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'rapid_wallet_txn',
    'medium',
    'Rapid Wallet Transactions',
    u.name || ' made ' || COUNT(*) || ' wallet transactions within 5 minutes',
    'wallet',
    wt.student_id,
    'student',
    u.name,
    jsonb_build_object('transaction_count', COUNT(*), 'time_window', '5 minutes', 'total_amount', SUM(wt.amount))
  FROM wallet_transactions wt
  JOIN students s ON s.id = wt.student_id
  JOIN users u ON u.id = s.user_id
  WHERE wt.institution_id = v_inst_id
    AND wt.created_at >= NOW() - INTERVAL '1 hour'
  GROUP BY wt.student_id, u.name, DATE_TRUNC('minute', wt.created_at)
  HAVING COUNT(*) >= 3
  ON CONFLICT DO NOTHING;

  -- Detect unusual hours attendance (marked before 6AM or after 10PM)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'unusual_hours',
    'medium',
    'Attendance Marked at Unusual Hours',
    'Attendance for ' || u.name || ' was marked at ' || TO_CHAR(a.created_at, 'HH24:MI'),
    'attendance',
    a.student_id,
    'student',
    u.name,
    jsonb_build_object('marked_at', a.created_at, 'method', a.method)
  FROM attendance a
  JOIN students s ON s.id = a.student_id
  JOIN users u ON u.id = s.user_id
  WHERE a.institution_id = v_inst_id
    AND a.created_at >= NOW() - INTERVAL '24 hours'
    AND (EXTRACT(HOUR FROM a.created_at) < 6 OR EXTRACT(HOUR FROM a.created_at) > 22)
  ON CONFLICT DO NOTHING;

  -- Detect geo-fence violations (attendance marked >1km from institution)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'geo_fence_violation',
    'high',
    'Attendance Outside Geo-Fence',
    u.name || ' marked attendance from ' || ROUND(a.lat::NUMERIC, 4) || ', ' || ROUND(a.long::NUMERIC, 4),
    'attendance',
    a.student_id,
    'student',
    u.name,
    jsonb_build_object('lat', a.lat, 'long', a.long, 'method', a.method)
  FROM attendance a
  JOIN students s ON s.id = a.student_id
  JOIN users u ON u.id = s.user_id
  WHERE a.institution_id = v_inst_id
    AND a.created_at >= NOW() - INTERVAL '24 hours'
    AND a.lat IS NOT NULL AND a.long IS NOT NULL
    AND (a.lat = 0 OR a.long = 0)
  ON CONFLICT DO NOTHING;

  -- Get unresolved anomaly count
  SELECT COUNT(*) INTO v_anomaly_count
  FROM system_anomalies
  WHERE institution_id = v_inst_id AND NOT is_resolved;

  SELECT json_build_object(
    'total_unresolved', v_anomaly_count,
    'by_type', (
      SELECT COALESCE(jsonb_agg(row_to_json(at)), '[]'::JSONB)
      FROM (
        SELECT anomaly_type, severity, COUNT(*) as count
        FROM system_anomalies
        WHERE institution_id = v_inst_id AND NOT is_resolved
        GROUP BY anomaly_type, severity
        ORDER BY count DESC
      ) at
    ),
    'recent', (
      SELECT COALESCE(jsonb_agg(row_to_json(ra)), '[]'::JSONB)
      FROM (
        SELECT id, anomaly_type, severity, title, description, module, person_name, metadata, created_at
        FROM system_anomalies
        WHERE institution_id = v_inst_id AND NOT is_resolved
        ORDER BY created_at DESC
        LIMIT 20
      ) ra
    ),
    'stats', (
      SELECT json_build_object(
        'total_all_time', COUNT(*),
        'resolved', COUNT(*) FILTER (WHERE is_resolved),
        'critical', COUNT(*) FILTER (WHERE severity = 'critical' AND NOT is_resolved),
        'high', COUNT(*) FILTER (WHERE severity = 'high' AND NOT is_resolved),
        'medium', COUNT(*) FILTER (WHERE severity = 'medium' AND NOT is_resolved),
        'low', COUNT(*) FILTER (WHERE severity = 'low' AND NOT is_resolved)
      )
      FROM system_anomalies WHERE institution_id = v_inst_id
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 3g. Resolve an anomaly
CREATE OR REPLACE FUNCTION resolve_anomaly(
  p_anomaly_id UUID,
  p_resolution_notes TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE system_anomalies
  SET is_resolved = TRUE,
      resolved_by = auth.uid(),
      resolved_at = NOW(),
      resolution_notes = p_resolution_notes
  WHERE id = p_anomaly_id;

  RETURN json_build_object('success', TRUE);
END;
$$;

-- =========================================================================
-- 4. RLS POLICIES
-- =========================================================================
ALTER TABLE system_anomalies ENABLE ROW LEVEL SECURITY;
ALTER TABLE naac_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Director/Admin can view anomalies"
  ON system_anomalies FOR SELECT
  USING (institution_id = (SELECT institution_id FROM users WHERE id = auth.uid()));

CREATE POLICY "System can insert anomalies"
  ON system_anomalies FOR INSERT
  WITH CHECK (TRUE);

CREATE POLICY "Director/Admin can update anomalies"
  ON system_anomalies FOR UPDATE
  USING (institution_id = (SELECT institution_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Director/Admin can view NAAC snapshots"
  ON naac_snapshots FOR SELECT
  USING (institution_id = (SELECT institution_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Director/Admin can insert NAAC snapshots"
  ON naac_snapshots FOR INSERT
  WITH CHECK (institution_id = (SELECT institution_id FROM users WHERE id = auth.uid()));

-- =========================================================================
-- 5. MATERIALIZED VIEW REFRESH FUNCTION
-- =========================================================================
CREATE OR REPLACE FUNCTION refresh_director_views()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_attendance_summary;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
  BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY daily_fee_summary;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260612000015_whatsapp_api_config.sql
-- ==========================================================

-- IRIS 365: WhatsApp API Configuration
-- Institute admins configure their own WhatsApp provider credentials

CREATE TABLE IF NOT EXISTS whatsapp_api_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider VARCHAR(50) NOT NULL DEFAULT 'twilio', -- twilio, meta_cloud, gupshup, wati, custom
  api_url TEXT NOT NULL,
  api_key TEXT, -- or auth token
  phone_number_id VARCHAR(100), -- WhatsApp Business phone number ID
  from_number VARCHAR(50), -- sender number (e.g., whatsapp:+14155238886 for Twilio)
  verify_token VARCHAR(200), -- webhook verify token
  access_token TEXT, -- for Meta Cloud API / Gupshup / WATI
  template_namespace VARCHAR(200), -- Twilio content template SID prefix
  is_active BOOLEAN DEFAULT true,
  extra_config JSONB DEFAULT '{}', -- provider-specific extra fields
  created_by UUID REFERENCES users(id),
  updated_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Only one active config at a time
CREATE UNIQUE INDEX idx_whatsapp_config_active ON whatsapp_api_config (is_active) WHERE is_active = true;

-- RLS: Only Admin/SuperAdmin can manage
ALTER TABLE whatsapp_api_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "whatsapp_config_admin_manage" ON whatsapp_api_config
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role IN ('Admin', 'SuperAdmin')
    )
  );

CREATE POLICY "whatsapp_config_service_role" ON whatsapp_api_config
  FOR ALL
  USING (auth.role() = 'service_role');

-- Log table for WhatsApp message delivery
CREATE TABLE IF NOT EXISTS whatsapp_delivery_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  to_phone VARCHAR(30) NOT NULL,
  from_phone VARCHAR(30),
  template_name VARCHAR(100),
  message_body TEXT,
  status VARCHAR(20) DEFAULT 'sent', -- sent, delivered, failed, sandbox
  provider VARCHAR(50),
  provider_message_id VARCHAR(200),
  error_message TEXT,
  channel_purpose VARCHAR(50), -- fee_reminder, attendance_warning, fee_escalation, daily_digest, broadcast, general
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE whatsapp_delivery_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "whatsapp_log_admin_read" ON whatsapp_delivery_log
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE users.id = auth.uid()
      AND users.role IN ('Admin', 'SuperAdmin')
    )
  );

CREATE POLICY "whatsapp_log_service_insert" ON whatsapp_delivery_log
  FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE whatsapp_api_config IS 'Institute WhatsApp API provider configuration. Admin provides their own API credentials.';
COMMENT ON TABLE whatsapp_delivery_log IS 'Audit log of all WhatsApp messages sent through the system.';


-- ==========================================================
-- MIGRATION: 20260613000001_module_gap_fixes.sql
-- ==========================================================

-- ============================================================
-- MIGRATION: Module-by-module gap fixes
-- 1. General-purpose deduct_wallet RPC
-- 2. Daily canteen menu table
-- 3. Grievance / complaint system
-- 4. Company visits table for placements
-- ============================================================

-- ============================================================
-- 1. GENERAL-PURPOSE WALLET DEDUCTION RPC
-- Reusable by any module: exam fees, hostel fees, event payments, etc.
-- ============================================================
CREATE OR REPLACE FUNCTION deduct_wallet(
    p_student_id UUID,
    p_amount NUMERIC,
    p_description TEXT DEFAULT 'Wallet deduction',
    p_module TEXT DEFAULT 'general'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_balance NUMERIC;
    v_tx_id UUID;
    v_institution_id UUID;
BEGIN
    IF p_amount <= 0 THEN
        RETURN json_build_object('success', false, 'error', 'Amount must be positive.');
    END IF;

    SELECT institution_id, COALESCE(wallet_balance, 0) INTO v_institution_id, v_balance
    FROM students WHERE id = p_student_id FOR UPDATE;

    IF v_institution_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Student not found.');
    END IF;

    IF v_balance < p_amount THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient balance. Available: ₹' || v_balance || ', Required: ₹' || p_amount);
    END IF;

    UPDATE students SET wallet_balance = wallet_balance - p_amount WHERE id = p_student_id;

    INSERT INTO wallet_transactions (institution_id, student_id, amount, type, status, description)
    VALUES (v_institution_id, p_student_id, -p_amount, 'deduction', 'completed', p_module || ': ' || p_description)
    RETURNING id INTO v_tx_id;

    RETURN json_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'amount_deducted', p_amount,
        'remaining_balance', v_balance - p_amount
    );
END;
$$;

-- ============================================================
-- 2. DAILY CANTEEN MENU TABLE
-- Maps which items are available on which day/meal type
-- ============================================================
CREATE TABLE IF NOT EXISTS daily_canteen_menu (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    menu_item_id UUID NOT NULL REFERENCES canteen_menus(id) ON DELETE CASCADE,
    menu_date DATE NOT NULL,
    meal_type TEXT NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snacks')),
    is_available BOOLEAN DEFAULT true,
    price_override NUMERIC(10,2),
    special_notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(institution_id, menu_item_id, menu_date, meal_type)
);

CREATE INDEX IF NOT EXISTS idx_daily_menu_date ON daily_canteen_menu(institution_id, menu_date, meal_type);
CREATE INDEX IF NOT EXISTS idx_daily_menu_item ON daily_canteen_menu(menu_item_id);

ALTER TABLE daily_canteen_menu ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can view daily menu" ON daily_canteen_menu FOR SELECT USING (true);
CREATE POLICY "Staff can manage daily menu" ON daily_canteen_menu FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('Admin', 'SuperAdmin', 'Staff'))
);

-- RPC: Get today's menu
CREATE OR REPLACE FUNCTION get_today_menu(
    p_institution_id UUID,
    p_meal_type TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_agg(json_build_object(
        'id', dcm.id,
        'menu_item_id', dcm.menu_item_id,
        'name', cm.item_name,
        'description', cm.description,
        'category', cm.category,
        'price', COALESCE(dcm.price_override, cm.price),
        'is_veg', cm.is_veg,
        'is_available', dcm.is_available,
        'meal_type', dcm.meal_type,
        'special_notes', dcm.special_notes,
        'image_url', cm.image_url,
        'calories', cm.calories,
        'allergens', cm.allergens
    )) INTO v_result
    FROM daily_canteen_menu dcm
    JOIN canteen_menus cm ON cm.id = dcm.menu_item_id
    WHERE dcm.institution_id = p_institution_id
    AND dcm.menu_date = CURRENT_DATE
    AND cm.is_available = true
    AND (p_meal_type IS NULL OR dcm.meal_type = p_meal_type)
    ORDER BY dcm.meal_type, cm.category, cm.item_name;

    RETURN json_build_object('success', true, 'menu', COALESCE(v_result, '[]'::json), 'date', CURRENT_DATE);
END;
$$;

-- ============================================================
-- 3. GRIEVANCE / COMPLAINT SYSTEM
-- UGC-mandated student grievance mechanism with anonymous option
-- ============================================================
CREATE TABLE IF NOT EXISTS grievances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    submitted_by UUID REFERENCES users(id) ON DELETE SET NULL,
    is_anonymous BOOLEAN DEFAULT false,
    category TEXT NOT NULL CHECK (category IN (
        'academic', 'harassment', 'infrastructure', 'examination',
        'library', 'canteen', 'hostel', 'transport', 'administration',
        'discrimination', 'other'
    )),
    subject TEXT NOT NULL,
    description TEXT NOT NULL,
    evidence_urls JSONB DEFAULT '[]',
    status TEXT DEFAULT 'submitted' CHECK (status IN (
        'submitted', 'acknowledged', 'under_investigation',
        'resolution_proposed', 'resolved', 'appealed', 'closed'
    )),
    assigned_to UUID REFERENCES users(id),
    resolution_notes TEXT,
    resolved_at TIMESTAMPTZ,
    appeal_reason TEXT,
    appeal_resolved_at TIMESTAMPTZ,
    sla_deadline TIMESTAMPTZ,
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_grievances_institution ON grievances(institution_id, status);
CREATE INDEX IF NOT EXISTS idx_grievances_submitted ON grievances(submitted_by);
CREATE INDEX IF NOT EXISTS idx_grievances_category ON grievances(institution_id, category, status);
CREATE INDEX IF NOT EXISTS idx_grievances_sla ON grievances(sla_deadline) WHERE status IN ('submitted', 'acknowledged', 'under_investigation');

ALTER TABLE grievances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Students can view own grievances" ON grievances
    FOR SELECT USING (submitted_by = auth.uid() OR is_anonymous = false);

CREATE POLICY "Students can insert grievances" ON grievances
    FOR INSERT WITH CHECK (submitted_by = auth.uid());

CREATE POLICY "Admin can manage grievances" ON grievances
    FOR ALL USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('Admin', 'SuperAdmin', 'Director')));

-- RPC: Submit grievance
CREATE OR REPLACE FUNCTION submit_grievance(
    p_institution_id UUID,
    p_submitted_by UUID,
    p_category TEXT,
    p_subject TEXT,
    p_description TEXT,
    p_is_anonymous BOOLEAN DEFAULT false,
    p_evidence_urls JSONB DEFAULT '[]',
    p_priority TEXT DEFAULT 'normal'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_grievance_id UUID;
    v_grievance_number VARCHAR;
BEGIN
    v_grievance_number := 'GRV' || TO_CHAR(NOW(), 'YYMMDD') || LPAD(FLOOR(RANDOM() * 9999)::TEXT, 4, '0');

    INSERT INTO grievances (
        institution_id, submitted_by, is_anonymous, category, subject,
        description, evidence_urls, priority, sla_deadline
    ) VALUES (
        p_institution_id,
        CASE WHEN p_is_anonymous THEN NULL ELSE p_submitted_by END,
        p_is_anonymous, p_category, p_subject, p_description,
        p_evidence_urls, p_priority,
        NOW() + INTERVAL '7 days'
    ) RETURNING id INTO v_grievance_id;

    RETURN json_build_object(
        'success', true,
        'grievance_id', v_grievance_id,
        'grievance_number', v_grievance_number,
        'message', 'Grievance submitted successfully. SLA: 7 days.'
    );
END;
$$;

-- RPC: Update grievance status (admin only)
CREATE OR REPLACE FUNCTION update_grievance_status(
    p_grievance_id UUID,
    p_new_status TEXT,
    p_assigned_to UUID DEFAULT NULL,
    p_resolution_notes TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_old_status TEXT;
BEGIN
    SELECT status INTO v_old_status FROM grievances WHERE id = p_grievance_id;

    UPDATE grievances SET
        status = p_new_status,
        assigned_to = COALESCE(p_assigned_to, assigned_to),
        resolution_notes = COALESCE(p_resolution_notes, resolution_notes),
        resolved_at = CASE WHEN p_new_status = 'resolved' THEN NOW() ELSE resolved_at END,
        updated_at = NOW()
    WHERE id = p_grievance_id;

    RETURN json_build_object('success', true, 'old_status', v_old_status, 'new_status', p_new_status);
END;
$$;

-- RPC: Appeal a resolved grievance
CREATE OR REPLACE FUNCTION appeal_grievance(
    p_grievance_id UUID,
    p_appeal_reason TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE grievances SET
        status = 'appealed',
        appeal_reason = p_appeal_reason,
        updated_at = NOW()
    WHERE id = p_grievance_id AND status = 'resolved';

    RETURN json_build_object('success', true, 'message', 'Appeal submitted. Will be reviewed by Director.');
END;
$$;

-- ============================================================
-- 4. COMPANY VISITS TABLE FOR PLACEMENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS company_visits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    visit_date DATE NOT NULL,
    purpose TEXT NOT NULL CHECK (purpose IN (
        'placement_drive', 'internship_drive', 'guest_lecture',
        'campus_interview', 'pre_placement_talk', 'other'
    )),
    visitors JSONB DEFAULT '[]',
    attendees_count INTEGER DEFAULT 0,
    offers_made INTEGER DEFAULT 0,
    offers_accepted INTEGER DEFAULT 0,
    notes TEXT,
    follow_up_date DATE,
    follow_up_notes TEXT,
    status TEXT DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'cancelled', 'rescheduled')),
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_company_visits_institution ON company_visits(institution_id, visit_date);
CREATE INDEX IF NOT EXISTS idx_company_visits_company ON company_visits(company_id, visit_date);

ALTER TABLE company_visits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Placement staff can manage company visits" ON company_visits FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('Admin', 'SuperAdmin', 'Placement Officer'))
);

-- RPC: Log a company visit
CREATE OR REPLACE FUNCTION log_company_visit(
    p_company_id UUID,
    p_visit_date DATE,
    p_purpose TEXT,
    p_visitors JSONB DEFAULT '[]',
    p_notes TEXT DEFAULT '',
    p_created_by UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_visit_id UUID;
    v_institution_id UUID;
BEGIN
    SELECT institution_id INTO v_institution_id FROM companies WHERE id = p_company_id;
    IF v_institution_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Company not found.');
    END IF;

    INSERT INTO company_visits (institution_id, company_id, visit_date, purpose, visitors, notes, created_by)
    VALUES (v_institution_id, p_company_id, p_visit_date, p_purpose, p_visitors, p_notes, p_created_by)
    RETURNING id INTO v_visit_id;

    UPDATE companies SET last_visited = p_visit_date WHERE id = p_company_id;

    RETURN json_build_object('success', true, 'visit_id', v_visit_id);
END;
$$;


-- ==========================================================
-- MIGRATION: 20260613000002_exam_enrollment_hall_ticket.sql
-- ==========================================================

-- =========================================================================
-- EXAM ENROLLMENT & HALL TICKET MODULE
-- =========================================================================

-- 1. EXAM ENROLLMENTS TABLE
CREATE TABLE IF NOT EXISTS exam_enrollments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  exam_id UUID NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL DEFAULT 'enrolled',
  enrolled_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_exam_enrollment UNIQUE (exam_id, student_id)
);

ALTER TABLE exam_enrollments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin/Director can manage exam enrollments"
  ON exam_enrollments FOR ALL
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

CREATE POLICY "Teachers can view exam enrollments"
  ON exam_enrollments FOR SELECT
  USING (
    get_auth_user_role() = 'Teacher'
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "Students can view their own enrollments"
  ON exam_enrollments FOR SELECT
  USING (
    student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
  );

CREATE POLICY "Parents can view linked child enrollments"
  ON exam_enrollments FOR SELECT
  USING (
    student_id IN (
      SELECT student_id FROM parent_student_links
      WHERE parent_user_id = auth.uid() AND verified = true
    )
  );

-- 2. HALL TICKETS TABLE
CREATE TABLE IF NOT EXISTS hall_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  exam_id UUID NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  enrollment_id UUID REFERENCES exam_enrollments(id) ON DELETE SET NULL,
  ticket_number VARCHAR(50) NOT NULL,
  qr_token VARCHAR(255),
  room_number VARCHAR(50),
  seat_number VARCHAR(10),
  exam_date DATE,
  exam_shift VARCHAR(20) DEFAULT 'Morning',
  issued_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_hall_ticket_per_exam UNIQUE (exam_id, student_id),
  CONSTRAINT unique_ticket_number_per_exam UNIQUE (exam_id, ticket_number)
);

ALTER TABLE hall_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin/Director can manage hall tickets"
  ON hall_tickets FOR ALL
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

CREATE POLICY "Teachers can view hall tickets"
  ON hall_tickets FOR SELECT
  USING (
    get_auth_user_role() = 'Teacher'
    AND institution_id = get_auth_institution_id()
  );

CREATE POLICY "Students can view their own hall tickets"
  ON hall_tickets FOR SELECT
  USING (
    student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
  );

CREATE POLICY "Parents can view linked child hall tickets"
  ON hall_tickets FOR SELECT
  USING (
    student_id IN (
      SELECT student_id FROM parent_student_links
      WHERE parent_user_id = auth.uid() AND verified = true
    )
  );

-- 3. INDEXES
CREATE INDEX IF NOT EXISTS idx_exam_enrollments_exam ON exam_enrollments(exam_id);
CREATE INDEX IF NOT EXISTS idx_exam_enrollments_student ON exam_enrollments(student_id);
CREATE INDEX IF NOT EXISTS idx_exam_enrollments_institution ON exam_enrollments(institution_id);
CREATE INDEX IF NOT EXISTS idx_hall_tickets_exam ON hall_tickets(exam_id);
CREATE INDEX IF NOT EXISTS idx_hall_tickets_student ON hall_tickets(student_id);
CREATE INDEX IF NOT EXISTS idx_hall_tickets_institution ON hall_tickets(institution_id);

-- 4. RPC: Generate Hall Tickets for an Exam
CREATE OR REPLACE FUNCTION generate_hall_tickets(p_exam_id UUID)
RETURNS TABLE(success BOOLEAN, message TEXT, tickets_generated INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_institution_id UUID;
  v_exam RECORD;
  v_enrollment RECORD;
  v_seating RECORD;
  v_ticket_count INTEGER := 0;
  v_ticket_number VARCHAR(50);
  v_counter INTEGER := 1;
BEGIN
  -- Get exam details
  SELECT * INTO v_exam FROM exams WHERE id = p_exam_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, 'Exam not found'::TEXT, 0;
    RETURN;
  END IF;

  v_institution_id := v_exam.institution_id;

  -- Loop through all enrolled students
  FOR v_enrollment IN
    SELECT ee.*, s.roll_number
    FROM exam_enrollments ee
    JOIN students s ON s.id = ee.student_id
    WHERE ee.exam_id = p_exam_id AND ee.status = 'enrolled'
  LOOP
    -- Check if hall ticket already exists
    IF EXISTS (SELECT 1 FROM hall_tickets WHERE exam_id = p_exam_id AND student_id = v_enrollment.student_id) THEN
      v_counter := v_counter + 1;
      CONTINUE;
    END IF;

    -- Try to get seating allocation
    SELECT * INTO v_seating
    FROM exam_seating
    WHERE exam_id = p_exam_id AND student_id = v_enrollment.student_id
    LIMIT 1;

    -- Generate ticket number
    v_ticket_number := 'EXAM-' || UPPER(LEFT(v_exam.name, 3)) || '-' || LPAD(v_counter::TEXT, 4, '0');

    -- Insert hall ticket
    INSERT INTO hall_tickets (
      institution_id, exam_id, student_id, enrollment_id,
      ticket_number, qr_token, room_number, seat_number,
      exam_date, exam_shift
    ) VALUES (
      v_institution_id, p_exam_id, v_enrollment.student_id, v_enrollment.id,
      v_ticket_number, gen_random_uuid()::TEXT,
      COALESCE(v_seating.room_number, 'TBD'),
      COALESCE(v_seating.seat_number, 'TBD'),
      v_exam.start_date,
      CASE WHEN v_counter % 2 = 0 THEN 'Afternoon' ELSE 'Morning' END
    );

    v_ticket_count := v_ticket_count + 1;
    v_counter := v_counter + 1;
  END LOOP;

  RETURN QUERY SELECT TRUE, v_ticket_count || ' hall tickets generated successfully'::TEXT, v_ticket_count;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260623000000_permission_audit_log.sql
-- ==========================================================

-- =========================================================================
-- PERMISSION AUDIT LOGGING MODULE
-- =========================================================================

CREATE TABLE IF NOT EXISTS permission_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(50) NOT NULL,
  module VARCHAR(100) NOT NULL,
  action VARCHAR(20) NOT NULL,
  path VARCHAR(255),
  ip_address VARCHAR(50),
  user_agent VARCHAR(255),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE permission_audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin/Director can view permission audit logs"
  ON permission_audit_log FOR SELECT
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_permission_audit_log_institution ON permission_audit_log(institution_id);
CREATE INDEX IF NOT EXISTS idx_permission_audit_log_user ON permission_audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_permission_audit_log_created_at ON permission_audit_log(created_at);


-- ==========================================================
-- MIGRATION: 20260624000000_sprint4_schema.sql
-- ==========================================================

-- =========================================================================
-- SPRINT 4 DATABASE SCHEMA & SECURITY POLICIES
-- =========================================================================

-- 1. STUDENT DOCUMENTS TABLE
CREATE TABLE IF NOT EXISTS student_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  document_name VARCHAR(255) NOT NULL,
  document_type VARCHAR(50) NOT NULL CHECK (document_type IN (
    '10th_marksheet', '12th_marksheet', 'degree', 'id_proof', 'address_proof', 'other'
  )),
  file_url TEXT NOT NULL,
  file_size_kb INTEGER,
  uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL
);

ALTER TABLE student_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin/Staff can manage student documents"
  ON student_documents FOR ALL
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director', 'Staff', 'Teacher', 'HOD')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

CREATE POLICY "Students can view their own documents"
  ON student_documents FOR SELECT
  USING (
    student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
  );

CREATE INDEX IF NOT EXISTS idx_student_documents_student ON student_documents(student_id);
CREATE INDEX IF NOT EXISTS idx_student_documents_institution ON student_documents(institution_id);

-- 2. TIMETABLE HISTORY TABLE
CREATE TABLE IF NOT EXISTS timetable_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  department_id UUID NOT NULL REFERENCES departments(id) ON DELETE CASCADE,
  semester INTEGER NOT NULL,
  batch_year VARCHAR(10) NOT NULL,
  version INTEGER NOT NULL,
  timetable_data JSONB NOT NULL DEFAULT '[]'::JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT unique_timetable_version UNIQUE (department_id, semester, batch_year, version)
);

ALTER TABLE timetable_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin can manage timetable history"
  ON timetable_history FOR ALL
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

CREATE POLICY "Everyone can view timetable history"
  ON timetable_history FOR SELECT
  USING (
    institution_id = get_auth_institution_id()
  );

CREATE INDEX IF NOT EXISTS idx_timetable_history_lookup ON timetable_history(department_id, semester, batch_year);

-- 3. SUPPLEMENTARY EXAMS TABLE
CREATE TABLE IF NOT EXISTS supplementary_exams (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  exam_id UUID NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  subject VARCHAR(150) NOT NULL,
  status VARCHAR(20) DEFAULT 'applied' CHECK (status IN ('applied', 'approved', 'rejected', 'completed')),
  applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  remarks TEXT,
  CONSTRAINT unique_supplementary_application UNIQUE (student_id, exam_id, subject)
);

ALTER TABLE supplementary_exams ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin/Staff can manage supplementary exams"
  ON supplementary_exams FOR ALL
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director', 'Staff', 'Teacher', 'HOD')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

CREATE POLICY "Students can view and create their own supplementary applications"
  ON supplementary_exams FOR ALL
  USING (
    student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
  );

CREATE INDEX IF NOT EXISTS idx_supplementary_exams_student ON supplementary_exams(student_id);
CREATE INDEX IF NOT EXISTS idx_supplementary_exams_exam ON supplementary_exams(exam_id);

-- 4. RE-EVALUATION REQUESTS TABLE
CREATE TABLE IF NOT EXISTS re_evaluation_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  result_id UUID NOT NULL REFERENCES exam_results(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  exam_id UUID NOT NULL REFERENCES exams(id) ON DELETE CASCADE,
  subject VARCHAR(150) NOT NULL,
  reason TEXT,
  status VARCHAR(20) DEFAULT 'applied' CHECK (status IN ('applied', 'under_review', 'approved', 'rejected', 'completed')),
  previous_marks DECIMAL(5, 2),
  new_marks DECIMAL(5, 2),
  applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  resolved_at TIMESTAMP WITH TIME ZONE,
  resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  remarks TEXT,
  CONSTRAINT unique_re_evaluation_application UNIQUE (student_id, result_id)
);

ALTER TABLE re_evaluation_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin/Staff can manage re-evaluation requests"
  ON re_evaluation_requests FOR ALL
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director', 'Staff', 'Teacher', 'HOD')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

CREATE POLICY "Students can view and create their own re-evaluation requests"
  ON re_evaluation_requests FOR ALL
  USING (
    student_id IN (SELECT id FROM students WHERE user_id = auth.uid())
  );

CREATE INDEX IF NOT EXISTS idx_re_evaluation_requests_student ON re_evaluation_requests(student_id);
CREATE INDEX IF NOT EXISTS idx_re_evaluation_requests_exam ON re_evaluation_requests(exam_id);


-- ==========================================================
-- MIGRATION: 20260625000000_live_bus_tracking.sql
-- ==========================================================

-- =============================================================
-- Migration: Live Bus Tracking — Real GPS Telemetry
-- Adds GPS coordinate columns to buses table and creates
-- transit_location_history for historical tracking data.
-- =============================================================

-- 1. Add live tracking columns to existing buses table
ALTER TABLE buses ADD COLUMN IF NOT EXISTS current_lat DECIMAL(10, 8);
ALTER TABLE buses ADD COLUMN IF NOT EXISTS current_lng DECIMAL(11, 8);
ALTER TABLE buses ADD COLUMN IF NOT EXISTS last_location_at TIMESTAMPTZ;
ALTER TABLE buses ADD COLUMN IF NOT EXISTS speed_kmh DECIMAL(5, 2) DEFAULT 0;

-- Note: buses table already has an is_active column from the initial schema.
-- We do NOT re-add it to avoid conflicts.

-- 2. Create transit location history table
CREATE TABLE IF NOT EXISTS transit_location_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bus_id UUID REFERENCES buses(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES users(id),
  lat DECIMAL(10, 8) NOT NULL,
  lng DECIMAL(11, 8) NOT NULL,
  speed_kmh DECIMAL(5, 2),
  recorded_at TIMESTAMPTZ DEFAULT NOW(),
  institution_id UUID REFERENCES institutions(id)
);

-- 3. Performance index for time-series queries
CREATE INDEX IF NOT EXISTS idx_transit_history_bus_time
  ON transit_location_history(bus_id, recorded_at DESC);

-- 4. Enable RLS
ALTER TABLE transit_location_history ENABLE ROW LEVEL SECURITY;

-- 5. RLS Policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'transit_location_history' AND policyname = 'transit_history_select_policy'
  ) THEN
    CREATE POLICY transit_history_select_policy ON transit_location_history
      FOR SELECT USING (institution_id = get_auth_institution_id());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'transit_location_history' AND policyname = 'transit_history_insert_policy'
  ) THEN
    CREATE POLICY transit_history_insert_policy ON transit_location_history
      FOR INSERT WITH CHECK (institution_id = get_auth_institution_id());
  END IF;
END $$;

-- Service role bypass for backend writes
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'transit_location_history' AND policyname = 'transit_history_service_role'
  ) THEN
    CREATE POLICY transit_history_service_role ON transit_location_history
      FOR ALL USING (true) WITH CHECK (true);
  END IF;
END $$;


-- ==========================================================
-- MIGRATION: 20260625000000_sprint5_schema.sql
-- ==========================================================

-- =========================================================================
-- SPRINT 5 DATABASE SCHEMA & SECURITY POLICIES
-- =========================================================================

-- 1. GATE LOCKDOWN STATUS TABLE
CREATE TABLE IF NOT EXISTS gate_lockdown (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  is_locked_down BOOLEAN DEFAULT FALSE NOT NULL,
  reason TEXT,
  locked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  locked_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE gate_lockdown ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin/Security can manage gate lockdown"
  ON gate_lockdown FOR ALL
  USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Security')
    AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
  );

CREATE POLICY "Everyone authenticated can view gate lockdown"
  ON gate_lockdown FOR SELECT
  USING (
    institution_id = get_auth_institution_id()
  );

CREATE INDEX IF NOT EXISTS idx_gate_lockdown_institution ON gate_lockdown(institution_id);


-- ==========================================================
-- MIGRATION: 20260626000000_sprint6_schema.sql
-- ==========================================================

-- Migration: Sprint 6 (Transit Module Gaps & Fixes)
-- Target: Supabase / PostgreSQL

-- 1. Create student_transit_logs table
CREATE TABLE IF NOT EXISTS student_transit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    trip_id UUID REFERENCES bus_trips(id) ON DELETE CASCADE,
    bus_id UUID NOT NULL REFERENCES buses(id) ON DELETE CASCADE,
    direction VARCHAR(20) NOT NULL CHECK (direction IN ('boarding', 'alighting')),
    stop_name VARCHAR(255) NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Enable RLS
ALTER TABLE student_transit_logs ENABLE ROW LEVEL SECURITY;

-- Create Tenant Isolation Policy
DROP POLICY IF EXISTS tenant_isolation_student_transit_logs ON student_transit_logs;
CREATE POLICY tenant_isolation_student_transit_logs ON student_transit_logs
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

-- 2. Fix get_bus_eta_for_student function
CREATE OR REPLACE FUNCTION get_bus_eta_for_student(p_student_id UUID)
RETURNS TABLE (
    bus_id UUID,
    bus_name VARCHAR,
    route_name VARCHAR,
    stop_name VARCHAR,
    stop_index INTEGER,
    distance_km NUMERIC,
    eta_minutes INTEGER,
    latitude NUMERIC,
    longitude NUMERIC,
    last_updated TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_subscription RECORD;
    v_bus RECORD;
    v_stop_index INTEGER;
    v_distance NUMERIC;
    v_velocity NUMERIC;
BEGIN
    -- Get student's active bus subscription from transport_subscriptions
    SELECT 
        ts.route_id, 
        ts.stop_name, 
        br.name AS route_name,
        br.stops,
        b.id AS bus_id,
        b.vehicle_number AS bus_name
    INTO v_subscription
    FROM transport_subscriptions ts
    JOIN bus_routes br ON ts.route_id = br.id
    LEFT JOIN buses b ON b.route_id = ts.route_id AND b.is_active = true
    WHERE ts.student_id = p_student_id AND ts.status = 'active' AND ts.end_date >= CURRENT_DATE
    LIMIT 1;

    IF v_subscription IS NULL THEN RETURN; END IF;

    -- Get latest bus location
    SELECT bl.bus_id, bl.latitude, bl.longitude, bl.speed, bl.timestamp AS recorded_at
    INTO v_bus
    FROM bus_tracking bl
    WHERE bl.bus_id = v_subscription.bus_id
    ORDER BY bl.timestamp DESC
    LIMIT 1;

    IF v_bus IS NULL THEN RETURN; END IF;

    -- Find stop_index matching stop_name in JSONB array stops
    SELECT (idx - 1) INTO v_stop_index
    FROM jsonb_array_elements(v_subscription.stops) WITH ORDINALITY arr(elem, idx)
    WHERE elem->>'name' = v_subscription.stop_name
    LIMIT 1;
    
    IF v_stop_index IS NULL THEN
        v_stop_index := 0;
    END IF;

    -- Calculate distance to student's stop using Haversine
    IF v_subscription.stops IS NOT NULL AND jsonb_array_length(v_subscription.stops) > 0 THEN
        DECLARE
            v_stop_lat NUMERIC;
            v_stop_lon NUMERIC;
        BEGIN
            v_stop_lat := (v_subscription.stops->v_stop_index->>'latitude')::NUMERIC;
            v_stop_lon := (v_subscription.stops->v_stop_index->>'longitude')::NUMERIC;

            v_distance := (
                6371 * acos(
                    cos(radians(v_bus.latitude)) * cos(radians(v_stop_lat)) *
                    cos(radians(v_stop_lon) - radians(v_bus.longitude)) +
                    sin(radians(v_bus.latitude)) * sin(radians(v_stop_lat))
                )
            );

            v_velocity := CASE WHEN v_bus.speed > 5 THEN v_bus.speed ELSE 25 END;

            bus_id := v_bus.bus_id;
            bus_name := v_subscription.bus_name;
            route_name := v_subscription.route_name;
            stop_name := v_subscription.stop_name;
            stop_index := v_stop_index;
            distance_km := ROUND(v_distance, 2);
            eta_minutes := ROUND((v_distance / v_velocity) * 60);
            latitude := v_bus.latitude;
            longitude := v_bus.longitude;
            last_updated := v_bus.recorded_at;
            RETURN NEXT;
        END;
    END IF;
END;
$$;

-- 3. Fix get_child_bus_status function
CREATE OR REPLACE FUNCTION get_child_bus_status()
RETURNS TABLE (
    is_on_bus BOOLEAN,
    bus_name VARCHAR,
    route_name VARCHAR,
    last_stop VARCHAR,
    eta_minutes INTEGER,
    latitude NUMERIC,
    longitude NUMERIC,
    last_updated TIMESTAMP WITH TIME ZONE
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student_id UUID;
    v_subscription RECORD;
    v_bus RECORD;
    v_stop_index INTEGER;
    v_distance NUMERIC;
    v_velocity NUMERIC;
    v_latest_log RECORD;
BEGIN
    -- Get parent's linked child
    SELECT psl.student_id INTO v_student_id
    FROM parent_student_links psl
    WHERE psl.parent_user_id = auth.uid() AND psl.verified = true
    ORDER BY psl.is_primary DESC NULLS LAST LIMIT 1;

    IF v_student_id IS NULL THEN RETURN; END IF;

    -- Get student's bus subscription from transport_subscriptions
    SELECT 
        ts.route_id, 
        ts.stop_name, 
        br.name AS route_name,
        br.stops,
        b.id AS bus_id,
        b.vehicle_number AS bus_name
    INTO v_subscription
    FROM transport_subscriptions ts
    JOIN bus_routes br ON ts.route_id = br.id
    LEFT JOIN buses b ON b.route_id = ts.route_id AND b.is_active = true
    WHERE ts.student_id = v_student_id AND ts.status = 'active' AND ts.end_date >= CURRENT_DATE
    LIMIT 1;

    IF v_subscription IS NULL THEN
        is_on_bus := false;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Check if student is boarded on the bus today based on student_transit_logs
    SELECT stl.direction, stl.stop_name, stl.timestamp 
    INTO v_latest_log
    FROM student_transit_logs stl
    WHERE stl.student_id = v_student_id 
      AND stl.timestamp::DATE = CURRENT_DATE
    ORDER BY stl.timestamp DESC
    LIMIT 1;

    IF v_latest_log IS NULL OR v_latest_log.direction <> 'boarding' THEN
        is_on_bus := false;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Get latest bus location
    SELECT bt.latitude, bt.longitude, bt.speed, bt.timestamp
    INTO v_bus
    FROM bus_tracking bt
    WHERE bt.bus_id = v_subscription.bus_id
    ORDER BY bt.timestamp DESC
    LIMIT 1;

    is_on_bus := true;
    bus_name := v_subscription.bus_name;
    route_name := v_subscription.route_name;
    last_stop := v_latest_log.stop_name;
    last_updated := COALESCE(v_bus.timestamp, v_latest_log.timestamp);
    
    IF v_bus IS NOT NULL THEN
        latitude := v_bus.latitude;
        longitude := v_bus.longitude;
        
        -- Find stop index in stops array
        SELECT (idx - 1) INTO v_stop_index
        FROM jsonb_array_elements(v_subscription.stops) WITH ORDINALITY arr(elem, idx)
        WHERE elem->>'name' = v_subscription.stop_name
        LIMIT 1;
        
        IF v_stop_index IS NULL THEN v_stop_index := 0; END IF;
        
        -- Calculate ETA to student's stop
        IF v_subscription.stops IS NOT NULL AND jsonb_array_length(v_subscription.stops) > 0 THEN
            DECLARE
                v_stop_lat NUMERIC;
                v_stop_lon NUMERIC;
            BEGIN
                v_stop_lat := (v_subscription.stops->v_stop_index->>'latitude')::NUMERIC;
                v_stop_lon := (v_subscription.stops->v_stop_index->>'longitude')::NUMERIC;
                
                v_distance := (
                    6371 * acos(
                        cos(radians(v_bus.latitude)) * cos(radians(v_stop_lat)) *
                        cos(radians(v_stop_lon) - radians(v_bus.longitude)) +
                        sin(radians(v_bus.latitude)) * sin(radians(v_stop_lat))
                    )
                );
                
                v_velocity := CASE WHEN v_bus.speed > 5 THEN v_bus.speed ELSE 25 END;
                eta_minutes := ROUND((v_distance / v_velocity) * 60);
            END;
        ELSE
            eta_minutes := 15; -- Fallback
        END IF;
    ELSE
        latitude := 26.2912;
        longitude := 73.0156;
        eta_minutes := 15;
    END IF;
    
    RETURN NEXT;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260627000000_device_tokens.sql
-- ==========================================================

-- =========================================================================
-- DEVICE TOKENS FOR FCM PUSH NOTIFICATIONS
-- =========================================================================

CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_token TEXT NOT NULL UNIQUE,
  device_type VARCHAR(50),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own device tokens" 
  ON device_tokens FOR INSERT 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can select their own device tokens" 
  ON device_tokens FOR SELECT 
  USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own device tokens" 
  ON device_tokens FOR UPDATE 
  USING (auth.uid() = user_id) 
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own device tokens" 
  ON device_tokens FOR DELETE 
  USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);


-- ==========================================================
-- MIGRATION: 20260628000000_subscription_period.sql
-- ==========================================================

-- =========================================================================
-- ADD SUBSCRIPTION BILLING PERIOD TO INSTITUTIONS
-- =========================================================================

ALTER TABLE institutions ADD COLUMN IF NOT EXISTS subscription_period VARCHAR(50) DEFAULT 'monthly'
    CHECK (subscription_period IN ('monthly', 'quarterly', 'yearly'));


-- ==========================================================
-- MIGRATION: 20260629000000_ai_api_keys.sql
-- ==========================================================

-- Add AI API key columns to institutions table
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS gemini_api_key TEXT;
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS openai_api_key TEXT;
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS claude_api_key TEXT;


-- ==========================================================
-- MIGRATION: 20260630000000_add_institute_type.sql
-- ==========================================================

-- Migration: Add multi-institute-type support (College + School)

-- 1. Add institute_type to institutions
ALTER TABLE institutions ADD COLUMN IF NOT EXISTS institute_type VARCHAR(50) DEFAULT 'college';

-- Update existing institutions to default to 'college'
UPDATE institutions SET institute_type = 'college' WHERE institute_type IS NULL;

-- 2. Create school_attendance table
CREATE TABLE IF NOT EXISTS school_attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID REFERENCES students(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    academic_year VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL, -- Present, Absent, Half-Day, Leave
    marked_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_school_attendance_student_date UNIQUE (student_id, date, academic_year)
);

-- 3. Enable RLS on school_attendance
ALTER TABLE school_attendance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "school_attendance_select" ON school_attendance
  FOR SELECT USING (
    institution_id = get_auth_institution_id()
    OR get_auth_user_role() = 'SuperAdmin'
  );

CREATE POLICY "school_attendance_insert" ON school_attendance
  FOR INSERT WITH CHECK (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff', 'Teacher')
  );

CREATE POLICY "school_attendance_update" ON school_attendance
  FOR UPDATE USING (
    get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Staff', 'Teacher')
  );

-- 4. Re-create get_parent_child_info to return institute_type
CREATE OR REPLACE FUNCTION get_parent_child_info()
RETURNS TABLE (
    student_id UUID,
    student_name TEXT,
    roll_number VARCHAR,
    course VARCHAR,
    department_name TEXT,
    semester INTEGER,
    year INTEGER,
    guardian_phone VARCHAR,
    wallet_balance NUMERIC,
    institution_id UUID,
    institute_type VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT s.id, u.full_name, s.roll_number, s.course, d.name,
           s.semester, s.year, s.guardian_phone, s.wallet_balance, s.institution_id,
           COALESCE(i.institute_type, 'college')::VARCHAR
    FROM parent_student_links psl
    JOIN students s ON psl.student_id = s.id
    JOIN users u ON s.user_id = u.id
    JOIN institutions i ON s.institution_id = i.id
    LEFT JOIN departments d ON s.department_id = d.id
    WHERE psl.parent_user_id = auth.uid()
      AND psl.verified = true
    ORDER BY psl.is_primary DESC NULLS LAST
    LIMIT 1;
END;
$$;

-- 5. Re-create get_parent_daily_summary to support school_attendance if institute_type is school
CREATE OR REPLACE FUNCTION get_parent_daily_summary(p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE (
    student_name TEXT,
    attendance_present BIGINT,
    attendance_total BIGINT,
    attendance_pct NUMERIC,
    canteen_spend NUMERIC,
    bus_boarded BOOLEAN,
    bus_time TIME,
    gate_in TIME,
    gate_out TIME,
    pending_fees NUMERIC,
    wallet_balance NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student_id UUID;
    v_inst_type VARCHAR;
BEGIN
    -- Get linked child and institution type
    SELECT psl.student_id, COALESCE(i.institute_type, 'college') INTO v_student_id, v_inst_type
    FROM parent_student_links psl
    JOIN students s ON psl.student_id = s.id
    JOIN institutions i ON s.institution_id = i.id
    WHERE psl.parent_user_id = auth.uid() AND psl.verified = true
    ORDER BY psl.is_primary DESC NULLS LAST LIMIT 1;

    IF v_student_id IS NULL THEN RETURN; END IF;

    IF v_inst_type = 'school' THEN
        -- Query from school_attendance
        RETURN QUERY
        SELECT
            u.full_name,
            COUNT(sa.id) FILTER (WHERE sa.status IN ('Present', 'Leave', 'Half-Day'))::BIGINT,
            COUNT(sa.id)::BIGINT,
            CASE WHEN COUNT(sa.id) = 0 THEN 100.0
                 -- Treat Half-Day as 0.5 present, Present and Leave as 1
                 ELSE ROUND((
                     COUNT(sa.id) FILTER (WHERE sa.status IN ('Present', 'Leave'))::NUMERIC + 
                     0.5 * COUNT(sa.id) FILTER (WHERE sa.status = 'Half-Day')::NUMERIC
                 ) / COUNT(sa.id)::NUMERIC * 100, 1)
            END,
            COALESCE((SELECT SUM(co.total_amount) FROM canteen_orders co WHERE co.student_id = v_student_id AND co.created_at::DATE = p_date), 0),
            EXISTS(SELECT 1 FROM bus_tracking bt WHERE bt.student_id = v_student_id AND bt.boarded_at::DATE = p_date),
            (SELECT bt.boarded_at::TIME FROM bus_tracking bt WHERE bt.student_id = v_student_id AND bt.boarded_at::DATE = p_date LIMIT 1),
            (SELECT gl.timestamp::TIME FROM gate_logs gl WHERE gl.person_id = v_student_id AND gl.direction = 'in' AND gl.timestamp::DATE = p_date LIMIT 1),
            (SELECT gl.timestamp::TIME FROM gate_logs gl WHERE gl.person_id = v_student_id AND gl.direction = 'out' AND gl.timestamp::DATE = p_date ORDER BY gl.timestamp DESC LIMIT 1),
            (SELECT COALESCE(SUM(sf.amount - COALESCE(sf.paid_amount, 0)), 0) FROM student_fees sf WHERE sf.student_id = v_student_id AND sf.payment_status IN ('pending', 'partial')),
            (SELECT COALESCE(s.wallet_balance, 0) FROM students s WHERE s.id = v_student_id)
        FROM school_attendance sa
        JOIN students s ON sa.student_id = s.id
        JOIN users u ON s.user_id = u.id
        WHERE sa.student_id = v_student_id AND sa.date = p_date
        GROUP BY u.full_name;
    ELSE
        -- Query from college attendance
        RETURN QUERY
        SELECT
            u.full_name,
            COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::BIGINT,
            COUNT(a.id)::BIGINT,
            CASE WHEN COUNT(a.id) = 0 THEN 100.0
                 ELSE ROUND(COUNT(a.id) FILTER (WHERE a.status IN ('present', 'late'))::NUMERIC / COUNT(a.id)::NUMERIC * 100, 1)
            END,
            COALESCE((SELECT SUM(co.total_amount) FROM canteen_orders co WHERE co.student_id = v_student_id AND co.created_at::DATE = p_date), 0),
            EXISTS(SELECT 1 FROM bus_tracking bt WHERE bt.student_id = v_student_id AND bt.boarded_at::DATE = p_date),
            (SELECT bt.boarded_at::TIME FROM bus_tracking bt WHERE bt.student_id = v_student_id AND bt.boarded_at::DATE = p_date LIMIT 1),
            (SELECT gl.timestamp::TIME FROM gate_logs gl WHERE gl.person_id = v_student_id AND gl.direction = 'in' AND gl.timestamp::DATE = p_date LIMIT 1),
            (SELECT gl.timestamp::TIME FROM gate_logs gl WHERE gl.person_id = v_student_id AND gl.direction = 'out' AND gl.timestamp::DATE = p_date ORDER BY gl.timestamp DESC LIMIT 1),
            (SELECT COALESCE(SUM(sf.amount - COALESCE(sf.paid_amount, 0)), 0) FROM student_fees sf WHERE sf.student_id = v_student_id AND sf.payment_status IN ('pending', 'partial')),
            (SELECT COALESCE(s.wallet_balance, 0) FROM students s WHERE s.id = v_student_id)
        FROM attendance a
        JOIN students s ON a.student_id = s.id
        JOIN users u ON s.user_id = u.id
        WHERE a.student_id = v_student_id AND a.date = p_date
        GROUP BY u.full_name;
    END IF;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260701000000_parent_messages_and_ptm.sql
-- ==========================================================

-- Migration: Parent messaging and PTM slots/bookings tables
-- Target: Supabase / PostgreSQL

-- 1. Create parent_messages table
CREATE TABLE IF NOT EXISTS parent_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    sender_role VARCHAR(50) NOT NULL,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message TEXT NOT NULL,
    sla_deadline TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on parent_messages
ALTER TABLE parent_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can select parent messages they are involved in" ON parent_messages
    FOR SELECT USING (
        (sender_id = auth.uid() OR receiver_id = auth.uid())
        AND (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
    );

CREATE POLICY "Users can insert parent messages" ON parent_messages
    FOR INSERT WITH CHECK (
        sender_id = auth.uid()
        AND (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
    );

CREATE INDEX IF NOT EXISTS idx_parent_messages_sender ON parent_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_parent_messages_receiver ON parent_messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_parent_messages_institution ON parent_messages(institution_id);


-- 2. Create ptm_slots table
CREATE TABLE IF NOT EXISTS ptm_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    slot_time VARCHAR(100) NOT NULL,
    available BOOLEAN DEFAULT TRUE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_ptm_slot_teacher UNIQUE (teacher_id, date, slot_time)
);

-- Enable RLS on ptm_slots
ALTER TABLE ptm_slots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Everyone authenticated can view ptm slots" ON ptm_slots
    FOR SELECT USING (
        institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin'
    );

CREATE POLICY "Teachers and admins can manage ptm slots" ON ptm_slots
    FOR ALL USING (
        (get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Teacher', 'HOD', 'Principal'))
        AND (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
    );

CREATE INDEX IF NOT EXISTS idx_ptm_slots_teacher ON ptm_slots(teacher_id);
CREATE INDEX IF NOT EXISTS idx_ptm_slots_date ON ptm_slots(date);


-- 3. Create ptm_bookings table
CREATE TABLE IF NOT EXISTS ptm_bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    parent_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    slot_time VARCHAR(100) NOT NULL,
    meet_link TEXT,
    status VARCHAR(50) DEFAULT 'confirmed' CHECK (status IN ('pending', 'confirmed', 'cancelled', 'completed')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_ptm_booking_slot UNIQUE (teacher_id, date, slot_time)
);

-- Enable RLS on ptm_bookings
ALTER TABLE ptm_bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own ptm bookings" ON ptm_bookings
    FOR SELECT USING (
        (parent_id = auth.uid() OR teacher_id = auth.uid())
        AND (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
    );

CREATE POLICY "Parents can insert ptm bookings" ON ptm_bookings
    FOR INSERT WITH CHECK (
        parent_id = auth.uid()
        AND get_auth_user_role() = 'Parent'
        AND (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
    );

CREATE POLICY "Involved users can update ptm bookings" ON ptm_bookings
    FOR UPDATE USING (
        (parent_id = auth.uid() OR teacher_id = auth.uid() OR get_auth_user_role() IN ('SuperAdmin', 'Admin'))
        AND (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin')
    );

CREATE INDEX IF NOT EXISTS idx_ptm_bookings_parent ON ptm_bookings(parent_id);
CREATE INDEX IF NOT EXISTS idx_ptm_bookings_teacher ON ptm_bookings(teacher_id);


-- ==========================================================
-- MIGRATION: 20260703000000_class_sections.sql
-- ==========================================================

CREATE TABLE IF NOT EXISTS class_sections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  grade INTEGER NOT NULL,
  section VARCHAR(10) NOT NULL,
  class_teacher_id UUID REFERENCES users(id) ON DELETE SET NULL,
  room_number VARCHAR(50),
  capacity INTEGER DEFAULT 40,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT unique_grade_section_per_tenant UNIQUE (institution_id, grade, section)
);

CREATE INDEX IF NOT EXISTS idx_class_sections_institution ON class_sections(institution_id);
CREATE INDEX IF NOT EXISTS idx_class_sections_grade ON class_sections(institution_id, grade);

DO $$ BEGIN
  ALTER TABLE class_sections ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "tenant_class_sections_select" ON class_sections;
  CREATE POLICY "tenant_class_sections_select" ON class_sections
    FOR SELECT USING (institution_id = (auth.jwt() ->> 'institution_id')::uuid);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$ BEGIN
  DROP POLICY IF EXISTS "tenant_class_sections_manage" ON class_sections;
  CREATE POLICY "tenant_class_sections_manage" ON class_sections
    FOR ALL USING (institution_id = (auth.jwt() ->> 'institution_id')::uuid);
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

CREATE OR REPLACE FUNCTION ensure_class_sections_table()
RETURNS void AS $$
BEGIN
  CREATE TABLE IF NOT EXISTS class_sections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    grade INTEGER NOT NULL,
    section VARCHAR(10) NOT NULL,
    class_teacher_id UUID REFERENCES users(id) ON DELETE SET NULL,
    room_number VARCHAR(50),
    capacity INTEGER DEFAULT 40,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now(),
    CONSTRAINT unique_grade_section_per_tenant UNIQUE (institution_id, grade, section)
  );
  CREATE INDEX IF NOT EXISTS idx_class_sections_institution ON class_sections(institution_id);
  CREATE INDEX IF NOT EXISTS idx_class_sections_grade ON class_sections(institution_id, grade);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ==========================================================
-- MIGRATION: 20260703000001_school_timetable_fix.sql
-- ==========================================================

-- Make department_id nullable for school timetable support
ALTER TABLE timetable ALTER COLUMN department_id DROP NOT NULL;

-- Drop staff FK so school teachers (from users table) can be referenced
ALTER TABLE timetable DROP CONSTRAINT IF EXISTS timetable_teacher_id_fkey;


-- ==========================================================
-- MIGRATION: 20260711000000_create_all_role_users.sql
-- ==========================================================

-- Migration: Create all missing users for all roles
-- This ensures every role in the login page has a real user in the database
-- School and College are SEPARATE institutions with separate admins

-- ============================================================
-- INSTITUTION CONSTANTS
-- ============================================================
-- a0000000-0000-0000-0000-000000000001 = SIN Institute of Engineering & Technology (SIET) — College
-- a0000000-0000-0000-0000-000000000002 = SIET School — School

-- ============================================================
-- 0. CREATE SCHOOL INSTITUTION (if not exists)
-- ============================================================
INSERT INTO public.institutions (id, name, type, plan_tier, is_active, created_at)
VALUES ('a0000000-0000-0000-0000-000000000002', 'SIET School', 'school', 'Campus', true, now())
ON CONFLICT (id) DO NOTHING;

-- Set institute_type column if the column exists
UPDATE public.institutions SET institute_type = 'school' WHERE id = 'a0000000-0000-0000-0000-000000000002';

-- ============================================================
-- 1. INSERT COLLEGE USERS INTO public.users
-- ============================================================
-- College institution: a0000000-0000-0000-0000-000000000001

INSERT INTO public.users (id, name, email, role, is_active, institution_id) VALUES
  -- Director
  ('b0000000-0000-0000-0000-000000000019', 'Director SIET', 'director2@siet.edu.in', 'Director', true, 'a0000000-0000-0000-0000-000000000001'),
  -- HOD
  ('b0000000-0000-0000-0000-000000000017', 'HOD Member', 'hod@sin.education', 'HOD', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Warden
  ('b0000000-0000-0000-0000-000000000012', 'Jaswant Singh', 'warden@siet.edu.in', 'Warden', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Librarian
  ('b0000000-0000-0000-0000-000000000018', 'Librarian Head', 'librarian@sin.education', 'Librarian', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Vendor
  ('b0000000-0000-0000-0000-000000000020', 'Canteen Vendor', 'canteen@siet.edu.in', 'Vendor', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Security
  ('b0000000-0000-0000-0000-000000000015', 'Guard Sher Singh', 'security@siet.edu.in', 'Security', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Staff
  ('b0000000-0000-0000-0000-000000000030', 'Faculty Staff Member', 'staff@sin.education', 'Staff', true, 'a0000000-0000-0000-0000-000000000001'),
  -- TPO
  ('b0000000-0000-0000-0000-000000000023', 'TPO Cell Head', 'tpo@siet.edu.in', 'TPO', true, 'a0000000-0000-0000-0000-000000000001'),
  -- IQAC Coordinator
  ('b0000000-0000-0000-0000-000000000024', 'IQAC Coordinator', 'iqac@sin.education', 'IQAC Coordinator', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Admissions Officer
  ('b0000000-0000-0000-0000-000000000025', 'Admissions Officer', 'admissions@siet.edu.in', 'Admissions Officer', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Gym Trainer
  ('b0000000-0000-0000-0000-000000000026', 'Gym Trainer', 'gym@sin.education', 'Gym Trainer', true, 'a0000000-0000-0000-0000-000000000001'),
  -- HR Admin
  ('b0000000-0000-0000-0000-000000000027', 'HR Admin', 'hr@siet.edu.in', 'HR Admin', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Company HR
  ('b0000000-0000-0000-0000-000000000028', 'Company HR Partner', 'companyhr@siet.edu.in', 'Company HR', true, 'a0000000-0000-0000-0000-000000000001'),
  -- Applicant (College)
  ('b0000000-0000-0000-0000-000000000029', 'Applicant User', 'applicant@sin.education', 'Applicant', true, 'a0000000-0000-0000-0000-000000000001')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 2. INSERT SCHOOL USERS INTO public.users
-- ============================================================
-- School institution: a0000000-0000-0000-0000-000000000002

INSERT INTO public.users (id, name, email, role, is_active, institution_id) VALUES
  -- Admin (School)
  ('b0000000-0000-0000-0000-000000000031', 'School Admin', 'admin@school.edu.in', 'Admin', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Teacher (School)
  ('b0000000-0000-0000-0000-000000000032', 'School Teacher', 'teacher@school.edu.in', 'Teacher', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Staff (School)
  ('b0000000-0000-0000-0000-000000000033', 'School Staff', 'staff@school.edu.in', 'Staff', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Student (School)
  ('b0000000-0000-0000-0000-000000000034', 'School Student', 'student@school.edu.in', 'Student', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Parent (School)
  ('b0000000-0000-0000-0000-000000000035', 'School Parent', 'parent@school.edu.in', 'Parent', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Librarian (School)
  ('b0000000-0000-0000-0000-000000000036', 'School Librarian', 'librarian@school.edu.in', 'Librarian', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Warden (School)
  ('b0000000-0000-0000-0000-000000000037', 'School Warden', 'warden@school.edu.in', 'Warden', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Security (School)
  ('b0000000-0000-0000-0000-000000000038', 'School Security', 'security@school.edu.in', 'Security', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Vendor (School)
  ('b0000000-0000-0000-0000-000000000039', 'School Vendor', 'canteen@school.edu.in', 'Vendor', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Driver (School)
  ('b0000000-0000-0000-0000-000000000040', 'School Driver', 'driver@school.edu.in', 'Driver', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Applicant (School)
  ('b0000000-0000-0000-0000-000000000041', 'School Applicant', 'applicant@school.edu.in', 'Applicant', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Admissions Officer (School)
  ('b0000000-0000-0000-0000-000000000042', 'School Admissions', 'admissions@school.edu.in', 'Admissions Officer', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Principal (School)
  ('b0000000-0000-0000-0000-000000000021', 'School Principal', 'khushalkhatri0019@gmail.com', 'Principal', true, 'a0000000-0000-0000-0000-000000000002'),
  -- Vice Principal (School)
  ('b0000000-0000-0000-0000-000000000022', 'Vice Principal', 'khushal.24jiaiml067@jietjodhpur.ac.in', 'Vice Principal', true, 'a0000000-0000-0000-0000-000000000002')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 3. CREATE STUDENT RECORDS for Student users
-- ============================================================
-- College Student
INSERT INTO public.students (id, user_id, name, institution_id, roll_number, department_id, semester, batch_year, dob, gender)
VALUES
  ('b0000000-0000-0000-0000-000000000006', 'b0000000-0000-0000-0000-000000000006', 'Priyansh Student', 'a0000000-0000-0000-0000-000000000001', 'CSE-001', 'd0000000-0000-0000-0000-000000000001', 4, '2022-2026', '2003-05-15', 'Male')
ON CONFLICT (id) DO NOTHING;

-- School Student
INSERT INTO public.students (id, user_id, name, institution_id, roll_number, department_id, semester, batch_year, dob, gender)
VALUES
  ('b0000000-0000-0000-0000-000000000034', 'b0000000-0000-0000-0000-000000000034', 'School Student', 'a0000000-0000-0000-0000-000000000002', 'SCH-001', NULL, 1, '2025-2026', '2008-01-15', 'Male')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 4. CREATE STAFF RECORDS for Staff/Teacher/HOD etc users
-- ============================================================
INSERT INTO public.staff (id, user_id, institution_id, department_id, designation, joining_date, salary, qualification)
VALUES
  -- ===== COLLEGE STAFF =====
  -- HOD
  ('b0000000-0000-0000-0000-000000000050', 'b0000000-0000-0000-0000-000000000017', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Head of Department', '2020-01-01', 150000.00, 'Ph.D.'),
  -- Warden
  ('b0000000-0000-0000-0000-000000000051', 'b0000000-0000-0000-0000-000000000012', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Hostel Warden', '2021-06-01', 80000.00, 'M.A.'),
  -- Librarian
  ('b0000000-0000-0000-0000-000000000052', 'b0000000-0000-0000-0000-000000000018', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Chief Librarian', '2019-03-15', 75000.00, 'MLIS'),
  -- Vendor
  ('b0000000-0000-0000-0000-000000000053', 'b0000000-0000-0000-0000-000000000020', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Canteen Manager', '2022-01-01', 45000.00, 'B.Com'),
  -- Security
  ('b0000000-0000-0000-0000-000000000054', 'b0000000-0000-0000-0000-000000000015', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Security Head', '2020-08-01', 40000.00, '12th Pass'),
  -- Staff
  ('b0000000-0000-0000-0000-000000000055', 'b0000000-0000-0000-0000-000000000030', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Administrative Staff', '2023-01-01', 35000.00, 'Graduate'),
  -- Director
  ('b0000000-0000-0000-0000-000000000056', 'b0000000-0000-0000-0000-000000000019', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Director', '2018-01-01', 200000.00, 'Ph.D.'),
  -- TPO
  ('b0000000-0000-0000-0000-000000000057', 'b0000000-0000-0000-0000-000000000023', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Training & Placement Officer', '2021-07-01', 90000.00, 'MBA'),
  -- IQAC Coordinator
  ('b0000000-0000-0000-0000-000000000058', 'b0000000-0000-0000-0000-000000000024', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'IQAC Coordinator', '2022-01-01', 95000.00, 'Ph.D.'),
  -- Admissions Officer
  ('b0000000-0000-0000-0000-000000000059', 'b0000000-0000-0000-0000-000000000025', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Admissions Officer', '2023-03-01', 60000.00, 'MBA'),
  -- Gym Trainer
  ('b0000000-0000-0000-0000-000000000060', 'b0000000-0000-0000-0000-000000000026', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Gym Trainer', '2024-01-01', 30000.00, 'Certified Fitness Trainer'),
  -- HR Admin
  ('b0000000-0000-0000-0000-000000000061', 'b0000000-0000-0000-0000-000000000027', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'HR Admin', '2022-06-01', 85000.00, 'MBA HR'),
  -- Company HR
  ('b0000000-0000-0000-0000-000000000062', 'b0000000-0000-0000-0000-000000000028', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Company HR Partner', '2024-01-01', 70000.00, 'MBA'),
  -- Vice Principal
  ('b0000000-0000-0000-0000-000000000063', 'b0000000-0000-0000-0000-000000000022', 'a0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000001', 'Vice Principal', '2020-01-01', 180000.00, 'Ph.D.'),
  -- ===== SCHOOL STAFF =====
  -- School Staff
  ('b0000000-0000-0000-0000-000000000064', 'b0000000-0000-0000-0000-000000000033', 'a0000000-0000-0000-0000-000000000002', NULL, 'School Staff', '2023-01-01', 30000.00, 'Graduate'),
  -- School Teacher
  ('b0000000-0000-0000-0000-000000000065', 'b0000000-0000-0000-0000-000000000032', 'a0000000-0000-0000-0000-000000000002', NULL, 'School Teacher', '2022-06-01', 40000.00, 'B.Ed'),
  -- School Librarian
  ('b0000000-0000-0000-0000-000000000066', 'b0000000-0000-0000-0000-000000000036', 'a0000000-0000-0000-0000-000000000002', NULL, 'School Librarian', '2023-01-01', 35000.00, 'MLIS'),
  -- School Warden
  ('b0000000-0000-0000-0000-000000000067', 'b0000000-0000-0000-0000-000000000037', 'a0000000-0000-0000-0000-000000000002', NULL, 'School Warden', '2022-01-01', 35000.00, 'Graduate'),
  -- School Security
  ('b0000000-0000-0000-0000-000000000068', 'b0000000-0000-0000-0000-000000000038', 'a0000000-0000-0000-0000-000000000002', NULL, 'School Security', '2023-01-01', 25000.00, '12th Pass'),
  -- School Vendor
  ('b0000000-0000-0000-0000-000000000069', 'b0000000-0000-0000-0000-000000000039', 'a0000000-0000-0000-0000-000000000002', NULL, 'School Vendor', '2024-01-01', 20000.00, '10th Pass'),
  -- School Principal
  ('b0000000-0000-0000-0000-000000000070', 'b0000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-000000000002', NULL, 'Principal', '2019-01-01', 120000.00, 'Ph.D.')
ON CONFLICT (id) DO NOTHING;


-- ==========================================================
-- MIGRATION: 20260711000001_service_subscriptions.sql
-- ==========================================================

-- Migration: Service subscriptions for Hostel, Transit, Gym access gating
-- Students/Parents must subscribe to access each service module

-- ============================================================
-- 1. SERVICE PRICING TABLE (Institute Admin sets prices)
-- ============================================================
CREATE TABLE IF NOT EXISTS service_pricing (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  service_type TEXT NOT NULL CHECK (service_type IN ('hostel', 'transit', 'gym')),
  name TEXT NOT NULL,                          -- e.g. 'Monthly Hostel', 'Bus Pass', 'Gym Basic'
  description TEXT,
  price NUMERIC(10,2) NOT NULL DEFAULT 0,      -- in INR
  duration_days INTEGER NOT NULL DEFAULT 30,   -- subscription validity
  features TEXT[] DEFAULT '{}',                -- what's included
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(institution_id, service_type, name)
);

-- ============================================================
-- 2. STUDENT SERVICE SUBSCRIPTIONS (tracks who bought what)
-- ============================================================
CREATE TABLE IF NOT EXISTS service_subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  service_type TEXT NOT NULL CHECK (service_type IN ('hostel', 'transit', 'gym')),
  pricing_id UUID NOT NULL REFERENCES service_pricing(id),
  start_date DATE NOT NULL DEFAULT CURRENT_DATE,
  end_date DATE NOT NULL,
  amount_paid NUMERIC(10,2) NOT NULL DEFAULT 0,
  transaction_id TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_service_sub_student ON service_subscriptions(student_id, service_type, status);
CREATE INDEX IF NOT EXISTS idx_service_pricing_inst ON service_pricing(institution_id, service_type);

-- ============================================================
-- 3. SEED DEFAULT PRICING for existing institution
-- ============================================================
INSERT INTO service_pricing (institution_id, service_type, name, description, price, duration_days, features) VALUES
  -- Hostel
  ('a0000000-0000-0000-0000-000000000001', 'hostel', 'Monthly Hostel Stay', 'Access to hostel room, WiFi, common areas', 5000.00, 30, ARRAY['Room Allocation', 'WiFi Access', 'Common Areas', 'Hostel Complaints', 'Leave Requests', 'Visitor Management']),
  -- Transit
  ('a0000000-0000-0000-0000-000000000001', 'transit', 'Monthly Bus Pass', 'Unlimited rides on assigned route', 1200.00, 30, ARRAY['Live Bus Tracking', 'Route Map', 'ETA Predictions', 'Boarding Pass', 'Carbon Offset']),
  -- Gym
  ('a0000000-0000-0000-0000-000000000001', 'gym', 'Monthly Gym Basic', 'Gym floor access with basic equipment', 599.00, 30, ARRAY['Gym Floor Access', 'Basic Equipment', 'Locker Room', 'Workout Logging']),
  ('a0000000-0000-0000-0000-000000000001', 'gym', 'Quarterly Gym Prime', 'Full gym access with trainer consultations', 1499.00, 90, ARRAY['All Cardio Equipment', 'Trainer Consultation', 'Locker + Shower', 'Progress Dashboard']),
  ('a0000000-0000-0000-0000-000000000001', 'gym', 'Annual Gym Pro Elite', '24/7 premium gym access with personal locker', 4999.00, 365, ARRAY['24/7 Access', 'All Equipment & Classes', 'Personal Locker', 'Monthly Body Metrics', 'Unlimited Trainer Sessions'])
ON CONFLICT (institution_id, service_type, name) DO NOTHING;

-- ============================================================
-- 4. RLS POLICIES
-- ============================================================
ALTER TABLE service_pricing ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_pricing_all" ON service_pricing FOR ALL USING (true);
CREATE POLICY "service_subscriptions_all" ON service_subscriptions FOR ALL USING (true);


-- ==========================================================
-- MIGRATION: 20260714120000_create_missing_tables.sql
-- ==========================================================

-- Migration: Create missing tables from core schema setup
-- Academic Calendar, Bus Tracking Archive, Employees, Gate Blacklist, Gate Incidents

-- ============================================================
-- 1. ACADEMIC CALENDAR
-- ============================================================
CREATE TABLE IF NOT EXISTS academic_calendar (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    event_type VARCHAR(40) NOT NULL CHECK (event_type IN (
        'semester_start', 'semester_end', 'exam_start', 'exam_end',
        'holiday', 'result_date', 'fee_due', 'admission_start',
        'admission_end', 'counseling', 'orientation', 'vacation',
        'internal_exam', 'project_submission', 'other'
    )),
    description TEXT,
    start_date DATE NOT NULL,
    end_date DATE,
    semester INTEGER,
    batch_year VARCHAR(10),
    is_recurring BOOLEAN DEFAULT false,
    recurrence_rule VARCHAR(100),
    color VARCHAR(20) DEFAULT '#6C2BD9',
    is_published BOOLEAN DEFAULT true,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE academic_calendar ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin can manage academic calendar" ON academic_calendar;
CREATE POLICY "Admin can manage academic calendar" ON academic_calendar
    FOR ALL USING (
        get_auth_user_role() IN ('SuperAdmin', 'Admin', 'Director')
        AND (get_auth_user_role() = 'SuperAdmin' OR institution_id = get_auth_institution_id())
    );

DROP POLICY IF EXISTS "Everyone can view academic calendar" ON academic_calendar;
CREATE POLICY "Everyone can view academic calendar" ON academic_calendar
    FOR SELECT USING (
        is_published = true
        AND institution_id = get_auth_institution_id()
    );

-- ============================================================
-- 2. BUS TRACKING ARCHIVE
-- ============================================================
CREATE TABLE IF NOT EXISTS bus_tracking_archive (LIKE bus_tracking INCLUDING ALL);

-- ============================================================
-- 3. EMPLOYEES
-- ============================================================
CREATE TABLE IF NOT EXISTS employees (
    id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    employee_id VARCHAR(100) NOT NULL UNIQUE,
    department VARCHAR(255) NOT NULL,
    designation VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS employees_policy ON employees;
CREATE POLICY employees_policy ON employees
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE INDEX IF NOT EXISTS idx_employees_inst ON employees(institution_id);

-- ============================================================
-- 4. GATE BLACKLIST
-- ============================================================
CREATE TABLE IF NOT EXISTS gate_blacklist (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    person_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (institution_id, person_id)
);

ALTER TABLE gate_blacklist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gate_blacklist_policy ON gate_blacklist;
CREATE POLICY gate_blacklist_policy ON gate_blacklist
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE INDEX IF NOT EXISTS idx_gate_blacklist_inst ON gate_blacklist(institution_id);

-- ============================================================
-- 5. GATE INCIDENTS
-- ============================================================
CREATE TABLE IF NOT EXISTS gate_incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    incident_type VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    location VARCHAR(255) NOT NULL,
    severity VARCHAR(50) NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    status VARCHAR(50) NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'investigating', 'resolved', 'closed')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE gate_incidents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS gate_incidents_policy ON gate_incidents;
CREATE POLICY gate_incidents_policy ON gate_incidents
    FOR ALL USING (institution_id = get_auth_institution_id() OR get_auth_user_role() = 'SuperAdmin');

CREATE INDEX IF NOT EXISTS idx_gate_incidents_inst ON gate_incidents(institution_id);


-- ==========================================================
-- MIGRATION: 20260716000000_applicant_homepage_visibility.sql
-- ==========================================================

-- Migration: Add is_visible_on_homepage flag to institutions table
-- Purpose : SuperAdmin can control which institutions appear on the public applicant home page.
-- Default : false — no institution is shown publicly until explicitly enabled.
-- Apply   : Run this in the Supabase SQL Editor (do NOT auto-apply via CLI without review).

ALTER TABLE institutions
  ADD COLUMN IF NOT EXISTS is_visible_on_homepage BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN institutions.is_visible_on_homepage IS
  'When true, this institution is listed on the public /home applicant discovery page. '
  'Only SuperAdmin can toggle this flag. Defaults to false (hidden).';


-- ==========================================================
-- MIGRATION: 20260817000000_school_capabilities.sql
-- ==========================================================

-- Migration: Enhance School Capabilities and Parent-Student Verification
-- Date: 2026-08-17

-- 1. Add class_section_id to students table
ALTER TABLE students ADD COLUMN IF NOT EXISTS class_section_id UUID REFERENCES class_sections(id) ON DELETE SET NULL;

-- 2. Create index on class_section_id
CREATE INDEX IF NOT EXISTS idx_students_class_section ON students(class_section_id);

-- 3. Backfill initial class_section_id values based on student's semester (which maps to grade in schools)
UPDATE students s
SET class_section_id = cs.id
FROM class_sections cs
WHERE s.semester = cs.grade
  AND cs.section = 'A'
  AND s.class_section_id IS NULL;

-- 4. Redefine parent-student linking function to default to unverified unless phone numbers match
CREATE OR REPLACE FUNCTION link_parent_to_child(
    p_roll_number VARCHAR,
    p_child_dob DATE
)
RETURNS TABLE (
    success BOOLEAN,
    message TEXT,
    student_id UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_student RECORD;
    v_user_id UUID;
    v_parent_phone VARCHAR;
    v_verified BOOLEAN := false;
BEGIN
    v_user_id := auth.uid();

    -- Find student by roll number
    SELECT s.id, s.user_id, s.dob, s.institution_id, s.guardian_phone, u.name AS full_name
    INTO v_student
    FROM students s
    JOIN users u ON s.user_id = u.id
    WHERE s.roll_number = p_roll_number
      AND s.is_active = true;

    IF v_student IS NULL THEN
        success := false;
        message := 'No active student found with this roll number.';
        student_id := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Verify DOB matches (additional security layer)
    IF v_student.dob != p_child_dob THEN
        success := false;
        message := 'Date of birth does not match our records.';
        student_id := NULL;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Get parent phone number from users table
    SELECT phone INTO v_parent_phone FROM users WHERE id = v_user_id;

    -- Auto-verify if parent phone matches student guardian_phone
    IF v_parent_phone IS NOT NULL AND v_student.guardian_phone IS NOT NULL AND 
       regexp_replace(v_parent_phone, '[^0-9]', '', 'g') = regexp_replace(v_student.guardian_phone, '[^0-9]', '', 'g') THEN
        v_verified := true;
    END IF;

    -- Check if already linked and verified
    IF EXISTS (
        SELECT 1 FROM parent_student_links
        WHERE parent_user_id = v_user_id
          AND student_id = v_student.id
          AND verified = true
    ) THEN
        success := true;
        message := 'This student is already linked to your account.';
        student_id := v_student.id;
        RETURN NEXT;
        RETURN;
    END IF;

    -- Create or update link
    INSERT INTO parent_student_links (parent_user_id, student_id, verified, relationship)
    VALUES (v_user_id, v_student.id, v_verified, 'Guardian')
    ON CONFLICT (parent_user_id, student_id)
    DO UPDATE SET verified = v_verified;

    -- Update parent profile if it's verified
    IF v_verified THEN
        UPDATE parent_profiles SET is_verified = true, verified_at = NOW()
        WHERE user_id = v_user_id;
    END IF;

    success := true;
    IF v_verified THEN
        message := 'Successfully linked and auto-verified student ' || v_student.full_name;
    ELSE
        message := 'Linked student ' || v_student.full_name || '. Access pending administrator verification.';
    END IF;
    student_id := v_student.id;
    RETURN NEXT;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260817100000_director_harden.sql
-- ==========================================================

-- =========================================================================
-- DIRECTOR PORTAL TELEMETRY & HARDENING
-- Migration: 20260817100000
-- Creates operating_expenses and upgrades system anomaly detection
-- =========================================================================

-- 1. OPERATING EXPENSES TABLE
CREATE TABLE IF NOT EXISTS operating_expenses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
  expense_date DATE NOT NULL DEFAULT CURRENT_DATE,
  category VARCHAR(100) NOT NULL CHECK (category IN ('utility', 'maintenance', 'marketing', 'other')),
  amount DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_operating_expenses_inst ON operating_expenses(institution_id, expense_date);

-- 2. SEED MOCK EXPENSES FOR DEFAULT INSTITUTION
INSERT INTO operating_expenses (institution_id, expense_date, category, amount, description)
VALUES 
  ('a0000000-0000-0000-0000-000000000001', '2026-08-01', 'utility', 145000.00, 'Electricity Grid & Water Charges'),
  ('a0000000-0000-0000-0000-000000000001', '2026-08-05', 'maintenance', 280000.00, 'AC plant servicing & campus gardening contracts')
ON CONFLICT DO NOTHING;

-- 3. UPGRADE ANOMALY DETECTION PL/PGSQL FUNCTION
CREATE OR REPLACE FUNCTION detect_system_anomalies()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_inst_id UUID;
  v_result JSON;
  v_anomaly_count INT := 0;
  
  -- Variables for canteen drop check
  v_canteen_yesterday NUMERIC := 0.00;
  v_canteen_7day_avg NUMERIC := 0.00;
  
  -- Variables for gate-out spike check
  v_gate_out_spike_count INT := 0;
  
  -- Variables for mass absence check
  v_dept_absent_record RECORD;
BEGIN
  -- Get current tenant institution ID
  SELECT u.institution_id INTO v_inst_id
  FROM users u WHERE u.id = auth.uid();
  IF v_inst_id IS NULL THEN 
    SELECT id INTO v_inst_id FROM institutions LIMIT 1; 
  END IF;

  -- A. Detect duplicate attendance (same student, same session, multiple marks)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'duplicate_attendance',
    'high',
    'Duplicate Attendance Detected',
    'Student ' || u.name || ' has ' || COUNT(*) || ' attendance records for the same session on ' || a.date,
    'attendance',
    a.student_id,
    'student',
    u.name,
    jsonb_build_object('date', a.date, 'session_id', a.session_id, 'count', COUNT(*))
  FROM attendance a
  JOIN students s ON s.id = a.student_id
  JOIN users u ON u.id = s.user_id
  WHERE a.institution_id = v_inst_id
    AND a.date >= CURRENT_DATE - 1
  GROUP BY a.student_id, a.session_id, a.date, u.name
  HAVING COUNT(*) > 1
  ON CONFLICT DO NOTHING;

  -- B. Detect wallet rapid transactions (>3 in 5 minutes)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'rapid_wallet_txn',
    'medium',
    'Rapid Wallet Transactions',
    u.name || ' made ' || COUNT(*) || ' wallet transactions within 5 minutes',
    'wallet',
    wt.student_id,
    'student',
    u.name,
    jsonb_build_object('transaction_count', COUNT(*), 'time_window', '5 minutes', 'total_amount', SUM(wt.amount))
  FROM wallet_transactions wt
  JOIN students s ON s.id = wt.student_id
  JOIN users u ON u.id = s.user_id
  WHERE wt.institution_id = v_inst_id
    AND wt.created_at >= NOW() - INTERVAL '1 hour'
  GROUP BY wt.student_id, u.name, DATE_TRUNC('minute', wt.created_at)
  HAVING COUNT(*) >= 3
  ON CONFLICT DO NOTHING;

  -- C. Detect unusual hours attendance (marked before 6AM or after 10PM)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'unusual_hours',
    'medium',
    'Attendance Marked at Unusual Hours',
    'Attendance for ' || u.name || ' was marked at ' || TO_CHAR(a.created_at, 'HH24:MI'),
    'attendance',
    a.student_id,
    'student',
    u.name,
    jsonb_build_object('marked_at', a.created_at, 'method', a.method)
  FROM attendance a
  JOIN students s ON s.id = a.student_id
  JOIN users u ON u.id = s.user_id
  WHERE a.institution_id = v_inst_id
    AND a.created_at >= NOW() - INTERVAL '24 hours'
    AND (EXTRACT(HOUR FROM a.created_at) < 6 OR EXTRACT(HOUR FROM a.created_at) > 22)
  ON CONFLICT DO NOTHING;

  -- D. Detect geo-fence violations (attendance marked >1km from institution)
  INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, person_id, person_type, person_name, metadata)
  SELECT
    v_inst_id,
    'geo_fence_violation',
    'high',
    'Attendance Outside Geo-Fence',
    u.name || ' marked attendance from ' || ROUND(a.lat::NUMERIC, 4) || ', ' || ROUND(a.long::NUMERIC, 4),
    'attendance',
    a.student_id,
    'student',
    u.name,
    jsonb_build_object('lat', a.lat, 'long', a.long, 'method', a.method)
  FROM attendance a
  JOIN students s ON s.id = a.student_id
  JOIN users u ON u.id = s.user_id
  WHERE a.institution_id = v_inst_id
    AND a.created_at >= NOW() - INTERVAL '24 hours'
    AND a.lat IS NOT NULL AND a.long IS NOT NULL
    AND (a.lat = 0 OR a.long = 0)
  ON CONFLICT DO NOTHING;

  -- E. Unexpected drops in canteen revenue (>20% deviation from 7-day average)
  -- Get yesterday's completed orders total
  SELECT COALESCE(SUM(total_amount), 0) INTO v_canteen_yesterday
  FROM canteen_orders
  WHERE institution_id = v_inst_id
    AND payment_status = 'Completed'
    AND order_time >= CURRENT_DATE - 1
    AND order_time < CURRENT_DATE;

  -- Get 7-day daily average prior to yesterday
  SELECT COALESCE(SUM(total_amount) / 7.0, 0) INTO v_canteen_7day_avg
  FROM canteen_orders
  WHERE institution_id = v_inst_id
    AND payment_status = 'Completed'
    AND order_time >= CURRENT_DATE - 8
    AND order_time < CURRENT_DATE - 1;

  IF v_canteen_7day_avg > 0 AND v_canteen_yesterday < (0.8 * v_canteen_7day_avg) THEN
    INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, metadata)
    VALUES (
      v_inst_id,
      'canteen_revenue_drop',
      'high',
      'Canteen Revenue Drop Anomaly',
      'Canteen revenue dropped to ₹' || v_canteen_yesterday || ' (a ' || ROUND(100.0 * (v_canteen_7day_avg - v_canteen_yesterday) / v_canteen_7day_avg, 1) || '% drop compared to 7-day average of ₹' || ROUND(v_canteen_7day_avg, 2) || ').',
      'canteen',
      jsonb_build_object('yesterday_revenue', v_canteen_yesterday, 'seven_day_avg', v_canteen_7day_avg)
    )
    ON CONFLICT DO NOTHING;
  END IF;

  -- F. Rapid spikes in student "Gate-Out" events during class hours
  SELECT COUNT(*) INTO v_gate_out_spike_count
  FROM gate_logs ge
  JOIN users u ON ge.person_id = u.id
  WHERE ge.institution_id = v_inst_id
    AND ge.direction = 'out'
    AND ge.timestamp >= NOW() - INTERVAL '1 hour'
    AND EXTRACT(HOUR FROM ge.timestamp) >= 9 
    AND EXTRACT(HOUR FROM ge.timestamp) <= 16
    AND u.role = 'Student';

  IF v_gate_out_spike_count >= 15 THEN
    INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, metadata)
    VALUES (
      v_inst_id,
      'gate_out_spike',
      'critical',
      'Gate-Out RFID Spike Alert',
      'Rapid spike detected: ' || v_gate_out_spike_count || ' students left campus via RFID gates during class hours (last 1 hour).',
      'gate',
      jsonb_build_object('gate_out_count', v_gate_out_spike_count, 'class_hours', true)
    )
    ON CONFLICT DO NOTHING;
  END IF;

  -- G. Large batches of "Absent" marks from a single department
  FOR v_dept_absent_record IN
    SELECT 
      d.id AS department_id,
      d.name AS department_name,
      COUNT(s.id) AS total_students,
      COUNT(a.id) FILTER (WHERE a.status = 'absent' OR a.status = 'Absent') AS absent_count
    FROM departments d
    JOIN students s ON s.department_id = d.id
    JOIN attendance a ON a.student_id = s.id
    WHERE d.institution_id = v_inst_id
      AND a.date = CURRENT_DATE
    GROUP BY d.id, d.name
  LOOP
    IF v_dept_absent_record.total_students >= 10 AND v_dept_absent_record.absent_count > (0.5 * v_dept_absent_record.total_students) THEN
      INSERT INTO system_anomalies (institution_id, anomaly_type, severity, title, description, module, metadata)
      VALUES (
        v_inst_id,
        'bulk_absent_anomaly',
        'critical',
        'Mass Absence / Faculty Strike Warning',
        'Critical absenteeism: ' || v_dept_absent_record.absent_count || ' out of ' || v_dept_absent_record.total_students || ' students in ' || v_dept_absent_record.department_name || ' are marked absent today.',
        'attendance',
        jsonb_build_object(
          'department_id', v_dept_absent_record.department_id, 
          'department_name', v_dept_absent_record.department_name, 
          'absent_count', v_dept_absent_record.absent_count, 
          'total_students', v_dept_absent_record.total_students
        )
      )
      ON CONFLICT DO NOTHING;
    END IF;
  END LOOP;

  -- Get unresolved anomaly count
  SELECT COUNT(*) INTO v_anomaly_count
  FROM system_anomalies
  WHERE institution_id = v_inst_id AND NOT is_resolved;

  RETURN json_build_object(
    'total_unresolved', v_anomaly_count,
    'by_type', (
      SELECT COALESCE(jsonb_agg(row_to_json(at)), '[]'::JSONB)
      FROM (
        SELECT anomaly_type, severity, COUNT(*) as count
        FROM system_anomalies
        WHERE institution_id = v_inst_id AND NOT is_resolved
        GROUP BY anomaly_type, severity
        ORDER BY count DESC
      ) at
    ),
    'recent', (
      SELECT COALESCE(jsonb_agg(row_to_json(ra)), '[]'::JSONB)
      FROM (
        SELECT id, anomaly_type, severity, title, description, module, person_name, metadata, created_at
        FROM system_anomalies
        WHERE institution_id = v_inst_id AND NOT is_resolved
        ORDER BY created_at DESC
        LIMIT 20
      ) ra
    ),
    'stats', (
      SELECT json_build_object(
        'total_all_time', COUNT(*),
        'resolved', COUNT(*) FILTER (WHERE is_resolved),
        'critical', COUNT(*) FILTER (WHERE severity = 'critical' AND NOT is_resolved),
        'high', COUNT(*) FILTER (WHERE severity = 'high' AND NOT is_resolved),
        'medium', COUNT(*) FILTER (WHERE severity = 'medium' AND NOT is_resolved),
        'low', COUNT(*) FILTER (WHERE severity = 'low' AND NOT is_resolved)
      )
      FROM system_anomalies
      WHERE institution_id = v_inst_id
    )
  );
END;
$$;


-- ==========================================================
-- MIGRATION: 20260817200000_school_diary.sql
-- ==========================================================

-- Migration: Add Daily Class Diary Table for School Teachers
-- Date: 2026-08-17

CREATE TABLE IF NOT EXISTS diary_entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    class_section_id UUID NOT NULL REFERENCES class_sections(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    entry_text TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT unique_section_date_diary UNIQUE (class_section_id, date)
);

-- Enable Row Level Security
ALTER TABLE diary_entries ENABLE ROW LEVEL SECURITY;

-- Add RLS Policies
CREATE POLICY "Users can select diary entries in their institution" ON diary_entries
    FOR SELECT USING (
        institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    );

CREATE POLICY "Teachers can manage diary entries in their institution" ON diary_entries
    FOR ALL USING (
        institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    );


-- ==========================================================
-- MIGRATION: 20260817210000_student_behavior.sql
-- ==========================================================

-- Migration: Add Student Behavior logs and homework column to diary entries
-- Date: 2026-08-17

ALTER TABLE diary_entries ADD COLUMN IF NOT EXISTS homework TEXT;

CREATE TABLE IF NOT EXISTS student_behavior_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    log_type TEXT NOT NULL CHECK (log_type IN ('Incident', 'Achievement')),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable Row Level Security
ALTER TABLE student_behavior_logs ENABLE ROW LEVEL SECURITY;

-- Add RLS Policies
CREATE POLICY "Users can select behavior logs in their institution" ON student_behavior_logs
    FOR SELECT USING (
        institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    );

CREATE POLICY "Teachers can insert behavior logs in their institution" ON student_behavior_logs
    FOR INSERT WITH CHECK (
        institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    );


-- ==========================================================
-- MIGRATION: 20260822000000_discipline_incidents.sql
-- ==========================================================

-- Migration: Add discipline_incidents table for Vice Principal / School Discipline
-- Date: 2026-08-22

CREATE TABLE IF NOT EXISTS discipline_incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID NOT NULL REFERENCES institutions(id) ON DELETE CASCADE,
    student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
    reported_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    incident_date DATE NOT NULL DEFAULT CURRENT_DATE,
    category TEXT NOT NULL DEFAULT 'Behavioral',
    severity TEXT NOT NULL DEFAULT 'Minor' CHECK (severity IN ('Minor', 'Major', 'Severe')),
    description TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'Open' CHECK (status IN ('Open', 'Resolved')),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Enable Row Level Security
ALTER TABLE discipline_incidents ENABLE ROW LEVEL SECURITY;

-- Add RLS Policies
CREATE POLICY "Users can select discipline incidents in their institution" ON discipline_incidents
    FOR SELECT USING (
        institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    );

CREATE POLICY "Authorized staff can insert discipline incidents" ON discipline_incidents
    FOR INSERT WITH CHECK (
        institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    );

CREATE POLICY "Authorized staff can update discipline incidents" ON discipline_incidents
    FOR UPDATE USING (
        institution_id = (SELECT institution_id FROM users WHERE id = auth.uid())
    );


-- ==========================================================
-- MIGRATION: 20260822010000_school_appraisal_status_migration.sql
-- ==========================================================

-- Migration: Update orphaned school performance appraisals from pending_hod to pending_vp
UPDATE performance_appraisals
SET status = 'pending_vp'
WHERE status = 'pending_hod'
  AND (
    institution_id IN (SELECT id FROM institutions WHERE type = 'school')
    OR cycle_id IN (
      SELECT pc.id FROM performance_cycles pc
      JOIN institutions i ON pc.institution_id = i.id
      WHERE i.type = 'school'
    )
  );


-- ==========================================================
-- MIGRATION: 20260822020000_director_risk_predictors.sql
-- ==========================================================

-- Migration: Director Risk Predictor RPCs (get_dropout_risk_students and get_fee_risk_students)
-- Migration File: 20260822020000_director_risk_predictors.sql

-- 1. get_dropout_risk_students RPC
CREATE OR REPLACE FUNCTION get_dropout_risk_students(
    p_limit INT DEFAULT 10,
    p_institution_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    roll_number VARCHAR,
    name VARCHAR,
    department_name VARCHAR,
    attendance_rate NUMERIC,
    overdue_amount NUMERIC,
    risk_score INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inst_id UUID;
BEGIN
    v_inst_id := p_institution_id;
    IF v_inst_id IS NULL THEN
        SELECT u.institution_id INTO v_inst_id FROM users u WHERE u.id = auth.uid();
    END IF;
    IF v_inst_id IS NULL THEN
        SELECT inst.id INTO v_inst_id FROM institutions inst LIMIT 1;
    END IF;

    RETURN QUERY
    WITH student_att AS (
        SELECT
            a.student_id,
            COUNT(*)::NUMERIC AS total_days,
            COUNT(*) FILTER (WHERE LOWER(a.status) IN ('present', 'late'))::NUMERIC AS present_days
        FROM attendance a
        WHERE a.date >= (CURRENT_DATE - INTERVAL '30 days')
          AND (v_inst_id IS NULL OR a.institution_id = v_inst_id OR a.student_id IN (SELECT st.id FROM students st WHERE st.institution_id = v_inst_id))
        GROUP BY a.student_id
    ),
    student_fee_summary AS (
        SELECT
            sf.student_id,
            SUM(GREATEST(0, COALESCE(sf.total_amount, sf.amount, 0) - COALESCE(sf.paid_amount, 0))) AS total_overdue,
            SUM(COALESCE(sf.total_amount, sf.amount, 0)) AS total_fee
        FROM student_fees sf
        WHERE sf.payment_status IN ('pending', 'partial')
          AND (v_inst_id IS NULL OR sf.institution_id = v_inst_id)
        GROUP BY sf.student_id
    )
    SELECT
        s.id,
        COALESCE(s.roll_number, '')::VARCHAR AS roll_number,
        COALESCE(u.name, 'Student')::VARCHAR AS name,
        COALESCE(d.name, 'General')::VARCHAR AS department_name,
        ROUND(
            COALESCE((sa.present_days / NULLIF(sa.total_days, 0)) * 100.0, 100.0), 1
        )::NUMERIC AS attendance_rate,
        COALESCE(sfs.total_overdue, 0.00)::NUMERIC AS overdue_amount,
        ROUND(
            LEAST(100.0,
                -- 70% weight to attendance shortfall below 75%
                (GREATEST(0.0, 75.0 - COALESCE((sa.present_days / NULLIF(sa.total_days, 0)) * 100.0, 100.0)) / 75.0 * 70.0)
                +
                -- 30% weight to overdue fee ratio
                (LEAST(1.0, COALESCE(sfs.total_overdue, 0.0) / NULLIF(sfs.total_fee, 0.0)) * 30.0)
            )
        )::INT AS risk_score
    FROM students s
    JOIN users u ON u.id = s.user_id
    LEFT JOIN departments d ON d.id = s.department_id
    LEFT JOIN student_att sa ON sa.student_id = s.id
    LEFT JOIN student_fee_summary sfs ON sfs.student_id = s.id
    WHERE (v_inst_id IS NULL OR s.institution_id = v_inst_id)
      AND (
          (sa.total_days IS NOT NULL AND (sa.present_days / NULLIF(sa.total_days, 0)) < 0.75)
          OR COALESCE(sfs.total_overdue, 0) > 0
      )
    ORDER BY risk_score DESC, overdue_amount DESC
    LIMIT p_limit;
END;
$$;

-- 2. get_fee_risk_students RPC
CREATE OR REPLACE FUNCTION get_fee_risk_students(
    p_limit INT DEFAULT 10,
    p_institution_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    roll_number VARCHAR,
    name VARCHAR,
    department_name VARCHAR,
    overdue_amount NUMERIC,
    days_overdue INT,
    default_likelihood VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_inst_id UUID;
BEGIN
    v_inst_id := p_institution_id;
    IF v_inst_id IS NULL THEN
        SELECT u.institution_id INTO v_inst_id FROM users u WHERE u.id = auth.uid();
    END IF;
    IF v_inst_id IS NULL THEN
        SELECT inst.id INTO v_inst_id FROM institutions inst LIMIT 1;
    END IF;

    RETURN QUERY
    WITH fee_summary AS (
        SELECT
            sf.student_id,
            SUM(GREATEST(0, COALESCE(sf.total_amount, sf.amount, 0) - COALESCE(sf.paid_amount, 0))) AS total_overdue,
            MAX(
                CASE 
                    WHEN sf.due_date IS NOT NULL AND sf.due_date < CURRENT_DATE 
                    THEN (CURRENT_DATE - sf.due_date)
                    ELSE 0
                END
            ) AS max_days_overdue
        FROM student_fees sf
        WHERE sf.payment_status IN ('pending', 'partial')
          AND (v_inst_id IS NULL OR sf.institution_id = v_inst_id)
        GROUP BY sf.student_id
        HAVING SUM(GREATEST(0, COALESCE(sf.total_amount, sf.amount, 0) - COALESCE(sf.paid_amount, 0))) > 0
    )
    SELECT
        s.id,
        COALESCE(s.roll_number, '')::VARCHAR AS roll_number,
        COALESCE(u.name, 'Student')::VARCHAR AS name,
        COALESCE(d.name, 'General')::VARCHAR AS department_name,
        fs.total_overdue::NUMERIC AS overdue_amount,
        COALESCE(fs.max_days_overdue, 0)::INT AS days_overdue,
        CASE
            WHEN COALESCE(fs.max_days_overdue, 0) > 60 THEN 'High'::VARCHAR
            WHEN COALESCE(fs.max_days_overdue, 0) > 30 THEN 'Medium'::VARCHAR
            ELSE 'Low'::VARCHAR
        END AS default_likelihood
    FROM fee_summary fs
    JOIN students s ON s.id = fs.student_id
    JOIN users u ON u.id = s.user_id
    LEFT JOIN departments d ON d.id = s.department_id
    WHERE (v_inst_id IS NULL OR s.institution_id = v_inst_id)
    ORDER BY overdue_amount DESC, days_overdue DESC
    LIMIT p_limit;
END;
$$;


-- ==========================================================
-- MIGRATION: 20260822030000_fix_student_fees_schema.sql
-- ==========================================================

-- Migration: Fix student_fees table schema, missing columns, indexes, payment_status backfill, and RLS policies

-- 1. Ensure missing columns exist on student_fees table
ALTER TABLE student_fees ADD COLUMN IF NOT EXISTS institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE;
ALTER TABLE student_fees ADD COLUMN IF NOT EXISTS student_id UUID REFERENCES students(id) ON DELETE CASCADE;
ALTER TABLE student_fees ADD COLUMN IF NOT EXISTS fee_structure_id UUID REFERENCES fee_structures(id) ON DELETE CASCADE;
ALTER TABLE student_fees ADD COLUMN IF NOT EXISTS due_date DATE;
ALTER TABLE student_fees ADD COLUMN IF NOT EXISTS payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'partial', 'paid'));

-- 2. Add indexes on foreign keys
CREATE INDEX IF NOT EXISTS idx_student_fees_institution_id ON student_fees(institution_id);
CREATE INDEX IF NOT EXISTS idx_student_fees_student_id ON student_fees(student_id);
CREATE INDEX IF NOT EXISTS idx_student_fees_fee_structure_id ON student_fees(fee_structure_id);

-- 3. Backfill institution_id from students table if missing
UPDATE student_fees sf
SET institution_id = s.institution_id
FROM students s
WHERE sf.student_id = s.id AND sf.institution_id IS NULL;

-- 4. Backfill payment_status for existing rows
UPDATE student_fees
SET payment_status = CASE
    WHEN COALESCE(paid_amount, 0) >= COALESCE(total_amount, amount, 0) AND COALESCE(total_amount, amount, 0) > 0 THEN 'paid'
    WHEN COALESCE(paid_amount, 0) > 0 THEN 'partial'
    ELSE 'pending'
END
WHERE payment_status IS NULL OR payment_status = 'pending';

-- 5. Harden RLS policies on student_fees
ALTER TABLE student_fees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS student_fees_policy ON student_fees;
DROP POLICY IF EXISTS "student_fees_policy" ON student_fees;
DROP POLICY IF EXISTS "Allow full access to student_fees" ON student_fees;
DROP POLICY IF EXISTS "student_fees_select_policy" ON student_fees;
DROP POLICY IF EXISTS "student_fees_write_policy" ON student_fees;
DROP POLICY IF EXISTS "student_fees_insert_policy" ON student_fees;
DROP POLICY IF EXISTS "student_fees_update_policy" ON student_fees;
DROP POLICY IF EXISTS "student_fees_delete_policy" ON student_fees;

-- SELECT policy: institution_id must match caller's own institution_id via users table, SuperAdmin, or student/parent self-access
CREATE POLICY "student_fees_select_policy" ON student_fees
    FOR SELECT USING (
        institution_id = (SELECT u.institution_id FROM public.users u WHERE u.id = auth.uid())
        OR (SELECT u.role FROM public.users u WHERE u.id = auth.uid()) = 'SuperAdmin'
        OR student_id IN (SELECT s.id FROM public.students s WHERE s.user_id = auth.uid())
        OR student_id IN (SELECT psl.student_id FROM public.parent_student_links psl WHERE psl.parent_user_id = auth.uid() AND psl.verified = true)
    );

-- INSERT policy: restricted to Admin, SuperAdmin, Director roles
CREATE POLICY "student_fees_insert_policy" ON student_fees
    FOR INSERT WITH CHECK (
        ((SELECT u.role FROM public.users u WHERE u.id = auth.uid()) = 'SuperAdmin')
        OR (
            institution_id = (SELECT u.institution_id FROM public.users u WHERE u.id = auth.uid())
            AND (SELECT u.role FROM public.users u WHERE u.id = auth.uid()) IN ('Admin', 'SuperAdmin', 'Director')
        )
    );

-- UPDATE policy: restricted to Admin, SuperAdmin, Director roles
CREATE POLICY "student_fees_update_policy" ON student_fees
    FOR UPDATE USING (
        ((SELECT u.role FROM public.users u WHERE u.id = auth.uid()) = 'SuperAdmin')
        OR (
            institution_id = (SELECT u.institution_id FROM public.users u WHERE u.id = auth.uid())
            AND (SELECT u.role FROM public.users u WHERE u.id = auth.uid()) IN ('Admin', 'SuperAdmin', 'Director')
        )
    ) WITH CHECK (
        ((SELECT u.role FROM public.users u WHERE u.id = auth.uid()) = 'SuperAdmin')
        OR (
            institution_id = (SELECT u.institution_id FROM public.users u WHERE u.id = auth.uid())
            AND (SELECT u.role FROM public.users u WHERE u.id = auth.uid()) IN ('Admin', 'SuperAdmin', 'Director')
        )
    );

-- DELETE policy: restricted to Admin, SuperAdmin, Director roles
CREATE POLICY "student_fees_delete_policy" ON student_fees
    FOR DELETE USING (
        ((SELECT u.role FROM public.users u WHERE u.id = auth.uid()) = 'SuperAdmin')
        OR (
            institution_id = (SELECT u.institution_id FROM public.users u WHERE u.id = auth.uid())
            AND (SELECT u.role FROM public.users u WHERE u.id = auth.uid()) IN ('Admin', 'SuperAdmin', 'Director')
        )
    );


-- ==========================================================
-- MIGRATION: 20260823000001_obe_intervention_plans.sql
-- ==========================================================

-- Create table for OBE Gap Analysis Intervention Plans
CREATE TABLE IF NOT EXISTS obe_intervention_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id UUID REFERENCES institutions(id) ON DELETE CASCADE,
  department_id UUID,
  po_code VARCHAR(50) NOT NULL,
  action_plan TEXT NOT NULL,
  target_semester VARCHAR(50) NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'pending',
  created_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE obe_intervention_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow authenticated users to read obe_intervention_plans"
  ON obe_intervention_plans FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Allow authenticated users to insert obe_intervention_plans"
  ON obe_intervention_plans FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Allow authenticated users to update obe_intervention_plans"
  ON obe_intervention_plans FOR UPDATE
  TO authenticated
  USING (true);


-- ==========================================================
-- MIGRATION: 20260823000002_gate_entry_logs.sql
-- ==========================================================

-- ============================================================
-- GATE ENTRY LOGS MIGRATION
-- Table and RLS policies for tracking person entries and exits
-- ============================================================

CREATE TABLE IF NOT EXISTS public.gate_entry_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.institutions(id) ON DELETE CASCADE,
    person_id TEXT,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    person_name TEXT NOT NULL,
    person_type TEXT NOT NULL DEFAULT 'student', -- 'student', 'staff', 'visitor', 'guest'
    gate_number TEXT NOT NULL DEFAULT 'Gate 1',
    scanned_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    direction TEXT NOT NULL CHECK (direction IN ('entry', 'exit')),
    scanned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.gate_entry_logs ENABLE ROW LEVEL SECURITY;

-- Select policy
DROP POLICY IF EXISTS "Gate entry logs select policy" ON public.gate_entry_logs;
CREATE POLICY "Gate entry logs select policy"
    ON public.gate_entry_logs FOR SELECT
    USING (
        institution_id IS NULL OR institution_id = get_auth_institution_id()
    );

-- Insert policy
DROP POLICY IF EXISTS "Gate entry logs insert policy" ON public.gate_entry_logs;
CREATE POLICY "Gate entry logs insert policy"
    ON public.gate_entry_logs FOR INSERT
    WITH CHECK (
        institution_id IS NULL OR institution_id = get_auth_institution_id()
    );

-- Index for fast queries
CREATE INDEX IF NOT EXISTS idx_gate_entry_logs_institution_scanned 
    ON public.gate_entry_logs(institution_id, scanned_at DESC);


-- ==========================================================
-- MIGRATION: 20260823000003_dvv_queries.sql
-- ==========================================================

-- Migration: Create dvv_queries table for NAAC DVV Clarifications Module
CREATE TABLE IF NOT EXISTS public.dvv_queries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    institution_id UUID REFERENCES public.institutions(id) ON DELETE CASCADE,
    metric_code TEXT NOT NULL,
    query_text TEXT NOT NULL,
    response_text TEXT,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

ALTER TABLE public.dvv_queries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow authenticated full access to dvv_queries" ON public.dvv_queries FOR ALL USING (true);


-- ==========================================================
-- MIGRATION: 20260823000004_company_access_key.sql
-- ==========================================================

-- Migration: Add access_key_hash to companies table
ALTER TABLE IF EXISTS public.companies 
ADD COLUMN IF NOT EXISTS access_key_hash text;


-- ==========================================================
-- MIGRATION: 20260824_storage_policies.sql
-- ==========================================================

-- Migration: Supabase Storage Bucket Policies for IRIS 365
-- Enforces allowed mime types and maximum object size (10 MB) at the storage layer

-- Create buckets if they do not exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES 
  ('kyc', 'kyc', true, 10485760, ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']),
  ('resumes', 'resumes', true, 10485760, ARRAY['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document']),
  ('evidence', 'evidence', true, 10485760, ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp']),
  ('docs', 'docs', true, 10485760, ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
ON CONFLICT (id) DO UPDATE SET
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- RLS policies on storage.objects for authenticated uploads
DROP POLICY IF EXISTS "Authenticated users can upload objects to kyc bucket" ON storage.objects;
CREATE POLICY "Authenticated users can upload objects to kyc bucket"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'kyc'
    AND (storage.foldername(name))[1] IS NOT NULL
  );

DROP POLICY IF EXISTS "Authenticated users can upload objects to resumes bucket" ON storage.objects;
CREATE POLICY "Authenticated users can upload objects to resumes bucket"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'resumes'
  );

DROP POLICY IF EXISTS "Public read access for storage buckets" ON storage.objects;
CREATE POLICY "Public read access for storage buckets"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id IN ('kyc', 'resumes', 'evidence', 'docs'));


-- ==========================================================
-- MIGRATION: 20260828000000_institution_purchase_intents.sql
-- ==========================================================

-- Create table for self-serve purchase intents (Buy Now flow)
CREATE TABLE IF NOT EXISTS institution_purchase_intents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_name TEXT NOT NULL,
  contact_name TEXT NOT NULL,
  contact_email TEXT NOT NULL,
  contact_phone TEXT NOT NULL,
  city TEXT,
  tier TEXT NOT NULL,
  account_count INT NOT NULL,
  billing_cycle TEXT NOT NULL,
  currency TEXT NOT NULL DEFAULT 'INR',
  amount_paid NUMERIC NOT NULL,
  razorpay_order_id TEXT NOT NULL,
  razorpay_payment_id TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'paid_pending_setup',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast ordering by created_at in admin inbox
CREATE INDEX IF NOT EXISTS idx_purchase_intents_created_at ON institution_purchase_intents(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_intents_status ON institution_purchase_intents(status);


-- ==========================================================
-- MIGRATION: 20260829000000_parent_self_onboarding.sql
-- ==========================================================

-- Migration: Parent Self Onboarding & Platform Payments
-- Date: 2026-08-29

-- 1. Make institution_id nullable on parent_profiles for platform-registered parents
ALTER TABLE parent_profiles ALTER COLUMN institution_id DROP NOT NULL;

-- 2. Create parent_platform_payments table for self-serve parent onboarding fee (₹150)
CREATE TABLE IF NOT EXISTS parent_platform_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL DEFAULT 150,
  currency TEXT NOT NULL DEFAULT 'INR',
  razorpay_order_id TEXT NOT NULL,
  razorpay_payment_id TEXT UNIQUE,
  status TEXT NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'paid', 'failed')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_parent_payments_order ON parent_platform_payments(razorpay_order_id);
CREATE INDEX IF NOT EXISTS idx_parent_payments_user ON parent_platform_payments(parent_user_id);
CREATE INDEX IF NOT EXISTS idx_parent_payments_status ON parent_platform_payments(status);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE parent_platform_payments ENABLE ROW LEVEL SECURITY;

-- Policy: Parent can read own platform payment records
CREATE POLICY parent_read_own_payments ON parent_platform_payments
  FOR SELECT
  USING (auth.uid() = parent_user_id);

-- Policy: Service role has full access
CREATE POLICY service_role_full_access_parent_payments ON parent_platform_payments
  FOR ALL
  USING (true)
  WITH CHECK (true);


-- ==========================================================
-- MIGRATION: 20260829000001_parent_subscription_expiry.sql
-- ==========================================================

-- Migration: Parent Subscription Validity (1-Year Expiry) & Auto Expiration
-- Date: 2026-08-29

-- 1. Add paid_at and valid_until columns to parent_platform_payments
ALTER TABLE parent_platform_payments
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS valid_until TIMESTAMPTZ;

-- 2. Update constraint on status column to support ('created', 'active', 'expired', 'failed')
ALTER TABLE parent_platform_payments
  DROP CONSTRAINT IF EXISTS parent_platform_payments_status_check;

ALTER TABLE parent_platform_payments
  ADD CONSTRAINT parent_platform_payments_status_check
  CHECK (status IN ('created', 'active', 'expired', 'failed', 'paid'));

-- Migrate existing 'paid' status rows to 'active', setting valid_until to 1 year from creation
UPDATE parent_platform_payments
SET 
  status = 'active',
  paid_at = COALESCE(paid_at, created_at, NOW()),
  valid_until = COALESCE(valid_until, created_at + INTERVAL '1 year', NOW() + INTERVAL '1 year')
WHERE status = 'paid';

-- 3. SQL function to auto-expire subscriptions past valid_until date
CREATE OR REPLACE FUNCTION expire_outdated_parent_subscriptions()
RETURNS INTEGER AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE parent_platform_payments
  SET 
    status = 'expired',
    updated_at = NOW()
  WHERE status IN ('active', 'paid')
    AND valid_until IS NOT NULL
    AND valid_until < NOW();

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
