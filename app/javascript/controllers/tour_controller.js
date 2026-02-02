import { Controller } from "@hotwired/stimulus"

// Professional Guided Tour Controller v4
// Uses RUPI's actual design system colors for perfect integration
export default class extends Controller {
  static values = {
    autoStart: Boolean,
    completed: Boolean
  }

  // Tour steps with explicit positioning preferences
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
      positions: ["right", "bottom", "top"]
    },
    {
      element: "[data-tour-target='netWorth']",
      title: "💰 Net Worth",
      content: "Track your total wealth over time. Assets minus liabilities = your net worth.",
      positions: ["right", "bottom", "left"]
    },
    {
      element: "[data-tour-target='uploadStatement']",
      title: "📄 Import Statements",
      content: "Upload bank statements from HDFC, ICICI, SBI, and 20+ Indian banks. We'll automatically categorize your transactions!",
      positions: ["bottom", "left", "right"]
    },
    {
      element: "[data-tour-target='aiChat']",
      title: "🤖 RUPI AI Assistant",
      content: "Ask questions in plain English! Try: 'How much did I spend last month?' or 'Show my top expenses'.",
      positions: ["left", "top", "bottom"]
    },
    {
      element: "[data-tour-target='sidebar']",
      title: "🧭 Navigation",
      content: "Access Transactions, Reports, and Budgets from the sidebar. Everything you need is one click away!",
      positions: ["right", "bottom", "top"]
    }
  ]

  currentStep = 0
  overlay = null
  ring = null
  tooltip = null
  styleElement = null
  
  // RUPI Design System Colors (from maybe-design-system.css)
  colors = {
    // Dark mode (primary)
    surface: '#0B0B0B',        // bg-surface dark
    container: '#171717',       // bg-container dark (gray-900)
    containerHover: '#242424',  // bg-container-hover dark (gray-800)
    text: '#FFFFFF',           // text-primary dark
    textSecondary: 'rgba(255,255,255,0.7)',
    textTertiary: 'rgba(255,255,255,0.5)',
    border: 'rgba(255,255,255,0.1)',
    success: '#12B76A',        // green-500
    successHover: '#10A861',   // green-600
    overlay: 'rgba(11,11,11,0.92)' // Near-black overlay
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
      this.showSetupPrompt()
      return
    }
    
    this.currentStep = 0
    this.injectStyles()
    this.createOverlay()
    this.createTooltip()
    this.showStep()
    
    document.body.style.overflow = 'hidden'
  }

  showSetupPrompt() {
    const modal = document.createElement("div")
    modal.className = "rupi-tour-modal-overlay"
    modal.innerHTML = `
      <div class="rupi-tour-modal">
        <div class="rupi-tour-modal-icon">💡</div>
        <h3 class="rupi-tour-modal-title">Tour Available After Setup</h3>
        <p class="rupi-tour-modal-text">Load sample data or add an account first, then try the tour again!</p>
        <button class="rupi-tour-modal-btn" onclick="this.closest('.rupi-tour-modal-overlay').remove()">Got it</button>
      </div>
    `
    document.body.appendChild(modal)
  }

  injectStyles() {
    // Remove old styles first
    const oldStyles = document.getElementById("rupi-tour-styles-v4")
    if (oldStyles) oldStyles.remove()
    
    this.styleElement = document.createElement("style")
    this.styleElement.id = "rupi-tour-styles-v4"
    this.styleElement.textContent = `
      /* Dark Overlay - always visible */
      .rupi-tour-overlay {
        position: fixed;
        inset: 0;
        z-index: 99990;
        background: ${this.colors.overlay};
        pointer-events: auto;
      }
      
      /* Spotlight highlight ring around target */
      .rupi-tour-spotlight {
        position: fixed;
        z-index: 99995;
        border: 3px solid ${this.colors.success};
        border-radius: 12px;
        box-shadow: 
          0 0 0 4px rgba(18, 183, 106, 0.25),
          0 0 40px rgba(18, 183, 106, 0.4),
          inset 0 0 0 2000px transparent;
        animation: rupi-spotlight-pulse 2s ease-in-out infinite;
        pointer-events: none;
        transition: all 0.35s cubic-bezier(0.4, 0, 0.2, 1);
        background: transparent;
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
      
      /* Tooltip - matching RUPI dark theme exactly */
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
      
      /* Completion Modal - centered celebration */
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
    `
    document.head.appendChild(this.styleElement)
  }

  createOverlay() {
    // Always create dark overlay for all steps
    this.overlay = document.createElement("div")
    this.overlay.className = "rupi-tour-overlay"
    document.body.appendChild(this.overlay)
    
    // Create highlight ring
    this.ring = document.createElement("div")
    this.ring.className = "rupi-tour-spotlight"
    this.ring.style.display = 'none' // Hidden initially
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
    
    if (!target || !this.isVisible(target)) {
      console.log(`[Tour] Skipping step ${this.currentStep + 1} - element not visible`)
      this.currentStep++
      return this.showStep()
    }

    // For center position, hide spotlight
    if (step.positions[0] === 'center') {
      this.ring.style.display = 'none'
    } else {
      this.ring.style.display = 'block'
      // Scroll element into view first
      target.scrollIntoView({ behavior: 'smooth', block: 'center' })
    }
    
    setTimeout(() => {
      if (step.positions[0] !== 'center') {
        this.updateSpotlight(target)
      }
      this.renderTooltip(step, target)
    }, 350)
  }

  updateSpotlight(target) {
    const rect = target.getBoundingClientRect()
    const padding = 20
    
    // Position the spotlight ring around the target
    this.ring.style.left = `${rect.left - padding}px`
    this.ring.style.top = `${rect.top - padding}px`
    this.ring.style.width = `${rect.width + padding * 2}px`
    this.ring.style.height = `${rect.height + padding * 2}px`
  }

  renderTooltip(step, target) {
    const totalSteps = this.steps.length
    const progressDots = this.steps.map((_, i) => {
      let dotClass = 'rupi-tour-dot'
      if (i < this.currentStep) dotClass += ' completed'
      if (i === this.currentStep) dotClass += ' active'
      return `<div class="${dotClass}"></div>`
    }).join('')
    
    this.tooltip.innerHTML = `
      <div class="rupi-tour-tooltip-header">
        <span class="rupi-tour-tooltip-title">${step.title}</span>
        <span class="rupi-tour-tooltip-step">${this.currentStep + 1} of ${totalSteps}</span>
      </div>
      <p class="rupi-tour-tooltip-content">${step.content}</p>
      <div class="rupi-tour-tooltip-actions">
        <button class="rupi-tour-btn rupi-tour-btn-skip" onclick="window.endRupiTour && window.endRupiTour()">Skip</button>
        <div class="rupi-tour-progress">${progressDots}</div>
        <button class="rupi-tour-btn rupi-tour-btn-next" onclick="window.nextRupiTourStep && window.nextRupiTourStep()">
          ${this.currentStep === totalSteps - 1 ? '✓ Done' : 'Next →'}
        </button>
      </div>
    `
    
    // Position tooltip
    this.positionTooltipWithCollisionDetection(target, step.positions)
    
    window.nextRupiTourStep = () => this.next()
    window.endRupiTour = () => this.finish()
  }

  positionTooltipWithCollisionDetection(target, positions) {
    const targetRect = target.getBoundingClientRect()
    const padding = 24
    const gap = 32
    const spotlightPadding = 20
    
    const tooltipRect = this.tooltip.getBoundingClientRect()
    const tooltipWidth = tooltipRect.width || 380
    const tooltipHeight = tooltipRect.height || 200

    for (const position of positions) {
      const coords = this.calculatePosition(position, targetRect, tooltipWidth, tooltipHeight, gap, padding, spotlightPadding)
      
      if (coords) {
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
        
        const overlaps = this.rectsOverlap(tooltipBounds, targetBounds)
        
        if (!overlaps) {
          this.tooltip.style.left = `${coords.left}px`
          this.tooltip.style.top = `${coords.top}px`
          console.log(`[Tour] Step ${this.currentStep + 1}: Using position "${position}"`)
          return
        }
      }
    }
    
    // Fallback: center on screen
    console.log(`[Tour] Step ${this.currentStep + 1}: Fallback to center`)
    this.tooltip.style.left = `${(window.innerWidth - tooltipWidth) / 2}px`
    this.tooltip.style.top = `${(window.innerHeight - tooltipHeight) / 2}px`
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
    } else if (position === 'top') {
      left = targetRect.left + (targetRect.width / 2) - (tooltipWidth / 2)
      top = targetRect.top - spotlightPadding - gap - tooltipHeight
    }
    
    // Clamp to viewport
    left = Math.max(padding, Math.min(left, window.innerWidth - tooltipWidth - padding))
    top = Math.max(padding, Math.min(top, window.innerHeight - tooltipHeight - padding))
    
    // Check if tooltip would be mostly off-screen
    if (left < 0 || left + tooltipWidth > window.innerWidth ||
        top < 0 || top + tooltipHeight > window.innerHeight) {
      return null
    }
    
    return { left, top }
  }

  rectsOverlap(rect1, rect2) {
    return !(
      rect1.right < rect2.left ||
      rect1.left > rect2.right ||
      rect1.bottom < rect2.top ||
      rect1.top > rect2.bottom
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
    this.showCompletionModal()
  }

  showCompletionModal() {
    const modal = document.createElement("div")
    modal.className = "rupi-tour-modal-overlay"
    modal.innerHTML = `
      <div class="rupi-tour-modal">
        <div class="rupi-tour-modal-icon">🎉</div>
        <h3 class="rupi-tour-modal-title">You're All Set!</h3>
        <p class="rupi-tour-modal-text">You now know the essentials of RUPI. Start by uploading a bank statement or exploring the AI assistant.<br><br>Need help anytime? Click <strong>"Help & FAQ"</strong> from the user menu.</p>
        <button class="rupi-tour-modal-btn" onclick="this.closest('.rupi-tour-modal-overlay').remove()">Let's Go!</button>
      </div>
    `
    document.body.appendChild(modal)
  }

  cleanup() {
    if (this.overlay) {
      this.overlay.remove()
      this.overlay = null
    }
    if (this.ring) {
      this.ring.remove()
      this.ring = null
    }
    if (this.tooltip) {
      this.tooltip.remove()
      this.tooltip = null
    }
    
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
