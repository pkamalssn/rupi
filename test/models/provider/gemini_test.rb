require "test_helper"

class Provider::GeminiTest < ActiveSupport::TestCase
  include ProviderTestHelper

  setup do
    @api_key = ENV.fetch("GOOGLE_AI_API_KEY", "test-gemini-key")
    @subject = Provider::Gemini.new(@api_key)
    @subject_model = "gemini-2.5-flash"
  end

  # ============================================
  # Model Support Tests
  # ============================================

  test "supports gemini model prefixes" do
    assert @subject.supports_model?("gemini-2.5-flash")
    assert @subject.supports_model?("gemini-2.0-flash")
    assert @subject.supports_model?("gemini-1.5-pro")
    assert @subject.supports_model?("gemini-3-something")
    assert @subject.supports_model?("gemini-exp-1234")
  end

  test "does not support non-gemini models" do
    refute @subject.supports_model?("gpt-4")
    refute @subject.supports_model?("claude-3")
    refute @subject.supports_model?("llama-2")
  end

  test "provider_name returns Google Gemini" do
    assert_equal "Google Gemini", @subject.provider_name
  end

  test "supported_models_description returns model prefixes" do
    expected = "models starting with: gemini-2.5, gemini-2.0, gemini-1.5, gemini-3, gemini-exp"
    assert_equal expected, @subject.supported_models_description
  end

  # ============================================
  # Initialization Tests
  # ============================================

  test "raises error when API key is blank" do
    assert_raises Provider::Gemini::Error do
      Provider::Gemini.new("")
    end

    assert_raises Provider::Gemini::Error do
      Provider::Gemini.new(nil)
    end
  end

  test "uses default model when none provided" do
    provider = Provider::Gemini.new("test-key")
    assert_equal "gemini-2.5-flash", provider.instance_variable_get(:@default_model)
  end

  test "uses custom model when provided" do
    provider = Provider::Gemini.new("test-key", model: "gemini-1.5-pro")
    assert_equal "gemini-1.5-pro", provider.instance_variable_get(:@default_model)
  end

  # ============================================
  # Schema Cleaning Tests
  # ============================================

  test "clean_schema_for_gemini removes unsupported keys" do
    schema = {
      type: "object",
      additionalProperties: false,
      uniqueItems: true,
      "$schema": "http://json-schema.org/draft-07/schema#",
      title: "Test",
      examples: [{}],
      default: {},
      properties: {
        name: { type: "string" }
      }
    }

    cleaned = @subject.send(:clean_schema_for_gemini, schema)

    assert_equal "object", cleaned[:type]
    assert cleaned[:properties].present?
    refute cleaned.key?(:additionalProperties)
    refute cleaned.key?(:uniqueItems)
    refute cleaned.key?(:"$schema")
    refute cleaned.key?(:title)
    refute cleaned.key?(:examples)
    refute cleaned.key?(:default)
  end

  test "clean_schema_for_gemini handles nested properties" do
    schema = {
      type: "object",
      properties: {
        user: {
          type: "object",
          additionalProperties: false,
          properties: {
            name: { type: "string", default: "John" }
          }
        }
      }
    }

    cleaned = @subject.send(:clean_schema_for_gemini, schema)

    refute cleaned[:properties][:user].key?(:additionalProperties)
    refute cleaned[:properties][:user][:properties][:name].key?(:default)
  end

  test "clean_schema_for_gemini adds type string for enum without type" do
    schema = {
      enum: ["one", "two", "three"]
    }

    cleaned = @subject.send(:clean_schema_for_gemini, schema)

    assert_equal "string", cleaned[:type]
    assert_equal ["one", "two", "three"], cleaned[:enum]
  end

  # ============================================
  # Build Tools Tests
  # ============================================

  test "build_tools returns empty array for blank functions" do
    assert_equal [], @subject.send(:build_tools, [])
    assert_equal [], @subject.send(:build_tools, nil)
  end

  test "build_tools formats function declarations correctly" do
    functions = [
      {
        name: "get_accounts",
        description: "Gets user accounts",
        params_schema: { type: "object", properties: {} }
      }
    ]

    tools = @subject.send(:build_tools, functions)

    assert_equal 1, tools.size
    assert tools[0][:functionDeclarations].present?
    
    fn_decl = tools[0][:functionDeclarations].first
    assert_equal "get_accounts", fn_decl[:name]
    assert_equal "Gets user accounts", fn_decl[:description]
  end

  # ============================================
  # SSE Parsing Tests
  # ============================================

  test "parse_sse_chunks handles single data line" do
    raw_body = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hello\"}]}}]}\n\n"
    
    chunks = []
    @subject.send(:parse_sse_chunks, raw_body) { |chunk| chunks << chunk }

    assert_equal 1, chunks.size
    assert_equal "Hello", chunks[0].dig("candidates", 0, "content", "parts", 0, "text")
  end

  test "parse_sse_chunks handles multiple data lines" do
    raw_body = <<~SSE
      data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}
      data: {"candidates":[{"content":{"parts":[{"text":" World"}]}}]}
    SSE

    chunks = []
    @subject.send(:parse_sse_chunks, raw_body) { |chunk| chunks << chunk }

    assert_equal 2, chunks.size
  end

  test "parse_sse_chunks ignores [DONE] marker" do
    raw_body = "data: {\"test\": true}\ndata: [DONE]\n"

    chunks = []
    @subject.send(:parse_sse_chunks, raw_body) { |chunk| chunks << chunk }

    assert_equal 1, chunks.size
  end

  test "parse_sse_chunks handles blank input" do
    chunks = []
    @subject.send(:parse_sse_chunks, "") { |chunk| chunks << chunk }
    assert_equal 0, chunks.size

    @subject.send(:parse_sse_chunks, nil) { |chunk| chunks << chunk }
    assert_equal 0, chunks.size
  end

  test "parse_sse_chunks handles malformed JSON gracefully" do
    raw_body = "data: {invalid json}\ndata: {\"valid\": true}\n"

    chunks = []
    @subject.send(:parse_sse_chunks, raw_body) { |chunk| chunks << chunk }

    # Should only get the valid chunk
    assert_equal 1, chunks.size
    assert_equal true, chunks[0]["valid"]
  end

  # ============================================
  # Auto Categorization Tests
  # ============================================

  test "auto_categorize raises error for too many transactions" do
    transactions = (1..26).map { |i| { id: i.to_s, name: "Test #{i}" } }

    assert_raises Provider::Gemini::Error do
      @subject.auto_categorize(transactions: transactions, user_categories: [{ name: "Test" }])
    end
  end

  test "auto_categorize raises error when no categories available" do
    assert_raises Provider::Gemini::Error do
      @subject.auto_categorize(transactions: [{ id: "1", name: "Test" }], user_categories: [])
    end
  end

  # ============================================
  # Auto Merchant Detection Tests
  # ============================================

  test "auto_detect_merchants raises error for too many transactions" do
    transactions = (1..26).map { |i| { id: i.to_s, name: "Test #{i}" } }

    assert_raises Provider::Gemini::Error do
      @subject.auto_detect_merchants(transactions: transactions)
    end
  end
end
