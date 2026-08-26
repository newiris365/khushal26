"use client";

import React, { useState } from 'react';
import { 
  Settings, Save, CheckCircle, AlertCircle, Loader2, Mail, Phone, ShieldCheck, 
  HelpCircle, MessageSquare, FileText
} from 'lucide-react';

export default function AdminSettingsPage() {
  const [processing, setProcessing] = useState(false);
  const [success, setSuccess] = useState<string | null>(null);

  // Offer Letter Settings
  const [sigAuthority, setSigAuthority] = useState('Registrar (Admissions)');
  const [depositAmount, setDepositAmount] = useState(10000);
  const [letterHeader, setLetterHeader] = useState('JIET, Jodhpur');

  // WhatsApp Campaign Templates
  const [selectedTemplate, setSelectedTemplate] = useState('follow_up');
  const [templateBody, setTemplateBody] = useState(
    "Dear {{name}},\n\nThank you for inquiring about B.Tech CSE at JIET. The admissions window is actively closing soon. Apply here: {{link}}\n\nRegards,\nRegistrar Office"
  );

  const handleTemplateChange = (key: string) => {
    setSelectedTemplate(key);
    if (key === 'follow_up') {
      setTemplateBody(
        "Dear {{name}},\n\nThank you for inquiring about B.Tech CSE at JIET. The admissions window is actively closing soon. Apply here: {{link}}\n\nRegards,\nRegistrar Office"
      );
    } else if (key === 'cutoff_alert') {
      setTemplateBody(
        "Dear {{name}},\n\nCongratulations! The Round {{round}} cutoffs have been published. You are listed under rank #{{rank}}. Please log in to accept the provisional offer: {{link}}\n\nRegards,\nJIET Admissions Desk"
      );
    } else if (key === 'fees_reminder') {
      setTemplateBody(
        "Dear {{name}},\n\nThis is a priority reminder that your seat confirmation deposit is pending for {{program}}. Revocation deadline: {{expiry_date}}. Secure your seat here: {{link}}\n\nRegards,\nJIET Accounts Office"
      );
    }
  };

  const handleSaveSettings = (e: React.FormEvent) => {
    e.preventDefault();
    setProcessing(true);
    setSuccess(null);

    setTimeout(() => {
      setSuccess('Admissions letter configurations and template bodies updated successfully!');
      setProcessing(false);
    }, 1000);
  };

  return (
    <div className="max-w-4xl mx-auto space-y-8">
      {success && (
        <div className="p-4 rounded-xl bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-xs font-semibold flex items-center gap-2">
          <CheckCircle className="w-4.5 h-4.5" /> {success}
        </div>
      )}

      <form onSubmit={handleSaveSettings} className="grid grid-cols-1 md:grid-cols-3 gap-8">
        
        {/* Left Column: Letter Configuration */}
        <div className="md:col-span-2 space-y-6">
          
          {/* Document Setup */}
          <div className="rounded-3xl border border-white/5 bg-[#13102A]/40 p-6 shadow-xl space-y-4">
            <h3 className="text-sm font-bold text-white flex items-center gap-2 border-b border-white/5 pb-2">
              <FileText className="w-4.5 h-4.5 text-[#A78BFA]" />
              Provisional Offer Letter Settings
            </h3>

            <div className="flex flex-col gap-1">
              <span className="text-[10px] uppercase font-bold text-[#C4B5FD]">Letter Head Header Title</span>
              <input
                type="text" required value={letterHeader}
                onChange={(e) => setLetterHeader(e.target.value)}
                className="w-full bg-[#0D0A1A] border border-[#6C2BD9]/30 py-2.5 px-3 rounded-xl text-xs text-white outline-none"
              />
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="flex flex-col gap-1">
                <span className="text-[10px] uppercase font-bold text-[#C4B5FD]">Signature Authority Title</span>
                <input
                  type="text" required value={sigAuthority}
                  onChange={(e) => setSigAuthority(e.target.value)}
                  className="w-full bg-[#0D0A1A] border border-[#6C2BD9]/30 py-2.5 px-3 rounded-xl text-xs text-white outline-none"
                />
              </div>

              <div className="flex flex-col gap-1">
                <span className="text-[10px] uppercase font-bold text-[#C4B5FD]">Confirmation Fee (₹)</span>
                <input
                  type="number" required value={depositAmount}
                  onChange={(e) => setDepositAmount(Number(e.target.value))}
                  className="w-full bg-[#0D0A1A] border border-[#6C2BD9]/30 py-2.5 px-3 rounded-xl text-xs text-white outline-none"
                />
              </div>
            </div>
          </div>

          {/* WhatsApp Template inspector */}
          <div className="rounded-3xl border border-white/5 bg-[#13102A]/40 p-6 shadow-xl space-y-4">
            <h3 className="text-sm font-bold text-white flex items-center gap-2 border-b border-white/5 pb-2">
              <MessageSquare className="w-4.5 h-4.5 text-[#A78BFA]" />
              WhatsApp Notification Campaigns
            </h3>

            <div className="flex flex-col gap-1">
              <span className="text-[10px] uppercase font-bold text-[#C4B5FD]">Select Notification Template</span>
              <select
                value={selectedTemplate}
                onChange={(e) => handleTemplateChange(e.target.value)}
                className="w-full bg-[#0D0A1A] border border-[#6C2BD9]/30 py-2.5 px-3 rounded-xl text-xs text-white outline-none"
              >
                <option value="follow_up">Prospectus Follow up</option>
                <option value="cutoff_alert">Merit Round Cutoff Alert</option>
                <option value="fees_reminder">Payment Dues Reminder</option>
              </select>
            </div>

            <div className="flex flex-col gap-1">
              <span className="text-[10px] uppercase font-bold text-[#C4B5FD]">Template Message Body</span>
              <textarea
                rows={5}
                required
                value={templateBody}
                onChange={(e) => setTemplateBody(e.target.value)}
                className="w-full bg-[#0D0A1A] border border-[#6C2BD9]/30 py-2.5 px-3 rounded-xl text-xs text-white font-mono outline-none resize-none leading-relaxed"
              />
            </div>
          </div>

          <div className="flex justify-end">
            <button
              type="submit"
              disabled={processing}
              className="py-3 px-8 bg-gradient-to-r from-[#6C2BD9] to-[#8B5CF6] hover:brightness-110 text-white font-bold rounded-xl text-xs transition-all shadow-md shadow-[#6C2BD9]/20 flex items-center gap-1.5"
            >
              {processing ? <Loader2 className="w-4 h-4 animate-spin" /> : <Save className="w-4 h-4" />}
              <span>Save System Settings</span>
            </button>
          </div>

        </div>

        {/* Right Column: Help */}
        <div className="space-y-6">
          <div className="rounded-3xl border border-white/5 bg-[#13102A]/40 p-6 shadow-xl space-y-4">
            <h4 className="text-xs font-bold text-[#C4B5FD] uppercase tracking-wider flex items-center gap-1">
              <HelpCircle className="w-4 h-4 text-indigo-400" />
              Template Formatting
            </h4>
            <p className="text-[10px] text-[#C4B5FD]/70 leading-relaxed">
              Use standard handlebars formatting (e.g. <code>{"{{name}}"}</code>, <code>{"{{link}}"}</code>) to map database values dynamically. Templates are synchronized automatically with the official WhatsApp Business API channel.
            </p>
          </div>
        </div>

      </form>
    </div>
  );
}
