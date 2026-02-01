import { Controller } from "@hotwired/stimulus"

// Professional Guided Tour Controller
// Provides a step-by-step walkthrough with spotlight effect
export default class extends Controller {
  static values = {
    autoStart: Boolean,
    completed: Boolean
  }

  // Tour steps configuration
  steps = [
    {
      element: "[data-tour-target='welcome']",
      title: "👋 Welcome to RUPI!",
      content: "Let's take a quick tour of your personal finance dashboard. This will only take a minute!",
      position: "center"
    },
    {
      element: "[data-tour-target='accounts']",
      title: "📊 Your Accounts",
      content: "All your bank accounts, credit cards, loans, and investments in one place. Click any account to see its transactions.",
      position: "right"
    },
    {
      element: "[data-tour-target='netWorth']",
      title: "💰 Net Worth",
      content: "Track your total wealth over time. Assets minus liabilities = your net worth.",
      position: "bottom"
    },
    {
      element: "[data-tour-target='uploadStatement']",
      title: "📄 Import Statements",
      content: "Upload bank statements from HDFC, ICICI, SBI, and 20+ Indian banks. We'll automatically categorize your transactions!",
      position: "bottom"
    },
    {
      element: "[data-tour-target='aiChat']",
      title: "🤖 RUPI AI Assistant",
      content: "Ask questions in plain English! Try: 'How much did I spend last month?' or 'Show my top expenses'.",
      position: "left"
    },
    {
      element: "[data-tour-target='sidebar']",
      title: "🧭 Navigation",
      content: "Access Transactions, Reports, and Budgets from the sidebar. Everything you need is one click away!",
      position: "right"
    }
  ]

  currentStep = 0
  spotlightOverlay = null
  tooltip = null
  styleElement = null

  connect() {
    // Make tour accessible globally for menu buttons
    window.startRupiTour = () => this.start()
    
    if (this.autoStartValue && !this.completedValue) {
      // Delay to let page render
      setTimeout(() => this.start(), 800)
    }
  }

  disconnect() {
    this.cleanup()
    delete window.startRupiTour
  }

  start() {
    // Check if at least one tour element exists
    const hasElements = this.steps.some(step => {
      const el = document.querySelector(step.element)
      return el && this.isVisible(el)
    })
    
    if (!hasElements) {
      this.showSetupPrompt()
      return
    }
    
    this.currentStep = 0
    this.injectStyles()
    this.createSpotlightOverlay()
    this.createTooltip()
    this.showStep()
    
    // Prevent body scroll
    document.body.style.overflow = 'hidden'
  }

  showSetupPrompt() {
    const notification = document.createElement("div")
    notification.className = "tour-notification"
    notification.innerHTML = `
      <div class="tour-notification-content">
        <span class="tour-notification-icon">💡</span>
        <div>
          <p class="tour-notification-title">Tour Available After Setup</p>
          <p class="tour-notification-text">Load sample data or add an account first, then try the tour again!</p>
        </div>
        <button onclick="this.closest('.tour-notification').remove()" class="tour-notification-close">✕</button>
      </div>
    `
    document.body.appendChild(notification)
    setTimeout(() => notification.remove(), 5000)
  }

  injectStyles() {
    if (document.getElementById("rupi-tour-styles")) return
    
    this.styleElement = document.createElement("style")
    this.styleElement.id = "rupi-tour-styles"
    this.styleElement.textContent = `
      /* Spotlight Overlay - covers everything except highlighted element */
      .tour-spotlight-overlay {
        position: fixed;
        inset: 0;
        z-index: 99990;
        pointer-events: none;
      }
      
      .tour-spotlight-overlay::before {
        content: '';
        position: absolute;
        inset: 0;
        background: rgba(0, 0, 0, 0.75);
        pointer-events: auto;
      }
      
      /* Spotlight cutout - transparent hole */
      .tour-spotlight {
        position: absolute;
        border-radius: 12px;
        box-shadow: 
          0 0 0 9999px rgba(0, 0, 0, 0.75),
          0 0 30px 5px rgba(16, 185, 129, 0.4);
        transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
        pointer-events: none;
        z-index: 99991;
      }
      
      /* Pulsing ring around spotlight */
      .tour-spotlight::after {
        content: '';
        position: absolute;
        inset: -4px;
        border: 2px solid rgba(16, 185, 129, 0.6);
        border-radius: 16px;
        animation: tour-pulse 2s ease-in-out infinite;
      }
      
      @keyframes tour-pulse {
        0%, 100% { opacity: 1; transform: scale(1); }
        50% { opacity: 0.5; transform: scale(1.02); }
      }
      
      /* Tooltip */
      .tour-tooltip {
        position: fixed;
        z-index: 99999;
        width: 340px;
        max-width: calc(100vw - 32px);
        background: linear-gradient(145deg, #1a1a2e 0%, #16213e 100%);
        border: 1px solid rgba(255, 255, 255, 0.1);
        border-radius: 16px;
        padding: 24px;
        box-shadow: 
          0 25px 50px -12px rgba(0, 0, 0, 0.5),
          0 0 0 1px rgba(255, 255, 255, 0.05);
        animation: tour-tooltip-enter 0.3s ease-out;
      }
      
      @keyframes tour-tooltip-enter {
        from { opacity: 0; transform: translateY(10px); }
        to { opacity: 1; transform: translateY(0); }
      }
      
      .tour-tooltip-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 12px;
      }
      
      .tour-tooltip-title {
        font-size: 18px;
        font-weight: 600;
        color: #ffffff;
      }
      
      .tour-tooltip-step {
        font-size: 12px;
        color: rgba(255, 255, 255, 0.5);
        background: rgba(255, 255, 255, 0.1);
        padding: 4px 10px;
        border-radius: 12px;
      }
      
      .tour-tooltip-content {
        font-size: 14px;
        color: rgba(255, 255, 255, 0.8);
        line-height: 1.6;
        margin-bottom: 20px;
      }
      
      .tour-tooltip-actions {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
      }
      
      .tour-btn {
        padding: 10px 20px;
        border-radius: 10px;
        font-size: 14px;
        font-weight: 500;
        cursor: pointer;
        transition: all 0.2s;
        border: none;
      }
      
      .tour-btn-skip {
        background: transparent;
        color: rgba(255, 255, 255, 0.6);
      }
      
      .tour-btn-skip:hover {
        color: #ffffff;
        background: rgba(255, 255, 255, 0.1);
      }
      
      .tour-btn-next {
        background: linear-gradient(135deg, #10b981 0%, #059669 100%);
        color: white;
        flex: 1;
        max-width: 120px;
      }
      
      .tour-btn-next:hover {
        transform: translateY(-1px);
        box-shadow: 0 4px 12px rgba(16, 185, 129, 0.4);
      }
      
      .tour-progress {
        display: flex;
        gap: 6px;
        justify-content: center;
        flex: 1;
      }
      
      .tour-progress-dot {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        background: rgba(255, 255, 255, 0.2);
        transition: all 0.3s;
      }
      
      .tour-progress-dot.active {
        background: #10b981;
        transform: scale(1.2);
      }
      
      .tour-progress-dot.completed {
        background: rgba(16, 185, 129, 0.5);
      }
      
      /* Arrow pointing to element */
      .tour-tooltip[data-position="right"]::before,
      .tour-tooltip[data-position="left"]::before,
      .tour-tooltip[data-position="top"]::before,
      .tour-tooltip[data-position="bottom"]::before {
        content: '';
        position: absolute;
        width: 0;
        height: 0;
        border: 10px solid transparent;
      }
      
      .tour-tooltip[data-position="right"]::before {
        left: -20px;
        top: 50%;
        transform: translateY(-50%);
        border-right-color: #1a1a2e;
      }
      
      .tour-tooltip[data-position="left"]::before {
        right: -20px;
        top: 50%;
        transform: translateY(-50%);
        border-left-color: #1a1a2e;
      }
      
      .tour-tooltip[data-position="bottom"]::before {
        top: -20px;
        left: 50%;
        transform: translateX(-50%);
        border-bottom-color: #1a1a2e;
      }
      
      .tour-tooltip[data-position="top"]::before {
        bottom: -20px;
        left: 50%;
        transform: translateX(-50%);
        border-top-color: #1a1a2e;
      }
      
      /* Notification toast */
      .tour-notification {
        position: fixed;
        top: 20px;
        right: 20px;
        z-index: 99999;
        background: linear-gradient(145deg, #1a1a2e 0%, #16213e 100%);
        border: 1px solid rgba(255, 255, 255, 0.1);
        border-radius: 12px;
        padding: 16px 20px;
        max-width: 360px;
        animation: tour-tooltip-enter 0.3s ease-out;
      }
      
      .tour-notification-content {
        display: flex;
        align-items: flex-start;
        gap: 12px;
      }
      
      .tour-notification-icon {
        font-size: 24px;
      }
      
      .tour-notification-title {
        font-weight: 600;
        color: #ffffff;
        font-size: 14px;
        margin-bottom: 4px;
      }
      
      .tour-notification-text {
        font-size: 13px;
        color: rgba(255, 255, 255, 0.7);
      }
      
      .tour-notification-close {
        background: none;
        border: none;
        color: rgba(255, 255, 255, 0.5);
        cursor: pointer;
        font-size: 16px;
        padding: 0;
        margin-left: auto;
      }
      
      .tour-notification-close:hover {
        color: #ffffff;
      }
    `
    document.head.appendChild(this.styleElement)
  }

  createSpotlightOverlay() {
    this.spotlightOverlay = document.createElement("div")
    this.spotlightOverlay.className = "tour-spotlight-overlay"
    this.spotlightOverlay.innerHTML = '<div class="tour-spotlight"></div>'
    
    // Click on overlay to close
    this.spotlightOverlay.addEventListener("click", (e) => {
      if (e.target === this.spotlightOverlay || e.target.classList.contains('tour-spotlight-overlay')) {
        // Don't close, just ignore clicks on overlay
      }
    })
    
    document.body.appendChild(this.spotlightOverlay)
  }

  createTooltip() {
    this.tooltip = document.createElement("div")
    this.tooltip.className = "tour-tooltip"
    document.body.appendChild(this.tooltip)
  }

  showStep() {
    const step = this.steps[this.currentStep]
    if (!step) return this.finish()

    const target = document.querySelector(step.element)
    
    // Skip invisible elements
    if (!target || !this.isVisible(target)) {
      console.log(`[Tour] Skipping step ${this.currentStep + 1} - element not visible`)
      this.currentStep++
      return this.showStep()
    }

    // Scroll element into view first
    target.scrollIntoView({ behavior: 'smooth', block: 'center' })
    
    // Wait for scroll, then position spotlight and tooltip
    setTimeout(() => {
      this.positionSpotlight(target)
      this.renderTooltip(step, target)
    }, 300)
  }

  positionSpotlight(target) {
    const spotlight = this.spotlightOverlay.querySelector('.tour-spotlight')
    const rect = target.getBoundingClientRect()
    const padding = 12
    
    spotlight.style.left = `${rect.left - padding}px`
    spotlight.style.top = `${rect.top - padding}px`
    spotlight.style.width = `${rect.width + padding * 2}px`
    spotlight.style.height = `${rect.height + padding * 2}px`
  }

  renderTooltip(step, target) {
    const totalSteps = this.steps.length
    const progressDots = this.steps.map((_, i) => {
      let dotClass = 'tour-progress-dot'
      if (i < this.currentStep) dotClass += ' completed'
      if (i === this.currentStep) dotClass += ' active'
      return `<div class="${dotClass}"></div>`
    }).join('')
    
    this.tooltip.setAttribute('data-position', step.position)
    this.tooltip.innerHTML = `
      <div class="tour-tooltip-header">
        <span class="tour-tooltip-title">${step.title}</span>
        <span class="tour-tooltip-step">${this.currentStep + 1} of ${totalSteps}</span>
      </div>
      <p class="tour-tooltip-content">${step.content}</p>
      <div class="tour-tooltip-actions">
        <button class="tour-btn tour-btn-skip" onclick="window.endRupiTour && window.endRupiTour()">Skip</button>
        <div class="tour-progress">${progressDots}</div>
        <button class="tour-btn tour-btn-next" onclick="window.nextRupiTourStep && window.nextRupiTourStep()">
          ${this.currentStep === totalSteps - 1 ? '✓ Done' : 'Next →'}
        </button>
      </div>
    `
    
    // Position tooltip
    this.positionTooltip(target, step.position)
    
    // Expose next/skip functions globally
    window.nextRupiTourStep = () => this.next()
    window.endRupiTour = () => this.finish()
  }

  positionTooltip(target, position) {
    const rect = target.getBoundingClientRect()
    const tooltipRect = this.tooltip.getBoundingClientRect()
    const gap = 24
    const padding = 16

    let left, top

    if (position === 'center') {
      left = (window.innerWidth - tooltipRect.width) / 2
      top = (window.innerHeight - tooltipRect.height) / 2
    } else if (position === 'right') {
      left = rect.right + gap
      top = rect.top + (rect.height / 2) - (tooltipRect.height / 2)
    } else if (position === 'left') {
      left = rect.left - tooltipRect.width - gap
      top = rect.top + (rect.height / 2) - (tooltipRect.height / 2)
    } else if (position === 'bottom') {
      left = rect.left + (rect.width / 2) - (tooltipRect.width / 2)
      top = rect.bottom + gap
    } else if (position === 'top') {
      left = rect.left + (rect.width / 2) - (tooltipRect.width / 2)
      top = rect.top - tooltipRect.height - gap
    }

    // Keep within viewport
    left = Math.max(padding, Math.min(left, window.innerWidth - tooltipRect.width - padding))
    top = Math.max(padding, Math.min(top, window.innerHeight - tooltipRect.height - padding))

    this.tooltip.style.left = `${left}px`
    this.tooltip.style.top = `${top}px`
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
    
    // Show completion message
    this.showCompletionMessage()
  }

  showCompletionMessage() {
    const notification = document.createElement("div")
    notification.className = "tour-notification"
    notification.innerHTML = `
      <div class="tour-notification-content">
        <span class="tour-notification-icon">🎉</span>
        <div>
          <p class="tour-notification-title">Tour Complete!</p>
          <p class="tour-notification-text">You're all set to manage your finances with RUPI. Need help? Click "Help & FAQ" anytime!</p>
        </div>
        <button onclick="this.closest('.tour-notification').remove()" class="tour-notification-close">✕</button>
      </div>
    `
    document.body.appendChild(notification)
    setTimeout(() => notification.remove(), 5000)
  }

  cleanup() {
    if (this.spotlightOverlay) {
      this.spotlightOverlay.remove()
      this.spotlightOverlay = null
    }
    if (this.tooltip) {
      this.tooltip.remove()
      this.tooltip = null
    }
    
    // Restore body scroll
    document.body.style.overflow = ''
    
    // Clean up global functions
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
