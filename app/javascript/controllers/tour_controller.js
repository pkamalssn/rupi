import { Controller } from "@hotwired/stimulus"

// Professional Guided Tour Controller v8
// Proper flow: Full tour first, then optional upload wizard at the end
export default class extends Controller {
  static values = {
    autoStart: Boolean,
    completed: Boolean
  }

  // Tour steps - reordered for better flow
  // v8: Upload is just a highlight, final step is celebration with upload CTA
  steps = [
    {
      element: "[data-tour-target='welcome']",
      title: "👋 Welcome to RUPI!",
      content: "Let's take a quick tour of your personal finance dashboard. This will only take a minute!",
      positions: ["center"]
    },
    {
      element: "[data-tour-target='accounts']",
      title: "📊 Your Accounts",
      content: "All your bank accounts, credit cards, loans, and investments in one place. Click any account to see its transactions.",
      positions: ["right", "bottom"]
    },
    {
      element: "[data-section-key='net_worth_chart']",
      title: "💰 Net Worth",
      content: "Track your total wealth over time. This shows your assets minus liabilities = your net worth.",
      positions: ["left", "bottom", "top"]
    },
    {
      element: "[data-tour-target='aiChat']",
      title: "🤖 RUPI AI Assistant",
      content: "Ask questions in plain English! Try: 'How much did I spend last month?' or 'Show my top expenses'.",
      positions: ["left", "bottom"]
    },
    {
      element: "[data-tour-target='sidebar']",
      title: "🧭 Navigation",
      content: "Access Transactions, Reports, and Budgets from the sidebar. Everything you need is one click away!",
      positions: ["right", "bottom"]
    },
    {
      element: "[data-tour-target='uploadStatement']",
      title: "📄 Upload Your Statements",
      content: "When you're ready, upload your bank statements from HDFC, ICICI, SBI, Axis, and 20+ Indian banks. We'll automatically import and categorize all your transactions!",
      positions: ["bottom", "bottom-start", "left"],
      isFinal: true  // Mark this as final step
    }
  ]

  currentStep = 0
  overlayTop = null
  overlayBottom = null
  overlayLeft = null
  overlayRight = null
  ring = null
  tooltip = null
  styleElement = null
  
  // RUPI Design System Colors
  colors = {
    surface: '#0B0B0B',
    container: '#171717',
    containerHover: '#242424',
    text: '#FFFFFF',
    textSecondary: 'rgba(255,255,255,0.7)',
    textTertiary: 'rgba(255,255,255,0.5)',
    border: 'rgba(255,255,255,0.1)',
    success: '#12B76A',
    successHover: '#10A861',
    overlay: 'rgba(11,11,11,0.92)'
  }

  connect() {
    window.startRupiTour = () => this.start()
    
    if (this.autoStartValue && !this.completedValue) {
      setTimeout(() => this.start(), 800)
    }
  }

  disconnect() {
    this.cleanup()
    delete window.startRupiTour
  }

  start() {
    const hasElements = this.steps.some(step => {
      const el = document.querySelector(step.element)
      return el && this.isVisible(el)
    })
    
    if (!hasElements) {
      this.showModal("💡", "Tour Available After Setup", "Load sample data or add an account first, then try the tour again!", "Got it")
      return
    }
    
    this.currentStep = 0
    this.injectStyles()
    this.createOverlays()
    this.createTooltip()
    this.showStep()
    
    document.body.style.overflow = 'hidden'
  }

  injectStyles() {
    const oldStyles = document.getElementById("rupi-tour-styles-v5")
    if (oldStyles) oldStyles.remove()
    
    this.styleElement = document.createElement("style")
    this.styleElement.id = "rupi-tour-styles-v5"
    this.styleElement.textContent = `
      /* Four-panel overlay system */
      .rupi-tour-overlay-panel {
        position: fixed;
        background: ${this.colors.overlay};
        z-index: 99990;
        pointer-events: auto;
        transition: all 0.35s ease-out;
      }
      
      /* Spotlight highlight ring */
      .rupi-tour-spotlight {
        position: fixed;
        z-index: 99995;
        border: 3px solid ${this.colors.success};
        border-radius: 12px;
        box-shadow: 
          0 0 0 4px rgba(18, 183, 106, 0.25),
          0 0 40px rgba(18, 183, 106, 0.4);
        animation: rupi-spotlight-pulse 2s ease-in-out infinite;
        pointer-events: none;
        transition: all 0.35s ease-out;
      }
      
      @keyframes rupi-spotlight-pulse {
        0%, 100% { 
          box-shadow: 
            0 0 0 4px rgba(18, 183, 106, 0.25),
            0 0 40px rgba(18, 183, 106, 0.4);
        }
        50% { 
          box-shadow: 
            0 0 0 8px rgba(18, 183, 106, 0.15),
            0 0 60px rgba(18, 183, 106, 0.5);
        }
      }
      
      /* Tooltip */
      .rupi-tour-tooltip {
        position: fixed;
        z-index: 99999;
        width: 380px;
        max-width: calc(100vw - 40px);
        background: ${this.colors.container};
        border: 1px solid ${this.colors.border};
        border-radius: 16px;
        padding: 24px;
        box-shadow: 
          0 25px 60px -12px rgba(0, 0, 0, 0.7),
          0 0 0 1px rgba(255, 255, 255, 0.05);
        animation: rupi-tooltip-enter 0.35s cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      
      @keyframes rupi-tooltip-enter {
        from { opacity: 0; transform: translateY(15px) scale(0.9); }
        to { opacity: 1; transform: translateY(0) scale(1); }
      }
      
      .rupi-tour-tooltip-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 14px;
      }
      
      .rupi-tour-tooltip-title {
        font-size: 18px;
        font-weight: 600;
        color: ${this.colors.text};
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-tour-tooltip-step {
        font-size: 12px;
        font-weight: 500;
        color: ${this.colors.textSecondary};
        background: ${this.colors.containerHover};
        padding: 5px 12px;
        border-radius: 20px;
      }
      
      .rupi-tour-tooltip-content {
        font-size: 15px;
        color: ${this.colors.textSecondary};
        line-height: 1.65;
        margin-bottom: 22px;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-tour-tooltip-actions {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 16px;
      }
      
      .rupi-tour-btn {
        padding: 11px 22px;
        border-radius: 10px;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
        border: none;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-tour-btn-skip {
        background: transparent;
        color: ${this.colors.textTertiary};
      }
      
      .rupi-tour-btn-skip:hover {
        color: ${this.colors.text};
        background: ${this.colors.containerHover};
      }
      
      .rupi-tour-btn-next {
        background: ${this.colors.success};
        color: white;
        min-width: 110px;
      }
      
      .rupi-tour-btn-next:hover {
        background: ${this.colors.successHover};
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(18, 183, 106, 0.45);
      }
      
      .rupi-tour-progress {
        display: flex;
        gap: 8px;
        justify-content: center;
        flex: 1;
      }
      
      .rupi-tour-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: ${this.colors.containerHover};
        transition: all 0.3s;
      }
      
      .rupi-tour-dot.active {
        background: ${this.colors.success};
        transform: scale(1.3);
        box-shadow: 0 0 10px rgba(18, 183, 106, 0.6);
      }
      
      .rupi-tour-dot.completed {
        background: ${this.colors.success};
        opacity: 0.4;
      }
      
      /* Modal */
      .rupi-tour-modal-overlay {
        position: fixed;
        inset: 0;
        z-index: 99999;
        background: ${this.colors.overlay};
        display: flex;
        align-items: center;
        justify-content: center;
        animation: rupi-modal-fade 0.3s ease-out;
        padding: 20px;
      }
      
      @keyframes rupi-modal-fade {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      
      .rupi-tour-modal {
        background: ${this.colors.container};
        border: 1px solid ${this.colors.border};
        border-radius: 24px;
        padding: 48px 40px;
        text-align: center;
        max-width: 420px;
        width: 100%;
        animation: rupi-modal-enter 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      
      @keyframes rupi-modal-enter {
        from { opacity: 0; transform: scale(0.7) translateY(30px); }
        to { opacity: 1; transform: scale(1) translateY(0); }
      }
      
      .rupi-tour-modal-icon {
        font-size: 72px;
        margin-bottom: 24px;
        display: block;
      }
      
      .rupi-tour-modal-title {
        font-size: 28px;
        font-weight: 700;
        color: ${this.colors.text};
        margin-bottom: 16px;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-tour-modal-text {
        font-size: 16px;
        color: ${this.colors.textSecondary};
        line-height: 1.7;
        margin-bottom: 32px;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-tour-modal-btn {
        background: ${this.colors.success};
        color: white;
        border: none;
        padding: 16px 48px;
        border-radius: 12px;
        font-size: 17px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-tour-modal-btn:hover {
        background: ${this.colors.successHover};
        transform: translateY(-3px);
        box-shadow: 0 10px 30px rgba(18, 183, 106, 0.5);
      }
      
      /* Final step buttons */
      .rupi-tour-final-btn {
        width: 100%;
        padding: 14px 20px;
        border-radius: 10px;
        font-size: 15px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s ease;
        border: none;
        font-family: 'Geist', system-ui, sans-serif;
      }
      
      .rupi-tour-final-btn--primary {
        background: linear-gradient(135deg, ${this.colors.success} 0%, ${this.colors.successHover} 100%);
        color: white;
        box-shadow: 0 4px 12px rgba(18, 183, 106, 0.3);
      }
      
      .rupi-tour-final-btn--primary:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(18, 183, 106, 0.4);
      }
      
      .rupi-tour-final-btn--secondary {
        background: transparent;
        color: ${this.colors.textSecondary};
        border: 1px solid ${this.colors.border};
      }
      
      .rupi-tour-final-btn--secondary:hover {
        background: ${this.colors.containerHover};
        color: ${this.colors.text};
      }
    `
    document.head.appendChild(this.styleElement)
  }

  // Create 4 overlay panels around the spotlight area
  createOverlays() {
    this.overlayTop = document.createElement("div")
    this.overlayTop.className = "rupi-tour-overlay-panel"
    document.body.appendChild(this.overlayTop)
    
    this.overlayBottom = document.createElement("div")
    this.overlayBottom.className = "rupi-tour-overlay-panel"
    document.body.appendChild(this.overlayBottom)
    
    this.overlayLeft = document.createElement("div")
    this.overlayLeft.className = "rupi-tour-overlay-panel"
    document.body.appendChild(this.overlayLeft)
    
    this.overlayRight = document.createElement("div")
    this.overlayRight.className = "rupi-tour-overlay-panel"
    document.body.appendChild(this.overlayRight)
    
    // Create highlight ring
    this.ring = document.createElement("div")
    this.ring.className = "rupi-tour-spotlight"
    this.ring.style.display = 'none'
    document.body.appendChild(this.ring)
  }

  createTooltip() {
    this.tooltip = document.createElement("div")
    this.tooltip.className = "rupi-tour-tooltip"
    document.body.appendChild(this.tooltip)
  }

  showStep() {
    const step = this.steps[this.currentStep]
    if (!step) return this.finish()

    const target = document.querySelector(step.element)
    
    console.log(`[Tour] Step ${this.currentStep + 1}: Looking for "${step.element}"`)
    console.log(`[Tour] Target found:`, target)
    
    if (!target || !this.isVisible(target)) {
      console.log(`[Tour] Skipping step ${this.currentStep + 1} - element not visible: ${step.element}`)
      this.currentStep++
      return this.showStep()
    }
    
    const rect = target.getBoundingClientRect()
    console.log(`[Tour] Target rect:`, { left: rect.left, top: rect.top, width: rect.width, height: rect.height })

    // For center position, cover entire screen
    if (step.positions[0] === 'center') {
      this.ring.style.display = 'none'
      this.positionOverlaysFullScreen()
    } else {
      this.ring.style.display = 'block'
      target.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
    
    setTimeout(() => {
      if (step.positions[0] !== 'center') {
        this.positionSpotlight(target)
      }
      this.renderTooltip(step, target)
    }, 350)
  }

  positionOverlaysFullScreen() {
    // Cover entire viewport for center steps
    this.overlayTop.style.cssText = `top:0;left:0;right:0;bottom:0;`
    this.overlayBottom.style.cssText = `display:none;`
    this.overlayLeft.style.cssText = `display:none;`
    this.overlayRight.style.cssText = `display:none;`
  }

  positionSpotlight(target) {
    const rect = target.getBoundingClientRect()
    const padding = 16
    
    // Spotlight dimensions
    const spotLeft = rect.left - padding
    const spotTop = rect.top - padding
    const spotRight = rect.right + padding
    const spotBottom = rect.bottom + padding
    const spotWidth = spotRight - spotLeft
    const spotHeight = spotBottom - spotTop
    
    // Position the 4 overlay panels around the spotlight hole
    // Top panel: covers from top of screen to top of spotlight
    this.overlayTop.style.cssText = `
      top: 0;
      left: 0;
      right: 0;
      height: ${spotTop}px;
    `
    
    // Bottom panel: covers from bottom of spotlight to bottom of screen
    this.overlayBottom.style.cssText = `
      top: ${spotBottom}px;
      left: 0;
      right: 0;
      bottom: 0;
      display: block;
    `
    
    // Left panel: covers left side of spotlight row
    this.overlayLeft.style.cssText = `
      top: ${spotTop}px;
      left: 0;
      width: ${spotLeft}px;
      height: ${spotHeight}px;
      display: block;
    `
    
    // Right panel: covers right side of spotlight row
    this.overlayRight.style.cssText = `
      top: ${spotTop}px;
      left: ${spotRight}px;
      right: 0;
      height: ${spotHeight}px;
      display: block;
    `
    
    // Position the ring
    this.ring.style.left = `${spotLeft}px`
    this.ring.style.top = `${spotTop}px`
    this.ring.style.width = `${spotWidth}px`
    this.ring.style.height = `${spotHeight}px`
  }

  renderTooltip(step, target) {
    const totalSteps = this.steps.length
    const progressDots = this.steps.map((_, i) => {
      let dotClass = 'rupi-tour-dot'
      if (i < this.currentStep) dotClass += ' completed'
      if (i === this.currentStep) dotClass += ' active'
      return `<div class="${dotClass}"></div>`
    }).join('')
    
    // Check if this is the final upload step
    const isFinalStep = step.isFinal === true
    
    this.tooltip.innerHTML = `
      <div class="rupi-tour-tooltip-header">
        <span class="rupi-tour-tooltip-title">${step.title}</span>
        <span class="rupi-tour-tooltip-step">${this.currentStep + 1} of ${totalSteps}</span>
      </div>
      <p class="rupi-tour-tooltip-content">${step.content}</p>
      ${isFinalStep ? `
        <div style="display: flex; flex-direction: column; gap: 8px; margin-bottom: 16px;">
          <button class="rupi-tour-final-btn rupi-tour-final-btn--primary" id="start-upload-now">
            📄 Upload Statement Now
          </button>
          <button class="rupi-tour-final-btn rupi-tour-final-btn--secondary" id="finish-tour-later">
            Maybe Later
          </button>
        </div>
      ` : `
        <div class="rupi-tour-tooltip-actions">
          <button class="rupi-tour-btn rupi-tour-btn-skip" onclick="window.endRupiTour && window.endRupiTour()">Skip</button>
          <div class="rupi-tour-progress">${progressDots}</div>
          <button class="rupi-tour-btn rupi-tour-btn-next" onclick="window.nextRupiTourStep && window.nextRupiTourStep()">
            Next →
          </button>
        </div>
      `}
    `
    
    // Add final step button handlers
    if (isFinalStep) {
      const uploadBtn = this.tooltip.querySelector('#start-upload-now')
      const laterBtn = this.tooltip.querySelector('#finish-tour-later')
      
      if (uploadBtn) {
        uploadBtn.addEventListener('click', () => this.startUploadWizard())
      }
      if (laterBtn) {
        laterBtn.addEventListener('click', () => this.finishWithMessage())
      }
    }
    
    this.positionTooltip(target, step.positions)
    
    window.nextRupiTourStep = () => this.next()
    window.endRupiTour = () => this.finish()
  }

  startUploadWizard() {
    // Mark tour as complete
    this.markTourComplete()
    
    // Start upload wizard tour
    localStorage.setItem('rupi_upload_tour', JSON.stringify({ step: 0, active: true }))
    
    // Navigate to upload page
    this.cleanup()
    window.location.href = '/bank_statement/new'
  }
  
  finishWithMessage() {
    this.markTourComplete()
    this.showCompletionModal()
  }
  
  markTourComplete() {
    this.cleanup()
    this.saveTourCompleted()
  }
  
  showCompletionModal() {
    this.showModal(
      "🎉", 
      "You're All Set!", 
      "You now know the essentials of RUPI. When you're ready, upload your bank statements to see your real financial data.<br><br>Need help anytime? Click <strong>\"Help & FAQ\"</strong> from the user menu.", 
      "Start Exploring!"
    )
  }

  positionTooltip(target, positions) {
    const targetRect = target.getBoundingClientRect()
    const padding = 24
    const gap = 32
    const spotlightPadding = 16
    
    // Force tooltip to render to get dimensions
    this.tooltip.style.visibility = 'hidden'
    this.tooltip.style.left = '0'
    this.tooltip.style.top = '0'
    
    const tooltipRect = this.tooltip.getBoundingClientRect()
    const tooltipWidth = tooltipRect.width
    const tooltipHeight = tooltipRect.height

    for (const position of positions) {
      const coords = this.calculatePosition(position, targetRect, tooltipWidth, tooltipHeight, gap, padding, spotlightPadding)
      
      if (coords && !this.wouldOverlap(coords, tooltipWidth, tooltipHeight, targetRect, spotlightPadding)) {
        this.tooltip.style.left = `${coords.left}px`
        this.tooltip.style.top = `${coords.top}px`
        this.tooltip.style.visibility = 'visible'
        console.log(`[Tour] Step ${this.currentStep + 1}: Using position "${position}"`)
        return
      }
    }
    
    // Fallback: center on screen
    console.log(`[Tour] Step ${this.currentStep + 1}: Fallback to center`)
    this.tooltip.style.left = `${(window.innerWidth - tooltipWidth) / 2}px`
    this.tooltip.style.top = `${(window.innerHeight - tooltipHeight) / 2}px`
    this.tooltip.style.visibility = 'visible'
  }

  calculatePosition(position, targetRect, tooltipWidth, tooltipHeight, gap, padding, spotlightPadding) {
    let left, top
    
    if (position === 'center') {
      return {
        left: (window.innerWidth - tooltipWidth) / 2,
        top: (window.innerHeight - tooltipHeight) / 2
      }
    }
    
    if (position === 'right') {
      left = targetRect.right + spotlightPadding + gap
      top = targetRect.top + (targetRect.height / 2) - (tooltipHeight / 2)
    } else if (position === 'left') {
      left = targetRect.left - spotlightPadding - gap - tooltipWidth
      top = targetRect.top + (targetRect.height / 2) - (tooltipHeight / 2)
    } else if (position === 'bottom') {
      left = targetRect.left + (targetRect.width / 2) - (tooltipWidth / 2)
      top = targetRect.bottom + spotlightPadding + gap
    } else if (position === 'bottom-start') {
      // Align tooltip left edge with target left edge
      left = targetRect.left - spotlightPadding
      top = targetRect.bottom + spotlightPadding + gap
    } else if (position === 'bottom-end') {
      // Align tooltip right edge with target right edge
      left = targetRect.right + spotlightPadding - tooltipWidth
      top = targetRect.bottom + spotlightPadding + gap
    } else if (position === 'top') {
      left = targetRect.left + (targetRect.width / 2) - (tooltipWidth / 2)
      top = targetRect.top - spotlightPadding - gap - tooltipHeight
    } else if (position === 'top-start') {
      left = targetRect.left - spotlightPadding
      top = targetRect.top - spotlightPadding - gap - tooltipHeight
    }
    
    // Clamp to viewport
    left = Math.max(padding, Math.min(left, window.innerWidth - tooltipWidth - padding))
    top = Math.max(padding, Math.min(top, window.innerHeight - tooltipHeight - padding))
    
    return { left, top }
  }

  wouldOverlap(coords, tooltipWidth, tooltipHeight, targetRect, spotlightPadding) {
    const tooltipBounds = {
      left: coords.left,
      right: coords.left + tooltipWidth,
      top: coords.top,
      bottom: coords.top + tooltipHeight
    }
    
    const targetBounds = {
      left: targetRect.left - spotlightPadding,
      right: targetRect.right + spotlightPadding,
      top: targetRect.top - spotlightPadding,
      bottom: targetRect.bottom + spotlightPadding
    }
    
    return !(
      tooltipBounds.right < targetBounds.left ||
      tooltipBounds.left > targetBounds.right ||
      tooltipBounds.bottom < targetBounds.top ||
      tooltipBounds.top > targetBounds.bottom
    )
  }

  isVisible(el) {
    if (!el) return false
    const rect = el.getBoundingClientRect()
    const style = window.getComputedStyle(el)
    return (
      rect.width > 0 &&
      rect.height > 0 &&
      style.display !== 'none' &&
      style.visibility !== 'hidden' &&
      style.opacity !== '0'
    )
  }

  next() {
    this.currentStep++
    if (this.currentStep >= this.steps.length) {
      this.finish()
    } else {
      this.showStep()
    }
  }

  finish() {
    this.cleanup()
    this.saveTourCompleted()
    this.showModal("🎉", "You're All Set!", "You now know the essentials of RUPI. Start by uploading a bank statement or exploring the AI assistant.<br><br>Need help anytime? Click <strong>\"Help & FAQ\"</strong> from the user menu.", "Let's Go!")
  }

  showModal(icon, title, text, buttonText) {
    const modal = document.createElement("div")
    modal.className = "rupi-tour-modal-overlay"
    modal.innerHTML = `
      <div class="rupi-tour-modal">
        <div class="rupi-tour-modal-icon">${icon}</div>
        <h3 class="rupi-tour-modal-title">${title}</h3>
        <p class="rupi-tour-modal-text">${text}</p>
        <button class="rupi-tour-modal-btn" onclick="this.closest('.rupi-tour-modal-overlay').remove()">${buttonText}</button>
      </div>
    `
    document.body.appendChild(modal)
  }

  cleanup() {
    if (this.overlayTop) { this.overlayTop.remove(); this.overlayTop = null }
    if (this.overlayBottom) { this.overlayBottom.remove(); this.overlayBottom = null }
    if (this.overlayLeft) { this.overlayLeft.remove(); this.overlayLeft = null }
    if (this.overlayRight) { this.overlayRight.remove(); this.overlayRight = null }
    if (this.ring) { this.ring.remove(); this.ring = null }
    if (this.tooltip) { this.tooltip.remove(); this.tooltip = null }
    
    document.body.style.overflow = ''
    delete window.nextRupiTourStep
    delete window.endRupiTour
  }

  async saveTourCompleted() {
    try {
      await fetch("/dashboard/preferences", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({
          preferences: { tour_completed: true }
        })
      })
    } catch (e) {
      console.log("Could not save tour preference")
    }
  }
}
