# RUPI v2.3 🇮🇳

### Get ready to manage your Rupees easier with RUPI! ✨

A next-generation personal finance dashboard built specifically for the **Indian context**. RUPI leverages advanced AI (Gemini 3 Flash) to automate tracking, categorize transactions, and extract insights from your financial documents.

> **Get ready to manage your Rupees easier with RUPI!**

![RUPI Dashboard](public/logo-pwa.png)

---

## 🚀 Beta is LIVE!

**Try RUPI now:** [https://rupiapp.in](https://rupiapp.in)

RUPI is currently in **open beta**. All features are free during this period. Help us build India's smartest personal finance app!

- **Pricing after beta:** ₹149/month or ₹1,499/year
- **Beta users get early-adopter discount**

---

## ✨ Why RUPI?

| Feature                 | Description                                                                |
| ----------------------- | -------------------------------------------------------------------------- |
| 🔒 **Privacy First**    | Documents auto-deleted after parsing. No bank login required.              |
| 🤖 **AI-Powered**       | Smart categorization, loan import from documents, natural language queries |
| 🇮🇳 **India-First**      | Built for HDFC, ICICI, SBI, Kotak & 12+ Indian banks                       |
| 👨‍👩‍👧 **Family Accounts**  | Track who owns what - Husband, Wife, or Shared                             |
| 📊 **Complete Picture** | Net worth, cash flow, loans, EMIs, investments - all in one place          |

---

## 🏦 Supported Banks & Services

### Bank Statements

- **Major Banks:** HDFC, ICICI, SBI, Axis, Kotak, RBL
- **Digital Banks:** Jupiter, Equitas, KVB, UBI, Bandhan
- **International:** Wise (TransferWise) with multi-currency support

### Credit Cards

- HDFC Credit Card, ICICI Amazon Pay, Scapia, Kotak Royale

### Investments

- Zerodha Tradebook, MFCentral CAS, NPS, PPF

### Loans

- Home Loans, Car Loans, Personal Loans (HDFC, ICICI, CRED, Bajaj)
- **AI Loan Import:** Upload sanction letters to auto-create loan accounts!

---

## 🤖 AI Features

### RUPI AI Assistant

Chat with RUPI about your finances:

- "What's my net worth?"
- "How much did I spend on food last month?"
- "Show me all my EMIs"

### Smart Document Parsing

- Password-protected PDFs ✅
- Automatic transaction categorization ✅
- Loan document extraction (principal, rate, EMI) ✅
- EMI reconciliation (links bank debits to loan EMIs) ✅

---

## 🔒 Privacy Architecture

Your privacy is our priority:

| What Happens      | Details                                 |
| ----------------- | --------------------------------------- |
| **Documents**     | Auto-deleted immediately after parsing  |
| **Bank Login**    | Never required - just upload statements |
| **Data Sharing**  | Zero third-party data sharing           |
| **Your Control**  | Export or delete all data anytime       |
| **AI Processing** | Only Google Gemini (no data retention)  |

---

## 🛠 Tech Stack

- **Backend:** Ruby on Rails 7.2
- **Frontend:** Hotwire (Turbo & Stimulus), Tailwind CSS
- **Database:** PostgreSQL (Primary), Redis (Jobs/Cache)
- **AI Engine:** Google Gemini 3 Flash Preview
- **PDF Processing:** HexaPDF, Poppler
- **Deployment:** Render.com (Docker)
- **Email:** Resend (HTTP API)
- **Domain:** rupiapp.in (GoDaddy + Cloudflare)

---

## 🚢 Deployment (Render.com)

RUPI is deployed on **Render.com** free tier using Docker.

### Environment Variables Required:

| Variable          | Description                                         |
| ----------------- | --------------------------------------------------- |
| `DATABASE_URL`    | PostgreSQL connection string                        |
| `REDIS_URL`       | Redis connection string                             |
| `GEMINI_API_KEY`  | Google AI API key                                   |
| `SECRET_KEY_BASE` | Rails secret (generate with `SecureRandom.hex(64)`) |
| `RESEND_API_KEY`  | Resend email API key                                |
| `EMAIL_SENDER`    | `noreply@yourdomain.com`                            |
| `APP_DOMAIN`      | `yourdomain.com` (no https://)                      |

### DNS Setup (for custom domain):

```
A     @     216.24.57.1
CNAME www   your-app.onrender.com
```

### Free Tier Limits:

- App sleeps after 15 min inactivity (~30s cold start)
- Database expires after 90 days (export & reimport)
- 500 build minutes/month

---

## 🆕 What's New in v2.3

- 🌐 **Custom Domain:** rupiapp.in with SSL
- 📧 **Professional Email:** Sender is noreply@rupiapp.in
- 🔐 **Password Reset:** 1-hour tokens with strength validator
- 📬 **Premium Emails:** Logo, feature reminders, developer contact
- 💬 **Better Errors:** User-friendly expired token messages
- 📱 **PWA Ready:** Installable as mobile app

---

## 🇮🇳 India-First Defaults

- **Currency:** INR (₹)
- **Date Format:** DD-MM-YYYY
- **Timezone:** Asia/Kolkata (IST)
- **Categories:** EMI Payments, Domestic Help, Recharges, Education, and more

---

## 📧 Contact & Support

For beta feedback, bugs, or feature requests:

- **Email:** [pkamalssn@gmail.com](mailto:pkamalssn@gmail.com)
- **Twitter/X:** [@storyteller_kp](https://x.com/storyteller_kp)

---

## 👨‍💻 Developer

Built with ❤️ in India by **Kamal Prakash**

Software engineer passionate about building tools that make personal finance accessible and stress-free for every Indian family.

- **GitHub:** [@pkamalssn](https://github.com/pkamalssn)
- **X (Twitter):** [@storyteller_kp](https://x.com/storyteller_kp)
- **Email:** [pkamalssn@gmail.com](mailto:pkamalssn@gmail.com)

---

## 📄 License

Private - For Personal Use Only.  
Copyright © 2025 Kamal Prakash.
