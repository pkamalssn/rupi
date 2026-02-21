# 📋 RUPI Beta Release Checklist

> Last Updated: February 22, 2026
> Target Version: v3.4.0-beta ✅ RELEASED
> Current Version: v3.4.0-beta

---

## ✅ Completed Features

### 1. First-Time User Onboarding Tour ✅

**Version:** v3.3.17 | **Status:** DONE

- [x] Auto-start tour for new users
- [x] Sample data loading option
- [x] 6-step guided tour covering all features
- [x] 4-panel spotlight overlay (reliable cutout)
- [x] Smart tooltip positioning with collision detection
- [x] Design system color integration
- [x] Centered completion modal with celebration
- [x] Tour completion preference saved

### 2. AI Chat Rate Limiting ✅

**Version:** v3.3.17 | **Status:** DONE

- [x] Daily message limit: 50 messages/user/day
- [x] Cooldown: 5 seconds between messages
- [x] Automatic reset at midnight IST
- [x] UI indicator showing remaining messages
- [x] Error messages with reset time
- [x] No migration required (uses preferences JSONB)

### 3. AI Chat Encryption ✅

**Version:** v3.3.17 | **Status:** DONE

- [x] Message content encrypted at rest
- [x] Rails 7 built-in encryption
- [x] Auto-detection of encryption keys
- [x] Follows EnableBankingItem pattern

---

## ⏳ Pending for Beta

### 4. Mobile Responsiveness 🔄

**Priority:** HIGH | **Effort:** 0.5-1 day | **Status:** AUDITED ✅

#### Audit Results (Feb 2, 2026)

**✅ Login Page (Public):**

- Mobile (375px): Excellent - centered card, full-width inputs
- Tablet (768px): Excellent - proper max-width constraint
- Desktop (1440px): Excellent - professional layout

**✅ Layout Structure:**

- [x] Mobile top nav with hamburger menu (`lg:hidden`)
- [x] Desktop left navbar (`hidden lg:block`)
- [x] Mobile bottom nav with safe-area-inset
- [x] Collapsible sidebars with touch handlers
- [x] Mobile sidebar overlay with close button

**✅ Dashboard:**

- [x] Touch-enabled sortable sections
- [x] Responsive grid layouts

**✅ Transactions:**

- [x] Responsive grid (`grid grid-cols-12`)
- [x] Category column hidden on mobile (`hidden md:flex`)
- [x] Proper truncation for long names

**⚠️ Minor Issues (Non-blocking):**

| Issue                     | Current | Recommended  | Priority |
| ------------------------- | ------- | ------------ | -------- |
| Icon button touch targets | 32-40px | 44px minimum | LOW      |

**Conclusion:** App is mobile-ready for Beta. Minor touch target improvements can be post-Beta.

### 5. Export AI Chat 📥

**Version:** v3.3.18 | **Status:** DONE ✅

- [x] Export as Markdown (downloads .md file)
- [x] Export for Print/PDF (opens printer-friendly page)
- [x] Include all messages with timestamps
- [x] Professional formatting
- [x] Meaningful filenames

### 6. Guided Action Onboarding 🎓

**Version:** v3.3.19 | **Status:** DONE ✅

- [x] 8-step interactive guided journey
- [x] Sample data loading as first step
- [x] Action-required progression (not passive)
- [x] Progress bar with step counter
- [x] Skip option for returning users
- [x] Restart from Settings → Learning & Help
- [x] State persisted in user preferences
- [x] Visual tour still available separately

---

## 🔮 Deferred to Post-Beta

### Daily Expense Tracker (v3.5+)

**Effort:** 3-5 days

- [ ] Quick expense entry widget
- [ ] Text input parsing with AI
- [ ] Voice input support
- [ ] Auto-categorization
- [ ] Smart sync with statement uploads
- [ ] Duplicate detection and merging
- [ ] FAB button for quick access

### Paid Tiers (v3.6+)

**Effort:** 2-3 days

- [ ] Free tier: 20 messages/day
- [ ] Basic tier (₹99): 50 messages/day
- [ ] Pro tier (₹299): 200 messages/day
- [ ] Unlimited tier (₹499): No limits
- [ ] Stripe/Razorpay integration
- [ ] Upgrade prompts in UI

---

## 🔧 Configuration for Beta

### Environment Variables Required

```bash
# AI API (Required)
GOOGLE_AI_API_KEY=your_key

# Encryption (Auto-generated if missing)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=xxx
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=xxx
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=xxx

# Rate Limiting (Defaults in code)
# AI_DAILY_LIMIT=50 (hardcoded in User model)
# AI_COOLDOWN_SECONDS=5 (hardcoded in User model)
```

### Adjusting Rate Limits

```ruby
# app/models/user.rb
AI_DAILY_LIMIT = 50         # Change this for different limits
AI_COOLDOWN_SECONDS = 5     # Change this for different cooldowns
```

---

## 📊 Beta Success Metrics

### User Engagement

- [ ] Track daily active users
- [ ] Track AI messages per user
- [ ] Track statement uploads per user
- [ ] Track tour completion rate

### Cost Monitoring

- [ ] Monitor Gemini API usage
- [ ] Alert if daily tokens exceed budget
- [ ] Track cost per user

### Error Tracking

- [ ] Monitor 500 errors
- [ ] Track failed statement imports
- [ ] Track AI response failures

---

## 🚀 Beta Launch Checklist

### Pre-Launch

- [ ] All HIGH priority items completed
- [ ] Mobile responsiveness verified
- [ ] Tour tested with fresh account
- [ ] Rate limiting tested
- [ ] Error messages user-friendly
- [ ] Help & FAQ page updated

### Launch Day

- [ ] Announce to beta users
- [ ] Monitor error logs
- [ ] Be available for support
- [ ] Collect feedback via in-app form

### Post-Launch

- [ ] Review user feedback
- [ ] Address critical bugs within 24h
- [ ] Weekly usage reports
- [ ] Plan v3.5 based on feedback

---

## 📅 Version History

| Version | Date        | Changes                             |
| ------- | ----------- | ----------------------------------- |
| v3.3.17 | Feb 2, 2026 | Rate limiting, encryption, tour fix |
| v3.3.16 | Feb 2, 2026 | Tour design system colors           |
| v3.3.15 | Feb 2, 2026 | Tour collision detection            |
| v3.3.14 | Feb 2, 2026 | Tour redesign (SVG mask)            |
| v3.3.13 | Feb 2, 2026 | Critical bug fixes                  |
| v3.3.12 | Feb 1, 2026 | UI Polish Release                   |

---

## 📝 Notes

- Beta target: 30 active users
- Estimated monthly AI cost: $10-15
- Rate limits can be increased based on usage patterns
- Encryption keys auto-generated for ALL modes (self-hosted and managed)
