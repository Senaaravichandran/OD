// Postgres access for the OD API.
//
// Serverless functions come and go, so the pool is cached on globalThis to
// survive hot reloads and warm invocations. Supabase's session pooler is
// already pooling on its side, so only a couple of connections are needed here.

import { Pool } from 'pg';

const globalForPg = globalThis;

function connectionString() {
  const raw = (process.env.SUPABASE_DB_URL || '')
    .trim()
    .replace(/^["']|["']$/g, '')
    .replace(/﻿/g, '');
  if (!raw) throw new Error('SUPABASE_DB_URL is not configured.');
  return raw;
}

export function pool() {
  if (!globalForPg.__odPool) {
    globalForPg.__odPool = new Pool({
      connectionString: connectionString(),
      max: 3,
      idleTimeoutMillis: 10_000,
      connectionTimeoutMillis: 10_000,
      // Supabase terminates TLS with its own chain; verifying it here would
      // need the CA bundle shipped with the function for no security gain,
      // since the host is pinned by the connection string.
      ssl: { rejectUnauthorized: false },
    });
  }
  return globalForPg.__odPool;
}

export async function query(text, params) {
  const result = await pool().query(text, params);
  return result.rows;
}

export async function one(text, params) {
  const rows = await query(text, params);
  return rows[0] || null;
}

/// Runs `fn` inside a transaction, rolling back if it throws.
export async function transaction(fn) {
  const client = await pool().connect();
  try {
    await client.query('begin');
    const result = await fn(client);
    await client.query('commit');
    return result;
  } catch (err) {
    await client.query('rollback').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/// Appends to the audit trail. Never throws: losing a log line must not fail
/// the action that was being recorded.
export async function audit(client, { actorUserId, actorEmail, actorRole, action, entityType, entityId, details }) {
  try {
    const runner = client || { query: (t, p) => pool().query(t, p) };
    await runner.query(
      `insert into audit_logs (actor_user_id, actor_email, actor_role, action, entity_type, entity_id, details)
       values ($1, $2, $3, $4, $5, $6, $7)`,
      [actorUserId || null, actorEmail || null, actorRole || null, action, entityType, entityId || null,
       details ? JSON.stringify(details) : null]
    );
  } catch (err) {
    console.warn('audit write failed:', err.message);
  }
}
