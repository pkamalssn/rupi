import { Controller } from "@hotwired/stimulus"

// Upload Wizard Tour Controller v4
// Simplified flow: Bank → File+Submit → Complete
// Shows completion modal when user returns to dashboard after import
export default class extends Controller {
  static values = {
    page: { type: String, default: "" }
  }

  guideBar = null
  
  // Steps displayed to user - simplified to 3 clear steps
  stepLabels = [
    { key: 'bank', label: 'Select Bank', icon: '🏦' },
    { key: 'upload', label: 'Upload & Submit', icon: '📄' },
    { key: 'complete', label: 'Complete', icon: '✅' }
  ]

  connect() {
    console.log('[UploadTour] Controller connected, checking tour state...')
    this.checkAndShowGuide()
    this.setupEventListeners()
  }

  disconnect() {
    this.removeEventListeners()
    // Don't hide on disconnect - let it persist across Turbo navigation
  }

  setupEventListeners() {
    // Listen for bank selection changes
    this.bankSelectHandler = this.onBankSelected.bind(this)
    const bankSelect = document.querySelector('[data-upload-tour="bank-select"], select[name*="bank"]')
    if (bankSelect) {
      bankSelect.addEventListener('change', this.bankSelectHandler)
      console.log('[UploadTour] Attached bank select listener')
    }
    
    // Listen for file selection - just visual feedback, doesn't complete step
    this.fileSelectHandler = this.onFileSelected.bind(this)
    const fileInputs = document.querySelectorAll('input[type=\"file\"]')
    fileInputs.forEach(input => {
      input.addEventListener('change', this.fileSelectHandler)
    })
    if (fileInputs.length) console.log('[UploadTour] Attached file input listeners')
    
    // Listen for form submissions - THIS completes the upload step
    this.formSubmitHandler = this.onFormSubmit.bind(this)
    const forms = document.querySelectorAll('form[action*=\"bank_statement\"], form[action*=\"import\"]')
    forms.forEach(form => {
      form.addEventListener('submit', this.formSubmitHandler)
    })
    if (forms.length) console.log('[UploadTour] Attached form submit listeners')
  }

  removeEventListeners() {
    const bankSelect = document.querySelector('[data-upload-tour="bank-select"], select[name*="bank"]')
    if (bankSelect && this.bankSelectHandler) {
      bankSelect.removeEventListener('change', this.bankSelectHandler)
    }
    
    const fileInputs = document.querySelectorAll('input[type=\"file\"]')
    fileInputs.forEach(input => {
      if (this.fileSelectHandler) {
        input.removeEventListener('change', this.fileSelectHandler)
      }
    })
  }

  // ============ EVENT HANDLERS ============
  
  onBankSelected(e) {
    console.log('[UploadTour] Bank selected:', e.target.value)
    if (e.target.value) {
      this.markStepDone('bank')
      this.refreshGuideBar()
    }
  }

  onFileSelected(e) {
    // File selection gives visual feedback but doesn't complete the step
    // User still needs to click "Upload & Import" to complete
    console.log('[UploadTour] File selected:', e.target.files?.length)
    if (e.target.files?.length > 0) {
      // Just update UI to show file is ready, don't mark step done
      this.showFileReadyHint()
    }
  }

  showFileReadyHint() {
    // Find the current step indicator and add a "ready" state
    const uploadStep = this.guideBar?.querySelector('.upload-wizard-step:nth-child(3)')
    if (uploadStep && !uploadStep.classList.contains('done')) {
      uploadStep.classList.add('ready')
    }
  }

  onFormSubmit(e) {
    console.log('[UploadTour] Form submitted - marking upload step complete')
    this.markStepDone('bank')  // Ensure bank is marked
    this.markStepDone('upload') // Mark upload complete
    
    // Save state indicating import is in progress
    this.saveTourState({ 
      ...this.getTourState(), 
      importStarted: true,
      importStartedAt: Date.now()
    })
    
    // Hide the wizard bar during import flow - the import UI has its own progress
    this.hideGuideBar()
  }

  hideGuideBar() {
    const bar = document.querySelector('.upload-wizard-bar')
    if (bar) {
      bar.classList.remove('visible')
      setTimeout(() => bar.remove(), 400)
    }
  }

  // ============ GUIDE BAR DISPLAY ============
  
  checkAndShowGuide() {
    const tourData = this.getTourState()
    console.log('[UploadTour] Tour state:', tourData)
    
    if (!tourData?.active) {
      console.log('[UploadTour] Tour not active, skipping')
      return
    }
    
    const path = window.location.pathname
    console.log('[UploadTour] Current path:', path)
    
    // Check if user just completed an import and is back on dashboard
    if ((path === '/' || path.includes('/dashboard')) && tourData.importStarted) {
      // User is back on dashboard after starting an import - show completion!
      console.log('[UploadTour] User returned to dashboard after import - showing completion')
      this.showCompletionModal()
      this.completeTour()
      return
    }
    
    // Don't show wizard on import processing pages - they have their own UI
    if (path.includes('/imports/')) {
      console.log('[UploadTour] On import page, hiding wizard (import UI handles this)')
      return
    }
    
    // Show wizard on bank statement upload page
    if (path.includes('/bank_statement/new')) {
      const completedSteps = tourData.completedSteps || []
      if (completedSteps.includes('bank')) {
        this.showGuideBar('upload')
      } else {
        this.showGuideBar('bank')
      }
      return
    }
    
    // On other pages with active tour, show current step
    if (tourData.active && tourData.completedSteps?.length > 0) {
      this.showGuideBar(this.getCurrentStep())
    }
  }

  showGuideBar(currentStepKey) {
    // Remove existing bar first
    const existingBar = document.querySelector('.upload-wizard-bar')
    if (existingBar) existingBar.remove()
    
    this.injectStyles()
    
    const state = this.getTourState() || { completedSteps: [] }
    const completedSteps = state.completedSteps || []
    
    this.guideBar = document.createElement('div')
    this.guideBar.className = 'upload-wizard-bar'
    
    const stepsHtml = this.stepLabels.map((step, i) => {
      const isDone = completedSteps.includes(step.key)
      const isCurrent = step.key === currentStepKey
      const isLast = i === this.stepLabels.length - 1
      
      return `
        <div class="upload-wizard-step ${isDone ? 'done' : ''} ${isCurrent ? 'current' : ''}">
          <div class="upload-wizard-step-icon">${isDone ? '✓' : step.icon}</div>
          <span class="upload-wizard-step-label">${step.label}</span>
        </div>
        ${!isLast ? '<div class="upload-wizard-connector"></div>' : ''}
      `
    }).join('')
    
    // Add contextual hint based on current step
    let hint = ''
    if (currentStepKey === 'bank') {
      hint = 'Choose your bank from the dropdown above'
    } else if (currentStepKey === 'upload') {
      hint = 'Select your PDF/Excel file, then click the green "Upload & Import" button'
    }
    
    this.guideBar.innerHTML = `
      <div class="upload-wizard-content">
        <div class="upload-wizard-header">
          <span class="upload-wizard-title">📥 Upload Wizard</span>
          <span class="upload-wizard-subtitle">${hint || 'Follow these steps to import your statement'}</span>
        </div>
        <div class="upload-wizard-steps">
          ${stepsHtml}
        </div>
        <button class="upload-wizard-dismiss" id="dismiss-wizard" title="Dismiss">Skip</button>
      </div>
    `
    
    document.body.appendChild(this.guideBar)
    
    // Attach dismiss handler
    document.getElementById('dismiss-wizard')?.addEventListener('click', () => {
      this.completeTour()
      this.guideBar?.remove()
    })
    
    // Animate in
    requestAnimationFrame(() => {
      this.guideBar.classList.add('visible')
    })
  }

  refreshGuideBar() {
    const currentStep = this.getCurrentStep()
    this.showGuideBar(currentStep)
  }

  getCurrentStep() {
    const state = this.getTourState()
    if (!state) return 'bank'
    
    const completedSteps = state.completedSteps || []
    for (const step of this.stepLabels) {
      if (!completedSteps.includes(step.key)) {
        return step.key
      }
    }
    return 'complete'
  }

  showCompletionModal() {
    this.injectStyles()
    
    const modal = document.createElement('div')
    modal.className = 'upload-wizard-modal-overlay'
    modal.innerHTML = `
      <div class="upload-wizard-modal">
        <div class="upload-wizard-modal-icon">🎉</div>
        <h3 class="upload-wizard-modal-title">Statement Imported!</h3>
        <p class="upload-wizard-modal-text">
          Your transactions have been imported and categorized by AI. 
          Check your accounts in the sidebar to explore your data!
        </p>
        <p class="upload-wizard-modal-text" style="font-size: 14px; color: rgba(255,255,255,0.5);">
          Want to clear the sample data loaded earlier?
        </p>
        <div class="upload-wizard-modal-actions">
          <button class="upload-wizard-modal-btn upload-wizard-modal-btn--secondary" id="wizard-keep-sample">
            Keep Sample Data
          </button>
          <button class="upload-wizard-modal-btn upload-wizard-modal-btn--danger" id="wizard-clear-sample">
            Clear Sample Data
          </button>
        </div>
        <button class="upload-wizard-modal-btn upload-wizard-modal-btn--primary" id="wizard-done" style="margin-top: 12px;">
          Start Exploring →
        </button>
      </div>
    `
    
    document.body.appendChild(modal)
    
    // Animate in
    requestAnimationFrame(() => {
      modal.classList.add('visible')
    })
    
    // Button handlers
    document.getElementById('wizard-keep-sample')?.addEventListener('click', () => {
      modal.remove()
    })
    
    document.getElementById('wizard-clear-sample')?.addEventListener('click', () => {
      modal.innerHTML = `
        <div class="upload-wizard-modal">
          <div class="upload-wizard-modal-icon">⏳</div>
          <h3 class="upload-wizard-modal-title">Clearing Sample Data...</h3>
        </div>
      `
      // Submit form to clear demo data
      const form = document.createElement('form')
      form.method = 'POST'
      form.action = '/clear_demo_data'
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
    })
    
    document.getElementById('wizard-done')?.addEventListener('click', () => {
      modal.remove()
    })
  }

  // ============ STATE MANAGEMENT ============
  
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
      console.log('[UploadTour] Marked step done:', stepKey, 'All:', state.completedSteps)
    }
    state.lastStep = stepKey
    this.saveTourState(state)
  }

  completeTour() {
    console.log('[UploadTour] Completing tour')
    localStorage.removeItem('rupi_upload_tour')
  }

  // ============ STYLES ============
  
  injectStyles() {
    if (document.getElementById('upload-wizard-styles-v4')) return
    
    const style = document.createElement('style')
    style.id = 'upload-wizard-styles-v4'
    style.textContent = `
      /* ========== FLOATING PROGRESS BAR ========== */
      .upload-wizard-bar {
        position: fixed;
        bottom: -100px;
        left: 50%;
        transform: translateX(-50%);
        z-index: 9999;
        transition: bottom 0.4s cubic-bezier(0.16, 1, 0.3, 1);
        max-width: 95vw;
      }
      
      .upload-wizard-bar.visible {
        bottom: 20px;
      }
      
      .upload-wizard-content {
        display: flex;
        align-items: center;
        gap: 24px;
        background: linear-gradient(135deg, #1e1e1e 0%, #121212 100%);
        border: 1px solid rgba(255,255,255,0.15);
        border-radius: 20px;
        padding: 16px 24px;
        box-shadow: 
          0 20px 60px rgba(0,0,0,0.5),
          0 0 0 1px rgba(255,255,255,0.05),
          0 0 40px rgba(18, 183, 106, 0.1);
      }
      
      .upload-wizard-header {
        display: flex;
        flex-direction: column;
        gap: 2px;
        border-right: 1px solid rgba(255,255,255,0.1);
        padding-right: 20px;
        min-width: 200px;
      }
      
      .upload-wizard-title {
        font-size: 16px;
        font-weight: 700;
        color: #12B76A;
        white-space: nowrap;
      }
      
      .upload-wizard-subtitle {
        font-size: 12px;
        color: rgba(255,255,255,0.6);
        max-width: 200px;
      }
      
      .upload-wizard-steps {
        display: flex;
        align-items: center;
        gap: 8px;
      }
      
      .upload-wizard-step {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px 16px;
        border-radius: 12px;
        background: rgba(255,255,255,0.03);
        border: 1px solid transparent;
        transition: all 0.3s ease;
      }
      
      .upload-wizard-step.current {
        background: rgba(18, 183, 106, 0.15);
        border-color: rgba(18, 183, 106, 0.4);
        box-shadow: 0 0 20px rgba(18, 183, 106, 0.2);
      }
      
      .upload-wizard-step.ready {
        background: rgba(251, 191, 36, 0.15);
        border-color: rgba(251, 191, 36, 0.4);
      }
      
      .upload-wizard-step.done {
        background: rgba(18, 183, 106, 0.08);
      }
      
      .upload-wizard-step.done .upload-wizard-step-icon {
        background: #12B76A;
        color: white;
      }
      
      .upload-wizard-step-icon {
        width: 32px;
        height: 32px;
        border-radius: 50%;
        background: rgba(255,255,255,0.08);
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 16px;
        transition: all 0.3s ease;
      }
      
      .upload-wizard-step.current .upload-wizard-step-icon {
        background: #12B76A;
        animation: pulse 2s ease-in-out infinite;
      }
      
      @keyframes pulse {
        0%, 100% { box-shadow: 0 0 0 0 rgba(18, 183, 106, 0.4); }
        50% { box-shadow: 0 0 0 8px rgba(18, 183, 106, 0); }
      }
      
      .upload-wizard-step-label {
        font-size: 14px;
        font-weight: 500;
        color: rgba(255,255,255,0.5);
        white-space: nowrap;
      }
      
      .upload-wizard-step.current .upload-wizard-step-label {
        color: #12B76A;
        font-weight: 600;
      }
      
      .upload-wizard-step.done .upload-wizard-step-label {
        color: rgba(255,255,255,0.3);
      }
      
      .upload-wizard-connector {
        width: 24px;
        height: 2px;
        background: rgba(255,255,255,0.1);
        border-radius: 1px;
      }
      
      .upload-wizard-dismiss {
        background: none;
        border: none;
        color: rgba(255,255,255,0.3);
        font-size: 13px;
        cursor: pointer;
        padding: 8px 12px;
        border-radius: 8px;
        transition: all 0.2s;
        margin-left: 8px;
      }
      
      .upload-wizard-dismiss:hover {
        color: rgba(255,255,255,0.6);
        background: rgba(255,255,255,0.05);
      }
      
      /* ========== COMPLETION MODAL ========== */
      .upload-wizard-modal-overlay {
        position: fixed;
        inset: 0;
        z-index: 10000;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(0, 0, 0, 0);
        backdrop-filter: blur(0px);
        transition: all 0.3s ease;
        padding: 20px;
      }
      
      .upload-wizard-modal-overlay.visible {
        background: rgba(0, 0, 0, 0.7);
        backdrop-filter: blur(8px);
      }
      
      .upload-wizard-modal {
        background: linear-gradient(145deg, #1e1e1e 0%, #121212 100%);
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 24px;
        padding: 40px;
        max-width: 450px;
        text-align: center;
        transform: scale(0.9) translateY(20px);
        opacity: 0;
        transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1);
        box-shadow: 0 25px 80px rgba(0,0,0,0.5);
      }
      
      .upload-wizard-modal-overlay.visible .upload-wizard-modal {
        transform: scale(1) translateY(0);
        opacity: 1;
      }
      
      .upload-wizard-modal-icon {
        font-size: 64px;
        margin-bottom: 20px;
      }
      
      .upload-wizard-modal-title {
        font-size: 24px;
        font-weight: 700;
        color: white;
        margin: 0 0 16px;
      }
      
      .upload-wizard-modal-text {
        font-size: 15px;
        color: rgba(255,255,255,0.6);
        line-height: 1.6;
        margin: 0 0 20px;
      }
      
      .upload-wizard-modal-actions {
        display: flex;
        gap: 12px;
        justify-content: center;
        margin-top: 8px;
      }
      
      .upload-wizard-modal-btn {
        border: none;
        border-radius: 12px;
        padding: 14px 24px;
        font-size: 15px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s ease;
        width: 100%;
      }
      
      .upload-wizard-modal-btn--primary {
        background: linear-gradient(135deg, #12B76A 0%, #0EA55E 100%);
        color: white;
      }
      
      .upload-wizard-modal-btn--primary:hover {
        transform: translateY(-2px);
        box-shadow: 0 8px 25px rgba(18, 183, 106, 0.4);
      }
      
      .upload-wizard-modal-btn--secondary {
        background: rgba(255,255,255,0.05);
        color: rgba(255,255,255,0.6);
        border: 1px solid rgba(255,255,255,0.1);
      }
      
      .upload-wizard-modal-btn--secondary:hover {
        background: rgba(255,255,255,0.1);
        color: white;
      }
      
      .upload-wizard-modal-btn--danger {
        background: rgba(239, 68, 68, 0.1);
        color: #EF4444;
        border: 1px solid rgba(239, 68, 68, 0.2);
      }
      
      .upload-wizard-modal-btn--danger:hover {
        background: #EF4444;
        color: white;
      }
      
      /* ========== RESPONSIVE ========== */
      @media (max-width: 900px) {
        .upload-wizard-header {
          display: none;
        }
        
        .upload-wizard-step-label {
          display: none;
        }
        
        .upload-wizard-step {
          padding: 8px;
        }
        
        .upload-wizard-content {
          padding: 12px 16px;
          gap: 12px;
        }
      }
    `
    document.head.appendChild(style)
  }
}
