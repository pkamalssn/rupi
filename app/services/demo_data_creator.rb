# frozen_string_literal: true

# Service to create demo data for new users
# Creates a realistic but minimal Indian financial portfolio
class DemoDataCreator
  DEMO_CATEGORIES = [
    { name: "Salary", color: "#10B981", classification: "income" },
    { name: "Food & Dining", color: "#EF4444", classification: "expense" },
    { name: "Shopping", color: "#8B5CF6", classification: "expense" },
    { name: "Transportation", color: "#3B82F6", classification: "expense" },
    { name: "Utilities", color: "#F59E0B", classification: "expense" },
    { name: "Entertainment", color: "#EC4899", classification: "expense" },
    { name: "Healthcare", color: "#06B6D4", classification: "expense" },
    { name: "EMI Payments", color: "#6366F1", classification: "expense" },
    { name: "Investments", color: "#14B8A6", classification: "expense" },
    { name: "Rent", color: "#F97316", classification: "expense" },
    { name: "Interest Income", color: "#22C55E", classification: "income" },
    { name: "Other Income", color: "#84CC16", classification: "income" }
  ].freeze

  def initialize(family)
    @family = family
    @currency = family.currency || "INR"
  end

  def call
    # Only check for active accounts (exclude soft-deleted pending_deletion)
    existing_count = @family.accounts.where.not(status: :pending_deletion).count
    
    if existing_count > 0
      Rails.logger.info "[DemoDataCreator] Skipped: Family #{@family.id} has #{existing_count} active accounts."
      return false 
    end

    Rails.logger.info "[DemoDataCreator] Starting creation for family #{@family.id}"

    ActiveRecord::Base.transaction do
      create_categories
      create_savings_accounts
      create_credit_cards
      create_loans
      create_investments
      
      # Mark that this family has demo data loaded
      @family.update!(demo_data_loaded: true) if @family.respond_to?(:demo_data_loaded=)
    end

    true
  rescue => e
    Rails.logger.error "[DemoDataCreator] Failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    false
  end

  # Clear all demo data for a family
  # This deletes ALL accounts, transactions, and categories created by demo data
  def self.clear(family)
    return false unless family.present?

    ActiveRecord::Base.transaction do
      # Delete all accounts (this also cascades to entries/transactions)
      family.accounts.destroy_all
      
      # Delete demo categories (keep user-created ones if identifiable)
      # For simplicity, we delete categories matching DEMO_CATEGORIES names
      demo_category_names = DEMO_CATEGORIES.map { |c| c[:name] }
      family.categories.where(name: demo_category_names).destroy_all
      
      # Clear demo data flag
      family.update!(demo_data_loaded: false) if family.respond_to?(:demo_data_loaded=)
    end

    Rails.logger.info "[DemoDataCreator] Cleared demo data for family #{family.id}"
    true
  rescue => e
    Rails.logger.error "[DemoDataCreator] Clear failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
    false
  end

  private

  def create_categories
    DEMO_CATEGORIES.each do |cat|
      @family.categories.find_or_create_by!(name: cat[:name]) do |c|
        c.color = cat[:color]
        c.classification = cat[:classification] || "expense"
      end
    end
  end

  # ============ SAVINGS ACCOUNTS ============
  def create_savings_accounts
    # Primary HDFC Account
    hdfc = create_account(
      name: "HDFC Savings Account",
      balance: 185000,
      bank_name: "HDFC Bank",
      type: "Depository"
    )
    create_hdfc_transactions(hdfc)

    # SBI Salary Account
    sbi = create_account(
      name: "SBI Salary Account", 
      balance: 42500,
      bank_name: "State Bank of India",
      type: "Depository"
    )
    create_sbi_transactions(sbi)
  end

  # ============ CREDIT CARDS ============
  def create_credit_cards
    # HDFC Credit Card
    hdfc_cc = create_account(
      name: "HDFC Millennia Credit Card",
      balance: -18500, # Outstanding balance (negative = owed)
      bank_name: "HDFC Bank",
      type: "CreditCard"
    )
    create_hdfc_cc_transactions(hdfc_cc)

    # Amazon Pay ICICI
    icici_cc = create_account(
      name: "Amazon Pay ICICI Card",
      balance: -8200,
      bank_name: "ICICI Bank", 
      type: "CreditCard"
    )
    create_icici_cc_transactions(icici_cc)
  end

  # ============ LOANS ============
  def create_loans
    # Home Loan
    create_account(
      name: "SBI Home Loan",
      balance: -4250000, # 42.5 lakhs outstanding
      bank_name: "State Bank of India",
      type: "Loan",
      loan_details: {
        original_balance: 5000000,
        interest_rate: 8.5,
        term_months: 240
      }
    )

    # Personal Loan
    create_account(
      name: "Bajaj Personal Loan",
      balance: -185000,
      bank_name: "Bajaj Finance",
      type: "Loan",
      loan_details: {
        original_balance: 300000,
        interest_rate: 14.0,
        term_months: 36
      }
    )
  end

  # ============ INVESTMENTS ============
  def create_investments
    # PPF - Investment type
    create_account(
      name: "PPF Account",
      balance: 520000,
      bank_name: "SBI",
      type: "Investment"
    )

    # Fixed Deposit - Depository with FD subtype
    create_account(
      name: "ICICI Fixed Deposit",
      balance: 200000,
      bank_name: "ICICI Bank",
      type: "Depository"
    )
  end

  # ============ HELPER METHODS ============
  def create_account(name:, balance:, bank_name:, type:, loan_details: nil)
    accountable = case type
    when "Depository"
      # Depository doesn't have bank_name column - account name includes bank info
      Depository.create!
    when "CreditCard"
      CreditCard.create!(
        annual_fee: 500,
        minimum_payment: [balance.abs * 0.05, 500].max.round
      )
    when "Loan"
      Loan.create!(
        interest_rate: loan_details&.dig(:interest_rate) || 10.0,
        term_months: loan_details&.dig(:term_months) || 60,
        rate_type: "fixed"
      )
    when "Investment"
      Investment.create!
    end

    @family.accounts.create!(
      name: name,
      currency: @currency,
      balance: balance,
      accountable: accountable,
      status: :active
    )
  end

  def create_entry(account, date:, name:, amount:, category_name: nil)
    category = category_name ? @family.categories.find_by(name: category_name) : nil
    
    account.entries.create!(
      date: date,
      name: name,
      amount: amount,
      currency: @currency,
      entryable: ::Transaction.create!(category: category)
    )
  end

  # ============ TRANSACTION DATA ============
  def create_hdfc_transactions(account)
    # Last 2 months of transactions
    [
      { days: 2, name: "Swiggy Order", amount: -485, cat: "Food & Dining" },
      { days: 5, name: "Amazon Purchase", amount: -2899, cat: "Shopping" },
      { days: 7, name: "Uber Ride", amount: -325, cat: "Transportation" },
      { days: 10, name: "Netflix Subscription", amount: -649, cat: "Entertainment" },
      { days: 12, name: "Electricity Bill - TANGEDCO", amount: -1850, cat: "Utilities" },
      { days: 15, name: "Zomato Order", amount: -380, cat: "Food & Dining" },
      { days: 18, name: "Flipkart Purchase", amount: -1599, cat: "Shopping" },
      { days: 20, name: "Mobile Recharge - Jio", amount: -299, cat: "Utilities" },
      { days: 25, name: "Health Checkup - Apollo", amount: -2500, cat: "Healthcare" },
      { days: 30, name: "Rapido Auto", amount: -120, cat: "Transportation" },
      { days: 35, name: "Groceries - BigBasket", amount: -3200, cat: "Food & Dining" },
      { days: 40, name: "DMart Shopping", amount: -1850, cat: "Shopping" },
      { days: 45, name: "Ola Ride", amount: -450, cat: "Transportation" },
      { days: 50, name: "Disney+ Hotstar", amount: -299, cat: "Entertainment" }
    ].each do |txn|
      create_entry(account, date: txn[:days].days.ago.to_date, name: txn[:name], amount: txn[:amount], category_name: txn[:cat])
    end
  end

  def create_sbi_transactions(account)
    # Salary credits and rent
    [
      { days: 1, name: "Salary Credit - TCS", amount: 95000, cat: "Salary" },
      { days: 5, name: "Rent Payment - UPI", amount: -25000, cat: "Rent" },
      { days: 8, name: "SBI Home Loan EMI", amount: -42500, cat: "EMI Payments" },
      { days: 10, name: "PPF Investment", amount: -12500, cat: "Investments" },
      { days: 31, name: "Salary Credit - TCS", amount: 95000, cat: "Salary" },
      { days: 35, name: "Rent Payment - UPI", amount: -25000, cat: "Rent" },
      { days: 38, name: "SBI Home Loan EMI", amount: -42500, cat: "EMI Payments" },
      { days: 40, name: "PPF Investment", amount: -12500, cat: "Investments" },
      { days: 45, name: "FD Interest Credit", amount: 1250, cat: "Interest Income" }
    ].each do |txn|
      create_entry(account, date: txn[:days].days.ago.to_date, name: txn[:name], amount: txn[:amount], category_name: txn[:cat])
    end
  end

  def create_hdfc_cc_transactions(account)
    [
      { days: 3, name: "Myntra Fashion", amount: -3499, cat: "Shopping" },
      { days: 8, name: "Barbeque Nation", amount: -2800, cat: "Food & Dining" },
      { days: 15, name: "Spotify Premium", amount: -119, cat: "Entertainment" },
      { days: 20, name: "Reliance Digital", amount: -8999, cat: "Shopping" },
      { days: 28, name: "Dominos Pizza", amount: -650, cat: "Food & Dining" }
    ].each do |txn|
      create_entry(account, date: txn[:days].days.ago.to_date, name: txn[:name], amount: txn[:amount], category_name: txn[:cat])
    end
  end

  def create_icici_cc_transactions(account)
    [
      { days: 4, name: "Amazon.in Purchase", amount: -4299, cat: "Shopping" },
      { days: 12, name: "Amazon Prime", amount: -1499, cat: "Entertainment" },
      { days: 22, name: "Amazon Pantry", amount: -1850, cat: "Food & Dining" },
      { days: 35, name: "Amazon.in Purchase", amount: -2599, cat: "Shopping" }
    ].each do |txn|
      create_entry(account, date: txn[:days].days.ago.to_date, name: txn[:name], amount: txn[:amount], category_name: txn[:cat])
    end
  end
end
