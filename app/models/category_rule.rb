# frozen_string_literal: true

require "digest"
require "concurrent"

# CategoryRule stores learned rules for auto-categorizing transactions.
# 
# RULE LIFECYCLE:
# 1. AI creates rule as "candidate" (status: candidate, confidence: 0.65)
# 2. After N matches, rule promoted to "active" but "probationary"
# 3. If overridden during probation → quarantined (IMMEDIATE, synchronous)
# 4. After probation (5 uses without override) → fully trusted
# 5. User confirmation immediately promotes to "active" + trusted
# 6. Manual rules start active but can still be demoted if repeatedly wrong
#
# PERFORMANCE:
# - pattern_hash_exact (SHA256) for indexed exact-match lookups ONLY
# - Class-level LRU regex cache (capped at 1000 entries)
# - Pre-filtered queries by scope + status + account_id
#
# CAPACITY:
# - Auto-prune lowest utility rules when limits exceeded
# - Quarantine cleanup: keep last N per family, delete >90 days old
#
class CategoryRule < ApplicationRecord
  belongs_to :family
  belongs_to :category
  belongs_to :account, optional: true

  # ==========================================
  # CLASS-LEVEL REGEX CACHE (LRU-ish, capped)
  # ==========================================
  REGEX_CACHE_MAX_SIZE = 1000
  @regex_cache = Concurrent::Map.new
  @regex_cache_keys = []  # For LRU eviction
  @regex_cache_mutex = Mutex.new
  
  class << self
    attr_reader :regex_cache, :regex_cache_keys, :regex_cache_mutex
    
    def cached_regex(pattern, flags = Regexp::IGNORECASE)
      cache_key = "#{pattern}:#{flags}"
      
      # Try cache first
      cached = @regex_cache[cache_key]
      return cached if cached
      
      # Compile and cache
      compiled = begin
        Regexp.new(pattern, flags)
      rescue RegexpError
        nil
      end
      
      return nil unless compiled
      
      # LRU eviction if needed
      @regex_cache_mutex.synchronize do
        if @regex_cache_keys.size >= REGEX_CACHE_MAX_SIZE
          oldest_key = @regex_cache_keys.shift
          @regex_cache.delete(oldest_key)
        end
        @regex_cache_keys.push(cache_key)
      end
      
      @regex_cache[cache_key] = compiled
      compiled
    end
    
    def cached_word_boundary_regex(pattern)
      cached_regex("\\b#{Regexp.escape(pattern)}\\b", Regexp::IGNORECASE)
    end
    
    def clear_regex_cache!
      @regex_cache_mutex.synchronize do
        @regex_cache.clear
        @regex_cache_keys.clear
      end
    end
  end

  # Match types ordered by specificity
  MATCH_TYPES = {
    "exact" => 100,
    "regex_anchored" => 90,
    "starts_with" => 80,
    "ends_with" => 70,
    "contains" => 50,
    "regex" => 45
  }.freeze
  
  SOURCE_BASE_WEIGHTS = {
    "manual" => 100,
    "system" => 80,
    "ai" => 50,
    "auto" => 30
  }.freeze
  
  STATUSES = %w[candidate active inactive quarantined].freeze
  SCOPES = %w[global narration merchant account_specific].freeze
  
  # Limits
  MAX_ACCOUNT_SPECIFIC_RULES = 2000
  MAX_GLOBAL_RULES = 5000
  MAX_TOTAL_RULES_PER_FAMILY = 10000
  MAX_QUARANTINED_PER_FAMILY = 2000
  QUARANTINE_RETENTION_DAYS = 90
  
  # Thresholds
  PROMOTION_THRESHOLD = 2
  PROBATION_USES = 5
  PROBATION_OVERRIDE_TOLERANCE = 0
  
  # Confidence
  INITIAL_AI_CONFIDENCE = 0.65
  CONFIRMED_CONFIDENCE = 0.95
  MANUAL_CONFIDENCE = 1.0
  MIN_CONFIDENCE = 0.3
  
  OVERRIDE_PENALTY_PRIORITY = 5000

  validates :pattern, presence: true
  validates :match_type, inclusion: { in: MATCH_TYPES.keys }
  validates :source, inclusion: { in: SOURCE_BASE_WEIGHTS.keys }
  validates :status, inclusion: { in: STATUSES }
  validates :scope, inclusion: { in: SCOPES }
  validates :pattern, uniqueness: { scope: [:family_id, :scope], case_sensitive: false }
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :active, -> { where(status: "active") }
  scope :candidates, -> { where(status: "candidate") }
  scope :quarantined, -> { where(status: "quarantined") }
  scope :matchable, -> { where(status: ["active", "candidate"]) }
  scope :trusted, -> { where(probationary: false, status: "active") }
  scope :by_priority, -> { order(priority: :desc, confidence: :desc) }
  scope :for_scope, ->(scope_type) { where(scope: [scope_type, "global"]) }
  scope :by_utility, -> { order(Arel.sql("(times_matched - (COALESCE(times_overridden, 0) * 3) - EXTRACT(EPOCH FROM (NOW() - created_at)) / 86400 / 30) DESC")) }
  scope :exact_match_type, -> { where(match_type: "exact") }

  before_validation :calculate_priority
  before_validation :set_defaults, on: :create
  before_validation :detect_regex_type
  before_validation :compute_pattern_hashes

  # ==========================================
  # PATTERN HASHES (SHA256, for exact rules only)
  # ==========================================
  
  def compute_pattern_hashes
    # Only compute hash for exact match rules
    if match_type == "exact"
      # Use light normalization (same as matching uses)
      normalized = self.class.normalize_light(pattern.to_s)
      self.pattern_hash_exact = Digest::SHA256.hexdigest(normalized)
    else
      self.pattern_hash_exact = nil
    end
  end

  # ==========================================
  # NORMALIZATION (Two-level)
  # ==========================================
  
  def self.normalize_light(description)
    return "" if description.blank?
    desc = description.dup
    desc = desc.gsub(/\b\d{14,}\b/, "")
    desc = desc.gsub(/\d{2}[-\/]\d{2}[-\/]\d{4}/, "")
    desc = desc.gsub(/\s+/, " ")
    desc.strip.downcase
  end
  
  def self.normalize_aggressive(description)
    return "" if description.blank?
    desc = description.dup
    desc = desc.gsub(/\b[A-Z0-9]{12,}\b/, "")
    desc = desc.gsub(/\b\d{10,}\b/, "")
    desc = desc.gsub(/\d{2}[-\/]\d{2}[-\/]\d{2,4}/, "")
    desc = desc.gsub(/ref\s*:?\s*\S+/i, "")
    desc = desc.gsub(/upi\s*ref\s*no\s*\S+/i, "")
    desc = desc.gsub(/txn\s*id\s*:?\s*\S+/i, "")
    desc = desc.gsub(/[^\w\s]/, " ")
    desc = desc.gsub(/\s+/, " ")
    desc.strip.downcase
  end

  # ==========================================
  # MAIN MATCHING LOGIC (Optimized)
  # ==========================================
  
  def self.find_matching_rule(description, family:, scope: "narration", account: nil)
    return nil if description.blank?
    
    normalized = normalize_light(description)
    
    # FAST PATH: Hash lookup for EXACT rules only
    description_hash = Digest::SHA256.hexdigest(normalized)
    exact_match = active
      .exact_match_type
      .where(family: family, pattern_hash_exact: description_hash)
      .for_scope(scope)
      .first
    
    if exact_match
      # Double-check with actual matching (hash collision safety)
      return exact_match if exact_match.matches?(normalized, description)
    end
    
    # STANDARD PATH: Query with proper indexes
    # Index: (family_id, status, scope) and (family_id, status, priority DESC)
    query = active
      .where(family: family)
      .for_scope(scope)
      .by_priority
    
    if account
      query = query.where("account_id IS NULL OR account_id = ?", account.id)
    else
      query = query.where(account_id: nil)
    end
    
    # Use find_each for memory efficiency at scale
    query.find_each(batch_size: 100) do |rule|
      return rule if rule.matches?(normalized, description)
    end
    
    nil
  end
  
  def self.categorize_by_rules(description, family:, scope: "narration", account: nil)
    rule = find_matching_rule(description, family: family, scope: scope, account: account)
    return nil unless rule
    
    rule.record_match!
    rule.category
  end
  
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
      regex = self.class.cached_regex(pattern, Regexp::IGNORECASE)
      return false unless regex
      normalized_description.match?(regex) || raw_lower.match?(regex)
    else # contains
      if generic_pattern?
        regex = self.class.cached_word_boundary_regex(pattern_lower)
        return false unless regex
        normalized_description.match?(regex) || raw_lower.match?(regex)
      else
        normalized_description.include?(pattern_lower) || raw_lower.include?(pattern_lower)
      end
    end
  end
  
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

  # ==========================================
  # CAPACITY MANAGEMENT & AUTO-PRUNE
  # ==========================================
  
  def self.enforce_limits!(family)
    # Prune active rules if over limit
    global_count = where(family: family, scope: "global", status: "active").count
    if global_count > MAX_GLOBAL_RULES
      prune_lowest_utility!(family, scope: "global", target: MAX_GLOBAL_RULES)
    end
    
    # Check total
    total_count = where(family: family).where.not(status: "quarantined").count
    if total_count > MAX_TOTAL_RULES_PER_FAMILY
      prune_lowest_utility!(family, target: MAX_TOTAL_RULES_PER_FAMILY)
    end
    
    # Clean up quarantined rules
    cleanup_quarantined!(family)
  end
  
  def self.prune_lowest_utility!(family, scope: nil, account: nil, target:)
    query = where(family: family, status: "active")
    query = query.where(scope: scope) if scope
    query = query.where(account: account) if account
    
    current_count = query.count
    return if current_count <= target
    
    to_prune = current_count - target
    
    lowest = query
      .where(user_confirmed: false)
      .where.not(source: "manual")
      .by_utility
      .last(to_prune)
    
    lowest.each { |rule| rule.quarantine!(reason: "auto_pruned_capacity") }
    
    Rails.logger.info("CategoryRule auto-pruned #{lowest.size} rules for family #{family.id}")
  end
  
  # Clean up old/excess quarantined rules
  def self.cleanup_quarantined!(family)
    # Delete quarantined rules older than retention period (except manual)
    old_quarantined = where(family: family, status: "quarantined")
      .where("quarantined_at < ?", QUARANTINE_RETENTION_DAYS.days.ago)
      .where.not(source: "manual")
    
    deleted_old = old_quarantined.delete_all
    
    # Keep only last N quarantined per family
    quarantine_count = where(family: family, status: "quarantined").count
    if quarantine_count > MAX_QUARANTINED_PER_FAMILY
      excess = quarantine_count - MAX_QUARANTINED_PER_FAMILY
      oldest_ids = where(family: family, status: "quarantined")
        .where.not(source: "manual")
        .order(quarantined_at: :asc)
        .limit(excess)
        .pluck(:id)
      
      deleted_excess = where(id: oldest_ids).delete_all
      Rails.logger.info("CategoryRule cleaned #{deleted_old + deleted_excess} quarantined rules for family #{family.id}")
    end
  end
  
  def utility_score
    age_days = (Time.current - created_at) / 1.day
    age_decay = age_days / 30.0
    times_matched - ((times_overridden || 0) * 3) - age_decay
  end

  # ==========================================
  # MATCH TRACKING & PROMOTION
  # ==========================================
  
  def record_match!
    increment!(:times_matched)
    
    new_confidence = calculate_new_confidence_after_match
    update_column(:confidence, new_confidence)
    
    if status == "candidate" && times_matched >= PROMOTION_THRESHOLD
      promote_to_active!
    end
    
    if probationary? && times_matched >= PROBATION_USES && (times_overridden || 0) == 0
      exit_probation!
    end
    
    recalculate_priority!
  end
  
  def calculate_new_confidence_after_match
    matches = times_matched
    increment = if matches <= 3
      0.05
    elsif matches <= 8
      0.02
    else
      0.01
    end
    
    if last_overridden_at && last_overridden_at > 24.hours.ago
      increment = 0
    end
    
    [confidence + increment, 0.99].min
  end
  
  def promote_to_active!
    update!(status: "active", probationary: true)
    Rails.logger.info("CategoryRule promoted to active (probationary): pattern='#{pattern}'")
  end
  
  def exit_probation!
    update!(probationary: false)
    Rails.logger.info("CategoryRule exited probation: pattern='#{pattern}'")
  end
  
  # ==========================================
  # QUARANTINE (SYNCHRONOUS - no background job!)
  # ==========================================
  
  def quarantine!(reason:)
    # IMPORTANT: This is synchronous to ensure immediate effect
    update!(
      status: "quarantined",
      quarantine_reason: reason,
      quarantined_at: Time.current
    )
    Rails.logger.warn("CategoryRule quarantined: pattern='#{pattern}' reason='#{reason}'")
  end
  
  # SYNCHRONOUS override - must be instant for user trust
  def record_override!
    # Use transaction for consistency
    self.class.transaction do
      increment!(:times_overridden)
      update_column(:last_overridden_at, Time.current)
      
      decrement = source == "ai" ? 0.20 : 0.15
      new_confidence = [confidence - decrement, 0].max
      update_column(:confidence, new_confidence)
      
      # Immediate quarantine during probation (no delay!)
      if probationary? && (times_overridden || 0) > PROBATION_OVERRIDE_TOLERANCE
        quarantine!(reason: "failed_probation")
        return
      end
      
      # Quarantine if confidence too low
      if new_confidence < MIN_CONFIDENCE
        quarantine!(reason: "low_confidence")
        return
      end
      
      recalculate_priority!
    end
  end
  
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
    base_source_weight = SOURCE_BASE_WEIGHTS[source] || 30
    
    override_penalty = (times_overridden || 0) * OVERRIDE_PENALTY_PRIORITY
    effective_source_weight = [base_source_weight * 1000 - override_penalty, 0].max
    
    match_strength = MATCH_TYPES[match_type] || 50
    pattern_specificity = [pattern.to_s.length, 50].min
    confidence_bonus = (confidence * 10).round
    user_confirmed_bonus = user_confirmed? ? 200 : 0
    probation_penalty = probationary? ? 100 : 0
    
    scope_bonus = case self.scope
    when "account_specific" then 300
    when "merchant" then 200
    when "narration" then 100
    else 0
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

  def self.create_from_ai_categorization(description:, category:, family:, 
                                          confidence: nil, scope: "narration", account: nil)
    pattern = extract_pattern(description)
    return nil if pattern.blank? || pattern.length < 3
    
    existing = find_by(family: family, pattern: pattern.downcase, scope: scope)
    if existing
      existing.record_match!
      return existing
    end
    
    conflicting = where(family: family, scope: scope)
                    .where("LOWER(pattern) = ?", pattern.downcase)
                    .where(source: ["manual", "system"])
                    .exists?
    return nil if conflicting
    
    rule = create(
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
    
    enforce_limits!(family) if rule.persisted?
    rule
  end

  def self.learn_from_user(transaction:, category:, scope: "narration")
    description = transaction.entry.name
    return nil if description.blank?
    
    pattern = extract_pattern(description)
    return nil if pattern.blank?
    
    existing = find_by(family: transaction.family, pattern: pattern.downcase, scope: scope)
    if existing
      if existing.category_id == category.id
        existing.confirm!
      else
        existing.record_override!  # SYNCHRONOUS!
        return create(
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
  # EXPLANATION
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
      utility: utility_score.round(2),
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
    
    confidence_desc = confidence >= 0.9 ? "high confidence" :
                      confidence >= 0.7 ? "good confidence" :
                      confidence >= 0.5 ? "moderate confidence" : "low confidence"
    
    trust_desc = probationary? ? ", probationary" : ""
    
    "Transaction #{match_desc} \"#{pattern}\" → #{category.name} (#{source_label}, #{confidence_desc}#{trust_desc}, #{times_matched} matches)"
  end

  # ==========================================
  # HELPERS
  # ==========================================
  
  def probationary?
    probationary == true
  end
  
  def detect_regex_type
    return unless match_type&.start_with?("regex")
    self.match_type = pattern.match?(/\\b|^\^|\$$/) ? "regex_anchored" : "regex"
  end
  
  def self.determine_match_type(pattern)
    return "contains" if pattern.blank?
    return "exact" if pattern.length <= 4
    return "starts_with" if pattern.match?(/^[a-z]+$/i) && pattern.length >= 5
    "contains"
  end

  def self.extract_pattern(description)
    return nil if description.blank?
    normalized = normalize_aggressive(description)
    return nil if normalized.blank?
    
    tokens = normalized.split(/\s+/).reject { |t| t.length < 3 }
    noise_words = %w[
      upi imps neft rtgs the and for from to via by at on in of
      debit credit transfer payment transaction ref no number id
      mobile wallet bank account pvt ltd limited india private pos ach wire check cheque
    ]
    meaningful = tokens.reject { |t| noise_words.include?(t) }
    pattern = meaningful.first(3).join(" ")
    pattern = normalized.split(/\s+/).first(3).join(" ") if pattern.length < 4 && normalized.length >= 4
    pattern.presence
  end

  def self.extract_merchant_name(description)
    return nil if description.blank?
    normalize_light(description).split(/\s+/).reject { |t| t.length < 3 }.first&.titleize
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
