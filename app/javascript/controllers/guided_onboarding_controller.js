import { Controller } from "@hotwired/stimulus"

// Guided Action Onboarding Controller v3
// Fixed: Step numbering, route path, localStorage sync, tour handoff
export default class extends Controller {
  static values = {
    currentStep: { type: Number, default: 0 },
    dismissed: { type: Boolean, default: false },
    hasAccounts: { type: Boolean, default: false }
  }

  // Onboarding steps - each requires a specific action
  // Note: Welcome is step 0, actual numbered steps start from index 1
  steps = [
    {
      id: "welcome",
      title: "👋 Welcome to RUPI!",
      content: "Your intelligent personal finance assistant. Let's get you set up in just a few minutes.",
      action: "continue",
      buttonText: "Let's Start →",
      skipAllowed: true,
      showProgress: false
    },
    {
      id: "load_sample_data",
      title: "📊 Load Sample Data",
      content: "Before uploading your own data, let's explore RUPI with sample data. This helps you understand all the features safely.",
      action: "load_sample_data",
      buttonText: "Load Sample Data",
      skipAllowed: false,
      showProgress: true,
      stepNumber: 1
    },
    {
      id: "explore_accounts",
      title: "🏦 Explore Accounts",
      content: "Great! Now you have sample accounts. Click on any account in the left sidebar to see its transactions.",
      action: "navigate",
      targetPath: "/transactions",
      buttonText: "Go to Transactions",
      altButtonText: "I've explored the accounts",
      skipAllowed: false,
      showProgress: true,
      stepNumber: 2
    },
    {
      id: "try_ai",
      title: "🤖 Chat with RUPI AI",
      content: "Try asking RUPI a question! For example: 'What did I spend on food last month?' or 'Show my biggest expenses'",
      action: "try_ai",
      suggestedPrompt: "What are my top 5 spending categories?",
      buttonText: "I've tried the AI",
      skipAllowed: false,
      showProgress: true,
      stepNumber: 3
    },
    {
      id: "explore_reports",
      title: "📈 View Reports",
      content: "RUPI automatically generates spending reports, category breakdowns, and trends. Check out the Reports section!",
      action: "navigate",
      targetPath: "/reports",
      buttonText: "Go to Reports",
      altButtonText: "I've seen the reports",
      skipAllowed: false,
      showProgress: true,
      stepNumber: 4
    },
    {
      id: "upload_own",
      title: "📄 Upload Your Statement",
      content: "Now that you understand RUPI, let's add your real data! Upload a bank statement from HDFC, ICICI, SBI, or 20+ other banks.",
      action: "navigate",
      targetPath: "/bank_statement/new",  // Fixed: singular, not plural
      buttonText: "Go to Upload",
      altButtonText: "I'll upload later",
      skipAllowed: true,
      showProgress: true,
      stepNumber: 5
    },
    {
      id: "complete",
      title: "🎉 You're All Set!",
      content: "You've completed the RUPI setup! Now let's take a quick visual tour to show you around.",
      action: "finish",
      buttonText: "Start Visual Tour →",
      skipAllowed: false,
      showProgress: false
    }
  ]

  overlayElement = null

  connect() {
    this.checkAndShowOnboarding()
  }

  disconnect() {
    this.hide()
  }

  checkAndShowOnboarding() {
    // Don't show if already dismissed via server
    if (this.dismissedValue) return
    
    // Check localStorage for completion
    const savedStep = localStorage.getItem('rupi_onboarding_step')
    if (savedStep === 'complete') return
    
    // Check if user has accounts
    const hasAccounts = this.hasAccountsValue || 
      document.querySelector('[data-has-accounts]')?.dataset.hasAccounts === 'true'
    
    // Check if user has completed tour
    const hasCompletedTour = document.querySelector('[data-tour-completed]')?.dataset.tourCompleted === 'true'
    
    // If has accounts but hasn't completed onboarding, resume from saved step
    if (hasAccounts && savedStep && parseInt(savedStep) > 1) {
      // User has accounts, resume from where they left off
      this.currentStepValue = parseInt(savedStep)
      setTimeout(() => this.show(), 800)
      return
    }
    
    // Show onboarding for new users with no accounts
    if (!hasAccounts && !hasCompletedTour) {
      this.currentStepValue = savedStep ? parseInt(savedStep) : 0
      setTimeout(() => this.show(), 800)
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
        animation: rupi-ob-fade 0.3s ease-out;
      }
      
      @keyframes rupi-ob-fade {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      
      .rupi-onboarding-modal {
        background: #171717;
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 24px;
        width: 100%;
        max-width: 440px;
        overflow: hidden;
        animation: rupi-ob-slide 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      
      @keyframes rupi-ob-slide {
        from { opacity: 0; transform: translateY(30px) scale(0.95); }
        to { opacity: 1; transform: translateY(0) scale(1); }
      }
      
      .rupi-onboarding-header {
        padding: 28px 24px 12px;
        text-align: center;
      }
      
      .rupi-onboarding-logo {
        font-size: 28px;
        font-weight: 700;
        background: linear-gradient(135deg, #12B76A, #FACC15);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
      }
      
      .rupi-onboarding-progress {
        padding: 0 24px 16px;
      }
      
      .rupi-onboarding-progress-bar {
        height: 4px;
        background: #333;
        border-radius: 2px;
        overflow: hidden;
        margin-bottom: 8px;
      }
      
      .rupi-onboarding-progress-fill {
        height: 100%;
        background: linear-gradient(90deg, #12B76A, #10A861);
        border-radius: 2px;
        transition: width 0.4s ease-out;
      }
      
      .rupi-onboarding-progress-text {
        font-size: 12px;
        color: rgba(255,255,255,0.4);
        text-align: center;
      }
      
      .rupi-onboarding-content {
        padding: 8px 24px 24px;
        text-align: center;
      }
      
      .rupi-onboarding-title {
        font-size: 22px;
        font-weight: 600;
        color: white;
        margin-bottom: 12px;
      }
      
      .rupi-onboarding-description {
        font-size: 14px;
        color: rgba(255,255,255,0.6);
        line-height: 1.6;
        margin-bottom: 24px;
      }
      
      .rupi-onboarding-action-area {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      
      .rupi-onboarding-btn-primary {
        width: 100%;
        padding: 14px 24px;
        background: #12B76A;
        color: white;
        border: none;
        border-radius: 12px;
        font-size: 15px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
      }
      
      .rupi-onboarding-btn-primary:hover {
        background: #10A861;
        transform: translateY(-1px);
      }
      
      .rupi-onboarding-btn-secondary {
        width: 100%;
        padding: 12px 24px;
        background: transparent;
        color: rgba(255,255,255,0.5);
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 12px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.2s;
      }
      
      .rupi-onboarding-btn-secondary:hover {
        background: rgba(255,255,255,0.05);
        color: rgba(255,255,255,0.8);
        border-color: rgba(255,255,255,0.2);
      }
      
      .rupi-onboarding-btn-destructive {
        width: 100%;
        padding: 12px 24px;
        background: rgba(239, 68, 68, 0.1);
        color: #EF4444;
        border: 1px solid rgba(239, 68, 68, 0.3);
        border-radius: 12px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.2s;
      }
      
      .rupi-onboarding-btn-destructive:hover {
        background: rgba(239, 68, 68, 0.2);
        border-color: rgba(239, 68, 68, 0.5);
      }
      
      .rupi-onboarding-ai-prompt {
        background: rgba(18, 183, 106, 0.1);
        border: 1px solid rgba(18, 183, 106, 0.2);
        border-radius: 12px;
        padding: 14px;
        margin-bottom: 16px;
      }
      
      .rupi-onboarding-ai-prompt-label {
        font-size: 11px;
        color: rgba(255,255,255,0.4);
        margin-bottom: 6px;
        text-transform: uppercase;
        letter-spacing: 0.5px;
      }
      
      .rupi-onboarding-ai-prompt-text {
        font-size: 14px;
        color: #12B76A;
        font-style: italic;
      }
      
      .rupi-onboarding-footer {
        padding: 12px 24px 20px;
        text-align: center;
      }
      
      .rupi-onboarding-skip {
        font-size: 12px;
        color: rgba(255,255,255,0.3);
        background: none;
        border: none;
        cursor: pointer;
        padding: 8px 16px;
      }
      
      .rupi-onboarding-skip:hover {
        color: rgba(255,255,255,0.6);
      }
      
      .rupi-onboarding-celebration {
        font-size: 56px;
        margin-bottom: 12px;
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
    
    // Calculate progress for numbered steps only (steps 1-5)
    const totalNumberedSteps = 5
    const progressPercent = step.stepNumber 
      ? (step.stepNumber / totalNumberedSteps) * 100 
      : 0
    
    // Build the modal HTML
    this.overlayElement.innerHTML = `
      <div class="rupi-onboarding-modal">
        <div class="rupi-onboarding-header">
          <div class="rupi-onboarding-logo">RUPI</div>
        </div>
        
        ${step.showProgress ? `
          <div class="rupi-onboarding-progress">
            <div class="rupi-onboarding-progress-bar">
              <div class="rupi-onboarding-progress-fill" style="width: ${progressPercent}%"></div>
            </div>
            <div class="rupi-onboarding-progress-text">Step ${step.stepNumber} of ${totalNumberedSteps}</div>
          </div>
        ` : ''}
        
        <div class="rupi-onboarding-content">
          <h2 class="rupi-onboarding-title">${step.stepNumber ? `Step ${step.stepNumber}: ` : ''}${step.title}</h2>
          <p class="rupi-onboarding-description">${step.content}</p>
          <div class="rupi-onboarding-action-area" id="rupi-ob-actions"></div>
        </div>
        
        ${step.skipAllowed ? `
          <div class="rupi-onboarding-footer">
            <button class="rupi-onboarding-skip" id="rupi-ob-skip">Skip setup for now</button>
          </div>
        ` : ''}
      </div>
    `
    
    // Add action buttons with proper event listeners
    const actionArea = this.overlayElement.querySelector('#rupi-ob-actions')
    this.addActionButtons(actionArea, step)
    
    // Add skip listener if present
    const skipBtn = this.overlayElement.querySelector('#rupi-ob-skip')
    if (skipBtn) {
      skipBtn.addEventListener('click', () => this.skipOnboarding())
    }
  }

  addActionButtons(container, step) {
    switch (step.action) {
      case 'continue': {
        const btn = this.createButton(step.buttonText, 'primary')
        btn.addEventListener('click', () => this.nextStep())
        container.appendChild(btn)
        break
      }
        
      case 'load_sample_data': {
        const btn = this.createButton(step.buttonText, 'primary')
        btn.addEventListener('click', () => this.loadSampleData())
        container.appendChild(btn)
        break
      }
        
      case 'try_ai': {
        // Add suggested prompt
        const promptDiv = document.createElement('div')
        promptDiv.className = 'rupi-onboarding-ai-prompt'
        promptDiv.innerHTML = `
          <div class="rupi-onboarding-ai-prompt-label">Try asking:</div>
          <div class="rupi-onboarding-ai-prompt-text">"${step.suggestedPrompt}"</div>
        `
        container.appendChild(promptDiv)
        
        const primaryBtn = this.createButton('Open AI Chat', 'primary')
        primaryBtn.addEventListener('click', () => this.openAIChat())
        container.appendChild(primaryBtn)
        
        const secondaryBtn = this.createButton(step.buttonText, 'secondary')
        secondaryBtn.addEventListener('click', () => this.nextStep())
        container.appendChild(secondaryBtn)
        break
      }
        
      case 'navigate': {
        const primaryBtn = this.createButton(step.buttonText, 'primary')
        primaryBtn.addEventListener('click', () => this.navigateTo(step.targetPath))
        container.appendChild(primaryBtn)
        
        if (step.altButtonText) {
          const secondaryBtn = this.createButton(step.altButtonText, 'secondary')
          secondaryBtn.addEventListener('click', () => this.nextStep())
          container.appendChild(secondaryBtn)
        }
        break
      }
        
      case 'finish': {
        const celebration = document.createElement('div')
        celebration.className = 'rupi-onboarding-celebration'
        celebration.textContent = '🎉'
        container.appendChild(celebration)
        
        const btn = this.createButton(step.buttonText, 'primary')
        btn.addEventListener('click', () => this.finishAndStartTour())
        container.appendChild(btn)
        
        // Also add a skip tour option
        const skipBtn = this.createButton('Skip Tour', 'secondary')
        skipBtn.addEventListener('click', () => this.finish())
        container.appendChild(skipBtn)
        break
      }
    }
  }

  createButton(text, variant) {
    const btn = document.createElement('button')
    btn.className = `rupi-onboarding-btn-${variant}`
    btn.textContent = text
    return btn
  }

  nextStep() {
    this.currentStepValue++
    this.saveProgress()
    this.renderStep()
  }

  loadSampleData() {
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
    
    // Save progress before navigation
    this.currentStepValue++
    this.saveProgress()
    
    form.submit()
  }

  navigateTo(path) {
    // Save progress before navigation
    this.currentStepValue++
    this.saveProgress()
    
    // Navigate in the main window, not modal
    window.location.href = path
  }

  openAIChat() {
    // Hide the overlay to let user interact with AI chat
    this.hide()
    
    // Find and click the AI chat sidebar button
    const chatInput = document.querySelector('[data-chat-input]') ||
                      document.querySelector('[placeholder*="Ask"]') ||
                      document.querySelector('.chat-input')
    
    if (chatInput) {
      chatInput.focus()
    }
    
    // Show a toast or hint
    this.showToast("Chat with RUPI AI in the sidebar! Click 'I've tried the AI' when done.")
    
    // Save current step so coming back will show the "I've tried the AI" option
    // But don't advance yet
  }

  showToast(message) {
    const toast = document.createElement('div')
    toast.style.cssText = `
      position: fixed;
      bottom: 100px;
      left: 50%;
      transform: translateX(-50%);
      background: #171717;
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 12px;
      padding: 16px 24px;
      color: white;
      font-size: 14px;
      z-index: 99998;
      max-width: 400px;
      text-align: center;
      box-shadow: 0 10px 40px rgba(0,0,0,0.5);
    `
    
    // Add a "Continue Onboarding" button
    toast.innerHTML = `
      <p style="margin-bottom: 12px;">${message}</p>
      <button id="resume-onboarding" style="
        background: #12B76A;
        color: white;
        border: none;
        padding: 10px 20px;
        border-radius: 8px;
        cursor: pointer;
        font-weight: 600;
      ">Continue Onboarding →</button>
    `
    document.body.appendChild(toast)
    
    // Add listener to resume button
    toast.querySelector('#resume-onboarding').addEventListener('click', () => {
      toast.remove()
      this.nextStep()
      this.show()
    })
    
    // Auto-remove after 30 seconds
    setTimeout(() => {
      if (toast.parentNode) toast.remove()
    }, 30000)
  }

  finishAndStartTour() {
    // Mark onboarding as complete
    localStorage.setItem('rupi_onboarding_step', 'complete')
    this.hide()
    
    // Dismiss on server
    this.dismissOnServer()
    
    // Start the visual tour
    setTimeout(() => {
      if (window.startRupiTour) {
        window.startRupiTour()
      }
    }, 500)
  }

  finish() {
    // Mark onboarding as complete
    localStorage.setItem('rupi_onboarding_step', 'complete')
    this.hide()
    
    // Dismiss on server
    this.dismissOnServer()
  }

  skipOnboarding() {
    localStorage.setItem('rupi_onboarding_step', 'complete')
    this.hide()
    this.dismissOnServer()
  }

  saveProgress() {
    localStorage.setItem('rupi_onboarding_step', this.currentStepValue.toString())
  }

  dismissOnServer() {
    fetch('/onboarding/dismiss', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
      }
    }).catch(() => {
      // Silent fail
    })
  }
}
