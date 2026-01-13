# Solid Cable Implementation Plan

**Created:** January 13, 2026  
**Status:** 🚧 IN PROGRESS  
**Objective:** Replace Redis-based ActionCable with database-backed Solid Cable

---

## Background

### Problem

- ActionCable in production requires Redis for pub/sub messaging
- Google Cloud Run doesn't have a built-in Redis service
- Options like Memorystore require VPC setup and add $25+/month cost

### Solution

- **Solid Cable** - A database-backed ActionCable adapter
- Uses existing PostgreSQL (Cloud SQL) instead of Redis
- Compatible with Rails 7.2.2 (our current version)
- Zero additional infrastructure cost

### Benefits

- ✅ No Redis dependency
- ✅ Uses existing Cloud SQL database
- ✅ Works across multiple Cloud Run instances
- ✅ Zero additional cost
- ✅ Future-proof for scaling

---

## Pre-Implementation Checklist

- [x] Commit current state to git (rupi-v3)
- [x] Commit current state to git (rupi-engine)
- [x] Push to remote repositories
- [x] Create this implementation plan

---

## Implementation Phases

### Phase 1: Install Solid Cable Gem

**Status:** ⏳ Pending

- [ ] Add `gem "solid_cable"` to Gemfile
- [ ] Run `bundle install`
- [ ] Verify gem installed correctly

### Phase 2: Run Solid Cable Installer

**Status:** ⏳ Pending

- [ ] Run `bin/rails solid_cable:install`
- [ ] Review generated configuration files
- [ ] Review generated migration

### Phase 3: Configure cable.yml

**Status:** ⏳ Pending

- [ ] Update `config/cable.yml` for production
- [ ] Set appropriate polling interval
- [ ] Configure message retention

### Phase 4: Database Migration

**Status:** ⏳ Pending

- [ ] Run migration locally to test
- [ ] Verify solid_cable_messages table created
- [ ] Test ActionCable functionality locally

### Phase 5: Local Testing

**Status:** ⏳ Pending

- [ ] Start local dev server
- [ ] Test AI Chat functionality
- [ ] Verify WebSocket connections work
- [ ] Test message streaming

### Phase 6: Production Deployment

**Status:** ⏳ Pending

- [ ] Build new Docker image (v1.5.0)
- [ ] Push to Artifact Registry
- [ ] Deploy to Cloud Run
- [ ] Run database migration on Cloud SQL
- [ ] Verify production functionality

### Phase 7: Verification & Cleanup

**Status:** ⏳ Pending

- [ ] Test AI Chat on rupiapp.in
- [ ] Test Bank Statement upload
- [ ] Commit final changes
- [ ] Update documentation
- [ ] Update RUPI_SIDECAR_SESSION.md

---

## Rollback Plan

If Solid Cable implementation fails:

1. **Revert to commit:** `9fa131c` (Pre-Solid Cable snapshot)
2. **Redeploy v1.4.0** (current working version)
3. **Alternative:** Use `adapter: async` temporarily

---

## Technical Details

### Current cable.yml (Redis-based)

```yaml
production:
  adapter: redis
  url: <%= ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" } %>
  channel_prefix: sure_production
```

### Target cable.yml (Solid Cable)

```yaml
production:
  adapter: solid_cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

---

## Notes

- Solid Cable uses database polling instead of Redis pub/sub
- Slight latency increase (~100ms) vs Redis - acceptable for chat
- Messages auto-expire based on retention setting
- No cleanup jobs needed - handled by gem

---

_Document maintained by: Claude (Antigravity AI)_  
_Last updated: January 13, 2026_
