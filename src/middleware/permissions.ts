import { Request, Response, NextFunction } from 'express';
import { supabaseServiceRole } from '../config/supabase';

// Simple LRU cache implementation with TTL expiration
class SimpleCache<K, V> {
  private map = new Map<K, { value: V; expiresAt: number }>();
  private maxEntries: number;

  constructor(maxEntries = 1000) {
    this.maxEntries = maxEntries;
  }

  get(key: K): V | null {
    const entry = this.map.get(key);
    if (!entry) return null;
    if (entry.expiresAt < Date.now()) {
      this.map.delete(key);
      return null;
    }
    // Refresh LRU order on hit
    this.map.delete(key);
    this.map.set(key, entry);
    return entry.value;
  }

  set(key: K, value: V, ttlMs: number): void {
    if (this.map.size >= this.maxEntries) {
      // Evict oldest item (first item in Map insertion order)
      const firstKey = this.map.keys().next().value;
      if (firstKey !== undefined) {
        this.map.delete(firstKey);
      }
    }
    this.map.set(key, { value, expiresAt: Date.now() + ttlMs });
  }
}

// Instantiate LRU caches for features and permissions (3 second TTL for features to allow instant toggles, 5 second TTL for permissions)
const featureCache = new SimpleCache<string, boolean>(1000);
const permissionCache = new SimpleCache<string, { can_read: boolean; can_write: boolean; can_delete: boolean }>(2000);
const FEATURE_CACHE_TTL_MS = 3000;
const PERMISSION_CACHE_TTL_MS = 5000;

/**
 * Helper to log permission denials to the permission_audit_log table asynchronously.
 */
async function logPermissionDenial(req: Request, logType: 'feature' | 'module', name: string, action: string) {
  if (!req.user) return;
  try {
    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const userAgent = req.headers['user-agent'] || 'unknown';

    // Execute DB insert asynchronously without blocking the client response
    supabaseServiceRole
      .from('permission_audit_log')
      .insert({
        institution_id: req.user.institution_id,
        user_id: req.user.id,
        role: req.user.role,
        module: `${logType}:${name}`,
        action,
        path: req.originalUrl || req.path,
        ip_address: ip,
        user_agent: userAgent
      })
      .then(({ error }) => {
        if (error) {
          console.error('Error inserting permission audit log:', error);
        }
      });
  } catch (err) {
    console.error('Failed to log permission denial:', err);
  }
}

// Feature toggle check: blocks access if a module is disabled for the institution
export function requireFeature(featureKey: string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    // For authenticated requests, strictly use req.user.institution_id (do NOT accept body/query overrides)
    let institutionId: string | undefined;
    if (req.user) {
      institutionId = req.user.institution_id;
    } else {
      institutionId = (req.body?.institution_id as string) || (req.query?.institution_id as string);
    }

    if (!institutionId) {
      // If we cannot determine the institution and there is no user, allow it to pass.
      // This allows public routes (like /register) to function if they don't have institution_id.
      return next();
    }

    // SuperAdmin bypasses feature checks
    if (req.user?.role === 'SuperAdmin') {
      return next();
    }

    const cacheKey = `${institutionId}:${featureKey}`;
    const cached = featureCache.get(cacheKey);
    if (cached !== null) {
      if (!cached) {
        return res.status(403).json({
          success: false,
          error: `The '${featureKey}' module is not enabled for your institution.`
        });
      }
      return next();
    }

    try {
      const { data, error } = await supabaseServiceRole
        .from('institution_features')
        .select('enabled')
        .eq('institution_id', institutionId)
        .eq('feature_key', featureKey)
        .single();

      if (error || !data) {
        // Default to enabled if no record found
        featureCache.set(cacheKey, true, FEATURE_CACHE_TTL_MS);
        return next();
      }

      featureCache.set(cacheKey, data.enabled, FEATURE_CACHE_TTL_MS);

      if (!data.enabled) {
        if (req.user) {
          await logPermissionDenial(req, 'feature', featureKey, 'read');
        }
        return res.status(403).json({
          success: false,
          error: `The '${featureKey}' module is not enabled for your institution.`
        });
      }

      next();
    } catch (err) {
      console.error('Feature check error:', err);
      return res
        .status(500)
        .json({ success: false, error: 'Internal server error performing feature enablement check.' });
    }
  };
}

// Module permission check: verifies read/write/delete for the user's role
export function requireModulePermission(module: string, action: 'read' | 'write' | 'delete') {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ success: false, error: 'Authentication required.' });
    }

    // SuperAdmin bypasses all permission checks
    if (req.user.role === 'SuperAdmin') {
      return next();
    }

    const cacheKey = `${req.user.institution_id}:${req.user.role}:${module}`;
    const cached = permissionCache.get(cacheKey);

    let permissionData = cached;

    if (!permissionData) {
      try {
        const { data, error } = await supabaseServiceRole
          .from('module_permissions')
          .select('can_read, can_write, can_delete')
          .eq('institution_id', req.user.institution_id)
          .eq('role', req.user.role)
          .eq('module', module)
          .single();

        if (error || !data) {
          // No permission record found: default deny for write/delete, allow read
          const defaultPerm = {
            can_read: true,
            can_write: false,
            can_delete: false
          };
          permissionCache.set(cacheKey, defaultPerm, PERMISSION_CACHE_TTL_MS);
          permissionData = defaultPerm;
        } else {
          const perm = {
            can_read: !!data.can_read,
            can_write: !!data.can_write,
            can_delete: !!data.can_delete
          };
          permissionCache.set(cacheKey, perm, PERMISSION_CACHE_TTL_MS);
          permissionData = perm;
        }
      } catch (err) {
        console.error('Permission check error:', err);
        // Fail-closed in production
        return res
          .status(500)
          .json({ success: false, error: 'Internal server error performing role permission validation.' });
      }
    }

    const hasPermission =
      (action === 'read' && permissionData.can_read) ||
      (action === 'write' && permissionData.can_write) ||
      (action === 'delete' && permissionData.can_delete);

    if (!hasPermission) {
      await logPermissionDenial(req, 'module', module, action);
      return res.status(403).json({
        success: false,
        error: `Your role '${req.user.role}' does not have '${action}' permission for '${module}'.`
      });
    }

    next();
  };
}
