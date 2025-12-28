# frozen_string_literal: true

# CategoryRule stores learned rules for auto-categorizing transactions.
# 
# RULE LIFECYCLE:
# 1. AI creates rule as "candidate" (status: candidate, confidence: 0.65)
# 2. After N matches (default: 2), rule promoted to "active" but "probationary"
# 3. If overridden during probation → demote immediately
# 4. After probation (5 uses without override) → fully trusted
# 5. User confirmation immediately promotes to "active" + trusted
# 6. Manual rules start active but can still be demoted if repeatedly wrong
#
# PRECEDENCE (after all scoring):
# 1. Highest priority wins (calculated from multiple factors)
# 2. Manual rules start higher but can lose priority if overridden
# 3. Specific patterns beat broad patterns
#
class CategoryRule < ApplicationRecord
  belongs_to :family
  belongs_to :category
  belongs_to :account, optional: true  # For account-specific rules

  # Match types ordered by specificity (higher = more specific)
  MATCH_TYPES = {
    "exact" => 100,
    "regex_anchored" => 90,   # Regex with \b or ^ or $
    "starts_with" => 80,
    "ends_with" => 70,
    "contains" => 50,
    "regex" => 45             # Unanchored regex
  }.freeze
  
  # Sources ordered by base trust level
  SOURCE_BASE_WEIGHTS = {
    "manual" => 100,
    "system" => 80,
    "ai" => 50,
    "auto" => 30
  }.freeze
  
  # Rule statuses
  STATUSES = %w[candidate active inactive].freeze
  
  # Rule scopes - what the rule applies to
  SCOPES = %w[global narration merchant account_specific].freeze
  
  # Promotion and probation thresholds
  PROMOTION_THRESHOLD = 2           # Matches to promote candidate → active
  PROBATION_USES = 5                # Uses before rule is "trusted"
  PROBATION_OVERRIDE_TOLERANCE = 0  # Overrides allowed during probation (0 = strict)
  
  # Confidence settings
  INITIAL_AI_CONFIDENCE = 0.65
  CONFIRMED_CONFIDENCE = 0.95
  MANUAL_CONFIDENCE = 1.0
  MIN_CONFIDENCE = 0.3              # Below this, demote to inactive
  
  # Override penalty
  OVERRIDE_PENALTY_PRIORITY = 5000  # Per override, reduce priority by this

  validates :pattern, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES.keys }
  validates :source, inclusion: { in: SOURCE_BASE_WEIGHTS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :scope, inclusion: { in: SCOPES }
  validates :pattern, uniqueness: { scope: [:family_id, :scope], case_sensitive: false }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :active, -> { where(status: "active") }
  scope :candidates, -> { where(status: "candidate") }
  scope :trusted, -> { where(probationary: false, status: "active") }
  scope :by_priority, -> { order(priority: :desc, confidence: :desc) }
  scope :for_scope, ->(scope_type) { where(scope: [scope_type, "global"]) }

  before_validation :calculate_priority
  before_validation :set_defaults, on: :create
  before_validation :detect_regex_type

  # ==========================================
  # NORMALIZATION (Two-level)
  # ==========================================
  
  # Light normalization - preserves useful signals, used for MATCHING
  def self.normalize_light(description)
    return "" if description.blank?
    
    desc = description.dup
    
    # Only remove very obvious noise
    desc = desc.gsub(/\b\d{14,}\b/, "")              # Very long numbers (14+ digits)
    desc = desc.gsub(/\d{2}[-\/]\d{2}[-\/]\d{4}/, "") # Dates
    desc = desc.gsub(/\s+/, " ")                      # Collapse whitespace
    
    desc.strip.downcase
  end
  
  # Aggressive normalization - for rule pattern EXTRACTION only
  def self.normalize_aggressive(description)
    return "" if description.blank?
    
    desc = description.dup
    
    # Remove noise patterns
    desc = desc.gsub(/\b[A-Z0-9]{12,}\b/, "")         # Long alphanumeric codes
    desc = desc.gsub(/\b\d{10,}\b/, "")               # Long numbers
    desc = desc.gsub(/\d{2}[-\/]\d{2}[-\/]\d{2,4}/, "") # Dates
    desc = desc.gsub(/ref\s*:?\s*\S+/i, "")           # Reference patterns
    desc = desc.gsub(/upi\s*ref\s*no\s*\S+/i, "")     # UPI refs  
    desc = desc.gsub(/txn\s*id\s*:?\s*\S+/i, "")      # Transaction IDs
    desc = desc.gsub(/[^\w\s]/, " ")                  # Punctuation → spaces
    desc = desc.gsub(/\s+/, " ")                      # Collapse whitespace
    
    desc.strip.downcase
  end

  # ==========================================
  # MAIN MATCHING LOGIC
  # ==========================================
  
  # Find the best matching rule for a transaction
  def self.find_matching_rule(description, family:, scope: "narration", account: nil)
    return nil if description.blank?
    
    # Light normalization for matching
    normalized = normalize_light(description)
    
    # Build query - active rules for this family and scope
    query = active.where(family: family).for_scope(scope).by_priority
    
    # If account specified, also check account-specific rules
    if account
      query = query.where("account_id IS NULL OR account_id = ?", account.id)
    else
      query = query.where(account_id: nil)
    end
    
    # Find first matching rule (already sorted by priority)
    query.find { |rule| rule.matches?(normalized, description) }
  end
  
  # Find category for a description using rules
  def self.categorize_by_rules(description, family:, scope: "narration", account: nil)
    rule = find_matching_rule(description, family: family, scope: scope, account: account)
    return nil unless rule
    
    # Track the match and potentially promote
    rule.record_match!
    
    rule.category
  end
  
  # Check if this rule matches a description
  def matches?(normalized_description, raw_description = nil)
    return false if normalized_description.blank?
    
    pattern_lower = pattern.downcase.strip
    raw_lower = raw_description&.downcase || normalized_description
    
    case match_type
    when "exact"
      normalized_description == pattern_lower || raw_lower == pattern_lower
    when "starts_with"
      normalized_description.start_with?(pattern_lower) || raw_lower.start_with?(pattern_lower)
    when "ends_with"
      normalized_description.end_with?(pattern_lower) || raw_lower.end_with?(pattern_lower)
    when "regex_anchored", "regex"
      safe_regex_match?(normalized_description, pattern) || safe_regex_match?(raw_lower, pattern)
    else # contains (default)
      # For generic patterns, use word boundary matching
      if generic_pattern?
        word_boundary_match?(normalized_description, pattern_lower) || 
          word_boundary_match?(raw_lower, pattern_lower)
      else
        normalized_description.include?(pattern_lower) || raw_lower.include?(pattern_lower)
      end
    end
  end
  
  # Dangerous/generic patterns that need word-boundary matching
  GENERIC_PATTERNS = %w[
    hdfc icici axis sbi kotak yes indusind rbl ubi bandhan
    paytm phonepe gpay google amazon flipkart
    jio airtel vi bsnl vodafone
    upi imps neft rtgs
    food hotel coffee shop store mall bank
  ].freeze
  
  def generic_pattern?
    GENERIC_PATTERNS.any? { |g| pattern.downcase.include?(g) }
  end
  
  def word_boundary_match?(description, pattern)
    regex = Regexp.new("\\b#{Regexp.escape(pattern)}\\b", Regexp::IGNORECASE)
    description.match?(regex)
  rescue RegexpError
    description.include?(pattern)
  end
  
  def safe_regex_match?(description, pattern)
    description.match?(Regexp.new(pattern, Regexp::IGNORECASE))
  rescue RegexpError
    false
  end

  # ==========================================
  # MATCH TRACKING & PROMOTION
  # ==========================================
  
  def record_match!
    increment!(:times_matched)
    
    # Increase confidence (diminishing returns curve)
    new_confidence = calculate_new_confidence_after_match
    update_column(:confidence, new_confidence)
    
    # Auto-promote candidates after threshold
    if status == "candidate" && times_matched >= PROMOTION_THRESHOLD
      promote_to_active!
    end
    
    # Exit probation if enough uses without recent overrides
    if probationary? && times_matched >= PROBATION_USES
      if recent_overrides_count == 0
        exit_probation!
      end
    end
    
    recalculate_priority!
  end
  
  # Diminishing returns: +0.05 for first 3, +0.02 for next 5, +0.01 after
  def calculate_new_confidence_after_match
    current = confidence
    matches = times_matched
    
    increment = if matches <= 3
      0.05
    elsif matches <= 8
      0.02
    else
      0.01
    end
    
    # Don't increase if recently overridden (cooldown)
    if last_overridden_at && last_overridden_at > 24.hours.ago
      increment = 0
    end
    
    [current + increment, 0.99].min
  end
  
  def recent_overrides_count
    # Count overrides in last N matches
    # For simplicity, we track times_overridden total
    times_overridden || 0
  end
  
  def promote_to_active!
    update!(status: "active", probationary: true)
    Rails.logger.info("CategoryRule promoted to active (probationary): pattern='#{pattern}'")
  end
  
  def exit_probation!
    update!(probationary: false)
    Rails.logger.info("CategoryRule exited probation: pattern='#{pattern}'")
  end
  
  def demote_to_inactive!
    update!(status: "inactive")
    Rails.logger.warn("CategoryRule demoted to inactive: pattern='#{pattern}'")
  end
  
  # Called when user overrides this rule's categorization
  def record_override!
    increment!(:times_overridden)
    update_column(:last_overridden_at, Time.current)
    
    # Decrease confidence (more aggressive for AI rules)
    decrement = source == "ai" ? 0.20 : 0.15
    new_confidence = [confidence - decrement, 0].max
    update_column(:confidence, new_confidence)
    
    # PROBATIONARY RULES: Demote immediately on first override
    if probationary? && times_overridden > PROBATION_OVERRIDE_TOLERANCE
      demote_to_inactive!
      Rails.logger.warn("CategoryRule demoted during probation: pattern='#{pattern}'")
      return
    end
    
    # Any rule: Demote if confidence too low
    if new_confidence < MIN_CONFIDENCE
      demote_to_inactive!
    end
    
    recalculate_priority!
  end
  
  # User confirms this rule is correct
  def confirm!
    update!(
      confidence: [confidence, CONFIRMED_CONFIDENCE].max,
      status: "active",
      probationary: false,
      user_confirmed: true
    )
    recalculate_priority!
    Rails.logger.info("CategoryRule confirmed by user: pattern='#{pattern}'")
  end

  # ==========================================
  # PRIORITY CALCULATION
  # ==========================================
  
  def calculate_priority
    # Base from source (can be reduced by overrides)
    base_source_weight = SOURCE_BASE_WEIGHTS[source] || 30
    
    # Override penalty - even manual rules lose priority if repeatedly wrong
    override_penalty = (times_overridden || 0) * OVERRIDE_PENALTY_PRIORITY
    effective_source_weight = [base_source_weight * 1000 - override_penalty, 0].max
    
    # Match strength
    match_strength = MATCH_TYPES[match_type] || 50
    
    # Pattern specificity (longer = more specific, capped)
    pattern_specificity = [pattern.to_s.length, 50].min
    
    # Confidence bonus (0-10)
    confidence_bonus = (confidence * 10).round
    
    # User confirmed bonus
    user_confirmed_bonus = user_confirmed? ? 200 : 0
    
    # Probationary penalty (active but not yet trusted)
    probation_penalty = probationary? ? 100 : 0
    
    # Scope bonus (more specific scope = higher priority)
    scope_bonus = case self.scope
    when "account_specific" then 300
    when "merchant" then 200
    when "narration" then 100
    else 0  # global
    end
    
    self.priority = effective_source_weight + 
                    (match_strength * 10) + 
                    pattern_specificity + 
                    confidence_bonus +
                    user_confirmed_bonus +
                    scope_bonus -
                    probation_penalty
  end
  
  def recalculate_priority!
    calculate_priority
    update_column(:priority, priority)
  end

  # ==========================================
  # RULE CREATION
  # ==========================================

  # Create a rule from an AI categorization (starts as candidate + probationary)
  def self.create_from_ai_categorization(description:, category:, family:, 
                                          confidence: nil, scope: "narration", account: nil)
    # Use aggressive normalization for pattern extraction
    pattern = extract_pattern(description)
    return nil if pattern.blank?
    return nil if pattern.length < 3  # Too short = too generic
    
    # Check for existing rule with same pattern
    existing = find_by(family: family, pattern: pattern.downcase, scope: scope)
    if existing
      existing.record_match!
      return existing
    end
    
    # Don't create if there's a conflicting manual/system rule
    conflicting = where(family: family, scope: scope)
                    .where("LOWER(pattern) = ?", pattern.downcase)
                    .where(source: ["manual", "system"])
                    .exists?
    return nil if conflicting
    
    create(
      family: family,
      category: category,
      account: account,
      pattern: pattern.downcase,
      match_type: determine_match_type(pattern),
      source: "ai",
      scope: scope,
      status: "candidate",
      probationary: true,
      confidence: confidence || INITIAL_AI_CONFIDENCE,
      merchant_name: extract_merchant_name(description),
      user_confirmed: false
    )
  end

  # Learn a rule from user's manual categorization
  def self.learn_from_user(transaction:, category:, scope: "narration")
    description = transaction.entry.name
    return nil if description.blank?
    
    pattern = extract_pattern(description)
    return nil if pattern.blank?
    
    existing = find_by(family: transaction.family, pattern: pattern.downcase, scope: scope)
    if existing
      if existing.category_id == category.id
        # User confirming existing rule
        existing.confirm!
      else
        # User correcting to different category - override old rule
        existing.record_override!
        
        # Create new manual rule
        return create(
          family: transaction.family,
          category: category,
          pattern: pattern.downcase,
          match_type: determine_match_type(pattern),
          source: "manual",
          scope: scope,
          status: "active",
          probationary: false,  # Manual rules skip probation
          confidence: MANUAL_CONFIDENCE,
          merchant_name: extract_merchant_name(description),
          user_confirmed: true
        )
      end
      return existing
    end
    
    create(
      family: transaction.family,
      category: category,
      pattern: pattern.downcase,
      match_type: determine_match_type(pattern),
      source: "manual",
      scope: scope,
      status: "active",
      probationary: false,
      confidence: MANUAL_CONFIDENCE,
      merchant_name: extract_merchant_name(description),
      user_confirmed: true
    )
  end

  # ==========================================
  # EXPLANATION (for "Why was this categorized?")
  # ==========================================
  
  def explanation
    {
      type: "rule",
      rule_id: id,
      matched_pattern: pattern,
      match_type: match_type,
      scope: scope,
      category_name: category.name,
      source: source,
      source_label: source_label,
      confidence: confidence.round(2),
      trusted: !probationary?,
      stats: {
        times_matched: times_matched,
        times_overridden: times_overridden || 0,
        user_confirmed: user_confirmed?
      },
      created_at: created_at,
      human_readable: human_readable_explanation
    }
  end
  
  def source_label
    base = case source
    when "manual" then "You created this rule"
    when "system" then "Default system rule"
    when "ai" then user_confirmed? ? "AI (you confirmed)" : "AI learned"
    else "Auto-detected"
    end
    
    base += " (probationary)" if probationary?
    base
  end
  
  def human_readable_explanation
    match_desc = case match_type
    when "exact" then "exactly matches"
    when "starts_with" then "starts with"
    when "ends_with" then "ends with"
    when "contains" then "contains"
    when "regex", "regex_anchored" then "matches pattern"
    end
    
    confidence_desc = if confidence >= 0.9
      "high confidence"
    elsif confidence >= 0.7
      "good confidence"
    elsif confidence >= 0.5
      "moderate confidence"
    else
      "low confidence"
    end
    
    trust_desc = probationary? ? ", probationary" : ""
    
    "Transaction #{match_desc} \"#{pattern}\" → #{category.name} (#{source_label}, #{confidence_desc}#{trust_desc}, #{times_matched} matches)"
  end

  # ==========================================
  # HELPERS
  # ==========================================
  
  def probationary?
    probationary == true
  end
  
  # Detect if regex has anchors (more specific)
  def detect_regex_type
    return unless match_type&.start_with?("regex")
    
    if pattern.match?(/\\b|^\^|\$$/)
      self.match_type = "regex_anchored"
    else
      self.match_type = "regex"
    end
  end
  
  def self.determine_match_type(pattern)
    return "contains" if pattern.blank?
    
    # Very short patterns should be exact
    return "exact" if pattern.length <= 4
    
    # Patterns that look like clean merchant names → starts_with
    if pattern.match?(/^[a-z]+$/i) && pattern.length >= 5
      return "starts_with"
    end
    
    "contains"
  end

  # Extract pattern using AGGRESSIVE normalization
  def self.extract_pattern(description)
    return nil if description.blank?
    
    normalized = normalize_aggressive(description)
    return nil if normalized.blank?
    
    # Split into tokens and find meaningful ones
    tokens = normalized.split(/\s+/).reject { |t| t.length < 3 }
    
    # Remove noise words
    noise_words = %w[
      upi imps neft rtgs the and for from to via by at on in of
      debit credit transfer payment transaction ref no number id
      mobile wallet bank account pvt ltd limited india private
      pos ach wire check cheque
    ]
    meaningful_tokens = tokens.reject { |t| noise_words.include?(t) }
    
    # Take first 2-3 meaningful tokens
    pattern = meaningful_tokens.first(3).join(" ")
    
    # Fallback if too generic
    if pattern.length < 4 && normalized.length >= 4
      pattern = normalized.split(/\s+/).first(3).join(" ")
    end
    
    pattern.presence
  end

  def self.extract_merchant_name(description)
    return nil if description.blank?
    
    # Light normalization to preserve useful signals
    normalized = normalize_light(description)
    tokens = normalized.split(/\s+/).reject { |t| t.length < 3 }
    
    # First meaningful token is often the merchant
    tokens.first&.titleize
  end

  private

  def set_defaults
    self.status ||= (source == "manual" ? "active" : "candidate")
    self.probationary = (source != "manual") if probationary.nil?
    self.confidence ||= (source == "manual" ? MANUAL_CONFIDENCE : INITIAL_AI_CONFIDENCE)
    self.times_matched ||= 0
    self.times_overridden ||= 0
    self.user_confirmed ||= (source == "manual")
    self.scope ||= "narration"
  end
end
