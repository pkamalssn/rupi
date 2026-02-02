import { Controller } from "@hotwired/stimulus"

// Guided Action Onboarding Controller v1
// Interactive onboarding that requires user actions, not just viewing
export default class extends Controller {
  static values = {
    currentStep: { type: Number, default: 0 },
    dismissed: { type: Boolean, default: false }
  }

  static targets = ["overlay", "modal", "progressBar", "progressText", "stepTitle", "stepContent", "actionArea"]

  // Onboarding steps - each requires a specific action
  steps = [
    {
      id: "welcome",
      title: "👋 Welcome to RUPI!",
      content: "Your intelligent personal finance assistant. Let's get you set up in just a few minutes.",
      action: "continue", // Just a continue button
      buttonText: "Let's Start →",
      skipAllowed: true
    },
    {
      id: "load_sample_data",
      title: "📊 Step 1: Load Sample Data",
      content: "Before uploading your own data, let's explore RUPI with sample data. This helps you understand all the features safely.",
      action: "load_sample_data",
      buttonText: "Load Sample Data",
      skipAllowed: false,
      checkComplete: () => this.hasSampleData()
    },
    {
      id: "explore_accounts",
      title: "🏦 Step 2: Explore Accounts",
      content: "Great! Now you have sample accounts. Click on any account in the left sidebar to see its transactions.",
      action: "navigate",
      targetPath: "/accounts",
      buttonText: "I've explored the accounts",
      skipAllowed: false
    },
    {
      id: "try_ai",
      title: "🤖 Step 3: Chat with RUPI AI",
      content: "Try asking RUPI a question! For example: 'What did I spend on food last month?' or 'Show my biggest expenses'",
      action: "try_ai",
      suggestedPrompt: "What are my top 5 spending categories?",
      buttonText: "I've tried the AI",
      skipAllowed: false,
      checkComplete: () => this.hasUsedAI()
    },
    {
      id: "explore_reports",
      title: "📈 Step 4: View Reports",
      content: "RUPI automatically generates spending reports, category breakdowns, and trends. Check out the Reports section!",
      action: "navigate",
      targetPath: "/reports",
      buttonText: "I've seen the reports",
      skipAllowed: false
    },
    {
      id: "upload_own",
      title: "📄 Step 5: Upload Your Statement",
      content: "Now that you understand RUPI, let's add your real data! Upload a bank statement from HDFC, ICICI, SBI, or 20+ other banks.",
      action: "navigate",
      targetPath: "/bank_statements/new",
      buttonText: "I'll upload later",
      skipAllowed: true
    },
    {
      id: "clear_sample",
      title: "🧹 Step 6: Clear Sample Data",
      content: "Ready to use RUPI with just your own data? Clear the sample data to start fresh. (You can keep it if you prefer)",
      action: "clear_sample_data",
      buttonText: "Keep Sample Data",
      altButtonText: "Clear Sample Data",
      skipAllowed: true
    },
    {
      id: "complete",
      title: "🎉 You're All Set!",
      content: "You've completed the RUPI setup! Your financial journey starts now. Remember, you can always ask RUPI AI for help.",
      action: "finish",
      buttonText: "Start Using RUPI",
      skipAllowed: false
    }
  ]

  connect() {
    // Check if onboarding should show
    this.checkAndShowOnboarding()
    
    // Listen for events from other parts of the app
    window.addEventListener('rupi:sample-data-loaded', () => this.onSampleDataLoaded())
    window.addEventListener('rupi:sample-data-cleared', () => this.onSampleDataCleared())
    window.addEventListener('rupi:ai-message-sent', () => this.onAIMessageSent())
  }

  disconnect() {
    window.removeEventListener('rupi:sample-data-loaded', () => this.onSampleDataLoaded())
    window.removeEventListener('rupi:sample-data-cleared', () => this.onSampleDataCleared())
    window.removeEventListener('rupi:ai-message-sent', () => this.onAIMessageSent())
  }

  checkAndShowOnboarding() {
    // Don't show if already dismissed
    if (this.dismissedValue) return
    
    // Check if user has completed onboarding
    const savedStep = localStorage.getItem('rupi_onboarding_step')
    if (savedStep === 'complete') return
    
    // Check if user is new (no accounts)
    const hasAccounts = document.querySelector('[data-has-accounts]')?.dataset.hasAccounts === 'true'
    const hasCompletedTour = document.querySelector('[data-tour-completed]')?.dataset.tourCompleted === 'true'
    
    // Show onboarding for new users
    if (!hasAccounts && !hasCompletedTour) {
      this.currentStepValue = savedStep ? parseInt(savedStep) : 0
      setTimeout(() => this.show(), 500)
    }
  }

  show() {
    this.injectStyles()
    this.createOverlay()
    this.renderStep()
  }

  hide() {
    if (this.overlayElement) {
      this.overlayElement.remove()
      this.overlayElement = null
    }
  }

  injectStyles() {
    if (document.getElementById('rupi-onboarding-styles')) return
    
    const style = document.createElement('style')
    style.id = 'rupi-onboarding-styles'
    style.textContent = `
      .rupi-onboarding-overlay {
        position: fixed;
        inset: 0;
        z-index: 99999;
        background: rgba(11, 11, 11, 0.95);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 20px;
        animation: rupi-onboarding-fade 0.3s ease-out;
      }
      
      @keyframes rupi-onboarding-fade {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      
      .rupi-onboarding-modal {
        background: #171717;
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 24px;
        width: 100%;
        max-width: 480px;
        overflow: hidden;
        animation: rupi-onboarding-slide 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      
      @keyframes rupi-onboarding-slide {
        from { opacity: 0; transform: translateY(30px) scale(0.95); }
        to { opacity: 1; transform: translateY(0) scale(1); }
      }
      
      .rupi-onboarding-header {
        padding: 24px 24px 16px;
        text-align: center;
      }
      
      .rupi-onboarding-logo {
        font-size: 32px;
        font-weight: 700;
        background: linear-gradient(135deg, #12B76A, #FACC15);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
        margin-bottom: 8px;
      }
      
      .rupi-onboarding-progress {
        padding: 0 24px;
      }
      
      .rupi-onboarding-progress-bar {
        height: 6px;
        background: #333;
        border-radius: 3px;
        overflow: hidden;
        margin-bottom: 8px;
      }
      
      .rupi-onboarding-progress-fill {
        height: 100%;
        background: linear-gradient(90deg, #12B76A, #10A861);
        border-radius: 3px;
        transition: width 0.5s ease-out;
      }
      
      .rupi-onboarding-progress-text {
        font-size: 12px;
        color: rgba(255,255,255,0.5);
        text-align: center;
      }
      
      .rupi-onboarding-content {
        padding: 24px;
        text-align: center;
      }
      
      .rupi-onboarding-title {
        font-size: 24px;
        font-weight: 600;
        color: white;
        margin-bottom: 12px;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-onboarding-description {
        font-size: 15px;
        color: rgba(255,255,255,0.7);
        line-height: 1.6;
        margin-bottom: 24px;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-onboarding-action-area {
        display: flex;
        flex-direction: column;
        gap: 12px;
      }
      
      .rupi-onboarding-btn-primary {
        width: 100%;
        padding: 14px 24px;
        background: #12B76A;
        color: white;
        border: none;
        border-radius: 12px;
        font-size: 16px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-onboarding-btn-primary:hover {
        background: #10A861;
        transform: translateY(-2px);
        box-shadow: 0 8px 24px rgba(18, 183, 106, 0.4);
      }
      
      .rupi-onboarding-btn-secondary {
        width: 100%;
        padding: 12px 24px;
        background: transparent;
        color: rgba(255,255,255,0.6);
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 12px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.2s;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-onboarding-btn-secondary:hover {
        background: rgba(255,255,255,0.05);
        color: white;
        border-color: rgba(255,255,255,0.2);
      }
      
      .rupi-onboarding-btn-destructive {
        width: 100%;
        padding: 12px 24px;
        background: rgba(239, 68, 68, 0.1);
        color: #ef4444;
        border: 1px solid rgba(239, 68, 68, 0.2);
        border-radius: 12px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.2s;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-onboarding-btn-destructive:hover {
        background: rgba(239, 68, 68, 0.2);
        border-color: rgba(239, 68, 68, 0.4);
      }
      
      .rupi-onboarding-ai-prompt {
        background: #0B0B0B;
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 12px;
        padding: 16px;
        margin-bottom: 16px;
      }
      
      .rupi-onboarding-ai-prompt-label {
        font-size: 12px;
        color: rgba(255,255,255,0.5);
        margin-bottom: 8px;
      }
      
      .rupi-onboarding-ai-prompt-text {
        font-size: 14px;
        color: #12B76A;
        font-style: italic;
      }
      
      .rupi-onboarding-footer {
        padding: 16px 24px 24px;
        text-align: center;
        border-top: 1px solid rgba(255,255,255,0.05);
      }
      
      .rupi-onboarding-skip {
        font-size: 13px;
        color: rgba(255,255,255,0.4);
        background: none;
        border: none;
        cursor: pointer;
        padding: 8px 16px;
        transition: color 0.2s;
      }
      
      .rupi-onboarding-skip:hover {
        color: rgba(255,255,255,0.7);
      }
      
      .rupi-onboarding-celebration {
        font-size: 64px;
        margin-bottom: 16px;
      }
    `
    document.head.appendChild(style)
  }

  createOverlay() {
    this.overlayElement = document.createElement('div')
    this.overlayElement.className = 'rupi-onboarding-overlay'
    document.body.appendChild(this.overlayElement)
  }

  renderStep() {
    const step = this.steps[this.currentStepValue]
    if (!step) return this.finish()
    
    const progress = ((this.currentStepValue) / (this.steps.length - 1)) * 100
    
    let actionArea = ''
    
    // Build action area based on step type
    switch (step.action) {
      case 'continue':
        actionArea = `<button class="rupi-onboarding-btn-primary" data-action="click->guided-onboarding#nextStep">${step.buttonText}</button>`
        break
        
      case 'load_sample_data':
        actionArea = `
          <button class="rupi-onboarding-btn-primary" data-action="click->guided-onboarding#loadSampleData">
            ${step.buttonText}
          </button>
        `
        break
        
      case 'try_ai':
        actionArea = `
          <div class="rupi-onboarding-ai-prompt">
            <div class="rupi-onboarding-ai-prompt-label">Try asking:</div>
            <div class="rupi-onboarding-ai-prompt-text">"${step.suggestedPrompt}"</div>
          </div>
          <button class="rupi-onboarding-btn-primary" data-action="click->guided-onboarding#openAIChat">
            Open AI Chat
          </button>
          <button class="rupi-onboarding-btn-secondary" data-action="click->guided-onboarding#nextStep">
            ${step.buttonText}
          </button>
        `
        break
        
      case 'navigate':
        actionArea = `
          <button class="rupi-onboarding-btn-primary" data-action="click->guided-onboarding#navigateTo" data-path="${step.targetPath}">
            Go to ${step.targetPath === '/accounts' ? 'Accounts' : step.targetPath === '/reports' ? 'Reports' : 'Upload Page'}
          </button>
          <button class="rupi-onboarding-btn-secondary" data-action="click->guided-onboarding#nextStep">
            ${step.buttonText}
          </button>
        `
        break
        
      case 'clear_sample_data':
        actionArea = `
          <button class="rupi-onboarding-btn-destructive" data-action="click->guided-onboarding#clearSampleData">
            ${step.altButtonText}
          </button>
          <button class="rupi-onboarding-btn-secondary" data-action="click->guided-onboarding#nextStep">
            ${step.buttonText}
          </button>
        `
        break
        
      case 'finish':
        actionArea = `
          <div class="rupi-onboarding-celebration">🎉</div>
          <button class="rupi-onboarding-btn-primary" data-action="click->guided-onboarding#finish">
            ${step.buttonText}
          </button>
        `
        break
    }
    
    this.overlayElement.innerHTML = `
      <div class="rupi-onboarding-modal">
        <div class="rupi-onboarding-header">
          <div class="rupi-onboarding-logo">RUPI</div>
        </div>
        
        <div class="rupi-onboarding-progress">
          <div class="rupi-onboarding-progress-bar">
            <div class="rupi-onboarding-progress-fill" style="width: ${progress}%"></div>
          </div>
          <div class="rupi-onboarding-progress-text">Step ${this.currentStepValue + 1} of ${this.steps.length}</div>
        </div>
        
        <div class="rupi-onboarding-content">
          <h2 class="rupi-onboarding-title">${step.title}</h2>
          <p class="rupi-onboarding-description">${step.content}</p>
          <div class="rupi-onboarding-action-area">
            ${actionArea}
          </div>
        </div>
        
        ${step.skipAllowed ? `
          <div class="rupi-onboarding-footer">
            <button class="rupi-onboarding-skip" data-action="click->guided-onboarding#skipOnboarding">
              Skip setup for now
            </button>
          </div>
        ` : ''}
      </div>
    `
  }

  nextStep() {
    this.currentStepValue++
    this.saveProgress()
    this.renderStep()
  }

  previousStep() {
    if (this.currentStepValue > 0) {
      this.currentStepValue--
      this.saveProgress()
      this.renderStep()
    }
  }

  loadSampleData() {
    // Click the actual load demo data form
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = '/load_demo_data'
    
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = 'authenticity_token'
      input.value = csrfToken
      form.appendChild(input)
    }
    
    document.body.appendChild(form)
    form.submit()
    
    // Save that we're on the next step
    this.currentStepValue++
    this.saveProgress()
  }

  clearSampleData() {
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = '/clear_demo_data'
    
    const methodInput = document.createElement('input')
    methodInput.type = 'hidden'
    methodInput.name = '_method'
    methodInput.value = 'DELETE'
    form.appendChild(methodInput)
    
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = 'authenticity_token'
      input.value = csrfToken
      form.appendChild(input)
    }
    
    document.body.appendChild(form)
    form.submit()
    
    this.nextStep()
  }

  openAIChat() {
    // Hide overlay temporarily
    this.hide()
    
    // Navigate to chats or open AI sidebar
    window.location.href = '/chats'
  }

  navigateTo(event) {
    const path = event.currentTarget.dataset.path
    
    // Hide overlay and navigate
    this.hide()
    window.location.href = path
  }

  skipOnboarding() {
    if (confirm('Are you sure you want to skip? You can always restart from Help & FAQ.')) {
      this.dismiss()
    }
  }

  dismiss() {
    localStorage.setItem('rupi_onboarding_step', 'complete')
    this.saveDismissed()
    this.hide()
  }

  finish() {
    localStorage.setItem('rupi_onboarding_step', 'complete')
    this.saveCompleted()
    this.hide()
  }

  saveProgress() {
    localStorage.setItem('rupi_onboarding_step', this.currentStepValue.toString())
  }

  async saveDismissed() {
    try {
      await fetch('/onboarding/dismiss', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
    } catch (e) {
      console.log('Could not save dismissal')
    }
  }

  async saveCompleted() {
    try {
      await fetch('/dashboard/preferences', {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          preferences: { guided_onboarding_completed: true, tour_completed: true }
        })
      })
    } catch (e) {
      console.log('Could not save completion')
    }
  }

  // Event handlers
  onSampleDataLoaded() {
    // If we were waiting on sample data, move to next step
    if (this.steps[this.currentStepValue]?.id === 'load_sample_data') {
      this.nextStep()
    }
  }

  onSampleDataCleared() {
    // Nothing special needed
  }

  onAIMessageSent() {
    // Track that user has tried AI
    localStorage.setItem('rupi_onboarding_ai_used', 'true')
  }

  // Helper checks
  hasSampleData() {
    return document.querySelector('[data-has-accounts]')?.dataset.hasAccounts === 'true'
  }

  hasUsedAI() {
    return localStorage.getItem('rupi_onboarding_ai_used') === 'true'
  }
}
