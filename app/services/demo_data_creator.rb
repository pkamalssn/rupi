# frozen_string_literal: true

# Service to create demo data for new users
# Can be called on first login or from admin console
class DemoDataCreator
  DEMO_CATEGORIES = [
    { name: "Food & Dining", color: "#EF4444" },
    { name: "Shopping", color: "#8B5CF6" },
    { name: "Transportation", color: "#3B82F6" },
    { name: "Utilities", color: "#F59E0B" },
    { name: "Entertainment", color: "#EC4899" },
    { name: "Income", color: "#10B981" }
  ].freeze

  DEMO_TRANSACTIONS = [
    { days_ago: 1, name: "Salary Credit", amount: 75000, category: "Income" },
    { days_ago: 2, name: "Swiggy Order", amount: -450, category: "Food & Dining" },
    { days_ago: 3, name: "Amazon Purchase", amount: -2500, category: "Shopping" },
    { days_ago: 5, name: "Electricity Bill - TANGEDCO", amount: -1200, category: "Utilities" },
    { days_ago: 7, name: "Uber Ride", amount: -350, category: "Transportation" },
    { days_ago: 8, name: "Netflix Subscription", amount: -649, category: "Entertainment" },
    { days_ago: 10, name: "Zomato Order", amount: -380, category: "Food & Dining" },
    { days_ago: 12, name: "Flipkart Purchase", amount: -1800, category: "Shopping" },
    { days_ago: 15, name: "Mobile Recharge - Jio", amount: -299, category: "Utilities" },
    { days_ago: 18, name: "Rapido Auto", amount: -120, category: "Transportation" }
  ].freeze

  def initialize(family)
    @family = family
  end

  def call
    return false if @family.accounts.exists?

    ActiveRecord::Base.transaction do
      create_categories
      create_demo_account
      create_demo_transactions
    end

    true
  rescue => e
    Rails.logger.error "[DemoDataCreator] Failed: #{e.message}"
    false
  end

  private

  def create_categories
    DEMO_CATEGORIES.each do |cat|
      @family.categories.find_or_create_by!(name: cat[:name]) do |c|
        c.color = cat[:color]
      end
    end
  end

  def create_demo_account
    @account = @family.accounts.create!(
      name: "Demo Savings Account",
      currency: @family.currency || "INR",
      balance: 68052, # After all demo transactions
      accountable: Depository.create!(bank_name: "Demo Bank"),
      is_active: true
    )
  end

  def create_demo_transactions
    DEMO_TRANSACTIONS.each do |txn|
      category = @family.categories.find_by(name: txn[:category])
      
      @account.entries.create!(
        date: txn[:days_ago].days.ago.to_date,
        name: txn[:name],
        amount: txn[:amount],
        currency: @family.currency || "INR",
        entryable: Account::Transaction.create!(category: category),
        marked_as_transfer: false
      )
    end
  end
end
