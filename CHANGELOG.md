# Changelog - Indian Finance App

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] - 2024-12-24

### Added - Indian Demo Data
- Indian demo data generator with 200+ transactions
- Indian expense categories (Food & Dining, Shopping, Transportation, Utilities, Healthcare, Investments & Savings, Loan Payments)
- Indian income categories (Salary, Freelance Income, Rental Income, Investment Income)
- Indian bank accounts (HDFC Savings, ICICI Salary, SBI Current)
- Indian credit cards (HDFC Credit Card, ICICI Amazon Pay Card)
- Indian investment accounts (Zerodha Demat, MF Central, PPF Account, EPF Account)
- Indian loan accounts (Home Loan - HDFC, Car Loan - SBI)
- Indian merchants in transactions (Swiggy, Zomato, Amazon, Flipkart, BigBasket, Blinkit, Uber, Ola, Rapido, Barbeque Nation, etc.)
- Property and vehicle valuations in INR

### Added - UI/UX Improvements
- "Upload Statement" button added to dashboard header (desktop + mobile)
- Bank statement upload made PRIMARY action in empty dashboard state
- Helpful text showing supported banks (HDFC, ICICI, SBI, Axis, Kotak)

### Changed
- Demo data generator now creates Indian family with INR currency, India country, Asia/Kolkata timezone, DD-MM-YYYY date format
- Budget auto-fill now uses INR currency and rounds to nearest ₹500

### Removed - US/EU Provider Features
- Plaid integration routes and JavaScript removed (US-only)
- SimpleFIN integration routes removed (US-only)
- Enable Banking integration routes removed (EU-only)
- Lunchflow integration routes removed (US-only)
- Plaid webhooks removed
- Account creation method selector simplified to manual entry + bank statement upload
- US provider links removed from UI

---

## [0.1.x] - 2024-12-23

### Added - Indian Features
- Bank statement parsers for HDFC, ICICI, SBI, Axis, Kotak banks
- Generic bank statement parser for other Indian banks
- PDF and Excel statement parsing support
- Smart auto-categorization for Indian merchants (Swiggy, Zomato, Amazon, Flipkart, etc.)
- Bank statement upload UI at `/bank_statement/new`
- Indian date format support (DD/MM/YYYY)
- Default currency changed to INR (₹)

---

## [Original] - Forked from Sure Finance

This project was forked from [Sure Finance](https://github.com/we-promise/sure), a community fork of Maybe Finance. Original features included:

- Multi-asset account tracking (banking, investment, crypto, property, vehicle)
- Transaction management with categories and tags
- Budget management
- Net worth tracking
- Investment portfolio tracking
- Plaid integration (US/EU)
- CSV import
- Multi-currency support
- Hotwire (Turbo + Stimulus) frontend
- ViewComponent UI library
- D3.js charts
- Tailwind CSS styling

---

## Planned Future Releases

### v0.3.0 - Indian Investment Types
- [ ] PPF (Public Provident Fund) as dedicated account type
- [ ] EPF (Employees' Provident Fund) as dedicated account type
- [ ] NPS (National Pension System) as dedicated account type
- [ ] Mutual Fund integration with AMFI
- [ ] Stock holdings with NSE/BSE integration
- [ ] Sovereign Gold Bonds
- [ ] Fixed Deposits
- [ ] Recurring Deposits

### v0.4.0 - Indian Loan Types
- [ ] Home Loan (with Section 24 tax tracking)
- [ ] Personal Loan
- [ ] Gold Loan
- [ ] Education Loan (with tax benefits)
- [ ] Auto Loan
- [ ] Business Loan
- [ ] Loan Against Property
- [ ] Overdraft/Credit Line

### v0.5.0 - UPI Integration
- [ ] UPI transaction import
- [ ] GPay, PhonePe, Paytm, CRED, BharatPe support
- [ ] UPI ID linking to accounts
- [ ] UPI merchant categorization

### v0.6.0 - Tax Features
- [ ] TDS tracking
- [ ] Advance Tax tracking
- [ ] Section 80C deduction calculator
- [ ] Section 80D (health insurance) tracking
- [ ] Section 80CCD (NPS) tracking
- [ ] Capital gains tracking (STCG, LTCG)
- [ ] Form 26AS integration

### v0.7.0 - Account Aggregator
- [ ] RBI AA framework integration
- [ ] Finvu integration
- [ ] OneScrape integration
- [ ] Consent management

### v0.8.0 - Localization
- [ ] Hindi translations
- [ ] Indian number formatting (₹1,23,456.78)
- [ ] Regional language support

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 0.2.0 | 2024-12-24 | Indian demo data, US providers removed, UI improvements |
| 0.1.x | 2024-12-23 | Initial Indian bank statement parsers added |
| Original | - | Forked from Sure Finance |

---

## Migration Guide

### From 0.1.x to 0.2.0

1. **US Providers Removed**: Plaid, SimpleFIN, Enable Banking, and Lunchflow routes are now disabled
2. **Demo Data**: Run `rake demo_data:default` to load Indian demo data
3. **Currency**: New families default to INR, Asia/Kolkata timezone, DD-MM-YYYY date format

### From Original Sure Finance

If you're upgrading from the original Sure Finance:

1. **Currency**: Default currency is now INR instead of USD
2. **Bank Sync**: Plaid/SimpleFIN have been removed (US/EU only)
3. **Import**: Use bank statement upload instead for Indian banks
4. **Categories**: New Indian-specific categories added

### Data Migration

Existing families will keep their currency setting. New families will default to INR.
