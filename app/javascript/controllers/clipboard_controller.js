import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["source", "iconDefault", "iconSuccess", "icon", "text"];
  static values = { text: String };

  copy(event) {
    event.preventDefault();
    
    // Use the text value if provided, otherwise use source target content
    const textToCopy = this.hasTextValue 
      ? this.textValue 
      : (this.hasSourceTarget ? this.sourceTarget.textContent : null);
    
    if (textToCopy) {
      navigator.clipboard
        .writeText(textToCopy)
        .then(() => {
          this.showSuccess();
        })
        .catch((error) => {
          console.error("Failed to copy text: ", error);
        });
    }
  }

  showSuccess() {
    // Try the new icon/text targets first
    if (this.hasIconTarget && this.hasTextTarget) {
      const originalText = this.textTarget.textContent;
      this.textTarget.textContent = "Copied!";
      this.iconTarget.classList.add("text-green-500");
      
      setTimeout(() => {
        this.textTarget.textContent = originalText;
        this.iconTarget.classList.remove("text-green-500");
      }, 2000);
      return;
    }
    
    // Fallback to the original iconDefault/iconSuccess pattern
    if (this.hasIconDefaultTarget && this.hasIconSuccessTarget) {
      this.iconDefaultTarget.classList.add("hidden");
      this.iconSuccessTarget.classList.remove("hidden");
      setTimeout(() => {
        this.iconDefaultTarget.classList.remove("hidden");
        this.iconSuccessTarget.classList.add("hidden");
      }, 3000);
    }
  }
}
