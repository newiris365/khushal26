'use client';

import React, { useState, useEffect } from 'react';
import {
  ShoppingBag,
  Building2,
  User,
  Mail,
  Phone,
  CheckCircle,
  Clock,
  Search,
  RefreshCw,
  CreditCard
} from 'lucide-react';

interface PurchaseIntent {
  id: string;
  institution_name: string;
  contact_name: string;
  contact_email: string;
  contact_phone: string;
  city: string;
  tier: string;
  account_count: number;
  billing_cycle: string;
  currency: string;
  amount_paid: number;
  razorpay_order_id: string;
  razorpay_payment_id: string;
  status: 'paid_pending_setup' | 'provisioned';
  created_at: string;
}

export default function PurchaseIntentsAdminPage() {
  const [intents, setIntents] = useState<PurchaseIntent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');

  const fetchPurchaseIntents = async () => {
    setLoading(true);
    setError(null);
    try {
      const token = localStorage.getItem('token') || '';
      const res = await fetch('/api/v1/service-subscriptions/purchase-intents', {
        headers: { Authorization: `Bearer ${token}` }
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to fetch purchase intents');
      }
      setIntents(data.purchase_intents || []);
    } catch (err: any) {
      setError(err.message || 'Error fetching purchase intents');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPurchaseIntents();
  }, []);

  const handleMarkProvisioned = async (id: string) => {
    try {
      const token = localStorage.getItem('token') || '';
      const res = await fetch(`/api/v1/service-subscriptions/purchase-intent/${id}/status`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`
        },
        body: JSON.stringify({ status: 'provisioned' })
      });
      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to update status');
      }
      // Update local state
      setIntents((prev) => prev.map((item) => (item.id === id ? { ...item, status: 'provisioned' } : item)));
    } catch (err: any) {
      alert(`Error updating status: ${err.message}`);
    }
  };

  const filteredIntents = intents.filter(
    (item) =>
      item.institution_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      item.contact_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      item.contact_email.toLowerCase().includes(searchQuery.toLowerCase()) ||
      item.razorpay_payment_id.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="p-6 md:p-10 space-y-8 bg-slate-950 min-h-screen text-slate-100 font-sans">
      {/* Header Title */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-4">
        <div>
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/10 text-indigo-400 font-mono text-xs uppercase font-bold">
            <ShoppingBag className="w-3.5 h-3.5" />
            SuperAdmin Inbox
          </div>
          <h1 className="text-3xl font-extrabold text-white tracking-tight mt-1">Institution Purchase Intents</h1>
          <p className="text-xs text-slate-400">
            Review self-serve purchases and manage manual institution provisioning setup.
          </p>
        </div>

        <button
          onClick={fetchPurchaseIntents}
          className="flex items-center gap-2 px-4 py-2 rounded-xl bg-slate-900 border border-slate-800 hover:bg-slate-800 text-xs font-mono font-bold text-slate-300 transition-all"
        >
          <RefreshCw className={`w-3.5 h-3.5 ${loading ? 'animate-spin' : ''}`} />
          Refresh Inbox
        </button>
      </div>

      {/* Search and Filters */}
      <div className="relative max-w-md">
        <Search className="w-4 h-4 text-slate-500 absolute left-3.5 top-3" />
        <input
          type="text"
          placeholder="Search by institution, contact, or payment ID..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          className="w-full bg-slate-900 border border-slate-800 rounded-xl py-2 pl-10 pr-4 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-indigo-500"
        />
      </div>

      {error && (
        <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/30 text-rose-400 text-xs font-semibold">
          {error}
        </div>
      )}

      {/* Table List */}
      <div className="bg-slate-900 border border-slate-800 rounded-2xl overflow-hidden shadow-xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-slate-950 text-slate-400 uppercase font-mono text-[10px] tracking-wider border-b border-slate-800">
              <tr>
                <th className="py-3.5 px-4">Institution & Contact</th>
                <th className="py-3.5 px-4">Plan & Accounts</th>
                <th className="py-3.5 px-4">Amount Paid</th>
                <th className="py-3.5 px-4">Payment Ref</th>
                <th className="py-3.5 px-4">Status</th>
                <th className="py-3.5 px-4 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              {loading && intents.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-8 text-center text-slate-500 font-mono">
                    Loading purchase records...
                  </td>
                </tr>
              ) : filteredIntents.length === 0 ? (
                <tr>
                  <td colSpan={6} className="py-8 text-center text-slate-500 font-mono">
                    No purchase intent records found.
                  </td>
                </tr>
              ) : (
                filteredIntents.map((item) => (
                  <tr key={item.id} className="hover:bg-slate-800/30 transition-colors">
                    {/* Institution & Contact */}
                    <td className="py-4 px-4 space-y-1">
                      <div className="font-bold text-white flex items-center gap-1.5">
                        <Building2 className="w-3.5 h-3.5 text-indigo-400 shrink-0" />
                        <span>{item.institution_name}</span>
                      </div>
                      <div className="text-slate-400 text-[11px] flex items-center gap-2">
                        <span>{item.contact_name}</span>
                        <span>•</span>
                        <span>{item.contact_email}</span>
                      </div>
                      <div className="text-slate-500 text-[10px] font-mono">
                        {item.contact_phone} {item.city ? `(${item.city})` : ''}
                      </div>
                    </td>

                    {/* Plan & Accounts */}
                    <td className="py-4 px-4 space-y-1 font-mono">
                      <span className="px-2 py-0.5 rounded bg-indigo-500/20 text-indigo-300 uppercase font-bold text-[10px]">
                        {item.tier} Tier
                      </span>
                      <div className="text-white text-xs font-bold pt-1">
                        {item.account_count.toLocaleString()} accounts
                      </div>
                      <div className="text-slate-400 capitalize text-[10px]">Billed {item.billing_cycle}</div>
                    </td>

                    {/* Amount Paid */}
                    <td className="py-4 px-4 font-mono font-bold text-emerald-400 text-sm">
                      {item.currency === 'INR'
                        ? '₹'
                        : item.currency === 'USD'
                          ? '$'
                          : item.currency === 'EUR'
                            ? '€'
                            : '£'}
                      {item.amount_paid.toLocaleString()}
                    </td>

                    {/* Payment Ref */}
                    <td className="py-4 px-4 font-mono text-[11px] space-y-0.5">
                      <div className="text-slate-300 font-semibold">{item.razorpay_payment_id}</div>
                      <div className="text-slate-500 text-[10px]">{item.razorpay_order_id}</div>
                    </td>

                    {/* Status Badge */}
                    <td className="py-4 px-4">
                      {item.status === 'provisioned' ? (
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 font-mono text-[10px] font-bold">
                          <CheckCircle className="w-3 h-3" />
                          Provisioned
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-amber-500/10 border border-amber-500/30 text-amber-400 font-mono text-[10px] font-bold">
                          <Clock className="w-3 h-3" />
                          Pending Setup
                        </span>
                      )}
                    </td>

                    {/* Actions */}
                    <td className="py-4 px-4 text-right">
                      {item.status === 'paid_pending_setup' && (
                        <button
                          onClick={() => handleMarkProvisioned(item.id)}
                          className="px-3 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-[11px] font-mono transition-all shadow-md"
                        >
                          Mark Provisioned
                        </button>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
