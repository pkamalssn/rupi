# Changelog - RUPI

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

---

## [3.3.18] - 2026-02-02

### Added - Export AI Chat 📥

Users can now export their AI conversations for offline reference:

**Export as Markdown:**

- Downloads a `.md` file with full chat history
- Includes timestamps for each message
- Formatted with headers and separators
- Includes chat ID for reference

**Export for Print (PDF):**

- Opens a printer-friendly page
- One-click "Print / Save as PDF" button
- Professional styling with RUPI branding
- Messages formatted with proper page breaks
- Back to Chat button for easy navigation

**Access:**

- Chat menu (three dots) → "Export as Markdown" or "Export for Print"

---

## [3.3.17] - 2026-02-02

### 🚀 Beta Release Features

#### AI Rate Limiting 🚦

Implemented sustainable usage limits to protect API costs during Beta:

- **Daily Limit**: 50 messages per user per day
- **Cooldown**: 5 seconds between messages (spam prevention)
- **Reset**: Automatic daily reset at midnight IST
- **UI Indicator**: Shows remaining messages when < 10 left
- **Error Messages**: User-friendly alerts with reset time

**Technical Details:**

- Uses existing `preferences` JSONB field (no migration needed)
- Rate tracking: `User#ai_rate_limit_status`, `#can_send_ai_message?`
- Controller enforcement in `MessagesController#check_rate_limit`

#### AI Chat Encryption 🔐

Enhanced privacy for user's financial conversations:

- **Encryption at Rest**: All AI message content is now encrypted
- **Rails 7 Encryption**: Uses built-in `encrypts :content`
- **Auto-Detection**: Only enables if encryption keys are configured
- **Pattern**: Follows same approach as EnableBankingItem

#### Tour Spotlight Fix 🎯

Final fix for the onboarding tour spotlight:

- **4-Panel Overlay**: Uses 4 overlay divs instead of SVG mask
- **Reliable Cutout**: Target element is now truly visible (not dimmed)
- **Better Positioning**: Improved collision detection for tooltip placement

---

## [3.3.16] - 2026-02-02

### Fixed - Tour Design System Integration 🎨

Complete color and styling overhaul to match RUPI's design system exactly:

**Colors (from maybe-design-system.css):**

- Surface: `#0B0B0B` (bg-surface dark)
- Container: `#171717` (gray-900, bg-container dark)
- Container Hover: `#242424` (gray-800)
- Success: `#12B76A` (green-500)
- Overlay: `rgba(11,11,11,0.92)` (near-black)

**Fixes:**

- ✅ **Dark overlay now ALWAYS visible** - even on "Welcome" step
- ✅ **Spotlight ring hidden on center steps** - no confusing highlight
- ✅ **Removed SVG mask** - using solid overlay + ring for reliability
- ✅ **Geist font** - matches app typography
- ✅ **Renamed all CSS classes** - `rupi-tour-*` prefix to avoid conflicts

---

## [3.3.15] - 2026-02-02

### Fixed - Tour UX Issues 🔧

Critical fixes based on user feedback:

- **🔦 SVG Mask Spotlight** - Proper cutout effect using SVG mask technique
  - Target element is now FULLY VISIBLE (not dimmed)
  - Clean rectangular hole in dark overlay
- **💡 Highlight Ring** - Pulsing green border around target element
  - 3px solid border with animated glow
  - Makes it crystal clear what's being explained
- **📍 Smart Positioning** - Tooltip placed AWAY from target, never on top
  - Configurable minimum offset per step
  - Proper viewport boundary detection
- **🎨 Consistent Styling** - Uses app's CSS variables
  - `--color-container`, `--color-text-primary`, `--color-success`
  - Matches dark mode perfectly
- **🎉 Centered Completion Modal** - Big celebratory popup in center
  - Replaces tiny corner notification
  - "You're All Set!" with clear CTA

---

## [3.3.14] - 2026-02-02

### Changed - Professional Tour Redesign 🎯

Complete rewrite of the guided tour system for a professional, polished experience:

- **Spotlight Effect** - Dark overlay with transparent cutout highlighting the target element
- **Pulsing Border** - Animated green glow around highlighted element draws attention
- **Premium Tooltip Design** - Gradient background, smooth animations, arrow pointers
- **Progress Indicators** - Visual dots showing current step and completion status
- **Smooth Transitions** - 0.4s cubic-bezier animations between steps
- **Completion Message** - Celebratory notification when tour finishes
- **Auto-start After Demo Data** - Tour automatically starts after loading sample data
- **Reduced Steps** - Condensed from 8 to 6 focused, essential steps

### Technical

- Spotlight uses `box-shadow: 0 0 0 9999px` technique for cutout effect
- CSS animations for pulse and tooltip entry
- Global functions (`window.startRupiTour`, `window.nextRupiTourStep`) for menu integration
- Proper cleanup of DOM elements on tour end

---

## [3.3.13] - 2026-02-02

### Fixed - Critical Bug Fixes

- **🔴 Tour Feature** - Fixed "Take a Tour" completely broken
  - Added `plain_button` variant to DS::MenuItem for Stimulus actions
  - Made tour controller globally accessible via `window.startRupiTour()`
  - Tour now works properly from user menu
- **Category Badge Truncation** - Fixed category names like "Food & Di" cut off mid-word
  - Added tooltip showing full category name on hover
  - Increased category column width from 2 to 3 grid columns
  - Reduced transaction name column from 8 to 7 columns

### Removed

- **AI Prompts** - Removed OpenAI prompt settings (RUPI uses Gemini, not OpenAI)
- **LLM Usage** - Removed LLM usage tracking (was tracking OpenAI, not our Gemini sidecar)
- **API Key** - Removed API key generation (not needed for SaaS, potential security exposure)

---

## [3.3.12] - 2026-02-01

### Changed - UI Polish Release

- **AI Chat Input** - Removed non-functional placeholder buttons (+, ⌘, @, pointer)
- **Dashboard Buttons** - Renamed "+New" to "New Account" for clarity
- **Dashboard Button Alignment** - All action buttons now use consistent DS::Link components
- **Sankey Chart Labels** - Long category names (>15 chars) now truncated with ellipsis
- **Balance Sheet Progress Bars** - Modern horizontal bar style replaces ASCII vertical bars
- **Transaction Date Headers** - Changed from "DATE · 1" to "DATE (1 transaction)"

### Fixed

- **Transaction Category Badges** - Added max-width constraint to prevent overlap with amount column

---

## [3.3.11] - 2026-02-01

### Fixed

- **Profile Page Crash** - Fixed "Service account credentials missing" error when viewing Profile Info
  - Replaced direct `profile_image.url` call with `safe_avatar_url` proxy method

---

## [3.3.10] - 2026-02-01

### Fixed

- **Login Redirect Loop** - Fixed session not persisting after successful login
  - Root cause: Stale `session_token` cookie from old sessions was being read instead of new session
  - Fix: Clear old cookies before creating session + set both Rails session AND signed cookie

---

## [3.3.1] - 2026-01-15

### Added

- **Clear All Data Button** - One-click button to delete all demo/sample data
- **DemoDataCreator.clear()** - Class method to remove all demo accounts and categories

### Fixed

- **Memory Limit** - Increased Cloud Run memory from 512MB to 1GB
- **Sample Data Check** - Now excludes soft-deleted (pending_deletion) accounts
- **Profile Upload Crash** - Added graceful error handling for storage failures
- **Profile Upload Error Message** - Shows user-friendly message instead of 500 error

---

## [3.3.0] - 2026-01-14

### Added - Onboarding & Security Release 🚀

#### 🎉 Onboarding Experience

- **Redesigned Welcome Screen** - Clean, modern design without emojis
- **Load Sample Data** - One-click button to populate demo Indian financial portfolio
- **Guided Tour** - 7-step interactive tour for first-time users
- **Tour Auto-Start** - Tour triggers automatically after loading sample data
- **"Take a Tour" Button** - Manual tour trigger in user menu

#### 📊 Sample Data (Demo Portfolio)

- 2 Savings Accounts (HDFC, SBI) with realistic transactions
- 2 Credit Cards (HDFC Millennia, Amazon Pay ICICI)
- 2 Loans (SBI Home Loan ₹42.5L, Bajaj Personal Loan ₹1.85L)
- 2 Investments (PPF ₹5.2L, ICICI Fixed Deposit ₹2L)
- 30+ realistic Indian transactions (Swiggy, Zomato, TCS Salary, etc.)

#### 🔒 Security Hardening

- **Database Backups** - Automated daily backups at 3 AM
- **SSL Required** - All database connections now require SSL
- **Field-Level Encryption** - Account numbers encrypted (AES-256-GCM)
- **Google Cloud Storage** - Profile images stored in GCS (persistent across deployments)
- **Graceful Avatar Handling** - `safe_avatar_url` prevents crashes on missing files

#### 🛠️ Bug Fixes

- Fixed "Supports HDFC, ICICI..." text placement (now inside Upload card)
- Fixed dark mode icon colors on welcome screen
- Fixed profile image upload persistence (was using container disk)
- Changed onboarding button from "Complete" to "Next"

### Changed

- Welcome screen uses design system tokens for consistent theming
- Sample data button has confirmation dialog before loading

---

## [3.2.0] - 2026-01-14

### Added - Pre-BETA Security & UX Release

#### 🔒 Security Hardening

- **Rate Limiting** - Rack::Attack protection on AI and parsing endpoints
- **Input Validation** - Message length limits (2-5000 chars), chat history limits
- **Graceful Error Handling** - User-friendly messages for AI timeouts and failures

#### 🎨 UX Improvements

- **Enhanced AI Chat Suggestions** - 6 India-specific example questions
- **Improved Loading States** - Animated bouncing dots indicator
- **Better Error Messages** - Context-aware error text with retry suggestions
- **AI Response Copy Button** - One-click copy for AI insights
- **Enhanced Onboarding** - Welcome screen with 3 action cards for new users

#### 📱 Mobile Enhancements

- **Touch Target Optimization** - Minimum 44px touch targets
- **Input Zoom Prevention** - 16px font for mobile inputs
- **Improved Scrolling** - Smooth touch scrolling on all views

#### 📄 Legal Pages

- **Privacy Policy** - Comprehensive privacy policy at `/privacy`
- **Terms of Service** - Full terms at `/terms`
- **Footer Links** - Help, Privacy, Terms accessible from footer
- **User Menu Links** - Legal pages accessible from profile dropdown

#### 🛠️ Developer Experience

- **Demo Data Creator** - Service class for sample transactions
- **CI/CD Pipeline** - Cloud Build auto-deploy on push to master

### Changed

- Enhanced clipboard controller with text value support
- Footer now links to full legal pages instead of modals
- Improved error response format with `retry_after` hints

---

## [3.1.0] - 2026-01-14

### Added - Production Deployment

- 🌐 **Google Cloud Run Deployment** - Production-grade infrastructure
- 📧 **Resend Email Integration** - Professional email from `mail.rupiapp.in`
- 🔌 **Solid Cable** - Database-backed ActionCable (no Redis needed)
- 🤖 **Gemini 3 Flash** - Upgraded to `gemini-3-flash-preview`

### Changed

- Email senders now use custom domain:
  - Welcome: `vanakkam@mail.rupiapp.in`
  - Password Reset: `noreply@mail.rupiapp.in`
  - Invitations: `support@mail.rupiapp.in`
- ActionCable uses PostgreSQL instead of Redis
- Improved email templates (removed repetition, cleaner design)
- Version display now dynamic (uses `Rupi.full_version`)

### Fixed

- Docker file permissions (chown entire /rails directory)
- WebSocket connections in Cloud Run environment
- AI Chat personality consistency

---

## [3.0.0] - 2026-01-04

### Added - Open Core Architecture

- **Provider::Engine client** for communicating with RUPI Engine API
- **SSE streaming support** for real-time AI chat responses
- **Tool execution framework** - AI can query database via function calling
- **Assistant responder** with Gemini 3 thoughtSignature support
- **Context-aware fallbacks** when AI returns empty responses
- **RUPI_SIDECAR_SESSION.md** documentation for debugging

### Changed - Architecture Refactor

- AI chat now uses RUPI Engine API instead of local Gemini calls
- Bank statement parsing moved to RUPI Engine (not in this repo)
- Auto-categorization moved to RUPI Engine (not in this repo)
- Renamed project from "RUPI v2.3" to "RUPI" (open-source base)

### Removed - Proprietary Features

- Local Gemini API integration (moved to RUPI Engine)
- Bank statement parsers (moved to RUPI Engine)
- Auto-categorization logic (moved to RUPI Engine)
- EMI reconciliation engine (moved to RUPI Engine)

### Fixed - AI Chat Stability

- Fixed triple text duplication in AI responses
- Fixed "Analyzing your data..." getting stuck
- Fixed thoughtSignature handling for Gemini 3
- Fixed empty responses when period has no data
- Added smart period defaults (last complete month)

---

## [2.3.0] - 2025-12-27

### Added

- 🌐 **Custom Domain:** rupiapp.in with SSL
- 📧 **Professional Email:** Sender is noreply@rupiapp.in
- 🔐 **Password Reset:** 1-hour tokens with strength validator
- 📬 **Premium Emails:** Logo, feature reminders, developer contact
- 💬 **Better Errors:** User-friendly expired token messages
- 📱 **PWA Ready:** Installable as mobile app

---

## [2.0.0] - 2024-12-24

### Added - Indian Demo Data

- Indian demo data generator with 200+ transactions
- Indian expense categories (Food & Dining, Shopping, Transportation, etc.)
- Indian bank accounts (HDFC Savings, ICICI Salary, SBI Current)
- Indian credit cards (HDFC Credit Card, ICICI Amazon Pay Card)
- Indian investment accounts (Zerodha Demat, MF Central, PPF, EPF)
- Indian loan accounts (Home Loan - HDFC, Car Loan - SBI)
- Indian merchants (Swiggy, Zomato, Amazon, Flipkart, etc.)

### Changed

- Demo data generator creates Indian family with INR currency
- Budget auto-fill uses INR and rounds to nearest ₹500
- Default timezone set to Asia/Kolkata (IST)
- Date format default is DD-MM-YYYY

### Removed - US/EU Provider Features

- Plaid integration (US-only)
- SimpleFIN integration (US-only)
- Enable Banking integration (EU-only)
- Lunchflow integration (US-only)

---

## [1.0.0] - 2024-12-23

### Added - Indian Features

- Bank statement parsers for HDFC, ICICI, SBI, Axis, Kotak
- Generic bank statement parser for other Indian banks
- PDF and Excel statement parsing support
- Smart auto-categorization for Indian merchants
- Bank statement upload UI at `/bank_statement/new`
- Indian date format support (DD/MM/YYYY)
- Default currency changed to INR (₹)

---

## [Original] - Forked from Sure Finance

This project was forked from [Sure Finance](https://github.com/we-promise/sure), a community fork of Maybe Finance. Original features included:

- Multi-asset account tracking
- Transaction management with categories and tags
- Budget management
- Net worth tracking
- Investment portfolio tracking
- CSV import
- Multi-currency support
- Hotwire frontend
- ViewComponent UI library
- D3.js charts
- Tailwind CSS styling

---

## Version History

| Version  | Date       | Notes                                          |
| -------- | ---------- | ---------------------------------------------- |
| 3.1.0    | 2026-01-14 | Google Cloud, Solid Cable, Resend email        |
| 3.0.0    | 2026-01-04 | Open Core architecture, AI via RUPI Engine API |
| 2.3.0    | 2025-12-27 | Custom domain, PWA, email improvements         |
| 2.0.0    | 2024-12-24 | Indian demo data, US providers removed         |
| 1.0.0    | 2024-12-23 | Initial Indian bank statement parsers          |
| Original | -          | Forked from Sure Finance                       |

---

## License

RUPI is licensed under **AGPLv3**. See [LICENSE](LICENSE) for details.
