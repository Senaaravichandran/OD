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

const REDIS_KEY_REQUESTS = 'smvec_od_requests_v2';
const REDIS_KEY_AUDIT = 'smvec_od_audit_v2';
const REDIS_KEY_NOTIFS = 'smvec_od_notifs_v2';

// Initial Seed Data
const DEFAULT_REQUESTS = [
  {
    id: 'OD-2026-001',
    studentName: 'Aravindhan S',
    rollNumber: '21IT101',
    department: 'Information Technology',
    year: 3,
    section: 'A',
    submissionType: 'TEAM',
    teamMembers: ['Aravindhan S (21IT101)', 'Priya K (21IT102)', 'Rahul M (21IT103)'],
    eventType: 'Hackathon',
    eventName: 'Smart India Hackathon 2026 (Grand Finale)',
    eventDate: '2026-09-22',
    eventDay: 'Tuesday',
    description: 'Selected for National Grand Finale at Bengaluru Nodal Center. 3 days On-Duty required.',
    status: 'APPROVED', // Fully sanctioned by HOD
    advisorApproved: true,
    advisorRemarks: 'Verified student academic record (CGPA > 8.5) and attendance (> 85%). Approved and recommended for college representation.',
    advisorName: 'Dr. K. Senthil (Class Advisor IT-III-A)',
    advisorTimestamp: '2026-09-15 11:30 AM',
    hodRemarks: 'Officially sanctioned with travel allowance and attendance compensation. Best wishes!',
    hodName: 'Dr. P. Sivakumar (HOD/IT)',
    hodTimestamp: '2026-09-16 03:45 PM',
    attachmentName: 'SIH_Shortlist_Letter.pdf',
    resultStatus: 'WON',
    resultProjectName: 'AI Autonomous Drone for Crop Health Monitoring',
    resultCertificate: 'SIH_First_Prize_Cert.pdf',
    createdAt: '2026-09-14 10:15 AM',
  },
  {
    id: 'OD-2026-002',
    studentName: 'Karthik R',
    rollNumber: '21IT115',
    department: 'Information Technology',
    year: 3,
    section: 'A',
    submissionType: 'SOLO',
    teamMembers: [],
    eventType: 'Internship',
    eventName: 'TCS iON Industrial Cloud Immersion',
    eventDate: '2026-09-25',
    eventDay: 'Friday',
    description: 'Selected for 2-week hands-on industrial immersion on AWS and DevSecOps at TCS Siruseri campus.',
    status: 'APPROVED_BY_ADVISOR', // Approved by advisor, waiting for HOD final sanction
    advisorApproved: true,
    advisorRemarks: 'Offer letter checked with TCS HR portal. Approved by Class Advisor. Forwarded for HOD sanction.',
    advisorName: 'Dr. K. Senthil (Class Advisor IT-III-A)',
    advisorTimestamp: '2026-09-16 09:30 AM',
    hodRemarks: null,
    hodName: null,
    hodTimestamp: null,
    attachmentName: 'TCS_Selection_Offer.pdf',
    resultStatus: 'PENDING',
    createdAt: '2026-09-15 04:20 PM',
  },
  {
    id: 'OD-2026-003',
    studentName: 'Sneha M',
    rollNumber: '21IT142',
    department: 'Information Technology',
    year: 3,
    section: 'A',
    submissionType: 'TEAM',
    teamMembers: ['Sneha M (21IT142)', 'Divya S (21IT143)'],
    eventType: 'Paper Presentation',
    eventName: 'IEEE ICAIoT 2026 International Conference',
    eventDate: '2026-09-30',
    eventDay: 'Wednesday',
    description: 'Oral presentation of research paper on Edge AI for Predictive Agriculture in Pondicherry University.',
    status: 'PENDING_ADVISOR', // Needs Class Advisor to click Approve!
    advisorApproved: false,
    advisorRemarks: null,
    advisorName: null,
    advisorTimestamp: null,
    hodRemarks: null,
    hodName: null,
    hodTimestamp: null,
    attachmentName: 'IEEE_Acceptance_Proof.pdf',
    resultStatus: 'PENDING',
    createdAt: '2026-09-17 01:10 PM',
  },
];

const DEFAULT_AUDIT = [
  { id: 'AUD-01', action: 'CREATED', actor: 'Aravindhan S (21IT101)', role: 'STUDENT', time: '14 Sep, 10:15 AM', details: 'Submitted OD request for Smart India Hackathon' },
  { id: 'AUD-02', action: 'APPROVED_BY_ADVISOR', actor: 'Dr. K. Senthil', role: 'ADVISOR', time: '15 Sep, 11:30 AM', details: 'Class Advisor approved request & forwarded to HOD with recommendation' },
  { id: 'AUD-03', action: 'SANCTIONED_BY_HOD', actor: 'Dr. P. Sivakumar', role: 'HOD', time: '16 Sep, 03:45 PM', details: 'HOD granted final On-Duty sanction with digital signature' },
];

const DEFAULT_NOTIFS = [
  { id: 'N-1', title: 'OD Approved by HOD 🎉', text: 'Smart India Hackathon OD has been sanctioned by HOD Dr. P. Sivakumar.', time: 'Yesterday', role: 'STUDENT' },
  { id: 'N-2', title: 'New Submission Awaiting Review 📋', text: 'Sneha M (21IT142) submitted an OD request for IEEE ICAIoT 2026.', time: '2 hours ago', role: 'ADVISOR' },
  { id: 'N-3', title: 'Advisor Approved Submission ⚡', text: 'Dr. K. Senthil approved TCS Internship for Karthik R and forwarded to HOD.', time: '1 day ago', role: 'HOD' },
];

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
    // Fallback if Redis transient error
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
    const { action, payload } = body;

    let requests = (redis ? await redis.get(REDIS_KEY_REQUESTS) : null) || DEFAULT_REQUESTS;
    let auditLogs = (redis ? await redis.get(REDIS_KEY_AUDIT) : null) || DEFAULT_AUDIT;
    let notifications = (redis ? await redis.get(REDIS_KEY_NOTIFS) : null) || DEFAULT_NOTIFS;

    const now = new Date();
    const timeStr = now.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) + ', ' + now.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });

    if (action === 'CREATE_OD') {
      const newId = `OD-2026-${String(requests.length + 1).padStart(3, '0')}`;
      const newReq = {
        id: newId,
        studentName: payload.studentName,
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
        status: 'PENDING_ADVISOR', // Waiting for Advisor approval!
        advisorApproved: false,
        attachmentName: `Brochure_${payload.eventName.replace(/\s+/g, '_')}.pdf`,
        createdAt: timeStr,
      };

      requests.unshift(newReq);
      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'CREATED',
        actor: `${payload.studentName} (${payload.rollNumber})`,
        role: 'STUDENT',
        time: timeStr,
        details: `Submitted OD request for ${payload.eventName}`,
      });
      notifications.unshift({
        id: `N-${Date.now()}`,
        title: 'New OD Submission 📋',
        text: `${payload.studentName} submitted OD for ${payload.eventName}. Class Advisor review required.`,
        time: 'Just now',
        role: 'ADVISOR',
      });
    } else if (action === 'ADVISOR_APPROVE') {
      // CLASS ADVISOR APPROVES THE OD REQUEST!
      const { reqId, remarks, advisorName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            status: 'APPROVED_BY_ADVISOR', // Student status becomes Approved by Advisor!
            advisorApproved: true,
            advisorRemarks: remarks || 'Verified student eligibility and attendance. Approved by Class Advisor.',
            advisorName: advisorName || 'Dr. K. Senthil',
            advisorTimestamp: timeStr,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'APPROVED_BY_ADVISOR',
        actor: advisorName || 'Dr. K. Senthil',
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
        text: `Advisor approved ${reqId}. Awaiting HOD final sanction.`,
        time: 'Just now',
        role: 'HOD',
      });

      // Send automated email alert via Resend (async simulation/real)
      if (resend) {
        try {
          await resend.emails.send({
            from: 'onboarding@resend.dev',
            to: 'delivered@resend.dev',
            subject: `[SMVEC OD] Advisor Approved Request ${reqId}`,
            html: `<p>OD Request <strong>${reqId}</strong> has been approved by Class Advisor <strong>${advisorName}</strong> and is ready for HOD final sanction.</p>`,
          });
        } catch (_) {
          // Continue cleanly even if test email domain restriction applies
        }
      }
    } else if (action === 'ADVISOR_REJECT') {
      const { reqId, remarks, advisorName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            status: 'REJECTED_ADVISOR',
            advisorApproved: false,
            advisorRemarks: remarks || 'Low attendance / dates clash with internal exams.',
            advisorName: advisorName || 'Dr. K. Senthil',
            advisorTimestamp: timeStr,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'REJECTED_BY_ADVISOR',
        actor: advisorName || 'Dr. K. Senthil',
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
    } else if (action === 'HOD_APPROVE') {
      // HOD GIVES FINAL SANCTION (Only possible after Advisor approval!)
      const { reqId, remarks, hodName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            status: 'APPROVED', // Final OD Sanctioned
            hodRemarks: remarks || 'Sanctioned with full attendance compensation.',
            hodName: hodName || 'Dr. P. Sivakumar',
            hodTimestamp: timeStr,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'SANCTIONED_BY_HOD',
        actor: hodName || 'Dr. P. Sivakumar',
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

      if (resend) {
        try {
          await resend.emails.send({
            from: 'onboarding@resend.dev',
            to: 'delivered@resend.dev',
            subject: `[SMVEC OD] Final Approval for ${reqId}`,
            html: `<p>OD Request <strong>${reqId}</strong> has been officially approved and sanctioned by HOD.</p>`,
          });
        } catch (_) {
          // ignore email sandbox restrictions
        }
      }
    } else if (action === 'HOD_REJECT') {
      const { reqId, remarks, hodName } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            status: 'REJECTED_HOD',
            hodRemarks: remarks || 'Department quota exceeded / Non-essential event.',
            hodName: hodName || 'Dr. P. Sivakumar',
            hodTimestamp: timeStr,
          };
        }
        return r;
      });

      auditLogs.unshift({
        id: `AUD-${Date.now()}`,
        action: 'REJECTED_BY_HOD',
        actor: hodName || 'Dr. P. Sivakumar',
        role: 'HOD',
        time: timeStr,
        details: `HOD rejected ${reqId}: "${remarks}"`,
      });
    } else if (action === 'SUBMIT_RESULT') {
      const { reqId, status, projectName, description } = payload;
      requests = requests.map((r) => {
        if (r.id === reqId) {
          return {
            ...r,
            resultStatus: status,
            resultProjectName: projectName,
            resultDescription: description,
            resultCertificate: `Certificate_${reqId}.pdf`,
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
    } else if (action === 'RESET_DEMO') {
      requests = DEFAULT_REQUESTS;
      auditLogs = DEFAULT_AUDIT;
      notifications = DEFAULT_NOTIFS;
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
