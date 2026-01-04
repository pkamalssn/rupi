# RUPI Sidecar Implementation Session Document

**Document Version:** 2.0  
**Last Updated:** January 4, 2026  
**Total Sessions:** 2  
**Status:** ✅ COMPLETE - AI Chat Sidecar Working with Gemini 3 Compatibility

---

## TABLE OF CONTENTS

1. [Session 1: Initial Sidecar Implementation (Jan 1, 2026)](#session-1-initial-sidecar-implementation)
2. [Session 2: Gemini 3 Debugging & Duplication Fixes (Jan 4, 2026)](#session-2-gemini-3-debugging--duplication-fixes)
3. [Architecture Overview](#architecture-overview)
4. [Known Issues & Workarounds](#known-issues--workarounds)
5. [Lessons Learned](#lessons-learned)

---

# SESSION 1: Initial Sidecar Implementation

**Date:** January 1, 2026  
**Duration:** ~2 hours  
**Objective:** Complete the sidecar architecture for RUPI's AI Chat feature

## Initial Error

```json
{
  "error": "ai_error",
  "message": "Invalid JSON payload received. Unknown name \"uniqueItems\" at 'tools[0]..."
}
```

## Issues Fixed

### Issue #1: Schema Fields Not Supported by Gemini

- **Fix:** Removed `uniqueItems`, `minItems`, `additionalProperties` from function schemas
- **Files:** `rupi-v3/app/models/assistant/function/get_transactions.rb`, `rupi-v3/app/models/assistant/function.rb`

### Issue #2: Enum Fields Require Type String

- **Fix:** Added `type: "string"` to all enum fields
- **File:** `rupi-v3/app/models/assistant/function/get_transactions.rb`

### Issue #3: ActionController::Parameters Not a Hash

- **Fix:** Convert to hash before type checking: `schema.to_unsafe_h`
- **File:** `rupi-engine/app/controllers/api/v1/chat_controller.rb`

### Issue #4: No Text Streaming (Empty Content)

- **Fix:** Modified streamer to emit text from response chunks that have usageMetadata
- **File:** `rupi-engine/app/controllers/api/v1/chat_controller.rb`

### Issue #5: Frozen String Error

- **Fix:** Use `String.new("")` for mutable strings with `frozen_string_literal: true`
- **File:** `rupi-v3/app/models/provider/engine.rb`

### Issue #6: Missing :usage Parameter

- **Fix:** Added `usage: nil` to all `ChatStreamChunk.new` calls
- **File:** `rupi-v3/app/models/provider/engine.rb`

---

# SESSION 2: Gemini 3 Debugging & Duplication Fixes

**Date:** January 4, 2026  
**Duration:** ~3 hours  
**Objective:** Fix persistent text duplication, Gemini 3 compatibility issues, and stuck responses

## 🔴 THE PROBLEM

After upgrading to `gemini-3-flash-preview`, multiple critical issues emerged:

1. **Triple text duplication** - AI responses appeared 3x on screen
2. **Responses getting stuck** on "Analyzing your data..."
3. **Empty responses** when data was available
4. **Basic queries failing** ("Show spending insights" → no response)

---

## 🔍 ROOT CAUSE ANALYSIS

### Issue #1: Double `handle_follow_up_response` Calls

**Symptom:** Text appearing 2-3 times  
**Root Cause:** SSE events emitting function_requests TWICE

```
tool_call event → emits function_requests → handle_follow_up_response called
done event → emits SAME function_requests → handle_follow_up_response called AGAIN
```

**How we found it:** Added debug logging to trace event flow:

```ruby
Rails.logger.info("[Responder] handle_follow_up_response called with #{response.function_requests.size} function_requests")
```

**Fix Location:** `rupi-v3/app/models/provider/engine.rb`

**Fix Applied:** When `tool_call` event emits function_requests, return `true` to set `done_handled`, skipping the done event:

```ruby
when "tool_call"
  # ... emit response with function_requests ...
  streamer.call(chunk)
  return true  # This sets done_handled = true, skipping done event
```

---

### Issue #2: Gemini 3 Ignores `tool_config: NONE`

**Symptom:** Follow-up responses getting stuck, empty text returned  
**Root Cause:** Gemini 3 Flash Preview ignores `tool_config: { mode: "NONE" }` and still generates functionCall responses

**Evidence from logs:**

```json
{"candidates":[{"content":{"parts":[{"functionCall":{"name":"analyze_spending","args":{...}}}]}}]}
```

Even with this in the payload:

```json
{ "tool_config": { "function_calling_config": { "mode": "NONE" } } }
```

**Research Findings:**

- This is a KNOWN issue with Gemini 3 models (confirmed via web search)
- Community workaround: Remove `tools` parameter entirely (we already do this)
- Additional workaround needed: Ignore functionCall responses in follow-up mode

**Fix Location:** `rupi-engine/app/controllers/api/v1/chat_controller.rb`

**Fix Applied:**

1. Added `ignore_tool_calls` parameter to `build_streamer()` and `handle_final_response()`
2. When processing tool results (`stream_tool_results`), pass `ignore_tool_calls: true`
3. Skip emitting tool_call SSE events when this flag is true

```ruby
def stream_tool_results
  streamer = build_streamer(ignore_tool_calls: true)
  # ...
  if result && !@streamed_content
    handle_final_response(result, ignore_tool_calls: true)
  end
end

def build_streamer(ignore_tool_calls: false)
  proc do |chunk|
    # ONLY emit tool_call if tools are enabled
    if !ignore_tool_calls && response_data.function_requests&.any?
      send_sse_event("tool_call", {...})
    end
  end
end
```

---

### Issue #3: Missing thoughtSignature in Tool Results

**Symptom:** Gemini 3 returning confused responses  
**Root Cause:** `thought_signature` was captured from Gemini but dropped when normalizing tool results

**Gemini 3 Requirement (from docs):**

> "Function Calling (Strict): The API enforces strict validation on the 'Current Turn'. Missing signatures will result in a 400 error."

**Fix Location:** `rupi-engine/app/controllers/api/v1/chat_controller.rb`

**Fix Applied:**

```ruby
def normalize_tool_results(tool_results)
  tool_results.map do |result|
    normalized = {
      call_id: result["call_id"] || result[:call_id],
      name: result["name"] || result[:name],
      output: result["output"] || result[:output],
      arguments: result["arguments"] || result[:arguments] || {}
    }
    # CRITICAL: Include thought_signature for Gemini 3
    thought_sig = result["thought_signature"] || result[:thought_signature]
    normalized[:thought_signature] = thought_sig if thought_sig.present?
    normalized
  end
end
```

---

### Issue #4: Ambiguous Queries Defaulting to Empty Periods

**Symptom:** "Show spending insights" → stuck on "Analyzing your data..."  
**Root Cause:** Query defaulted to "this_month" (January 2026) which has NO transactions yet (only 4 days in)

**Fix Location:** `rupi-engine/app/controllers/api/v1/chat_controller.rb`

**Fix Applied:** Updated system prompt with smart defaults:

```ruby
def build_system_instructions(context)
  last_month = (Time.current - 1.month).strftime("%B %Y")  # "December 2025"

  <<~INSTRUCTIONS
    SMART DEFAULTS:
    - "Spending insights" without a period = analyze #{last_month} (the last complete month)
    - If today is early in a month, "recent spending" refers to the PREVIOUS COMPLETE MONTH
    - If a query about the current month returns empty/minimal data, use #{last_month} instead
  INSTRUCTIONS
end
```

---

### Issue #5: Empty Fallback Messages

**Symptom:** When Gemini returned empty response, user saw generic unhelpful message  
**Root Cause:** Fallback logic only had one generic message

**Fix Location:** `rupi-v3/app/models/assistant/responder.rb`

**Fix Applied:** Context-aware fallback messages:

```ruby
def generate_fallback_response(function_tool_calls)
  tool_names = function_tool_calls.map(&:function_name)

  if tool_names.include?("get_investments")
    parsed = JSON.parse(result)
    if parsed["holdings_count"] == 0
      return "📊 **No Investment Data Found**\n\nI don't have any investment holdings..."
    end
  end

  if tool_names.include?("get_loans")
    # Loan-specific fallback
  end

  if tool_names.include?("analyze_spending") && parsed["total_spending"] == 0
    # Period-specific fallback with suggestions
  end

  # Generic fallback with examples
end
```

---

### Issue #6: Duplicate Follow-up Processing

**Symptom:** Some queries showed response twice  
**Root Cause:** `handle_follow_up_response` could be called multiple times

**Fix Location:** `rupi-v3/app/models/assistant/responder.rb`

**Fix Applied:** Added tracking flag:

```ruby
def handle_follow_up_response(response)
  return if @follow_up_handled
  @follow_up_handled = true
  # ... rest of method
end
```

---

## 📁 FILES MODIFIED (Session 2)

### rupi-engine

| File                                        | Changes                                                                                                        |
| ------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `app/controllers/api/v1/chat_controller.rb` | Added `ignore_tool_calls` flag, improved system prompt with smart defaults, fixed `thought_signature` handling |
| `app/models/provider/gemini.rb`             | Added debug logging for SSE chunks                                                                             |

### rupi-v3

| File                                | Changes                                                                            |
| ----------------------------------- | ---------------------------------------------------------------------------------- |
| `app/models/provider/engine.rb`     | Fixed tool_call event to return true (skip done), improved event handling          |
| `app/models/assistant/responder.rb` | Added `@follow_up_handled` flag, improved fallback messages with context awareness |

---

## ✅ FINAL TEST RESULTS (Session 2)

```
User: Show spending insights
RUPI: Based on your activity for December 2025... ✅ (Single response, correct month)

User: How is my November spending summary?
RUPI: In November 2025, your total spending was... ✅ (Single response)

User: How is my investment portfolio?
RUPI: 📊 No Investment Data Found... ✅ (Helpful fallback)
```

---

# ARCHITECTURE OVERVIEW

```
┌─────────────────┐     SSE Stream     ┌─────────────────┐
│   rupi-v3       │ ◄────────────────► │  rupi-engine    │
│   (Port 3000)   │    HTTP/JSON       │  (Port 4000)    │
├─────────────────┤                    ├─────────────────┤
│ • UI Rendering  │                    │ • Gemini API    │
│ • Tool Execution│                    │ • AI Prompts    │
│ • DB Access     │                    │ • SSE Streaming │
│ • Provider::    │                    │ • Schema Clean  │
│   Engine client │                    │ • Tool Config   │
└─────────────────┘                    └─────────────────┘
```

---

# KNOWN ISSUES & WORKAROUNDS

## Gemini 3 Flash Preview Issues

| Issue                        | Description                                                 | Workaround                                                       |
| ---------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------- |
| `tool_config: NONE` ignored  | Model still generates functionCall even with mode NONE      | Ignore tool_calls in follow-up mode via `ignore_tool_calls` flag |
| Sequential tool calling      | Model tries to call more tools after receiving results      | Block with explicit instruction in system prompt                 |
| Empty responses              | Model returns `{"text":""}` when confused                   | Fallback message generation in rupi-v3                           |
| thoughtSignature requirement | Required for function calling, causes 400 errors if missing | Always pass through from initial response                        |

## Temperature Setting

From Gemini 3 docs:

> "If your existing code explicitly sets temperature (especially to low values), we recommend removing this parameter and using the Gemini 3 default of 1.0"

**Applied:** Don't set temperature for Gemini 3 models in `gemini.rb`

---

# LESSONS LEARNED

## From Session 1

1. **ActionController::Parameters is NOT a Hash** - Always convert with `to_unsafe_h`
2. **Frozen String Literals** - Use `String.new("")` for mutable strings
3. **Gemini Schema Restrictions** - No `uniqueItems`, `additionalProperties`, etc.
4. **SSE Streaming Complexity** - Text and usageMetadata come in same chunks
5. **Data.define Requires All Parameters** - No defaults allowed

## From Session 2

1. **SSE Events Can Overlap** - Both `tool_call` and `done` events may carry function_requests
2. **Gemini 3 API Quirks** - `tool_config: NONE` is NOT reliable; use additional safeguards
3. **thoughtSignature is Critical** - Must be passed through the entire flow for Gemini 3
4. **Smart Defaults Matter** - Vague queries need intelligent defaults (last complete month)
5. **Fallbacks are UX** - Context-aware fallbacks prevent "stuck" states
6. **Flag-based Deduplication** - Use instance flags to prevent duplicate processing
7. **Trace with Logging** - Add detailed logs at every event boundary when debugging

---

# DEBUGGING CHECKLIST

When AI chat issues occur, check in this order:

1. **Check rupi-engine logs** for Gemini API errors
2. **Check SSE event flow** - Look for duplicate events
3. **Verify thoughtSignature** is being passed through
4. **Check tool_config** - Is NONE being respected?
5. **Check time period** - Is query defaulting to empty period?
6. **Check function_results** - Is data actually present?
7. **Check for duplicate emits** - Are events firing multiple times?

---

# COMMANDS FOR RESTART

```bash
# Terminal 1: rupi-engine
cd /Users/kp/Projects/sure_finance/rupi-engine
bin/rails server -p 4000

# Terminal 2: rupi-v3
cd /Users/kp/Projects/sure_finance/rupi-v3
bin/dev
```

---

# COMMITS MADE

## Session 2 (January 4, 2026)

### rupi-engine

- `fix: When tool_call emits function_requests, skip done event processing`
- `fix: Ignore tool_calls in follow-up mode (stream_tool_results)`
- `fix: Include thought_signature in normalized tool_results`
- `fix: Ignore tool_calls in handle_final_response when processing tool results`
- `fix: Add explicit instruction to prevent Gemini 3 from making more tool calls`
- `fix: Strengthen instruction to always generate text response`
- `fix: Improve system prompt with smart period defaults`

### rupi-v3

- `fix: When tool_call emits function_requests, skip done event processing`
- `fix: Add fallback response when Gemini returns empty text`
- `fix: Prevent duplicate handle_follow_up_response calls`
- `feat: Improve fallback messages with context-aware responses`

---

_Document maintained by: Claude (Antigravity AI Assistant)_  
_Last updated: January 4, 2026_  
_Sidecar Architecture: VERIFIED WORKING with Gemini 3_
