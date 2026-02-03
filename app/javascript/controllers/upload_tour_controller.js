import { Controller } from "@hotwired/stimulus"

// Upload Wizard Tour Controller
// Guides new users through the bank statement upload process
// Persists across page navigations using localStorage
export default class extends Controller {
  static values = {
    page: { type: String, default: "" }  // "select", "upload", "processing", "success"
  }

  tooltipElement = null
  
  steps = {
    select: {
      title: "Step 1: Select Your Bank",
      content: "Choose your bank from the dropdown. We support HDFC, ICICI, SBI, Axis, and 20+ more Indian banks.",
      position: "below",
      target: "[data-upload-tour='bank-select']",
      nextAction: "After selecting, choose your file"
    },
    upload: {
      title: "Step 2: Upload Statement",
      content: "Drag & drop your PDF/Excel statement or click to browse. We'll automatically extract all transactions.",
      position: "below",
      target: "[data-upload-tour='file-drop']",
      nextAction: "Click 'Upload & Import' when ready"
    },
    processing: {
      title: "Processing Your Statement",
      content: "RUPI is reading your statement and categorizing transactions. This usually takes 10-30 seconds.",
      position: "center",
      target: null,
      nextAction: "Please wait..."
    },
    success: {
      title: "🎉 Import Complete!",
      content: "Your transactions are now imported. You can view them in Transactions, or explore Reports and AI insights.",
      position: "center",
      target: null,
      nextAction: "Explore your data"
    }
  }

  connect() {
    this.checkAndShowTour()
  }

  disconnect() {
    this.hide()
  }

  checkAndShowTour() {
    const tourData = this.getTourState()
    if (!tourData?.active) return
    
    // Determine current page based on URL and show appropriate tooltip
    const path = window.location.pathname
    
    if (path.includes('/bank_statement/new')) {
      setTimeout(() => this.showStep('select'), 500)
    } else if (path.includes('/imports/') && path.includes('/upload')) {
      setTimeout(() => this.showStep('upload'), 500)
    } else if (path.includes('/imports/') && (path.includes('/clean') || path.includes('/confirm'))) {
      setTimeout(() => this.showStep('processing'), 500)
    } else if (path.includes('/transactions')) {
      // Check if we just finished an import
      if (tourData.justImported) {
        setTimeout(() => this.showStep('success'), 500)
        this.completeTour()
      }
    }
  }

  getTourState() {
    try {
      return JSON.parse(localStorage.getItem('rupi_upload_tour'))
    } catch {
      return null
    }
  }

  saveTourState(data) {
    localStorage.setItem('rupi_upload_tour', JSON.stringify(data))
  }

  showStep(stepKey) {
    const step = this.steps[stepKey]
    if (!step) return
    
    this.hide()
    this.injectStyles()
    
    // Update tour state
    this.saveTourState({ active: true, currentStep: stepKey })
    
    if (step.position === 'center') {
      this.showCenterTooltip(step)
    } else {
      this.showTargetedTooltip(step)
    }
  }

  showCenterTooltip(step) {
    this.tooltipElement = document.createElement('div')
    this.tooltipElement.className = 'upload-tour-overlay'
    this.tooltipElement.innerHTML = `
      <div class="upload-tour-card upload-tour-card--center">
        <h3 class="upload-tour-title">${step.title}</h3>
        <p class="upload-tour-content">${step.content}</p>
        <div class="upload-tour-actions">
          <button class="upload-tour-btn upload-tour-btn--primary" id="upload-tour-ok">Got it</button>
        </div>
      </div>
    `
    document.body.appendChild(this.tooltipElement)
    
    this.tooltipElement.querySelector('#upload-tour-ok').addEventListener('click', () => this.hide())
  }

  showTargetedTooltip(step) {
    const target = document.querySelector(step.target)
    if (!target) {
      // Fallback: look for common elements
      const fallbackTarget = document.querySelector('select, .dropzone, [type="file"]')
      if (!fallbackTarget) return
    }
    
    const targetEl = target || document.querySelector('select, .dropzone')
    if (!targetEl) return
    
    const rect = targetEl.getBoundingClientRect()
    
    this.tooltipElement = document.createElement('div')
    this.tooltipElement.className = 'upload-tour-tooltip'
    this.tooltipElement.innerHTML = `
      <div class="upload-tour-arrow"></div>
      <h3 class="upload-tour-title">${step.title}</h3>
      <p class="upload-tour-content">${step.content}</p>
      <div class="upload-tour-actions">
        <button class="upload-tour-btn upload-tour-btn--text" id="upload-tour-skip">Skip tour</button>
        <button class="upload-tour-btn upload-tour-btn--small" id="upload-tour-ok">Got it</button>
      </div>
    `
    
    // Position tooltip below target
    const top = rect.bottom + window.scrollY + 12
    const left = Math.max(16, Math.min(rect.left + rect.width / 2 - 160, window.innerWidth - 336))
    
    this.tooltipElement.style.top = `${top}px`
    this.tooltipElement.style.left = `${left}px`
    
    // Highlight target
    targetEl.style.position = 'relative'
    targetEl.style.zIndex = '10001'
    targetEl.classList.add('upload-tour-highlight')
    
    document.body.appendChild(this.tooltipElement)
    
    this.tooltipElement.querySelector('#upload-tour-ok').addEventListener('click', () => this.hide())
    this.tooltipElement.querySelector('#upload-tour-skip').addEventListener('click', () => this.completeTour())
  }

  hide() {
    if (this.tooltipElement) {
      this.tooltipElement.remove()
      this.tooltipElement = null
    }
    
    // Remove highlights
    document.querySelectorAll('.upload-tour-highlight').forEach(el => {
      el.classList.remove('upload-tour-highlight')
      el.style.zIndex = ''
    })
  }

  completeTour() {
    localStorage.removeItem('rupi_upload_tour')
    this.hide()
  }

  // Called when user navigates to next step
  advanceStep() {
    const state = this.getTourState()
    if (!state?.active) return
    
    const stepOrder = ['select', 'upload', 'processing', 'success']
    const currentIndex = stepOrder.indexOf(state.currentStep)
    
    if (currentIndex < stepOrder.length - 1) {
      this.saveTourState({ 
        active: true, 
        currentStep: stepOrder[currentIndex + 1],
        justImported: state.currentStep === 'processing'
      })
    }
  }

  injectStyles() {
    if (document.getElementById('upload-tour-styles')) return
    
    const style = document.createElement('style')
    style.id = 'upload-tour-styles'
    style.textContent = `
      .upload-tour-overlay {
        position: fixed;
        inset: 0;
        z-index: 10000;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(0, 0, 0, 0.7);
        backdrop-filter: blur(4px);
        animation: uploadTourFade 0.3s ease-out;
      }
      
      @keyframes uploadTourFade {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      
      .upload-tour-card {
        background: #171717;
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 16px;
        padding: 24px;
        max-width: 360px;
        text-align: center;
        animation: uploadTourSlide 0.4s cubic-bezier(0.16, 1, 0.3, 1);
      }
      
      @keyframes uploadTourSlide {
        from { opacity: 0; transform: translateY(10px); }
        to { opacity: 1; transform: translateY(0); }
      }
      
      .upload-tour-tooltip {
        position: absolute;
        z-index: 10002;
        background: #171717;
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 12px;
        padding: 16px 20px;
        width: 320px;
        box-shadow: 0 10px 40px rgba(0,0,0,0.4);
        animation: uploadTourSlide 0.3s ease-out;
      }
      
      .upload-tour-arrow {
        position: absolute;
        top: -8px;
        left: 50%;
        transform: translateX(-50%);
        width: 0;
        height: 0;
        border-left: 8px solid transparent;
        border-right: 8px solid transparent;
        border-bottom: 8px solid #171717;
      }
      
      .upload-tour-title {
        font-size: 15px;
        font-weight: 600;
        color: #fff;
        margin: 0 0 8px;
      }
      
      .upload-tour-content {
        font-size: 13px;
        color: rgba(255,255,255,0.6);
        line-height: 1.5;
        margin: 0 0 16px;
      }
      
      .upload-tour-actions {
        display: flex;
        align-items: center;
        justify-content: flex-end;
        gap: 12px;
      }
      
      .upload-tour-btn {
        cursor: pointer;
        border: none;
        border-radius: 8px;
        font-size: 13px;
        font-weight: 500;
        transition: all 0.2s;
      }
      
      .upload-tour-btn--primary {
        background: #12B76A;
        color: white;
        padding: 10px 20px;
      }
      
      .upload-tour-btn--primary:hover {
        background: #10A861;
      }
      
      .upload-tour-btn--small {
        background: #12B76A;
        color: white;
        padding: 8px 16px;
      }
      
      .upload-tour-btn--small:hover {
        background: #10A861;
      }
      
      .upload-tour-btn--text {
        background: none;
        color: rgba(255,255,255,0.4);
        padding: 8px;
      }
      
      .upload-tour-btn--text:hover {
        color: rgba(255,255,255,0.7);
      }
      
      .upload-tour-highlight {
        outline: 2px solid #12B76A !important;
        outline-offset: 4px !important;
        border-radius: 8px !important;
      }
    `
    document.head.appendChild(style)
  }
}
