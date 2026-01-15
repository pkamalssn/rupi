import { Controller } from "@hotwired/stimulus"

// Guided Tour Controller
// Provides a step-by-step walkthrough of RUPI features
export default class extends Controller {
  static values = {
    autoStart: Boolean,
    completed: Boolean
  }

  static targets = ["overlay"]

  // Tour steps configuration
  steps = [
    {
      element: "[data-tour-target='sidebar']",
      title: "Navigation",
      content: "Access your Dashboard, Transactions, Reports, and Budgets from the sidebar.",
      position: "right"
    },
    {
      element: "[data-tour-target='netWorth']",
      title: "Net Worth",
      content: "Your total net worth is calculated from all assets minus liabilities. Track your wealth growth over time.",
      position: "bottom"
    },
    {
      element: "[data-tour-target='accounts']",
      title: "Your Accounts",
      content: "All your bank accounts, credit cards, loans, and investments in one place. Click any account to see its transactions.",
      position: "right"
    },
    {
      element: "[data-tour-target='uploadStatement']",
      title: "Import Statements",
      content: "Upload bank statements from HDFC, ICICI, SBI, and 20+ Indian banks. We'll automatically categorize your transactions.",
      position: "bottom"
    },
    {
      element: "[data-tour-target='aiChat']",
      title: "RUPI AI Assistant",
      content: "Ask questions about your finances. Try: 'How did I spend last month?' or 'What are my biggest expenses?'",
      position: "left"
    },
    {
      element: "[data-tour-target='reports']",
      title: "Reports & Insights",
      content: "View detailed spending analysis, trends, and category breakdowns to understand your financial habits.",
      position: "right"
    },
    {
      element: "[data-tour-target='budgets']",
      title: "Budget Management",
      content: "Set monthly budgets for different categories and track your progress throughout the month.",
      position: "right"
    }
  ]

  currentStep = 0
  overlay = null
  tooltip = null

  connect() {
    if (this.autoStartValue && !this.completedValue) {
      // Small delay to let page render
      setTimeout(() => this.start(), 500)
    }
  }

  start() {
    // Check if at least one tour element exists
    const hasElements = this.steps.some(step => document.querySelector(step.element))
    
    if (!hasElements) {
      // Show a message that tour is available after adding accounts
      this.showNoElementsMessage()
      return
    }
    
    this.currentStep = 0
    this.createOverlay()
    this.showStep()
  }

  showNoElementsMessage() {
    // Create a temporary notification
    const notification = document.createElement("div")
    notification.className = "fixed top-4 right-4 z-50 bg-container shadow-border-xs rounded-lg p-4 max-w-sm animate-in slide-in-from-top"
    notification.innerHTML = `
      <div class="flex items-start gap-3">
        <span class="text-lg">💡</span>
        <div>
          <p class="font-medium text-primary text-sm">Tour Available After Setup</p>
          <p class="text-secondary text-sm mt-1">Load sample data or add an account first, then try the tour again!</p>
        </div>
        <button onclick="this.parentElement.parentElement.remove()" class="text-secondary hover:text-primary ml-2">✕</button>
      </div>
    `
    document.body.appendChild(notification)
    
    // Auto-remove after 5 seconds
    setTimeout(() => notification.remove(), 5000)
  }

  createOverlay() {
    // Create overlay
    this.overlay = document.createElement("div")
    this.overlay.className = "tour-overlay"
    this.overlay.innerHTML = `
      <div class="tour-overlay-bg"></div>
    `
    document.body.appendChild(this.overlay)

    // Create tooltip
    this.tooltip = document.createElement("div")
    this.tooltip.className = "tour-tooltip"
    document.body.appendChild(this.tooltip)

    // Add styles if not already present
    if (!document.getElementById("tour-styles")) {
      const styles = document.createElement("style")
      styles.id = "tour-styles"
      styles.textContent = `
        .tour-overlay-bg {
          position: fixed;
          inset: 0;
          background: rgba(0, 0, 0, 0.6);
          z-index: 9998;
        }
        
        .tour-highlight {
          position: relative;
          z-index: 9999 !important;
          box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.6);
          border-radius: 8px;
        }
        
        .tour-tooltip {
          position: fixed;
          z-index: 10000;
          max-width: 320px;
          background: var(--color-container);
          border: 1px solid var(--color-border-primary);
          border-radius: 12px;
          padding: 20px;
          box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
        }
        
        .tour-tooltip-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 12px;
        }
        
        .tour-tooltip-title {
          font-size: 16px;
          font-weight: 600;
          color: var(--color-text-primary);
        }
        
        .tour-tooltip-step {
          font-size: 12px;
          color: var(--color-text-tertiary);
        }
        
        .tour-tooltip-content {
          font-size: 14px;
          color: var(--color-text-secondary);
          line-height: 1.5;
          margin-bottom: 16px;
        }
        
        .tour-tooltip-actions {
          display: flex;
          justify-content: space-between;
          align-items: center;
        }
        
        .tour-btn {
          padding: 8px 16px;
          border-radius: 8px;
          font-size: 14px;
          font-weight: 500;
          cursor: pointer;
          transition: all 0.15s;
        }
        
        .tour-btn-skip {
          background: transparent;
          border: none;
          color: var(--color-text-secondary);
        }
        
        .tour-btn-skip:hover {
          color: var(--color-text-primary);
        }
        
        .tour-btn-next {
          background: var(--color-success);
          border: none;
          color: white;
        }
        
        .tour-btn-next:hover {
          opacity: 0.9;
        }
        
        .tour-progress {
          display: flex;
          gap: 4px;
        }
        
        .tour-progress-dot {
          width: 6px;
          height: 6px;
          border-radius: 50%;
          background: var(--color-border-primary);
        }
        
        .tour-progress-dot.active {
          background: var(--color-success);
        }
      `
      document.head.appendChild(styles)
    }
  }

  showStep() {
    const step = this.steps[this.currentStep]
    if (!step) return this.finish()

    // Find target element
    const target = document.querySelector(step.element)
    
    // If element not found, skip to next step
    if (!target) {
      this.currentStep++
      return this.showStep()
    }

    // Highlight element
    this.clearHighlight()
    target.classList.add("tour-highlight")

    // Position tooltip
    const rect = target.getBoundingClientRect()
    this.positionTooltip(rect, step.position)

    // Render tooltip content
    this.tooltip.innerHTML = `
      <div class="tour-tooltip-header">
        <span class="tour-tooltip-title">${step.title}</span>
        <span class="tour-tooltip-step">${this.currentStep + 1} of ${this.steps.length}</span>
      </div>
      <p class="tour-tooltip-content">${step.content}</p>
      <div class="tour-tooltip-actions">
        <button class="tour-btn tour-btn-skip" data-action="tour#skip">Skip Tour</button>
        <div class="tour-progress">
          ${this.steps.map((_, i) => `<div class="tour-progress-dot ${i <= this.currentStep ? 'active' : ''}"></div>`).join('')}
        </div>
        <button class="tour-btn tour-btn-next" data-action="tour#next">
          ${this.currentStep === this.steps.length - 1 ? 'Finish' : 'Next'}
        </button>
      </div>
    `

    // Scroll element into view
    target.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }

  positionTooltip(rect, position) {
    const tooltip = this.tooltip
    const padding = 16

    switch (position) {
      case "right":
        tooltip.style.left = `${rect.right + padding}px`
        tooltip.style.top = `${rect.top}px`
        break
      case "left":
        tooltip.style.left = `${rect.left - tooltip.offsetWidth - padding}px`
        tooltip.style.top = `${rect.top}px`
        break
      case "bottom":
        tooltip.style.left = `${rect.left}px`
        tooltip.style.top = `${rect.bottom + padding}px`
        break
      case "top":
        tooltip.style.left = `${rect.left}px`
        tooltip.style.top = `${rect.top - tooltip.offsetHeight - padding}px`
        break
    }

    // Keep within viewport
    requestAnimationFrame(() => {
      const tooltipRect = tooltip.getBoundingClientRect()
      if (tooltipRect.right > window.innerWidth) {
        tooltip.style.left = `${window.innerWidth - tooltipRect.width - padding}px`
      }
      if (tooltipRect.left < 0) {
        tooltip.style.left = `${padding}px`
      }
    })
  }

  next() {
    this.currentStep++
    if (this.currentStep >= this.steps.length) {
      this.finish()
    } else {
      this.showStep()
    }
  }

  skip() {
    this.finish()
  }

  finish() {
    this.clearHighlight()
    if (this.overlay) {
      this.overlay.remove()
      this.overlay = null
    }
    if (this.tooltip) {
      this.tooltip.remove()
      this.tooltip = null
    }

    // Mark tour as completed
    this.saveTourCompleted()
  }

  clearHighlight() {
    document.querySelectorAll(".tour-highlight").forEach(el => {
      el.classList.remove("tour-highlight")
    })
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
