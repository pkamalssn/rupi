import { Controller } from "@hotwired/stimulus"

// Upload Wizard Tour Controller v2
// Non-intrusive floating guide bar at the bottom of screen
// Persists across page navigations using localStorage
export default class extends Controller {
  static values = {
    page: { type: String, default: "" }
  }

  guideBar = null
  
  // Steps with progress indicators
  steps = [
    { key: 'select', title: 'Select Bank', description: 'Choose your bank from the dropdown', done: false },
    { key: 'upload', title: 'Upload File', description: 'Drop your PDF/Excel statement', done: false },
    { key: 'import', title: 'Import', description: 'Confirm and import transactions', done: false },
    { key: 'done', title: 'Done!', description: 'View your transactions', done: false }
  ]

  connect() {
    this.checkAndShowGuide()
    this.setupEventListeners()
  }

  disconnect() {
    this.hide()
    this.removeEventListeners()
  }

  setupEventListeners() {
    // Listen for bank selection
    this.bankSelectHandler = this.onBankSelected.bind(this)
    const bankSelect = document.querySelector('[data-upload-tour="bank-select"]')
    if (bankSelect) {
      bankSelect.addEventListener('change', this.bankSelectHandler)
    }
    
    // Listen for file selection
    this.fileSelectHandler = this.onFileSelected.bind(this)
    const fileInput = document.querySelector('input[type="file"]')
    if (fileInput) {
      fileInput.addEventListener('change', this.fileSelectHandler)
    }
  }

  removeEventListeners() {
    const bankSelect = document.querySelector('[data-upload-tour="bank-select"]')
    if (bankSelect && this.bankSelectHandler) {
      bankSelect.removeEventListener('change', this.bankSelectHandler)
    }
    
    const fileInput = document.querySelector('input[type="file"]')
    if (fileInput && this.fileSelectHandler) {
      fileInput.removeEventListener('change', this.fileSelectHandler)
    }
  }

  onBankSelected(e) {
    if (e.target.value) {
      this.markStepDone('select')
      this.updateGuideBar()
    }
  }

  onFileSelected(e) {
    if (e.target.files?.length > 0) {
      this.markStepDone('upload')
      this.updateGuideBar()
    }
  }

  checkAndShowGuide() {
    const tourData = this.getTourState()
    if (!tourData?.active) return
    
    // Determine current page and update step progress
    const path = window.location.pathname
    
    if (path.includes('/bank_statement/new')) {
      this.showGuideBar('select')
    } else if (path.includes('/imports/') && path.includes('/upload')) {
      this.markStepDone('select')
      this.showGuideBar('upload')
    } else if (path.includes('/imports/') && (path.includes('/configuration') || path.includes('/clean') || path.includes('/confirm'))) {
      this.markStepDone('select')
      this.markStepDone('upload')
      this.showGuideBar('import')
    } else if (path.includes('/transactions') || path.includes('/dashboard')) {
      // Check if we just finished an import
      if (tourData.lastStep === 'import') {
        this.showSuccessToast()
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

  markStepDone(stepKey) {
    const state = this.getTourState() || { active: true, completedSteps: [] }
    if (!state.completedSteps) state.completedSteps = []
    if (!state.completedSteps.includes(stepKey)) {
      state.completedSteps.push(stepKey)
    }
    state.lastStep = stepKey
    this.saveTourState(state)
  }

  showGuideBar(currentStep) {
    this.hide()
    this.injectStyles()
    
    const state = this.getTourState() || { completedSteps: [] }
    const completedSteps = state.completedSteps || []
    
    this.guideBar = document.createElement('div')
    this.guideBar.className = 'upload-guide-bar'
    this.guideBar.innerHTML = `
      <div class="upload-guide-content">
        <div class="upload-guide-title">
          📄 Upload Wizard
        </div>
        <div class="upload-guide-steps">
          ${this.steps.slice(0, -1).map((step, i) => `
            <div class="upload-guide-step ${completedSteps.includes(step.key) ? 'done' : ''} ${step.key === currentStep ? 'current' : ''}">
              <div class="upload-guide-step-number">${completedSteps.includes(step.key) ? '✓' : i + 1}</div>
              <div class="upload-guide-step-text">
                <span class="upload-guide-step-title">${step.title}</span>
              </div>
            </div>
            ${i < this.steps.length - 2 ? '<div class="upload-guide-connector"></div>' : ''}
          `).join('')}
        </div>
        <button class="upload-guide-dismiss" id="dismiss-guide">×</button>
      </div>
    `
    
    document.body.appendChild(this.guideBar)
    
    this.guideBar.querySelector('#dismiss-guide').addEventListener('click', () => this.completeTour())
    
    // Animate in
    requestAnimationFrame(() => {
      this.guideBar.classList.add('visible')
    })
  }

  updateGuideBar() {
    // Just refresh the guide bar with new completion state
    const currentStep = this.getCurrentStep()
    if (currentStep) {
      this.showGuideBar(currentStep)
    }
  }

  getCurrentStep() {
    const state = this.getTourState()
    if (!state) return null
    
    const completedSteps = state.completedSteps || []
    for (const step of this.steps) {
      if (!completedSteps.includes(step.key)) {
        return step.key
      }
    }
    return 'done'
  }

  showSuccessToast() {
    const toast = document.createElement('div')
    toast.className = 'upload-success-toast'
    toast.innerHTML = `
      <span class="upload-success-icon">🎉</span>
      <span class="upload-success-text">Statement imported successfully!</span>
    `
    document.body.appendChild(toast)
    
    requestAnimationFrame(() => toast.classList.add('visible'))
    
    setTimeout(() => {
      toast.classList.remove('visible')
      setTimeout(() => toast.remove(), 300)
    }, 4000)
  }

  hide() {
    if (this.guideBar) {
      this.guideBar.classList.remove('visible')
      setTimeout(() => {
        this.guideBar?.remove()
        this.guideBar = null
      }, 300)
    }
  }

  completeTour() {
    localStorage.removeItem('rupi_upload_tour')
    this.hide()
  }

  injectStyles() {
    if (document.getElementById('upload-guide-styles-v2')) return
    
    const style = document.createElement('style')
    style.id = 'upload-guide-styles-v2'
    style.textContent = `
      .upload-guide-bar {
        position: fixed;
        bottom: -80px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 9999;
        transition: bottom 0.3s ease-out;
      }
      
      .upload-guide-bar.visible {
        bottom: 24px;
      }
      
      .upload-guide-content {
        display: flex;
        align-items: center;
        gap: 20px;
        background: linear-gradient(135deg, #1a1a1a 0%, #0f0f0f 100%);
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 16px;
        padding: 12px 20px;
        box-shadow: 0 10px 40px rgba(0,0,0,0.4), 0 0 0 1px rgba(255,255,255,0.05);
      }
      
      .upload-guide-title {
        font-size: 14px;
        font-weight: 600;
        color: #12B76A;
        white-space: nowrap;
      }
      
      .upload-guide-steps {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      
      .upload-guide-step {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 6px 12px;
        border-radius: 8px;
        background: rgba(255,255,255,0.03);
        transition: all 0.2s;
      }
      
      .upload-guide-step.current {
        background: rgba(18, 183, 106, 0.15);
        border: 1px solid rgba(18, 183, 106, 0.3);
      }
      
      .upload-guide-step.done {
        opacity: 0.6;
      }
      
      .upload-guide-step-number {
        width: 22px;
        height: 22px;
        border-radius: 50%;
        background: rgba(255,255,255,0.1);
        color: rgba(255,255,255,0.6);
        font-size: 12px;
        font-weight: 600;
        display: flex;
        align-items: center;
        justify-content: center;
      }
      
      .upload-guide-step.done .upload-guide-step-number {
        background: #12B76A;
        color: white;
      }
      
      .upload-guide-step.current .upload-guide-step-number {
        background: #12B76A;
        color: white;
      }
      
      .upload-guide-step-title {
        font-size: 13px;
        color: rgba(255,255,255,0.7);
        font-weight: 500;
      }
      
      .upload-guide-step.current .upload-guide-step-title {
        color: white;
      }
      
      .upload-guide-connector {
        width: 20px;
        height: 2px;
        background: rgba(255,255,255,0.1);
      }
      
      .upload-guide-dismiss {
        background: none;
        border: none;
        color: rgba(255,255,255,0.3);
        font-size: 18px;
        cursor: pointer;
        padding: 4px 8px;
        margin-left: 8px;
      }
      
      .upload-guide-dismiss:hover {
        color: rgba(255,255,255,0.6);
      }
      
      .upload-success-toast {
        position: fixed;
        bottom: -60px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 10000;
        display: flex;
        align-items: center;
        gap: 10px;
        background: linear-gradient(135deg, #12B76A 0%, #0EA55E 100%);
        color: white;
        padding: 14px 24px;
        border-radius: 12px;
        font-size: 15px;
        font-weight: 600;
        box-shadow: 0 10px 30px rgba(18, 183, 106, 0.3);
        transition: bottom 0.3s ease-out;
      }
      
      .upload-success-toast.visible {
        bottom: 24px;
      }
      
      .upload-success-icon {
        font-size: 20px;
      }
    `
    document.head.appendChild(style)
  }
}
