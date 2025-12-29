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
      # IMPORTANT: Parse FIRST to get metadata (closing balance, account type)
      # Then create account with correct balance
      parsed_data = parse_statement
      
      # Extract metadata from parsed data
      @parsed_metadata = extract_metadata(parsed_data)
      
      # Now find or create the account with the parsed closing balance
      mapped_account = find_or_create_account
      
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
  
  # Extract metadata from parsed data for account creation
  def extract_metadata(parsed_data)
    return {} unless parsed_data.is_a?(Hash)
    
    metadata = parsed_data[:metadata] || {}
    metadata[:opening_balance] ||= parsed_data[:opening_balance]
    metadata[:closing_balance] ||= parsed_data[:closing_balance]
    metadata[:account_type] ||= parsed_data[:account_type]
    metadata
  end

  private

  def investment_statement?
    SUPPORTED_INVESTMENTS.include?(bank_name)
  end

  def credit_card_statement?
    SUPPORTED_CREDIT_CARDS.include?(bank_name)
  end

  def import_transactions(parsed_data, mapped_account)
    return if parsed_data.blank?
    
    metadata = {}
    transactions = parsed_data

    # Handle structured data with metadata
    if parsed_data.is_a?(Hash) && parsed_data[:transactions]
      transactions = parsed_data[:transactions]
      metadata = parsed_data[:metadata] || {}
      # Merge top-level keys if any (legacy support)
      metadata[:opening_balance] ||= parsed_data[:opening_balance]
      metadata[:closing_balance] ||= parsed_data[:closing_balance]
    end
    
    new_transactions = []
    updated_entries = []
    claimed_entry_ids = Set.new
    
    # =====================================================
    # SMART BALANCE VERIFICATION - PRE-IMPORT CHECK
    # =====================================================
    
    # For EXISTING accounts (not empty): Check if statement opening balance matches current balance
    unless mapped_account.entries.empty?
      if metadata[:opening_balance].present?
        current_balance = mapped_account.balance.to_f
        statement_opening = metadata[:opening_balance].to_f
        balance_diff = (current_balance - statement_opening).abs
        
        if balance_diff > 1.0  # Allow ₹1 tolerance for rounding
          # Log warning - statement might overlap or have gaps
          Rails.logger.warn "⚠️ BALANCE CONTINUITY WARNING for #{mapped_account.name}:"
          Rails.logger.warn "   Current Account Balance: #{current_balance}"
          Rails.logger.warn "   Statement Opening Balance: #{statement_opening}"
          Rails.logger.warn "   Difference: #{balance_diff}"
          Rails.logger.warn "   This could indicate: overlapping statements, missing transactions, or statement gaps."
          
          # Store warning in import notes for user visibility
          self.update_column(:notes, [notes, "Balance Warning: Statement opening (#{statement_opening}) differs from current balance (#{current_balance}) by #{balance_diff.round(2)}"].compact.join("\n")) rescue nil
        else
          Rails.logger.info "✓ Balance continuity verified for #{mapped_account.name}: Current=#{current_balance}, Opening=#{statement_opening}"
        end
      end
    end
    
    # SMART FEATURE: Auto-Set Opening Balance for New Accounts
    # If the account has no entries, and we know the opening balance from PDF
    if mapped_account.entries.empty? && metadata[:opening_balance].present? && metadata[:opening_balance] > 0
      # Create an Opening Balance entry
      # Date: Use the date of the first transaction found, or today
      first_txn_date = transactions.first&.dig(:date) || Date.today
      
      opening_txn = Transaction.new(
        category: find_category("Opening Balance"), # Creates/Finds 'Opening Balance' category if needed
        entry: Entry.new(
          account: mapped_account,
          date: first_txn_date,
          amount: metadata[:opening_balance],
          name: "Opening Balance",
          currency: mapped_account.currency || family.currency,
          notes: "Auto-detected Opening Balance from Import",
          import: self
        )
      )
      new_transactions << opening_txn
      Rails.logger.info "Auto-creating Opening Balance of #{metadata[:opening_balance]} for #{mapped_account.name}"
    end

    transactions.each_with_index do |txn_data, index|
      next unless txn_data.is_a?(Hash) && txn_data[:date] && txn_data[:amount]
      
      # =====================================================
      # POLARITY CONVERSION: Parser → Rupi Convention
      # =====================================================
      # Parsers return: Deposits=+positive, Withdrawals=-negative (user-friendly)
      # Rupi expects:   Inflows=-negative, Outflows=+positive (accounting standard)
      # 
      # Rupi convention (from Import::Row#apply_transaction_signage_convention):
      #   - Negative amount = Inflow (money coming IN, increases balance)
      #   - Positive amount = Outflow (money going OUT, decreases balance)
      #
      # So we invert: rupi_amount = -parser_amount
      rupi_amount = -txn_data[:amount].to_d
      
      category = find_category(txn_data[:description])
      effective_currency = mapped_account.currency.presence || family.currency

      # Check for duplicates (using Rupi convention amount)
      adapter = Account::ProviderImportAdapter.new(mapped_account)
      duplicate_entry = adapter.find_duplicate_transaction(
        date: txn_data[:date],
        amount: rupi_amount,
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
            amount: rupi_amount,  # Use Rupi convention
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
    if new_transactions.any?
      # We need to save manually to handle the Entry association properly if bulk import is tricky
      # Or assume proper accepts_nested_attributes/autosave
      # ActiveRecord-Import works if configured properly
      # But Transaction + Entry is a nested creation.
      # Safest to save sequentially for now, or use specialized bulk import logic
      # Existing code used Transaction.import! recursive: true, which works for Rails 6+
      Transaction.import!(new_transactions, recursive: true)
    end
    
    # AI-powered categorization for uncategorized transactions
    # Collect IDs of transactions that don't have a category yet
    uncategorized_transactions = Transaction.where(id: new_transactions.map(&:id).compact, category_id: nil)
    uncategorized_count = uncategorized_transactions.count
    
    if uncategorized_count > 0
      # Start categorization tracking on the import
      job = AutoCategorizeJob.perform_later(
        family, 
        transaction_ids: uncategorized_transactions.pluck(:id),
        import_id: self.id
      )
      
      # Update import with categorization tracking info
      start_categorization!(
        job_id: job.job_id,
        total_count: uncategorized_count
      )
      
      Rails.logger.info("[Import #{id}] Started AI categorization for #{uncategorized_count} transactions")
    else
      # No transactions to categorize - mark as skipped
      skip_categorization!
      Rails.logger.info("[Import #{id}] No uncategorized transactions, skipping AI categorization")
    end
    
    # =====================================================
    # SMART BALANCE VERIFICATION - POST-IMPORT CHECK
    # =====================================================
    
    # Verify that final account balance matches statement's closing balance
    if metadata[:closing_balance].present?
      # Reload account to get fresh balance after import
      mapped_account.reload
      final_balance = mapped_account.balance.to_f
      statement_closing = metadata[:closing_balance].to_f
      reconciliation_diff = (final_balance - statement_closing).abs
      
      if reconciliation_diff <= 1.0  # Allow ₹1 tolerance
        Rails.logger.info "✓ RECONCILIATION SUCCESS for #{mapped_account.name}:"
        Rails.logger.info "   Final Account Balance: #{final_balance}"
        Rails.logger.info "   Statement Closing Balance: #{statement_closing}"
        Rails.logger.info "   All transactions imported correctly!"
      else
        Rails.logger.warn "⚠️ RECONCILIATION WARNING for #{mapped_account.name}:"
        Rails.logger.warn "   Final Account Balance: #{final_balance}"
        Rails.logger.warn "   Statement Closing Balance: #{statement_closing}"
        Rails.logger.warn "   Difference: #{reconciliation_diff}"
        Rails.logger.warn "   This could indicate: duplicate transactions, missing transactions, or rounding errors."
        
        # Store reconciliation info for user
        self.update_column(:notes, [notes, "Reconciliation: Final balance (#{final_balance.round(2)}) differs from statement closing (#{statement_closing.round(2)}) by #{reconciliation_diff.round(2)}"].compact.join("\n")) rescue nil
      end
    end
    
    # Log import summary
    Rails.logger.info "Import Complete: #{new_transactions.count} new, #{updated_entries.count} updated for #{mapped_account.name}"
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
    
    # Get closing balance from parsed metadata (or 0 if not available)
    # Note: @parsed_metadata is set by extract_metadata() called before this
    initial_balance = @parsed_metadata&.dig(:closing_balance).to_f || 0
    
    if credit_card_statement?
      # Credit cards are liabilities
      existing = family.accounts.where(accountable_type: "CreditCard")
                                .find_by("accounts.name ILIKE ?", "%#{bank_name.split('_').first}%")
      return existing if existing

      family.accounts.create!(
        name: account_name,
        balance: initial_balance,
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
        balance: initial_balance,
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

      # Smart subtype detection:
      # - Indian banks (HDFC, ICICI, SBI, etc.) are typically Savings accounts
      # - Wise and foreign banks might be Checking
      # - Can be overridden by metadata from parser
      subtype = detect_account_subtype
      
      family.accounts.create!(
        name: account_name,
        balance: initial_balance,
        currency: account_currency,
        accountable: Depository.new(subtype: subtype)
      )
    end
  end
  
  # Detect if this is a savings or checking account
  # Indian bank accounts are almost always Savings accounts
  INDIAN_BANKS = %w[
    HDFC ICICI SBI Axis Kotak RBL Bandhan Jupiter Equitas KVB UBI
  ].freeze
  
  CHECKING_BANKS = %w[
    Wise
  ].freeze
  
  def detect_account_subtype
    # 1. Check if parser provided explicit account type
    if @parsed_metadata&.dig(:account_type).present?
      return @parsed_metadata[:account_type].to_s.downcase == "checking" ? "checking" : "savings"
    end
    
    # 2. Indian banks are almost always savings
    base_bank = bank_name.split('_').first
    if INDIAN_BANKS.include?(base_bank)
      return "savings"
    end
    
    # 3. Some specific banks are typically checking
    if CHECKING_BANKS.include?(base_bank)
      return "checking"
    end
    
    # 4. Default to savings (most common globally)
    "savings"
  end

  def parse_statement
    # =====================================================
    # SIDECAR ARCHITECTURE: Use RupiEngine API for parsing
    # =====================================================
    # The proprietary parsing logic lives in rupi-engine (port 4000)
    # This keeps the secret sauce separate from the open-source shell
    
    # Download the file for API upload
    file_to_parse = download_statement_file
    
    begin
      # Call the proprietary parsing engine
      response = RupiEngine::Client.parse_statement(
        file_to_parse, 
        bank_name: bank_name, 
        password: effective_password
      )
      
      if response.success?
        Rails.logger.info("[RupiEngine] Successfully parsed #{response.transaction_count} transactions for #{bank_name}")
        
        # Bundle transactions with metadata from engine
        {
          transactions: response.transactions.map { |t| normalize_engine_transaction(t) },
          metadata: response.data&.dig("metadata") || {}
        }
      else
        # Handle specific error types
        case response.error_type
        when "password_required"
          raise BankStatementParser::PasswordRequiredError, response.error_message
        when "connection_error", "timeout"
          # Engine unavailable - fall back to local parsing (temporary)
          Rails.logger.warn("[RupiEngine] Engine unavailable (#{response.error_type}), falling back to local parser")
          parse_statement_locally
        else
          raise BankStatementParser::ParseError, response.error_message || "Failed to parse statement"
        end
      end
      
    rescue Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      # Engine not running - fall back to local parsing (for development)
      Rails.logger.warn("[RupiEngine] Connection failed (#{e.class}), falling back to local parser")
      parse_statement_locally
    ensure
      # Clean up temp file
      file_to_parse.close if file_to_parse.respond_to?(:close)
      file_to_parse.unlink if file_to_parse.respond_to?(:unlink) && file_to_parse.is_a?(Tempfile)
    end
  end
  
  # Normalize transaction hash from engine API to internal format
  def normalize_engine_transaction(txn)
    {
      date: txn["date"] || txn[:date],
      description: txn["description"] || txn[:description],
      amount: txn["amount"] || txn[:amount],
      balance: txn["balance"] || txn[:balance],
      notes: txn["notes"] || txn[:notes]
    }.compact
  end
  
  # Download statement file for API upload
  def download_statement_file
    if statement_file.respond_to?(:download)
      # ActiveStorage attachment
      temp = Tempfile.new(["statement", File.extname(statement_file.filename.to_s)])
      temp.binmode
      temp.write(statement_file.download)
      temp.rewind
      temp
    elsif statement_file.respond_to?(:path)
      File.open(statement_file.path)
    else
      statement_file
    end
  end
  
  # FALLBACK: Local parsing (to be removed once engine is stable)
  # TODO: Remove this once RupiEngine is deployed and stable
  def parse_statement_locally
    Rails.logger.info("[LocalParser] Using local parser for #{bank_name}")
    parser = parser_class.new(statement_file, password: effective_password)
    transactions = parser.parse
    
    {
      transactions: transactions,
      metadata: parser.respond_to?(:metadata) ? parser.metadata : {}
    }
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
    
    # ==========================================
    # PRIORITY 1: Check learned rules (highest priority, deterministic)
    # These are rules learned from AI or user corrections
    # ==========================================
    if (rule_category = CategoryRule.categorize_by_rules(description, family: family))
      Rails.logger.debug { "CategoryRule matched: '#{description}' -> '#{rule_category.name}'" }
      return rule_category
    end
    
    # ==========================================
    # PRIORITY 2: Keyword-based categorization (fallback)
    # Comprehensive Indian-specific keyword matching
    # ==========================================
    
    # Ordered by specificity - more specific matches first
    category_keywords = {
      # ==========================================
      # FOOD & DINING (Specific first)
      # ==========================================
      "Swiggy/Zomato" => ["swiggy", "zomato", "uber eats", "dunzo", "blinkit food"],
      "Groceries" => ["bigbasket", "blinkit", "zepto", "instamart", "dmart", "reliance fresh", "more supermarket", "spencers", "grocery", "vegetables", "fruits", "kirana"],
      "Restaurants" => ["restaurant", "hotel ", "dhaba", "cafe ", "dining", "eat ", "food court", "biryani", "dosa", "pizza hut", "dominos", "mcdonalds", "kfc", "burger king", "subway"],
      "Coffee & Cafe" => ["starbucks", "cafe coffee day", "ccd", "barista", "costa coffee", "blue tokai", "third wave", "coffee"],
      "Food & Dining" => ["food", "lunch", "dinner", "breakfast", "tiffin", "canteen", "mess", "bakery", "sweet shop", "mithai"],
      
      # ==========================================
      # SHOPPING (Specific first)
      # ==========================================
      "Amazon/Flipkart" => ["amazon", "flipkart", "myntra", "ajio", "meesho", "snapdeal", "shopclues", "tata cliq", "jiomart"],
      "Clothing" => ["clothing", "fashion", "garments", "fabindia", "westside", "pantaloons", "lifestyle", "max fashion", "zudio"],
      "Electronics" => ["croma", "reliance digital", "vijay sales", "electronics", "mobile", "laptop", "computer"],
      "Shopping" => ["mall", "store", "retail", "bazaar", "mart", "shop", "decathlon", "ikea", "nykaa"],
      
      # ==========================================
      # TRANSPORTATION (Specific first)
      # ==========================================
      "Uber/Ola/Rapido" => ["uber", "ola", "rapido", "meru", "bluedart cab", "shuttle"],
      "Metro/Train" => ["metro", "irctc", "railway", "train", "dmrc", "bmrc", "cmrl"],
      "Petrol/Fuel" => ["petrol", "fuel", "diesel", "hp ", "bharat petroleum", "iocl", "bpcl", "hpcl", "indian oil", "shell", "reliance petrol"],
      "Parking/Toll/FASTag" => ["fastag", "toll", "parking", "nhai", "toll plaza"],
      "Auto/Taxi" => ["auto", "taxi", "cab", "rickshaw"],
      "Flights" => ["indigo", "airindia", "spicejet", "vistara", "goair", "akasaair", "flight", "airfare", "aviation"],
      "Travel Booking" => ["makemytrip", "goibibo", "yatra", "cleartrip", "ixigo", "redbus", "abhibus", "easemytrip"],
      "Hotels/Stays" => ["oyo", "treebo", "fab hotels", "airbnb", "booking.com", "trivago", "taj ", "oberoi", "itc ", "marriott", "hyatt", "hotel"],
      "Transportation" => ["transport", "travel", "journey", "trip"],
      
      # ==========================================
      # UTILITIES & BILLS
      # ==========================================
      "Electricity" => ["electricity", "power bill", "bescom", "tata power", "adani electricity", "torrent power", "bses", "dhbvn", "uppcl", "msedcl", "tneb"],
      "Mobile/Internet" => ["jio", "airtel", "vodafone", "vi ", "bsnl", "recharge", "postpaid", "prepaid", "broadband", "act fibernet", "hathway", "tata sky broadband"],
      "DTH/Cable" => ["tata sky", "dish tv", "airtel dth", "sun direct", "d2h", "cable"],
      "Water Bill" => ["water bill", "bwssb", "water supply", "jalboard"],
      "Gas/LPG" => ["lpg", "gas cylinder", "indane", "bharat gas", "hp gas", "piped gas", "igl", "mahanagar gas", "gail"],
      "Utilities & Bills" => ["utility", "bill payment", "bills"],
      
      # ==========================================
      # HEALTHCARE
      # ==========================================
      "Medicines" => ["pharmacy", "medplus", "apollo pharmacy", "netmeds", "1mg", "pharmeasy", "tata 1mg", "medicine", "tablets", "drugs"],
      "Doctor/Consultation" => ["doctor", "dr ", "clinic", "consultation", "opd", "practo", "apollo 24|7"],
      "Hospital" => ["hospital", "fortis", "apollo hospital", "max hospital", "medanta", "narayana", "aiims", "manipal hospital", "aster", "columbia asia"],
      "Healthcare" => ["health", "medical", "diagnostic", "lab test", "pathology", "radiology", "scan", "mri", "ct scan"],
      
      # ==========================================
      # EDUCATION
      # ==========================================
      "School/College Fees" => ["school fees", "college fees", "tuition fees", "admission", "university", "institute"],
      "Coaching/Tuition" => ["coaching", "tuition", "kota", "allen", "fiitjee", "resonance", "aakash", "byju", "unacademy", "vedantu", "physics wallah"],
      "Online Courses" => ["udemy", "coursera", "skillshare", "linkedin learning", "upgrad", "great learning", "simplilearn"],
      "Education" => ["education", "learning", "study", "exam", "books", "stationery", "academic"],
      
      # ==========================================
      # ENTERTAINMENT & SUBSCRIPTIONS
      # ==========================================
      "Netflix/OTT" => ["netflix", "hotstar", "prime video", "amazon prime", "sonyliv", "zee5", "alt balaji", "mxplayer", "jio cinema", "ott"],
      "Spotify/Music" => ["spotify", "gaana", "wynk", "apple music", "youtube music", "music"],
      "Movies/Theatre" => ["pvr", "inox", "cinepolis", "bookmyshow", "movie", "cinema", "theatre", "film"],
      "Gaming" => ["playstation", "xbox", "steam", "gaming", "games", "valorant", "pubg"],
      "Subscriptions" => ["subscription", "membership", "renewal", "premium", "annual plan"],
      "Entertainment" => ["entertainment", "fun", "recreation", "party", "event", "show"],
      
      # ==========================================
      # HOUSING & HOME
      # ==========================================
      "Rent" => ["rent", "house rent", "flat rent", "pg ", "hostel"],
      "Society Maintenance" => ["maintenance", "society", "association", "apartment maintenance", "resident welfare"],
      "Domestic Help" => ["maid", "cook", "driver salary", "domestic", "household staff", "watchman"],
      "Home Repairs" => ["repair", "plumber", "electrician", "carpenter", "ac service", "home service", "urban company", "urbanclap"],
      "Furniture/Appliances" => ["furniture", "appliance", "godrej", "samsung ", "lg ", "whirlpool", "pepperfry", "urban ladder", "home centre"],
      
      # ==========================================
      # LOANS & EMI
      # ==========================================
      "Home Loan EMI" => ["home loan", "housing loan", "homeloan", "hdfc home", "icici home", "sbi home", "axis home", "lic housing", "pnb housing"],
      "Car/Vehicle Loan EMI" => ["car loan", "vehicle loan", "auto loan", "two wheeler loan", "bike loan"],
      "Personal Loan EMI" => ["personal loan", "personalloan", "bajaj finserv", "tata capital", "fullerton"],
      "Education Loan EMI" => ["education loan", "study loan", "credila", "avanse"],
      "Credit Card Payment" => ["credit card", "cc payment", "card payment", "cc bill", "credit bill"],
      "Loan Payments" => ["emi", "loan", "installment", "equated monthly"],
      
      # ==========================================
      # INVESTMENTS & SAVINGS
      # ==========================================
      "Mutual Funds SIP" => ["sip", "mutual fund", "mf sip", "systematic investment", "groww", "zerodha coin", "kuvera", "paytm money", "et money"],
      "Stocks/Trading" => ["stock", "share", "trading", "zerodha", "upstox", "angel", "5paisa", "icicidirect", "sharekhan", "kotak securities", "demat"],
      "PPF/EPF" => ["ppf", "epf", "provident fund", "pf contribution", "employee pf"],
      "NPS" => ["nps", "national pension", "pension scheme"],
      "Fixed Deposit" => ["fixed deposit", "fd ", "term deposit"],
      "Recurring Deposit" => ["recurring deposit", "rd ", "monthly deposit"],
      "Gold/Digital Gold" => ["gold", "digital gold", "sovereign gold", "gold bond", "augmont", "safegold", "mmtc gold"],
      "Investments & Savings" => ["investment", "invest", "portfolio", "wealth", "saving"],
      
      # ==========================================
      # INSURANCE
      # ==========================================
      "Health Insurance" => ["health insurance", "medical insurance", "mediclaim", "star health", "care health", "niva bupa", "hdfc ergo health"],
      "Life Insurance (LIC)" => ["lic ", "life insurance", "term plan", "endowment", "max life", "hdfc life", "icici pru", "sbi life", "bajaj life"],
      "Vehicle Insurance" => ["motor insurance", "car insurance", "bike insurance", "vehicle insurance", "national insurance", "new india insurance"],
      "Insurance" => ["insurance", "policy", "premium", "renewal"],
      
      # ==========================================
      # TAXES
      # ==========================================
      "Income Tax" => ["income tax", "it return", "itr ", "efiling"],
      "Advance Tax" => ["advance tax", "adv tax", "challan 280"],
      "GST" => ["gst ", "goods and service", "gstin"],
      "Taxes" => ["tax", "tds", "professional tax", "property tax", "municipal tax"],
      
      # ==========================================
      # PERSONAL CARE & FITNESS
      # ==========================================
      "Gym/Fitness" => ["gym", "fitness", "cult ", "cult.fit", "cure.fit", "yoga", "crossfit", "gold gym", "anytime fitness"],
      "Salon/Grooming" => ["salon", "parlour", "haircut", "spa", "barbershop", "grooming", "jawed habib", "lakme salon", "naturals"],
      "Personal Care" => ["personal care", "cosmetics", "beauty", "skincare", "nykaa", "purplle"],
      
      # ==========================================
      # KIDS & FAMILY
      # ==========================================
      "Childcare" => ["childcare", "daycare", "creche", "nanny", "babysitter"],
      "Kids Education" => ["kids school", "play school", "nursery", "kidzee", "eurokids", "podar"],
      "Toys & Games" => ["toys", "hamleys", "firstcry", "kids zone", "game zone"],
      
      # ==========================================
      # CELEBRATIONS & OCCASIONS
      # ==========================================
      "Wedding/Functions" => ["wedding", "marriage", "shaadi", "wedding venue", "catering", "band baja", "decorator"],
      "Festivals/Puja" => ["pooja", "puja", "temple", "mandir", "diwali", "holi", "eid", "christmas", "festival", "ganesh", "durga"],
      "Gifts" => ["gift", "present", "archies", "ferns n petals", "fnp ", "igp ", "winni"],
      "Celebrations" => ["birthday", "anniversary", "party", "celebration", "function", "event"],
      
      # ==========================================
      # DONATIONS & CHARITY
      # ==========================================
      "Temple/Religious" => ["temple", "church", "mosque", "gurudwara", "religious", "donation to temple", "devsthan"],
      "NGO/Charity" => ["ngo", "charity", "donation", "relief fund", "help", "support", "foundation"],
      "Donations & Charity" => ["donate", "contribution", "seva"],
      
      # ==========================================
      # FEES & CHARGES
      # ==========================================
      "Bank Charges" => ["bank charge", "service charge", "account maintenance", "min balance", "annual charge", "folio", "dpamount"],
      "ATM Fees" => ["atm fee", "atm charge", "cash withdrawal fee"],
      "Card AMC" => ["card amc", "annual fee", "membership fee", "card charges"],
      "Fees & Charges" => ["fee", "charge", "penalty", "fine", "late fee"],
      
      # ==========================================
      # TRANSFERS (Low priority - often internal)
      # ==========================================
      "Transfers" => ["transfer", "neft", "rtgs", "imps", "upi ", "p2p", "p2m", "a/c transfer"],
      
      # ==========================================
      # MISCELLANEOUS
      # ==========================================
      "ATM Withdrawal" => ["atm withdrawal", "cash withdrawal", "atm wd", "atm cash"],
      "Cash" => ["cash"],
      "Miscellaneous" => ["misc", "other", "general"]
    }
    
    # Generic/dangerous keywords that need word-boundary matching
    generic_keywords = %w[
      hdfc icici axis sbi kotak yes indusind
      paytm phonepe gpay google pay upi
      jio airtel vi bsnl vodafone
      amazon flipkart
      transfer credit debit payment
      food hotel coffee shop store mall
    ]

    # Normalize description (same as CategoryRule)
    normalized = CategoryRule.normalize_light(description)
    description_lower = description.downcase
    
    # Find matching category with improved matching
    category_keywords.each do |category_name, keywords|
      matched_keyword = keywords.find do |keyword|
        if generic_keywords.any? { |g| keyword.include?(g) }
          # Word-boundary matching for generic keywords
          normalized.match?(/\b#{Regexp.escape(keyword)}\b/)
        else
          # Standard substring matching for specific keywords
          normalized.include?(keyword) || description_lower.include?(keyword)
        end
      end
      
      if matched_keyword
        Rails.logger.debug { "Keyword matched: '#{description}' matched '#{matched_keyword}' -> '#{category_name}'" }
        
        return family.categories.find_or_create_by(name: category_name) do |cat|
          # Set defaults for new categories
          cat.color = "#6b7280"  # Gray as default
          cat.lucide_icon = "tag"
          cat.classification = "expense"
        end
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
