const { createClient } = require('@supabase/supabase-js');
require('dotenv').config();

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!url || !key) {
  console.error('Supabase credentials missing in .env');
  process.exit(1);
}

const supabase = createClient(url, key);

async function checkSupabase() {
  console.log(`Connecting to Supabase project (${url})...\n`);

  const tablesToCheck = [
    'users',
    'students',
    'institutions',
    'institution_settings',
    'fee_payments',
    'wallet_transactions',
    'gate_entries',
    'gate_lockdown',
    'campus_occupancy',
    'canteen_orders',
    'canteen_menu',
    'school_attendance',
    'discipline_incidents'
  ];

  let successCount = 0;
  let failCount = 0;

  for (const table of tablesToCheck) {
    try {
      const { data, error, count } = await supabase
        .from(table)
        .select('*', { count: 'exact', head: true });

      if (error) {
        console.log(`❌ Table '${table}': ERROR - ${error.message} (Code: ${error.code})`);
        failCount++;
      } else {
        console.log(`✅ Table '${table}': OK (Count: ${count ?? 0} rows)`);
        successCount++;
      }
    } catch (err) {
      console.log(`❌ Table '${table}': EXCEPTION - ${err.message}`);
      failCount++;
    }
  }

  console.log(`\nSummary: ${successCount}/${tablesToCheck.length} key schema tables verified on live Supabase instance.`);
}

checkSupabase();
