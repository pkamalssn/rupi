import { Controller } from "@hotwired/stimulus"

// Guided Onboarding Controller v6 - PREMIUM DESIGN + USER-SPECIFIC STORAGE
// Beautiful, minimal, matching RUPI's dark aesthetic
// Fixed: localStorage keys are now user-specific
export default class extends Controller {
  static values = {
    dismissed: { type: Boolean, default: false },
    hasAccounts: { type: Boolean, default: false },
    userId: { type: String, default: "" }
  }

  overlayElement = null

  // User-specific localStorage key
  get storageKey() {
    return `rupi_onboarding_complete_${this.userIdValue}`
  }

  connect() {
    this.checkAndShowOnboarding()
  }

  disconnect() {
    this.hide()
  }

  checkAndShowOnboarding() {
    // Skip if server says dismissed
    if (this.dismissedValue) return
    
    // Skip if localStorage says complete for THIS USER
    const completed = localStorage.getItem(this.storageKey)
    if (completed === 'true') return
    
    // Skip if user already has accounts
    if (this.hasAccountsValue) {
      localStorage.setItem(this.storageKey, 'true')
      return
    }
    
    setTimeout(() => this.showWelcome(), 600)
  }

  showWelcome() {
    this.injectStyles()
    this.createOverlay()
    this.renderWelcome()
  }

  hide() {
    if (this.overlayElement) {
      this.overlayElement.classList.add('rupi-ob--closing')
      setTimeout(() => {
        this.overlayElement?.remove()
        this.overlayElement = null
      }, 200)
    }
  }

  injectStyles() {
    if (document.getElementById('rupi-onboarding-styles-v5')) return
    
    const style = document.createElement('style')
    style.id = 'rupi-onboarding-styles-v5'
    style.textContent = `
      .rupi-ob {
        position: fixed;
        inset: 0;
        z-index: 99999;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        animation: rupiObIn 0.4s cubic-bezier(0.16, 1, 0.3, 1);
      }
      
      .rupi-ob--closing {
        animation: rupiObOut 0.2s ease-out forwards;
      }
      
      @keyframes rupiObIn {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      
      @keyframes rupiObOut {
        to { opacity: 0; }
      }
      
      .rupi-ob__backdrop {
        position: absolute;
        inset: 0;
        background: rgba(0, 0, 0, 0.85);
        backdrop-filter: blur(8px);
        -webkit-backdrop-filter: blur(8px);
      }
      
      .rupi-ob__card {
        position: relative;
        background: linear-gradient(180deg, #1a1a1a 0%, #0f0f0f 100%);
        border: 1px solid rgba(255,255,255,0.08);
        border-radius: 20px;
        width: 100%;
        max-width: 380px;
        overflow: hidden;
        animation: rupiObSlide 0.5s cubic-bezier(0.16, 1, 0.3, 1);
        box-shadow: 
          0 0 0 1px rgba(255,255,255,0.05),
          0 20px 50px -10px rgba(0,0,0,0.5),
          0 0 100px -20px rgba(18, 183, 106, 0.15);
      }
      
      @keyframes rupiObSlide {
        from { 
          opacity: 0; 
          transform: translateY(20px) scale(0.98); 
        }
        to { 
          opacity: 1; 
          transform: translateY(0) scale(1); 
        }
      }
      
      .rupi-ob__glow {
        position: absolute;
        top: -100px;
        left: 50%;
        transform: translateX(-50%);
        width: 300px;
        height: 200px;
        background: radial-gradient(ellipse, rgba(18, 183, 106, 0.15) 0%, transparent 70%);
        pointer-events: none;
      }
      
      .rupi-ob__content {
        position: relative;
        padding: 36px 32px 28px;
        text-align: center;
      }
      
      .rupi-ob__icon {
        width: 56px;
        height: 56px;
        margin: 0 auto 20px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 32px;
        background: linear-gradient(135deg, rgba(18, 183, 106, 0.15) 0%, rgba(18, 183, 106, 0.05) 100%);
        border: 1px solid rgba(18, 183, 106, 0.2);
        border-radius: 16px;
      }
      
      .rupi-ob__title {
        font-size: 20px;
        font-weight: 600;
        color: #fff;
        margin: 0 0 8px;
        letter-spacing: -0.02em;
      }
      
      .rupi-ob__subtitle {
        font-size: 14px;
        color: rgba(255,255,255,0.5);
        margin: 0 0 24px;
        line-height: 1.5;
      }
      
      .rupi-ob__features {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 8px;
        margin-bottom: 24px;
      }
      
      .rupi-ob__feature {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 10px 12px;
        background: rgba(255,255,255,0.03);
        border: 1px solid rgba(255,255,255,0.05);
        border-radius: 10px;
        font-size: 12px;
        color: rgba(255,255,255,0.7);
      }
      
      .rupi-ob__feature-icon {
        font-size: 14px;
        opacity: 0.9;
      }
      
      .rupi-ob__actions {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
      
      .rupi-ob__btn {
        width: 100%;
        padding: 14px 20px;
        border-radius: 12px;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s ease;
        border: none;
      }
      
      .rupi-ob__btn--primary {
        background: linear-gradient(135deg, #12B76A 0%, #0EA55E 100%);
        color: white;
        box-shadow: 0 4px 12px rgba(18, 183, 106, 0.25);
      }
      
      .rupi-ob__btn--primary:hover {
        transform: translateY(-1px);
        box-shadow: 0 6px 20px rgba(18, 183, 106, 0.35);
      }
      
      .rupi-ob__btn--secondary {
        background: rgba(255,255,255,0.05);
        color: rgba(255,255,255,0.7);
        border: 1px solid rgba(255,255,255,0.1);
      }
      
      .rupi-ob__btn--secondary:hover {
        background: rgba(255,255,255,0.08);
        color: rgba(255,255,255,0.9);
      }
      
      .rupi-ob__skip {
        margin-top: 8px;
        font-size: 12px;
        color: rgba(255,255,255,0.3);
        background: none;
        border: none;
        cursor: pointer;
        padding: 8px;
      }
      
      .rupi-ob__skip:hover {
        color: rgba(255,255,255,0.5);
      }
      
      .rupi-ob__step {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        margin-bottom: 20px;
      }
      
      .rupi-ob__dot {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: rgba(255,255,255,0.2);
        transition: all 0.3s ease;
      }
      
      .rupi-ob__dot--active {
        width: 20px;
        border-radius: 3px;
        background: #12B76A;
      }
    `
    document.head.appendChild(style)
  }

  createOverlay() {
    this.overlayElement = document.createElement('div')
    this.overlayElement.className = 'rupi-ob'
    document.body.appendChild(this.overlayElement)
  }

  renderWelcome() {
    this.overlayElement.innerHTML = `
      <div class="rupi-ob__backdrop"></div>
      <div class="rupi-ob__card">
        <div class="rupi-ob__glow"></div>
        <div class="rupi-ob__content">
          <div class="rupi-ob__step">
            <span class="rupi-ob__dot rupi-ob__dot--active"></span>
            <span class="rupi-ob__dot"></span>
          </div>
          
          <div class="rupi-ob__icon">👋</div>
          <h2 class="rupi-ob__title">Welcome to RUPI</h2>
          <p class="rupi-ob__subtitle">Your AI-powered personal finance assistant for Indian banks</p>
          
          <div class="rupi-ob__features">
            <div class="rupi-ob__feature">
              <span class="rupi-ob__feature-icon">📊</span>
              <span>Track accounts</span>
            </div>
            <div class="rupi-ob__feature">
              <span class="rupi-ob__feature-icon">🤖</span>
              <span>AI insights</span>
            </div>
            <div class="rupi-ob__feature">
              <span class="rupi-ob__feature-icon">📈</span>
              <span>Smart reports</span>
            </div>
            <div class="rupi-ob__feature">
              <span class="rupi-ob__feature-icon">🏦</span>
              <span>20+ banks</span>
            </div>
          </div>
          
          <div class="rupi-ob__actions">
            <button class="rupi-ob__btn rupi-ob__btn--primary" id="rupi-ob-start">
              Get Started
            </button>
          </div>
          <button class="rupi-ob__skip" id="rupi-ob-skip">Skip for now</button>
        </div>
      </div>
    `
    
    this.overlayElement.querySelector('#rupi-ob-start').addEventListener('click', () => this.showLoadData())
    this.overlayElement.querySelector('#rupi-ob-skip').addEventListener('click', () => this.skipOnboarding())
  }

  showLoadData() {
    const card = this.overlayElement.querySelector('.rupi-ob__card')
    card.style.animation = 'none'
    card.offsetHeight // Trigger reflow
    card.style.animation = 'rupiObSlide 0.4s cubic-bezier(0.16, 1, 0.3, 1)'
    
    this.overlayElement.querySelector('.rupi-ob__content').innerHTML = `
      <div class="rupi-ob__step">
        <span class="rupi-ob__dot"></span>
        <span class="rupi-ob__dot rupi-ob__dot--active"></span>
      </div>
      
      <div class="rupi-ob__icon">📊</div>
      <h2 class="rupi-ob__title">Try with Sample Data</h2>
      <p class="rupi-ob__subtitle">Explore all features safely before uploading your own statements</p>
      
      <div class="rupi-ob__actions">
        <button class="rupi-ob__btn rupi-ob__btn--primary" id="rupi-ob-load">
          Load Sample Data
        </button>
        <button class="rupi-ob__btn rupi-ob__btn--secondary" id="rupi-ob-upload">
          Upload my statement
        </button>
      </div>
      <button class="rupi-ob__skip" id="rupi-ob-skip">Skip for now</button>
    `
    
    this.overlayElement.querySelector('#rupi-ob-load').addEventListener('click', () => this.loadSampleData())
    this.overlayElement.querySelector('#rupi-ob-upload').addEventListener('click', () => this.goToUpload())
    this.overlayElement.querySelector('#rupi-ob-skip').addEventListener('click', () => this.skipOnboarding())
  }

  loadSampleData() {
    localStorage.setItem(this.storageKey, 'true')
    
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
    localStorage.setItem(this.storageKey, 'true')
    // Start the upload wizard tour
    localStorage.setItem('rupi_upload_tour', JSON.stringify({ step: 0, active: true }))
    this.dismissOnServer()
    window.location.href = '/bank_statement/new'
  }

  skipOnboarding() {
    localStorage.setItem(this.storageKey, 'true')
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
    }).catch(() => {})
  }
}
