# frozen_string_literal: true

# BankStatementImport handles importing transactions from Indian bank statements (PDF/Excel)
class BankStatementImport < Import
  SUPPORTED_BANKS = %w[
    HDFC
    ICICI
    SBI
    UBI
    Axis
    Kotak
    RBL
    Bandhan
    Jupiter
    Equitas
    KVB
    Wise
    Generic
  ].freeze

  SUPPORTED_CREDIT_CARDS = %w[
    HDFC_CC
    ICICI_Amazon
    Scapia
    Kotak_Royale
  ].freeze

  SUPPORTED_INVESTMENTS = %w[
    Zerodha
    MFCentral
    NPS
    PPF
  ].freeze

  # ActiveStorage attachment for the statement file
  has_one_attached :statement_file

  attr_accessor :password

  validates :bank_name, inclusion: { in: SUPPORTED_BANKS + SUPPORTED_CREDIT_CARDS + SUPPORTED_INVESTMENTS }, on: :create

  def self.all_supported_types
    {
      "Banks" => SUPPORTED_BANKS,
      "Credit Cards" => SUPPORTED_CREDIT_CARDS,
      "Investments" => SUPPORTED_INVESTMENTS
    }
  end

  # Override parent's publishable? since we use statement_file, not raw_file_str
  def publishable?
    statement_file.attached? && bank_name.present?
  end

  # Override uploaded? to check for statement_file attachment
  def uploaded?
    statement_file.attached?
  end

  # Override configured? - for bank statements, we're configured once file is uploaded and bank selected
  def configured?
    uploaded? && bank_name.present?
  end

  # Override cleaned? - bank statements don't have row validation like CSV
  def cleaned?
    configured?
  end

  # Override mapping_steps - bank statements don't have column mapping
  # This needs to be public for the nav partial
  def mapping_steps
    []
  end

  # Get the password to use - either user-provided or from ENV
  def effective_password
    return password if password.present?
    
    # Try to get password from ENV based on bank name
    env_key = "BANK_STATEMENT_PASSWORD_#{bank_name.to_s.upcase}"
    ENV[env_key]
  end

  # Get default password hint for UI
  def self.stored_password_for(bank_name)
    env_key = "BANK_STATEMENT_PASSWORD_#{bank_name.to_s.upcase}"
    ENV[env_key].present?
  end

  def publish
    raise MaxRowCountExceededError if row_count_exceeded?

    import!

    family.sync_later

    # PRIVACY: Delete the statement file after successful import
    # We only keep the extracted transaction data, not the original document
    purge_statement_file!

    update! status: :complete
  rescue => e
    # Check for password-related errors
    if e.message.downcase.include?("password")
      update! status: :pending, error: "Password required for this document"
    else
      update! status: :failed, error: e.message
    end
    # Note: We keep the file for failed imports so user can retry
  end

  # Privacy-first: Delete the original statement file
  def purge_statement_file!
    return unless statement_file.attached?
    
    statement_file.purge
    Rails.logger.info "[Privacy] Statement file purged for import ##{id}"
  end

  def import!
    transaction do
      # Find or create the account for this statement
      mapped_account = find_or_create_account

      # Parse the statement file
      parsed_data = parse_statement

      # Handle different parser outputs
      if investment_statement?
        import_investment_data(parsed_data, mapped_account)
      else
        import_transactions(parsed_data, mapped_account)
      end
    end
    
    # After successful import, queue EMI reconciliation for any loan accounts
    # This matches EMI debits (like "HDFC LTD EMI") to loan EMI entries
    LoanEmiReconciliationJob.perform_later(family.id) if family.present?
  end

  private

  def investment_statement?
    SUPPORTED_INVESTMENTS.include?(bank_name)
  end

  def credit_card_statement?
    SUPPORTED_CREDIT_CARDS.include?(bank_name)
  end

  def import_transactions(transactions, mapped_account)
    return if transactions.blank?
    
    # Handle case where parser returns structured data
    transactions = transactions[:transactions] if transactions.is_a?(Hash) && transactions[:transactions]
    
    new_transactions = []
    updated_entries = []
    claimed_entry_ids = Set.new

    transactions.each_with_index do |txn_data, index|
      next unless txn_data.is_a?(Hash) && txn_data[:date] && txn_data[:amount]
      
      category = find_category(txn_data[:description])
      effective_currency = mapped_account.currency.presence || family.currency

      # Check for duplicates
      adapter = Account::ProviderImportAdapter.new(mapped_account)
      duplicate_entry = adapter.find_duplicate_transaction(
        date: txn_data[:date],
        amount: txn_data[:amount],
        currency: effective_currency,
        name: txn_data[:description],
        exclude_entry_ids: claimed_entry_ids
      )

      if duplicate_entry
        duplicate_entry.transaction.category = category if category.present?
        duplicate_entry.notes = txn_data[:notes] if txn_data[:notes].present?
        duplicate_entry.import = self
        updated_entries << duplicate_entry
        claimed_entry_ids.add(duplicate_entry.id)
      else
        new_transactions << Transaction.new(
          category: category,
          entry: Entry.new(
            account: mapped_account,
            date: txn_data[:date],
            amount: txn_data[:amount],
            name: txn_data[:description],
            currency: effective_currency,
            notes: txn_data[:notes],
            import: self
          )
        )
      end
    end

    # Save updated entries
    updated_entries.each do |entry|
      entry.transaction.save!
      entry.save!
    end

    # Bulk import new transactions
    Transaction.import!(new_transactions, recursive: true) if new_transactions.any?
    
    # AI-powered categorization for uncategorized transactions
    # Collect IDs of transactions that don't have a category yet
    uncategorized_transaction_ids = new_transactions.map(&:id).compact
    if uncategorized_transaction_ids.any?
      family.auto_categorize_transactions_later(
        Transaction.where(id: uncategorized_transaction_ids, category_id: nil)
      )
    end
  end

  def import_investment_data(parsed_data, mapped_account)
    # For investment statements, we may need to create holdings, not just transactions
    case bank_name
    when "Zerodha"
      import_zerodha_trades(parsed_data, mapped_account)
    when "MFCentral"
      import_mf_holdings(parsed_data, mapped_account)
    when "NPS"
      import_nps_data(parsed_data, mapped_account)
    when "PPF"
      import_transactions(parsed_data, mapped_account)
    end
  end

  def import_zerodha_trades(trades, mapped_account)
    # Import trades as transactions with metadata
    import_transactions(trades, mapped_account)
    
    # TODO: Also update holdings if applicable
  end

  def import_mf_holdings(parsed_data, mapped_account)
    # Import transactions
    import_transactions(parsed_data[:transactions], mapped_account) if parsed_data[:transactions]
    
    # TODO: Create/update holding records for mutual funds
    # This would require the Holding model to support MF units/NAV
  end

  def import_nps_data(parsed_data, mapped_account)
    # Import contributions as transactions
    if parsed_data[:contributions]
      contributions_as_transactions = parsed_data[:contributions].map do |contrib|
        {
          date: contrib[:date],
          amount: contrib[:amount],
          description: "NPS #{contrib[:type]} Contribution",
          notes: "Imported from NPS statement"
        }
      end
      import_transactions(contributions_as_transactions, mapped_account)
    end
    
    # Also import any other transactions
    import_transactions(parsed_data[:transactions], mapped_account) if parsed_data[:transactions]
  end

  def find_or_create_account
    # Try to find existing account by account number
    return account if account.present?

    # Determine account type based on statement type
    account_name = "#{bank_name.gsub('_', ' ')} Import"
    
    if credit_card_statement?
      # Credit cards are liabilities
      existing = family.accounts.where(accountable_type: "CreditCard")
                                .find_by("accounts.name ILIKE ?", "%#{bank_name.split('_').first}%")
      return existing if existing

      family.accounts.create!(
        name: account_name,
        balance: 0,
        currency: family.currency,
        accountable: CreditCard.new
      )
    elsif investment_statement?
      # Investment accounts
      existing = family.accounts.where(accountable_type: "Investment")
                                .find_by("accounts.name ILIKE ?", "%#{bank_name}%")
      return existing if existing

      family.accounts.create!(
        name: account_name,
        balance: 0,
        currency: family.currency,
        accountable: Investment.new
      )
    else
      # Bank accounts are depositories
      # For Wise, use EUR currency
      account_currency = bank_name == "Wise" ? "EUR" : family.currency
      
      existing = family.accounts.where(accountable_type: "Depository")
                                .find_by("accounts.name ILIKE ?", "%#{bank_name}%")
      return existing if existing

      family.accounts.create!(
        name: account_name,
        balance: 0,
        currency: account_currency,
        accountable: Depository.new(subtype: "checking")
      )
    end
  end

  def parse_statement
    parser = parser_class.new(statement_file, password: effective_password)
    parser.parse
  end

  def parser_class
    case bank_name
    # Banks
    when "HDFC"
      BankStatementParser::Hdfc
    when "ICICI"
      BankStatementParser::Icici
    when "SBI"
      BankStatementParser::Sbi
    when "UBI"
      BankStatementParser::Ubi
    when "Axis"
      BankStatementParser::Axis
    when "Kotak"
      BankStatementParser::Kotak
    when "RBL"
      BankStatementParser::Rbl
    when "Bandhan"
      BankStatementParser::Bandhan
    when "Jupiter"
      BankStatementParser::Jupiter
    when "Equitas"
      BankStatementParser::Equitas
    when "KVB"
      BankStatementParser::Kvb
    when "Wise"
      BankStatementParser::Wise
    # Credit Cards
    when "HDFC_CC"
      BankStatementParser::HdfcCreditCard
    when "ICICI_Amazon"
      BankStatementParser::IciciAmazonPay
    when "Scapia"
      BankStatementParser::Scapia
    when "Kotak_Royale"
      BankStatementParser::KotakRoyale
    # Investments
    when "Zerodha"
      BankStatementParser::ZerodhaTradebook
    when "MFCentral"
      BankStatementParser::MfCentralCas
    when "NPS"
      BankStatementParser::NpsStatement
    when "PPF"
      BankStatementParser::Generic  # PPF is typically manual entry
    else
      BankStatementParser::Generic
    end
  end

  def find_category(description)
    return nil if description.blank?
    
    # Simple keyword-based categorization for Indian transactions
    category_keywords = {
      "Food & Drink" => ["swiggy", "zomato", "restaurant", "cafe", "pizza", "burger", "grocery", "bigbasket", "blinkit", "dunzo", "instamart"],
      "Shopping" => ["amazon", "flipkart", "myntra", "ajio", "shopping", "store", "mall", "nykaa", "meesho"],
      "Transportation" => ["uber", "ola", "rapido", "metro", "petrol", "fuel", "parking", "fastag", "irctc", "railway", "makemytrip"],
      "Utilities" => ["electricity", "water", "gas", "mobile", "internet", "recharge", "bill", "jio", "airtel", "vi ", "bsnl"],
      "Healthcare" => ["hospital", "pharmacy", "doctor", "medical", "health", "apollo", "medplus", "practo"],
      "Education" => ["school", "college", "fees", "education", "course", "udemy", "coursera", "byju"],
      "Entertainment" => ["netflix", "hotstar", "prime video", "spotify", "movie", "pvr", "inox", "bookmyshow"],
      "Subscriptions" => ["subscription", "membership", "annual", "monthly", "renewal"],
      "Investments & Savings" => ["mutual fund", "sip", "ppf", "epf", "nps", "stock", "investment", "zerodha", "groww", "kuvera"],
      "Insurance" => ["insurance", "lic", "policy", "premium", "hdfc life", "icici pru"],
      "Loan Payments" => ["emi", "loan", "housing", "vehicle", "personal loan", "home loan"],
      "Credit Card" => ["credit card", "card payment", "cc bill"],
      "Taxes" => ["tax", "tds", "gst", "income tax", "advance tax"],
      "Transfers" => ["transfer", "neft", "rtgs", "imps", "upi"] # Low priority - often internal
    }

    description_lower = description.downcase
    category_keywords.each do |category_name, keywords|
      if keywords.any? { |keyword| description_lower.include?(keyword) }
        return family.categories.find_or_create_by(name: category_name)
      end
    end

    nil
  end

  def required_column_keys
    [] # Not applicable for PDF imports
  end

  def column_keys
    [] # Not applicable for PDF imports
  end

  def mapping_steps
    [] # No manual mapping needed for PDF imports
  end

  def csv_template
    nil # Not applicable for PDF imports
  end
end
