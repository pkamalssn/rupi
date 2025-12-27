import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "fileName", "uploadArea", "uploadText", "dropzone", "filename"]

  connect() {
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("change", this.fileSelected.bind(this))
    }
    
    // Find the form element
    this.form = this.element.closest("form")
    if (this.form) {
      this.form.addEventListener("turbo:submit-start", this.formSubmitting.bind(this))
    }
  }

  disconnect() {
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("change", this.fileSelected.bind(this))
    }
    
    if (this.form) {
      this.form.removeEventListener("turbo:submit-start", this.formSubmitting.bind(this))
    }
  }

  triggerFileInput() {
    if (this.hasInputTarget) {
      this.inputTarget.click()
    }
  }

  // Alias for openFilePicker
  openFilePicker(event) {
    event.preventDefault()
    this.triggerFileInput()
  }

  fileSelected() {
    if (this.hasInputTarget && this.inputTarget.files.length > 0) {
      const fileName = this.inputTarget.files[0].name
      
      // Support both fileName and filename targets
      if (this.hasFileNameTarget) {
        const fileNameText = this.fileNameTarget.querySelector('p')
        if (fileNameText) {
          fileNameText.textContent = fileName
        }
        this.fileNameTarget.classList.remove("hidden")
      }
      
      if (this.hasFilenameTarget) {
        this.filenameTarget.textContent = `Selected: ${fileName}`
        this.filenameTarget.classList.remove("hidden")
      }
      
      if (this.hasUploadTextTarget) {
        this.uploadTextTarget.classList.add("hidden")
      }
    }
  }

  // Drag and drop handlers
  dragover(event) {
    event.preventDefault()
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.add("border-blue-500", "bg-blue-50")
    }
  }

  dragenter(event) {
    event.preventDefault()
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.add("border-blue-500", "bg-blue-50")
    }
  }

  dragleave(event) {
    event.preventDefault()
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.remove("border-blue-500", "bg-blue-50")
    }
  }

  drop(event) {
    event.preventDefault()
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.remove("border-blue-500", "bg-blue-50")
    }
    
    const files = event.dataTransfer.files
    if (files.length > 0 && this.hasInputTarget) {
      this.inputTarget.files = files
      this.fileSelected()
    }
  }
  
  formSubmitting() {
    if (this.hasFileNameTarget && this.hasInputTarget && this.inputTarget.files.length > 0) {
      const fileNameText = this.fileNameTarget.querySelector('p')
      if (fileNameText) {
        fileNameText.textContent = `Uploading ${this.inputTarget.files[0].name}...`
      }
      
      // Change the icon to a loader
      const iconContainer = this.fileNameTarget.querySelector('.lucide-file-text')
      if (iconContainer) {
        iconContainer.classList.add('animate-pulse')
      }
    }
    
    if (this.hasFilenameTarget && this.hasInputTarget && this.inputTarget.files.length > 0) {
      this.filenameTarget.textContent = `Uploading ${this.inputTarget.files[0].name}...`
    }
    
    if (this.hasUploadAreaTarget) {
      this.uploadAreaTarget.classList.add("opacity-70")
    }
    
    if (this.hasDropzoneTarget) {
      this.dropzoneTarget.classList.add("opacity-70")
    }
  }
} 