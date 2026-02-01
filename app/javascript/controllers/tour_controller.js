import { Controller } from "@hotwired/stimulus"

// Professional Guided Tour Controller v3
// With robust collision detection to prevent tooltip blocking target
export default class extends Controller {
  static values = {
    autoStart: Boolean,
    completed: Boolean
  }

  // Tour steps with explicit positioning preferences
  // Each step lists preferred positions in order of preference
  steps = [
    {
      element: "[data-tour-target='welcome']",
      title: "👋 Welcome to RUPI!",
      content: "Let's take a quick tour of your personal finance dashboard. This will only take a minute!",
      positions: ["center"] // Centered modal, no target
    },
    {
      element: "[data-tour-target='accounts']",
      title: "📊 Your Accounts",
      content: "All your bank accounts, credit cards, loans, and investments in one place. Click any account to see its transactions.",
      positions: ["right", "bottom", "top"] // Sidebar is on left, prefer right
    },
    {
      element: "[data-tour-target='netWorth']",
      title: "💰 Net Worth",
      content: "Track your total wealth over time. Assets minus liabilities = your net worth.",
      positions: ["bottom", "right", "top"] // Net worth widget in middle, prefer below
    },
    {
      element: "[data-tour-target='uploadStatement']",
      title: "📄 Import Statements",
      content: "Upload bank statements from HDFC, ICICI, SBI, and 20+ Indian banks. We'll automatically categorize your transactions!",
      positions: ["bottom", "left", "right"] // Button at top, prefer below
    },
    {
      element: "[data-tour-target='aiChat']",
      title: "🤖 RUPI AI Assistant",
      content: "Ask questions in plain English! Try: 'How much did I spend last month?' or 'Show my top expenses'.",
      positions: ["left", "top", "bottom"] // Chat pane on right, prefer left
    },
    {
      element: "[data-tour-target='sidebar']",
      title: "🧭 Navigation",
      content: "Access Transactions, Reports, and Budgets from the sidebar. Everything you need is one click away!",
      positions: ["right", "bottom", "top"] // Sidebar on left, prefer right
    }
  ]

  currentStep = 0
  overlay = null
  ring = null
  tooltip = null
  styleElement = null

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
    modal.className = "tour-modal-overlay"
    modal.innerHTML = `
      <div class="tour-modal">
        <div class="tour-modal-icon">💡</div>
        <h3 class="tour-modal-title">Tour Available After Setup</h3>
        <p class="tour-modal-text">Load sample data or add an account first, then try the tour again!</p>
        <button class="tour-modal-btn" onclick="this.closest('.tour-modal-overlay').remove()">Got it</button>
      </div>
    `
    document.body.appendChild(modal)
  }

  injectStyles() {
    if (document.getElementById("rupi-tour-styles-v3")) return
    
    this.styleElement = document.createElement("style")
    this.styleElement.id = "rupi-tour-styles-v3"
    this.styleElement.textContent = `
      /* Overlay with SVG mask for spotlight cutout */
      .tour-overlay {
        position: fixed;
        inset: 0;
        z-index: 99990;
        pointer-events: auto;
      }
      
      .tour-overlay svg {
        width: 100%;
        height: 100%;
      }
      
      /* Spotlight highlight ring */
      .tour-spotlight-ring {
        position: fixed;
        z-index: 99995;
        border: 3px solid var(--color-success, #10b981);
        border-radius: 12px;
        box-shadow: 
          0 0 0 4px rgba(16, 185, 129, 0.3),
          0 0 30px rgba(16, 185, 129, 0.5);
        animation: tour-ring-pulse 2s ease-in-out infinite;
        pointer-events: none;
        transition: all 0.4s cubic-bezier(0.4, 0, 0.2, 1);
      }
      
      @keyframes tour-ring-pulse {
        0%, 100% { 
          box-shadow: 
            0 0 0 4px rgba(16, 185, 129, 0.3),
            0 0 30px rgba(16, 185, 129, 0.5);
        }
        50% { 
          box-shadow: 
            0 0 0 8px rgba(16, 185, 129, 0.2),
            0 0 50px rgba(16, 185, 129, 0.6);
        }
      }
      
      /* Tooltip - using app's design system */
      .tour-tooltip {
        position: fixed;
        z-index: 99999;
        width: 380px;
        max-width: calc(100vw - 40px);
        background: var(--color-container, #1f2937);
        border: 1px solid var(--color-border-primary, rgba(255,255,255,0.15));
        border-radius: 16px;
        padding: 24px;
        box-shadow: 
          0 25px 60px -12px rgba(0, 0, 0, 0.6),
          0 0 0 1px rgba(255, 255, 255, 0.05);
        animation: tour-tooltip-enter 0.35s cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      
      @keyframes tour-tooltip-enter {
        from { opacity: 0; transform: translateY(15px) scale(0.9); }
        to { opacity: 1; transform: translateY(0) scale(1); }
      }
      
      .tour-tooltip-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 14px;
      }
      
      .tour-tooltip-title {
        font-size: 18px;
        font-weight: 600;
        color: var(--color-text-primary, #ffffff);
      }
      
      .tour-tooltip-step {
        font-size: 12px;
        font-weight: 500;
        color: var(--color-text-secondary, rgba(255,255,255,0.7));
        background: var(--color-surface-inset, rgba(255,255,255,0.08));
        padding: 5px 12px;
        border-radius: 20px;
      }
      
      .tour-tooltip-content {
        font-size: 15px;
        color: var(--color-text-secondary, rgba(255,255,255,0.85));
        line-height: 1.65;
        margin-bottom: 22px;
      }
      
      .tour-tooltip-actions {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 16px;
      }
      
      .tour-btn {
        padding: 11px 22px;
        border-radius: 10px;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
        border: none;
      }
      
      .tour-btn-skip {
        background: transparent;
        color: var(--color-text-tertiary, rgba(255,255,255,0.5));
      }
      
      .tour-btn-skip:hover {
        color: var(--color-text-primary, #ffffff);
        background: var(--color-surface-hover, rgba(255,255,255,0.08));
      }
      
      .tour-btn-next {
        background: var(--color-success, #10b981);
        color: white;
        min-width: 110px;
      }
      
      .tour-btn-next:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(16, 185, 129, 0.45);
      }
      
      .tour-progress {
        display: flex;
        gap: 8px;
        justify-content: center;
        flex: 1;
      }
      
      .tour-progress-dot {
        width: 10px;
        height: 10px;
        border-radius: 50%;
        background: var(--color-border-primary, rgba(255,255,255,0.2));
        transition: all 0.3s;
      }
      
      .tour-progress-dot.active {
        background: var(--color-success, #10b981);
        transform: scale(1.3);
        box-shadow: 0 0 8px rgba(16, 185, 129, 0.5);
      }
      
      .tour-progress-dot.completed {
        background: var(--color-success, #10b981);
        opacity: 0.4;
      }
      
      /* Completion Modal - centered celebration */
      .tour-modal-overlay {
        position: fixed;
        inset: 0;
        z-index: 99999;
        background: rgba(0, 0, 0, 0.85);
        display: flex;
        align-items: center;
        justify-content: center;
        animation: tour-modal-fade 0.3s ease-out;
        padding: 20px;
      }
      
      @keyframes tour-modal-fade {
        from { opacity: 0; }
        to { opacity: 1; }
      }
      
      .tour-modal {
        background: var(--color-container, #1f2937);
        border: 1px solid var(--color-border-primary, rgba(255,255,255,0.1));
        border-radius: 24px;
        padding: 48px 40px;
        text-align: center;
        max-width: 420px;
        width: 100%;
        animation: tour-modal-enter 0.5s cubic-bezier(0.34, 1.56, 0.64, 1);
      }
      
      @keyframes tour-modal-enter {
        from { opacity: 0; transform: scale(0.7) translateY(30px); }
        to { opacity: 1; transform: scale(1) translateY(0); }
      }
      
      .tour-modal-icon {
        font-size: 72px;
        margin-bottom: 24px;
        display: block;
      }
      
      .tour-modal-title {
        font-size: 28px;
        font-weight: 700;
        color: var(--color-text-primary, #ffffff);
        margin-bottom: 16px;
      }
      
      .tour-modal-text {
        font-size: 16px;
        color: var(--color-text-secondary, rgba(255,255,255,0.7));
        line-height: 1.7;
        margin-bottom: 32px;
      }
      
      .tour-modal-btn {
        background: var(--color-success, #10b981);
        color: white;
        border: none;
        padding: 16px 48px;
        border-radius: 12px;
        font-size: 17px;
        font-weight: 600;
        cursor: pointer;
        transition: all 0.2s;
      }
      
      .tour-modal-btn:hover {
        transform: translateY(-3px);
        box-shadow: 0 10px 30px rgba(16, 185, 129, 0.5);
      }
    `
    document.head.appendChild(this.styleElement)
  }

  createOverlay() {
    this.overlay = document.createElement("div")
    this.overlay.className = "tour-overlay"
    this.overlay.innerHTML = `
      <svg>
        <defs>
          <mask id="tour-mask">
            <rect x="0" y="0" width="100%" height="100%" fill="white"/>
            <rect class="tour-mask-hole" x="0" y="0" width="0" height="0" rx="12" fill="black"/>
          </mask>
        </defs>
        <rect x="0" y="0" width="100%" height="100%" fill="rgba(0,0,0,0.85)" mask="url(#tour-mask)"/>
      </svg>
    `
    document.body.appendChild(this.overlay)
    
    // Create highlight ring
    this.ring = document.createElement("div")
    this.ring.className = "tour-spotlight-ring"
    document.body.appendChild(this.ring)
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
    
    if (!target || !this.isVisible(target)) {
      console.log(`[Tour] Skipping step ${this.currentStep + 1} - element not visible`)
      this.currentStep++
      return this.showStep()
    }

    // Scroll element into view first
    target.scrollIntoView({ behavior: 'smooth', block: 'center' })
    
    setTimeout(() => {
      this.updateSpotlight(target)
      this.renderTooltip(step, target)
    }, 350)
  }

  updateSpotlight(target) {
    const rect = target.getBoundingClientRect()
    const padding = 16
    
    // Update SVG mask hole
    const hole = this.overlay.querySelector('.tour-mask-hole')
    hole.setAttribute('x', rect.left - padding)
    hole.setAttribute('y', rect.top - padding)
    hole.setAttribute('width', rect.width + padding * 2)
    hole.setAttribute('height', rect.height + padding * 2)
    
    // Update highlight ring
    this.ring.style.left = `${rect.left - padding}px`
    this.ring.style.top = `${rect.top - padding}px`
    this.ring.style.width = `${rect.width + padding * 2}px`
    this.ring.style.height = `${rect.height + padding * 2}px`
  }

  renderTooltip(step, target) {
    const totalSteps = this.steps.length
    const progressDots = this.steps.map((_, i) => {
      let dotClass = 'tour-progress-dot'
      if (i < this.currentStep) dotClass += ' completed'
      if (i === this.currentStep) dotClass += ' active'
      return `<div class="${dotClass}"></div>`
    }).join('')
    
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
    
    // Position tooltip using collision-free algorithm
    this.positionTooltipWithCollisionDetection(target, step.positions)
    
    window.nextRupiTourStep = () => this.next()
    window.endRupiTour = () => this.finish()
  }

  /**
   * Position tooltip trying each preferred position until one doesn't overlap
   */
  positionTooltipWithCollisionDetection(target, positions) {
    const targetRect = target.getBoundingClientRect()
    const padding = 20 // Padding from viewport edges
    const gap = 24 // Gap between tooltip and target
    const spotlightPadding = 16 // Must match spotlight padding
    
    // Get tooltip dimensions
    const tooltipRect = this.tooltip.getBoundingClientRect()
    const tooltipWidth = tooltipRect.width || 380
    const tooltipHeight = tooltipRect.height || 200
    
    // Expanded target rect (including spotlight padding)
    const expandedTarget = {
      left: targetRect.left - spotlightPadding - gap,
      right: targetRect.right + spotlightPadding + gap,
      top: targetRect.top - spotlightPadding - gap,
      bottom: targetRect.bottom + spotlightPadding + gap
    }

    // Try each position in order
    for (const position of positions) {
      const coords = this.calculatePosition(position, targetRect, tooltipWidth, tooltipHeight, gap, padding)
      
      if (coords) {
        // Check if this position overlaps with the expanded target
        const tooltipBounds = {
          left: coords.left,
          right: coords.left + tooltipWidth,
          top: coords.top,
          bottom: coords.top + tooltipHeight
        }
        
        const overlaps = this.rectsOverlap(tooltipBounds, {
          left: targetRect.left - spotlightPadding,
          right: targetRect.right + spotlightPadding,
          top: targetRect.top - spotlightPadding,
          bottom: targetRect.bottom + spotlightPadding
        })
        
        if (!overlaps) {
          // Found a good position!
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

  calculatePosition(position, targetRect, tooltipWidth, tooltipHeight, gap, padding) {
    let left, top
    
    if (position === 'center') {
      return {
        left: (window.innerWidth - tooltipWidth) / 2,
        top: (window.innerHeight - tooltipHeight) / 2
      }
    }
    
    if (position === 'right') {
      left = targetRect.right + gap + 16 // Extra gap for spotlight
      top = targetRect.top + (targetRect.height / 2) - (tooltipHeight / 2)
    } else if (position === 'left') {
      left = targetRect.left - tooltipWidth - gap - 16
      top = targetRect.top + (targetRect.height / 2) - (tooltipHeight / 2)
    } else if (position === 'bottom') {
      left = targetRect.left + (targetRect.width / 2) - (tooltipWidth / 2)
      top = targetRect.bottom + gap + 16
    } else if (position === 'top') {
      left = targetRect.left + (targetRect.width / 2) - (tooltipWidth / 2)
      top = targetRect.top - tooltipHeight - gap - 16
    }
    
    // Clamp to viewport
    left = Math.max(padding, Math.min(left, window.innerWidth - tooltipWidth - padding))
    top = Math.max(padding, Math.min(top, window.innerHeight - tooltipHeight - padding))
    
    // Check if tooltip would be off-screen
    if (left < padding || left + tooltipWidth > window.innerWidth - padding ||
        top < padding || top + tooltipHeight > window.innerHeight - padding) {
      return null // Position not viable
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
    modal.className = "tour-modal-overlay"
    modal.innerHTML = `
      <div class="tour-modal">
        <div class="tour-modal-icon">🎉</div>
        <h3 class="tour-modal-title">You're All Set!</h3>
        <p class="tour-modal-text">You now know the essentials of RUPI. Start by uploading a bank statement or exploring the AI assistant.<br><br>Need help anytime? Click <strong>"Help & FAQ"</strong> from the user menu.</p>
        <button class="tour-modal-btn" onclick="this.closest('.tour-modal-overlay').remove()">Let's Go!</button>
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
