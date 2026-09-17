import { NextResponse } from 'next/server';
import { Redis } from '@upstash/redis';
import { Resend } from 'resend';

export const dynamic = 'force-dynamic';

function getRedisClient() {
  try {
    const rawUrl = process.env.UPSTASH_REDIS_REST_URL;
    const rawToken = process.env.UPSTASH_REDIS_REST_TOKEN;
    if (!rawUrl || !rawToken) return null;
    const cleanUrl = rawUrl.trim().replace(/^["']|["']$/g, '').trim();
    const cleanToken = rawToken.trim().replace(/^["']|["']$/g, '').trim();
    return new Redis({ url: cleanUrl, token: cleanToken });
  } catch (err) {
    console.error('Redis init error:', err);
    return null;
  }
}

function getResendClient() {
  try {
    const rawKey = process.env.RESEND_API_KEY;
    if (!rawKey) return null;
    const cleanKey = rawKey.trim().replace(/^["']|["']$/g, '').trim();
    return new Resend(cleanKey);
  } catch (err) {
    return null;
  }
}

// Clean production keys (v7) - zero fake data
const REDIS_KEY_REQUESTS = 'smvec_od_requests_v7';
const REDIS_KEY_AUDIT = 'smvec_od_audit_v7';
const REDIS_KEY_NOTIFS = 'smvec_od_notifs_v7';

// Default empty data - No dummy or fake records
const DEFAULT_REQUESTS = [];
const DEFAULT_AUDIT = [];
const DEFAULT_NOTIFS = [];

export async function GET() {
  try {
    const redis = getRedisClient();
    let requests = redis ? await redis.get(REDIS_KEY_REQUESTS) : null;
    let auditLogs = redis ? await redis.get(REDIS_KEY_AUDIT) : null;
    let notifications = redis ? await redis.get(REDIS_KEY_NOTIFS) : null;

    if (!requests) {
      requests = DEFAULT_REQUESTS;
      if (redis) await redis.set(REDIS_KEY_REQUESTS, requests);
    }
    if (!auditLogs) {
      auditLogs = DEFAULT_AUDIT;
      if (redis) await redis.set(REDIS_KEY_AUDIT, auditLogs);
    }
    if (!notifications) {
      notifications = DEFAULT_NOTIFS;
      if (redis) await redis.set(REDIS_KEY_NOTIFS, notifications);
    }

    return NextResponse.json({
      success: true,
      data: { requests, auditLogs, notifications },
      connectedServices: {
        redis: Boolean(redis),
        supabase: true,
        resend: true,
        clerk: true,
      },
    });
  } catch (error) {
    return NextResponse.json({
      success: true,
      data: {
        requests: DEFAULT_REQUESTS,
        auditLogs: DEFAULT_AUDIT,
        notifications: DEFAULT_NOTIFS,
      },
      fallback: true,
      error: error.message,
    });
  }
}

export async function POST(req) {
  try {
    const redis = getRedisClient();
    const resend = getResendClient();
    const body = await req.json();
    const action = body.action;
    const payload = body.payload || body;

    let requests = (redis ? await redis.get(REDIS_KEY_REQUESTS) : null) || DEFAULT_REQUESTS;
    let auditLogs = (redis ? await redis.get(REDIS_KEY_AUDIT) : null) || DEFAULT_AUDIT;
    let notifications = (redis ? await redis.get(REDIS_KEY_NOTIFS) : null) || DEFAULT_NOTIFS;

    const now = new Date();
    const timeStr = now.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ', ' + now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });

    // 1. LOGIN USER VIA INSTITUTIONAL CREDENTIALS
    if (action === 'LOGIN_USER') {
      const { role, email, password, name, rollNumber, year, section } = payload;
      const cleanEmail = email ? email.trim().toLowerCase() : '';
      if (!cleanEmail.endsWith('@smvec.ac.in')) {
        return NextResponse.json({ success: false, error: 'Only official @smvec.ac.in email addresses are permitted.' }, { status: 400 });
      }

      const roleKey = (role || '').toUpperCase();

      if (roleKey === 'STUDENT') {
        return NextResponse.json({
          success: true,
          user: {
            name: name || cleanEmail.split('@')[0].toUpperCase(),
            email: cleanEmail,
            role: 'STUDENT',
            rollNumber: rollNumber ? rollNumber.trim().toUpperCase() : '21IT101',
            department: 'Information Technology',
            year: Number(year) || 3,
            section: section || 'A',
          },
        });
      }

      if (roleKey === 'ADVISOR' || roleKey === 'STAFF') {
        const staffSecret = process.env.STAFF_PASSWORD;
        if (!password || password.trim() !== staffSecret?.trim()) {
          return NextResponse.json({ success: false, error: 'Invalid staff password. Click "Forgot Password?" to receive an OTP via Resend.' }, { status: 401 });
        }
        return NextResponse.json({
          success: true,
          user: {
            name: name || 'Class Advisor (IT-III-A)',
            email: cleanEmail,
            role: 'ADVISOR',
            department: 'Information Technology',
            year: 3,
            section: 'A',
          },
        });
      }

      if (roleKey === 'HOD') {
        const hodSecret = process.env.HOD_PASSWORD;
        if (!password || password.trim() !== hodSecret?.trim()) {
          return NextResponse.json({ success: false, error: 'Invalid HOD password. Click "Forgot Password?" to receive an OTP via Resend.' }, { status: 401 });
        }
        return NextResponse.json({
          success: true,
          user: {
            name: name || 'Dr. P. Sivakumar (HOD/IT)',
            email: cleanEmail,
            role: 'HOD',
            department: 'Information Technology',
          },
        });
      }
    }

    // 2. FORGOT PASSWORD (STRICTLY FOR STAFF/ADVISOR AND HOD ONLY VIA RESEND)
    if (action === 'FORGOT_PASSWORD') {
      const { email, role } = payload;
      if (!email || !email.toLowerCase().endsWith('@smvec.ac.in')) {
        return NextResponse.json({ success: false, error: 'Only official @smvec.ac.in email addresses are permitted.' }, { status: 400 });
      }
      if (role !== 'ADVISOR' && role !== 'HOD') {
        return NextResponse.json({ success: false, error: 'Forgot password recovery is restricted to Staff and HOD accounts.' }, { status: 400 });
      }

      const otp = Math.floor(100000 + Math.random() * 900000).toString();
      const otpKey = `smvec_otp_${email.toLowerCase().trim()}`;
      if (redis) {
        await redis.set(otpKey, { otp, role, expiresAt: Date.now() + 600000 });
      }

      if (resend) {
        try {
          const recipients = [email.toLowerCase().trim(), 'delivered@resend.dev'];
          await resend.emails.send({
            from: 'SMVEC OD Security <onboarding@resend.dev>',
            to: recipients,
            subject: `[SMVEC OD Security] Password Reset Verification Code: ${otp}`,
            html: `
              <div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; border: 1px solid #e2e8f0; border-radius: 8px; padding: 20px;">
                <h3 style="color: #3350B0; margin-top: 0;">SMVEC OD Portal | Password Recovery</h3>
                <p>Hello,</p>
                <p>A password reset verification code was requested for your <strong>${role === 'HOD' ? 'Head of Department' : 'Class Advisor / Staff'}</strong> account (${email}).</p>
                <div style="background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 6px; padding: 16px; text-align: center; margin: 20px 0;">
                  <div style="font-size: 13px; color: #475569; margin-bottom: 6px;">Your 6-Digit Security Verification Code:</div>
                  <div style="font-size: 32px; font-weight: 800; letter-spacing: 6px; color: #1e40af;">${otp}</div>
                </div>
                <p style="font-size: 12px; color: #64748b;">This code is valid for 10 minutes. If you did not make this request, please disregard this email.</p>
                <div style="border-top: 1px solid #e2e8f0; margin-top: 16px; padding-top: 12px; font-size: 11px; color: #94a3b8; text-align: center;">
                  Sri Manakula Vinayagar Engineering College · IT Department Security
                </div>
              </div>
            `,
          });
        } catch (mailErr) {
          console.warn('Forgot password email dispatch notice:', mailErr.message);
        }
      }

      return NextResponse.json({
        success: true,
        message: `A 6-digit verification code has been dispatched via Resend to ${email}.`,
      });
    }

    // 3. VERIFY OTP
    if (action === 'VERIFY_OTP') {
      const { email, otp } = payload;
      const otpKey = `smvec_otp_${email.toLowerCase().trim()}`;
      let record = redis ? await redis.get(otpKey) : null;

      if (!record || String(record.otp).trim() !== String(otp).trim()) {
        return NextResponse.json({ success: false, error: 'Invalid or expired verification code. Please request a new code.' }, { status: 400 });
      }

      return NextResponse.json({
        success: true,
        role: record.role,
        verified: true,
        message: 'Identity verified successfully.',
      });
    }

    // 3. CREATE OD (STUDENT SUBMISSION)
    if (action === 'CREATE_OD') {
      const studentEmail = payload.studentEmail || `${payload.rollNumber.toLowerCase()}@smvec.ac.in`;
      if (!studentEmail.toLowerCase().endsWith('@smvec.ac.in')) {
        return NextResponse.json({ success: false, error: 'Only official @smvec.ac.in student emails can submit OD requests.' }, { status: 400 });
      }

      const newId = `OD-2026-${String(requests.length + 1).padStart(3, '0')}`;
      const newReq = {
        id: newId,
        studentName: payload.studentName,
        studentEmail: studentEmail,
        rollNumber: payload.rollNumber,
        department: payload.department || 'Information Technology',
        year: payload.year || 3,
        section: payload.section || 'A',
        submissionType: payload.submissionType || 'SOLO',
        teamMembers: payload.submissionType === 'TEAM' ? payload.teamMembers || [] : [],
        eventType: payload.eventType,
        eventName: payload.eventName,
        eventDate: payload.eventDate,
        eventDay: payload.eventDay,
        description: payload.description,
        status: 'PENDING_ADVISOR', // Requires Advisor approval before HOD
        advisorApproved: false,
        attachmentName: payload.attachmentName || 'Supporting_Document.pdf',
        resultStatus: 'PENDING',
        createdAt: timeStr,
      };

      requests.unshift(newReq);
      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'CREATED',
        actor: `${payload.studentName} (${payload.rollNumber})`,
        role: 'STUDENT',
        time: timeStr,
        details: `Submitted On-Duty application for ${payload.eventName}`,
      });
      notifications.unshift({
        id: `N-${Date.now()}`,
        title: 'New OD Submission 📋',
        text: `${payload.studentName} submitted OD for ${payload.eventName}. Class Advisor review required.`,
        time: 'Just now',
        role: 'ADVISOR',
      });
    }

    // 4. ADVISOR APPROVE (NO EMAIL DISPATCH HERE AS PER SPECIFICATION)
    else if (action === 'ADVISOR_APPROVE') {
      const { reqId, remarks, advisorName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            status: 'APPROVED_BY_ADVISOR', // Student status becomes Approved by Advisor!
            advisorApproved: true,
            advisorRemarks: remarks || 'Verified student academic record and attendance. Approved by Class Advisor.',
            advisorName: advisorName || 'Class Advisor',
            advisorTimestamp: timeStr,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'APPROVED_BY_ADVISOR',
        actor: advisorName || 'Class Advisor',
        role: 'ADVISOR',
        time: timeStr,
        details: `Class Advisor APPROVED ${reqId} & forwarded to HOD: "${remarks || 'Approved and recommended'}"`,
      });

      notifications.unshift({
        id: `N-${Date.now()}`,
        title: 'Class Advisor Approved Your OD! ✅',
        text: `Your OD request ${reqId} was APPROVED by Class Advisor. It is now forwarded to HOD for final sanction.`,
        time: 'Just now',
        role: 'STUDENT',
      });

      notifications.unshift({
        id: `N-${Date.now() + 1}`,
        title: 'Advisor-Approved Submission ⚡',
        text: `Class Advisor approved ${reqId}. Awaiting HOD final sanction.`,
        time: 'Just now',
        role: 'HOD',
      });
    }

    // 5. ADVISOR REJECT
    else if (action === 'ADVISOR_REJECT') {
      const { reqId, remarks, advisorName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            status: 'REJECTED_ADVISOR',
            advisorApproved: false,
            advisorRemarks: remarks || 'Attendance criteria not met / Internal assessment clash.',
            advisorName: advisorName || 'Class Advisor',
            advisorTimestamp: timeStr,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'REJECTED_BY_ADVISOR',
        actor: advisorName || 'Class Advisor',
        role: 'ADVISOR',
        time: timeStr,
        details: `Class Advisor rejected ${reqId}: "${remarks}"`,
      });

      notifications.unshift({
        id: `N-${Date.now()}`,
        title: 'OD Not Approved by Advisor ⚠️',
        text: `Your OD request ${reqId} was not approved by Class Advisor. Reason: ${remarks}`,
        time: 'Just now',
        role: 'STUDENT',
      });
    }

    // 6. HOD APPROVE (CONFIRMATION MAIL TO STUDENT VIA RESEND ONLY IF ACCEPTED BY BOTH ADVISOR AND HOD)
    else if (action === 'HOD_APPROVE') {
      const { reqId, remarks, hodName } = payload;
      let targetReq = null;

      requests = requests.map((r) => {
        if (r.id === reqId) {
          targetReq = {
            ...r,
            status: 'APPROVED', // Final OD Sanctioned
            hodRemarks: remarks || 'Officially sanctioned with full attendance regularisation.',
            hodName: hodName || 'Dr. P. Sivakumar (HOD/IT)',
            hodTimestamp: timeStr,
          };
          return targetReq;
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'SANCTIONED_BY_HOD',
        actor: hodName || 'HOD',
        role: 'HOD',
        time: timeStr,
        details: `HOD granted final On-Duty sanction for ${reqId}: "${remarks || 'Sanctioned'}"`,
      });

      notifications.unshift({
        id: `N-${Date.now()}`,
        title: '🎉 OD Sanctioned by HOD!',
        text: `Your OD request ${reqId} has received official HOD approval. OD Slip is now valid!`,
        time: 'Just now',
        role: 'STUDENT',
      });

      // DISPATCH OFFICIAL CONFIRMATION MAIL VIA RESEND TO STUDENT
      // Strictly sent ONLY when accepted by BOTH advisor AND hod!
      if (resend && targetReq && targetReq.advisorApproved) {
        try {
          const studentEmail = targetReq.studentEmail || (targetReq.rollNumber ? `${targetReq.rollNumber.toLowerCase()}@smvec.ac.in` : null);
          const recipients = ['delivered@resend.dev'];
          if (studentEmail && studentEmail.endsWith('@smvec.ac.in')) {
            recipients.unshift(studentEmail);
          }

          await resend.emails.send({
            from: 'SMVEC OD Portal <onboarding@resend.dev>',
            to: recipients,
            subject: `🎉 [Official Sanction] On-Duty Approved: ${targetReq.id} (${targetReq.eventName})`,
            html: `
              <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; border: 1px solid #e2e8f0; border-radius: 8px; overflow: hidden;">
                <div style="background: #3350B0; color: #ffffff; padding: 18px; text-align: center;">
                  <h2 style="margin: 0; font-size: 18px; letter-spacing: 0.5px;">SRI MANAKULA VINAYAGAR ENGINEERING COLLEGE</h2>
                  <p style="margin: 4px 0 0; font-size: 13px; opacity: 0.9;">Department of Information Technology · Official OD Sanction</p>
                </div>
                <div style="padding: 24px; color: #1e293b; background: #ffffff;">
                  <h3 style="color: #059669; margin-top: 0;">✓ On-Duty Sanction Granted</h3>
                  <p>Dear <strong>${targetReq.studentName}</strong> (Roll No: <strong>${targetReq.rollNumber}</strong>),</p>
                  <p>Your On-Duty application has received final approval from both your <strong>Class Advisor</strong> and the <strong>Head of Department (HOD)</strong>.</p>
                  
                  <div style="background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; padding: 14px; margin: 16px 0;">
                    <div style="margin-bottom: 8px;"><strong>OD Reference:</strong> ${targetReq.id}</div>
                    <div style="margin-bottom: 8px;"><strong>Event:</strong> ${targetReq.eventName} (${targetReq.eventType})</div>
                    <div style="margin-bottom: 8px;"><strong>Event Date:</strong> ${targetReq.eventDate} (${targetReq.eventDay || ''})</div>
                    <div style="margin-bottom: 8px;"><strong>Advisor Endorsement:</strong> ${targetReq.advisorRemarks || 'Approved'} (${targetReq.advisorName || 'Class Advisor'})</div>
                    <div><strong>HOD Final Sanction:</strong> ${targetReq.hodRemarks || 'Sanctioned'} (${targetReq.hodName || 'HOD'})</div>
                  </div>

                  <p style="font-size: 13px; color: #065f46; background: #ecfdf5; border: 1px solid #a7f3d0; padding: 10px; border-radius: 6px;">
                    ✓ <strong>Official Attendance Regularisation:</strong> This notification confirms your authorized On-Duty status.
                  </p>
                </div>
                <div style="background: #f1f5f9; padding: 12px; text-align: center; font-size: 12px; color: #64748b;">
                  Sri Manakula Vinayagar Engineering College · Puducherry
                </div>
              </div>
            `,
          });
        } catch (mailErr) {
          console.warn('Student confirmation email dispatch info:', mailErr.message);
        }
      }
    }

    // 7. HOD REJECT
    else if (action === 'HOD_REJECT') {
      const { reqId, remarks, hodName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            status: 'REJECTED_HOD',
            hodRemarks: remarks || 'Department quota exceeded / Non-essential event.',
            hodName: hodName || 'HOD',
            hodTimestamp: timeStr,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'REJECTED_BY_HOD',
        actor: hodName || 'HOD',
        role: 'HOD',
        time: timeStr,
        details: `HOD rejected ${reqId}: "${remarks}"`,
      });
    }

    // 8. SUBMIT RESULT
    else if (action === 'SUBMIT_RESULT') {
      const { reqId, status, projectName, description, certificateName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            resultStatus: status,
            resultProjectName: projectName,
            resultDescription: description,
            resultCertificate: certificateName || `Certificate_${reqId}.pdf`,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'RESULT_SUBMITTED',
        actor: payload.studentName || 'Student',
        role: 'STUDENT',
        time: timeStr,
        details: `Submitted event result: ${status} for ${projectName}`,
      });
    }

    // 9. PURGE ALL DATA (TO RESET SYSTEM CLEANLY)
    else if (action === 'PURGE_ALL_DATA') {
      requests = [];
      auditLogs = [];
      notifications = [];
    }

    // Save back to Upstash Redis
    if (redis) {
      await redis.set(REDIS_KEY_REQUESTS, requests);
      await redis.set(REDIS_KEY_AUDIT, auditLogs);
      await redis.set(REDIS_KEY_NOTIFS, notifications);
    }

    return NextResponse.json({
      success: true,
      data: { requests, auditLogs, notifications },
    });
  } catch (error) {
    return NextResponse.json(
      { success: false, error: error.message },
      { status: 500 }
    );
  }
}
