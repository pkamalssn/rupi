import { Controller } from "@hotwired/stimulus"

// Guided Onboarding Controller v4 - SIMPLIFIED
// Only: Welcome → Load Sample Data → Handoff to Visual Tour
// The Visual Tour handles everything else (accounts, reports, AI, upload)
export default class extends Controller {
  static values = {
    dismissed: { type: Boolean, default: false },
    hasAccounts: { type: Boolean, default: false }
  }

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
    const completed = localStorage.getItem('rupi_onboarding_complete')
    if (completed === 'true') return
    
    // Check if user has accounts (sample data loaded)
    const hasAccounts = this.hasAccountsValue || 
      document.querySelector('[data-has-accounts]')?.dataset.hasAccounts === 'true'
    
    // If has accounts, onboarding is done - let the Tour handle it
    if (hasAccounts) {
      localStorage.setItem('rupi_onboarding_complete', 'true')
      return
    }
    
    // Show onboarding for new users with no accounts
    setTimeout(() => this.showWelcome(), 800)
  }

  showWelcome() {
    this.injectStyles()
    this.createOverlay()
    this.renderWelcome()
  }

  hide() {
    if (this.overlayElement) {
      this.overlayElement.remove()
      this.overlayElement = null
    }
  }

  injectStyles() {
    if (document.getElementById('rupi-onboarding-styles-v4')) return
    
    const style = document.createElement('style')
    style.id = 'rupi-onboarding-styles-v4'
    style.textContent = `
      .rupi-ob-overlay {
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
      
      .rupi-ob-modal {
        background: #171717;
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 24px;
        width: 100%;
        max-width: 450px;
        padding: 40px;
        text-align: center;
        animation: rupi-ob-slide 0.4s cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      
      @keyframes rupi-ob-slide {
        from { opacity: 0; transform: translateY(30px) scale(0.95); }
        to { opacity: 1; transform: translateY(0) scale(1); }
      }
      
      .rupi-ob-logo {
        font-size: 32px;
        font-weight: 700;
        background: linear-gradient(135deg, #12B76A, #FACC15);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        background-clip: text;
        margin-bottom: 24px;
      }
      
      .rupi-ob-emoji {
        font-size: 64px;
        margin-bottom: 20px;
      }
      
      .rupi-ob-title {
        font-size: 24px;
        font-weight: 600;
        color: white;
        margin-bottom: 12px;
      }
      
      .rupi-ob-text {
        font-size: 15px;
        color: rgba(255,255,255,0.6);
        line-height: 1.6;
        margin-bottom: 32px;
      }
      
      .rupi-ob-btn-primary {
        width: 100%;
        padding: 16px 24px;
        background: #12B76A;
        color: white;
        border: none;
        border-radius: 12px;
        font-size: 16px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
        margin-bottom: 12px;
      }
      
      .rupi-ob-btn-primary:hover {
        background: #10A861;
        transform: translateY(-2px);
        box-shadow: 0 8px 24px rgba(18, 183, 106, 0.3);
      }
      
      .rupi-ob-btn-secondary {
        width: 100%;
        padding: 14px 24px;
        background: transparent;
        color: rgba(255,255,255,0.5);
        border: 1px solid rgba(255,255,255,0.15);
        border-radius: 12px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.2s;
      }
      
      .rupi-ob-btn-secondary:hover {
        background: rgba(255,255,255,0.05);
        color: rgba(255,255,255,0.8);
        border-color: rgba(255,255,255,0.25);
      }
      
      .rupi-ob-skip {
        display: block;
        margin-top: 20px;
        font-size: 12px;
        color: rgba(255,255,255,0.3);
        background: none;
        border: none;
        cursor: pointer;
        padding: 8px 16px;
      }
      
      .rupi-ob-skip:hover {
        color: rgba(255,255,255,0.6);
      }
      
      .rupi-ob-features {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 12px;
        margin-bottom: 28px;
        text-align: left;
      }
      
      .rupi-ob-feature {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 13px;
        color: rgba(255,255,255,0.7);
      }
      
      .rupi-ob-feature-icon {
        font-size: 16px;
      }
    `
    document.head.appendChild(style)
  }

  createOverlay() {
    this.overlayElement = document.createElement('div')
    this.overlayElement.className = 'rupi-ob-overlay'
    document.body.appendChild(this.overlayElement)
  }

  renderWelcome() {
    this.overlayElement.innerHTML = `
      <div class="rupi-ob-modal">
        <div class="rupi-ob-logo">RUPI</div>
        <div class="rupi-ob-emoji">👋</div>
        <h2 class="rupi-ob-title">Welcome to RUPI!</h2>
        <p class="rupi-ob-text">Your intelligent personal finance assistant for Indian banks. Let's get you started!</p>
        
        <div class="rupi-ob-features">
          <div class="rupi-ob-feature">
            <span class="rupi-ob-feature-icon">📊</span>
            <span>Track all accounts</span>
          </div>
          <div class="rupi-ob-feature">
            <span class="rupi-ob-feature-icon">🤖</span>
            <span>AI-powered insights</span>
          </div>
          <div class="rupi-ob-feature">
            <span class="rupi-ob-feature-icon">📈</span>
            <span>Spending reports</span>
          </div>
          <div class="rupi-ob-feature">
            <span class="rupi-ob-feature-icon">🏦</span>
            <span>20+ Indian banks</span>
          </div>
        </div>
        
        <button class="rupi-ob-btn-primary" id="rupi-ob-start">Let's Start →</button>
        <button class="rupi-ob-skip" id="rupi-ob-skip">Skip for now</button>
      </div>
    `
    
    // Add event listeners
    this.overlayElement.querySelector('#rupi-ob-start').addEventListener('click', () => this.showLoadData())
    this.overlayElement.querySelector('#rupi-ob-skip').addEventListener('click', () => this.skipOnboarding())
  }

  showLoadData() {
    this.overlayElement.innerHTML = `
      <div class="rupi-ob-modal">
        <div class="rupi-ob-logo">RUPI</div>
        <div class="rupi-ob-emoji">📊</div>
        <h2 class="rupi-ob-title">Load Sample Data</h2>
        <p class="rupi-ob-text">Before uploading your real bank statements, let's explore RUPI with sample data. This helps you understand all features safely!</p>
        
        <button class="rupi-ob-btn-primary" id="rupi-ob-load">Load Sample Data</button>
        <button class="rupi-ob-btn-secondary" id="rupi-ob-upload">I'll upload my own data</button>
        <button class="rupi-ob-skip" id="rupi-ob-skip">Skip for now</button>
      </div>
    `
    
    // Add event listeners
    this.overlayElement.querySelector('#rupi-ob-load').addEventListener('click', () => this.loadSampleData())
    this.overlayElement.querySelector('#rupi-ob-upload').addEventListener('click', () => this.goToUpload())
    this.overlayElement.querySelector('#rupi-ob-skip').addEventListener('click', () => this.skipOnboarding())
  }

  loadSampleData() {
    // Mark onboarding complete - Visual Tour will take over after page reload
    localStorage.setItem('rupi_onboarding_complete', 'true')
    
    // Create form to load sample data
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
  }

  goToUpload() {
    localStorage.setItem('rupi_onboarding_complete', 'true')
    this.dismissOnServer()
    window.location.href = '/bank_statement/new'
  }

  skipOnboarding() {
    localStorage.setItem('rupi_onboarding_complete', 'true')
    this.hide()
    this.dismissOnServer()
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
