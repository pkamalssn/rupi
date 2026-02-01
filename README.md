# RUPI 🇮🇳

### Personal Finance Dashboard for India

**Version 3.3.12** · **🔒 Security Hardened** · **🚀 Production Ready**

A clean, open-source frontend for managing your personal finances. Track accounts, view transactions, analyze spending patterns, and visualize your financial health — all designed for the Indian context.

![RUPI Logo](public/logo-pwa.png)

---

## 🌟 Overview

RUPI is an open-source personal finance dashboard built specifically for Indian users. It provides a comprehensive interface for:

- **Multi-account tracking** across all your bank accounts
- **Transaction management** with categories and tags
- **Financial reports** including balance sheets and income statements
- **Net worth tracking** with historical trends
- **Loan & EMI management** with payment schedules
- **Investment portfolio** visualization
- **Budget management** and spending analysis
- **Family accounts** — track who owns what (Self, Spouse, or Shared)

> **Note:** This is the open-source base for RUPI. Advanced AI features including bank statement import, smart categorization, and AI chat assistant are available through [RUPI Premium](https://rupiapp.in).

---

## ✨ Features

### Dashboard & Analytics

- 📊 **Net Worth Tracking** — See your complete financial picture
- 📈 **Cash Flow Analysis** — Income vs expenses over time
- 🥧 **Spending Breakdown** — Visual category-wise spending charts
- 📉 **Trend Analysis** — Historical comparisons

### Account Management

- 🏦 **Bank Accounts** — Savings, Current, Salary, NRI/NRO/NRE
- 💳 **Credit Cards** — Track balances and payment due dates
- 🏠 **Loans** — Home, Personal, Gold, Education, Auto loans with EMI schedules
- 📈 **Investments** — Stocks, Mutual Funds, PPF, EPF, NPS, FDs
- 🚗 **Assets** — Property, Vehicles, Gold with valuations

### Transaction Features

- 🏷️ **Categories** — Indian-specific categories (UPI, EMI, Recharges, etc.)
- 🔍 **Search & Filter** — Find any transaction quickly
- 📝 **Tags** — Custom tags for detailed tracking
- 🔄 **Transfer Detection** — Auto-match transfers between accounts

### India-First Design

- 💰 **INR (₹) Default** — Built for Rupees
- 📅 **Indian Date Format** — DD-MM-YYYY
- 🕐 **IST Timezone** — Asia/Kolkata
- 🏷️ **Local Categories** — Swiggy, Zomato, UPI, EMI, etc.

---

## 🚀 Try RUPI Premium

Want the full RUPI experience with AI-powered features?

**Visit:** [https://rupiapp.in](https://rupiapp.in)

RUPI Premium adds:

- 📄 **Bank Statement Import** — PDF/CSV from 20+ Indian banks
- 🤖 **AI Assistant** — Chat with RUPI about your finances
- 🏷️ **Smart Categorization** — Automatic merchant detection
- 📊 **Advanced Insights** — AI-powered spending analysis

---

## 🛠 Tech Stack

| Layer               | Technology                 |
| ------------------- | -------------------------- |
| **Backend**         | Ruby on Rails 7.2          |
| **Frontend**        | Hotwire (Turbo + Stimulus) |
| **Styling**         | Tailwind CSS               |
| **Database**        | PostgreSQL                 |
| **Background Jobs** | Sidekiq + Redis            |
| **Components**      | ViewComponent              |
| **Charts**          | D3.js                      |

---

## 📦 Installation

### Prerequisites

- Ruby 3.2+
- PostgreSQL 14+
- Redis 7+
- Node.js 18+ (for asset compilation)

### Quick Start

```bash
# Clone the repository
git clone https://github.com/pkamalssn/rupi.git
cd rupi

# Install dependencies
bundle install
yarn install

# Setup database
bin/rails db:prepare

# Start the development server
bin/dev
```

Visit `http://localhost:3000` to see RUPI running.

### Environment Variables

Create a `.env` file with:

```env
# Required
DATABASE_URL=postgres://localhost/rupi_development
REDIS_URL=redis://localhost:6379/0
SECRET_KEY_BASE=your-secret-key

# Optional - Email
RESEND_API_KEY=your-resend-key
EMAIL_SENDER=noreply@yourdomain.com

# Optional - RUPI Premium API (for AI features)
RUPI_ENGINE_URL=https://api.rupiapp.in
RUPI_ENGINE_API_KEY=your-api-key
```

---

## 🗂 Project Structure

```
rupi/
├── app/
│   ├── controllers/     # Rails controllers
│   ├── models/          # Domain models (Account, Transaction, etc.)
│   │   ├── assistant/   # AI chat interface (requires RUPI Engine)
│   │   └── provider/    # External service integrations
│   ├── views/           # ERB templates
│   ├── components/      # ViewComponents
│   └── javascript/      # Stimulus controllers
├── config/              # Rails configuration
├── db/                  # Migrations and schema
└── test/                # Test suite
```

---

## 🧑‍💻 Development

### Running Tests

```bash
# All tests
bin/rails test

# Specific test file
bin/rails test test/models/account_test.rb

# System tests (requires browser)
bin/rails test:system
```

### Linting

```bash
# Ruby
bin/rubocop

# JavaScript
npm run lint

# ERB templates
bundle exec erb_lint ./app/**/*.erb
```

### Demo Data

```bash
# Load Indian demo data for development
rake demo_data:default
```

---

## 🇮🇳 Indian Context

RUPI is specifically built for Indian users with:

| Feature           | Indian Adaptation                             |
| ----------------- | --------------------------------------------- |
| **Currency**      | INR (₹) as default                            |
| **Date Format**   | DD-MM-YYYY                                    |
| **Timezone**      | Asia/Kolkata (IST)                            |
| **Account Types** | NRE/NRO, PPF, EPF, NPS                        |
| **Loan Types**    | Home Loan (Sec 24), Gold Loan, Education Loan |
| **Categories**    | UPI, Swiggy, Zomato, EMI, Recharges, etc.     |
| **Tax Features**  | Section 80C tracking (planned)                |

---

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Areas for Contribution

- 🌐 Hindi translations
- 📊 New chart types
- 🏷️ Additional Indian categories
- 🐛 Bug fixes
- 📖 Documentation improvements

---

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPLv3)**.

See [LICENSE](LICENSE) for details.

### What This Means

- ✅ You can use, modify, and distribute this software
- ✅ You can use it for commercial purposes
- ⚠️ You must disclose source code of any modifications
- ⚠️ Network use (SaaS) requires source disclosure
- ⚠️ You must keep the same license

---

## 👨‍💻 Author

Built with ❤️ in India by **Kamal Prakash**

- **GitHub:** [@pkamalssn](https://github.com/pkamalssn)
- **Twitter/X:** [@storyteller_kp](https://x.com/storyteller_kp)
- **Email:** [pkamalssn@gmail.com](mailto:pkamalssn@gmail.com)

---

## 🙏 Acknowledgments

This project is a fork of [Sure Finance](https://github.com/we-promise/sure), which itself is a community fork of [Maybe Finance](https://github.com/maybe-finance/maybe). Thank you to the original authors for open-sourcing their work.

---

## 📧 Support

- **Issues:** [GitHub Issues](https://github.com/pkamalssn/rupi/issues)
- **Email:** [pkamalssn@gmail.com](mailto:pkamalssn@gmail.com)
- **Premium Support:** [rupiapp.in](https://rupiapp.in)
