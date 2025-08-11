// Azure Alert Deduplication Presentation JavaScript
// Handles slide navigation and presentation functionality

class Presentation {
    constructor() {
        this.currentSlide = 0;
        this.slides = document.querySelectorAll('.slide');
        this.totalSlides = this.slides.length;
        
        this.initializeElements();
        this.setupEventListeners();
        this.showSlide(0);
        this.updateCounter();
    }
    
    initializeElements() {
        // Get navigation elements
        this.prevButton = document.getElementById('prevBtn');
        this.nextButton = document.getElementById('nextBtn');
        this.slideCounter = document.getElementById('slideCounter');
        
        // Add slide numbers to each slide for reference
        this.slides.forEach((slide, index) => {
            slide.setAttribute('data-slide-number', index + 1);
        });
        
        // Add Microsoft logo to each slide
        this.addMicrosoftLogo();
    }
    
    addMicrosoftLogo() {
        // Microsoft logo SVG (simplified version)
        const microsoftLogoSVG = `
            <svg class="microsoft-logo" viewBox="0 0 87 18" xmlns="http://www.w3.org/2000/svg">
                <path d="M0 0h8.5v8.5H0V0zm9.8 0h8.5v8.5H9.8V0zM0 9.8h8.5v8.5H0V9.8zm9.8 0h8.5v8.5H9.8V9.8z" fill="#737373"/>
                <path d="M26.7 4.8c0-1.4.7-2.6 2.5-2.6 1.5 0 2.3.9 2.3 2.6v8.7h2.4V4.3c0-2.8-1.4-4.6-4.4-4.6-1.8 0-3.1.8-3.7 2.1h-.1V.3h-2.4v13.2h2.4V4.8z" fill="#737373"/>
                <path d="M35.5.3h2.4v13.2h-2.4z" fill="#737373"/>
                <path d="M48.5 8.2c-.3-2.1-1.8-3.9-4.4-3.9-3 0-5 2.3-5 5.2s2 5.2 5.2 5.2c2.4 0 4-1.4 4.6-3.6h-2.5c-.4 1-1.3 1.5-2.1 1.5-1.6 0-2.6-1.2-2.7-2.9h7-.1zm-6.9-1.1c.2-1.5 1.2-2.4 2.5-2.4 1.4 0 2.3 1 2.4 2.4h-4.9z" fill="#737373"/>
                <path d="M51.5 4.8c0-1.4.7-2.6 2.4-2.6.8 0 1.5.4 1.9 1h.1V.3h2.4v13.2h-2.4V11h-.1c-.4.6-1.1 1.7-2.7 1.7-2.2 0-3.6-1.8-3.6-4.5zm4.4 2.7V6.2c-.2-.8-.9-1.4-1.7-1.4-1.2 0-2 1-2 2.7s.8 2.7 2 2.7c.8 0 1.5-.6 1.7-1.7z" fill="#737373"/>
                <path d="M66.8 8.2c-.3-2.1-1.8-3.9-4.4-3.9-3 0-5 2.3-5 5.2s2 5.2 5.2 5.2c2.4 0 4-1.4 4.6-3.6h-2.5c-.4 1-1.3 1.5-2.1 1.5-1.6 0-2.6-1.2-2.7-2.9h7-.1zm-6.9-1.1c.2-1.5 1.2-2.4 2.5-2.4 1.4 0 2.3 1 2.4 2.4h-4.9z" fill="#737373"/>
                <path d="M69.8 4.8c0-1.4.7-2.6 2.4-2.6.8 0 1.5.4 1.9 1h.1V.3h2.4v13.2h-2.4V11h-.1c-.4.6-1.1 1.7-2.7 1.7-2.2 0-3.6-1.8-3.6-4.5zm4.4 2.7V6.2c-.2-.8-.9-1.4-1.7-1.4-1.2 0-2 1-2 2.7s.8 2.7 2 2.7c.8 0 1.5-.6 1.7-1.7z" fill="#737373"/>
                <path d="M87 4.8c0-1.4.7-2.6 2.4-2.6.8 0 1.5.4 1.9 1h.1V.3h2.4v13.2h-2.4V11h-.1c-.4.6-1.1 1.7-2.7 1.7-2.2 0-3.6-1.8-3.6-4.5zm4.4 2.7V6.2c-.2-.8-.9-1.4-1.7-1.4-1.2 0-2 1-2 2.7s.8 2.7 2 2.7c.8 0 1.5-.6 1.7-1.7z" fill="#737373"/>
            </svg>
        `;
        
        // Add logo to each slide
        this.slides.forEach((slide) => {
            const logoContainer = document.createElement('div');
            logoContainer.innerHTML = microsoftLogoSVG;
            slide.appendChild(logoContainer.firstElementChild);
        });
    }
    
    setupEventListeners() {
        // Navigation button events
        this.prevButton.addEventListener('click', () => this.previousSlide());
        this.nextButton.addEventListener('click', () => this.nextSlide());
        
        // Keyboard navigation
        document.addEventListener('keydown', (event) => {
            switch(event.key) {
                case 'ArrowLeft':
                case 'ArrowUp':
                    event.preventDefault();
                    this.previousSlide();
                    break;
                case 'ArrowRight':
                case 'ArrowDown':
                case ' ': // Spacebar
                    event.preventDefault();
                    this.nextSlide();
                    break;
                case 'Home':
                    event.preventDefault();
                    this.goToSlide(0);
                    break;
                case 'End':
                    event.preventDefault();
                    this.goToSlide(this.totalSlides - 1);
                    break;
                case 'Escape':
                    // Could be used for fullscreen exit
                    break;
            }
        });
        
        // Touch/swipe support for mobile
        let touchStartX = 0;
        let touchStartY = 0;
        
        document.addEventListener('touchstart', (event) => {
            touchStartX = event.touches[0].clientX;
            touchStartY = event.touches[0].clientY;
        });
        
        document.addEventListener('touchend', (event) => {
            if (!touchStartX || !touchStartY) return;
            
            const touchEndX = event.changedTouches[0].clientX;
            const touchEndY = event.changedTouches[0].clientY;
            
            const deltaX = touchStartX - touchEndX;
            const deltaY = touchStartY - touchEndY;
            
            // Ensure horizontal swipe is more significant than vertical
            if (Math.abs(deltaX) > Math.abs(deltaY) && Math.abs(deltaX) > 50) {
                if (deltaX > 0) {
                    // Swipe left - next slide
                    this.nextSlide();
                } else {
                    // Swipe right - previous slide
                    this.previousSlide();
                }
            }
            
            touchStartX = 0;
            touchStartY = 0;
        });
        
        // Click navigation on slides (optional)
        this.slides.forEach((slide) => {
            slide.addEventListener('click', (event) => {
                // Only advance if clicking on the slide content, not interactive elements
                if (event.target === slide || slide.contains(event.target)) {
                    const rect = slide.getBoundingClientRect();
                    const clickX = event.clientX - rect.left;
                    const slideWidth = rect.width;
                    
                    // Click on right half advances, left half goes back
                    if (clickX > slideWidth / 2) {
                        this.nextSlide();
                    } else {
                        this.previousSlide();
                    }
                }
            });
        });
    }
    
    showSlide(slideIndex) {
        // Hide all slides
        this.slides.forEach((slide, index) => {
            slide.classList.remove('active');
            if (index === slideIndex) {
                slide.classList.add('active');
            }
        });
        
        this.currentSlide = slideIndex;
        this.updateNavigation();
        this.updateCounter();
        
        // Trigger any slide-specific animations or effects
        this.onSlideChange(slideIndex);
    }
    
    nextSlide() {
        if (this.currentSlide < this.totalSlides - 1) {
            this.showSlide(this.currentSlide + 1);
        }
    }
    
    previousSlide() {
        if (this.currentSlide > 0) {
            this.showSlide(this.currentSlide - 1);
        }
    }
    
    goToSlide(slideIndex) {
        if (slideIndex >= 0 && slideIndex < this.totalSlides) {
            this.showSlide(slideIndex);
        }
    }
    
    updateNavigation() {
        // Update button states
        this.prevButton.disabled = (this.currentSlide === 0);
        this.nextButton.disabled = (this.currentSlide === this.totalSlides - 1);
    }
    
    updateCounter() {
        this.slideCounter.textContent = `${this.currentSlide + 1} / ${this.totalSlides}`;
    }
    
    onSlideChange(slideIndex) {
        // Add any slide-specific functionality here
        
        // Example: Add fade-in animation to slide content
        const currentSlideElement = this.slides[slideIndex];
        const slideContent = currentSlideElement.querySelector('.slide-content');
        
        if (slideContent) {
            slideContent.style.opacity = '0';
            slideContent.style.transform = 'translateY(20px)';
            
            // Trigger animation
            setTimeout(() => {
                slideContent.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
                slideContent.style.opacity = '1';
                slideContent.style.transform = 'translateY(0)';
            }, 50);
        }
        
        // Update page title to include current slide
        const slideTitle = currentSlideElement.querySelector('h1, h2');
        if (slideTitle) {
            document.title = `Azure Alert Deduplication - ${slideTitle.textContent}`;
        }
        
        // Log slide change for analytics (if needed)
        console.log(`Slide changed to: ${slideIndex + 1} / ${this.totalSlides}`);
    }
    
    // Utility methods for programmatic control
    isFirstSlide() {
        return this.currentSlide === 0;
    }
    
    isLastSlide() {
        return this.currentSlide === this.totalSlides - 1;
    }
    
    getCurrentSlideNumber() {
        return this.currentSlide + 1;
    }
    
    getTotalSlides() {
        return this.totalSlides;
    }
    
    // Method to enter fullscreen mode
    enterFullscreen() {
        const element = document.documentElement;
        if (element.requestFullscreen) {
            element.requestFullscreen();
        } else if (element.mozRequestFullScreen) {
            element.mozRequestFullScreen();
        } else if (element.webkitRequestFullscreen) {
            element.webkitRequestFullscreen();
        } else if (element.msRequestFullscreen) {
            element.msRequestFullscreen();
        }
    }
    
    // Method to exit fullscreen mode
    exitFullscreen() {
        if (document.exitFullscreen) {
            document.exitFullscreen();
        } else if (document.mozCancelFullScreen) {
            document.mozCancelFullScreen();
        } else if (document.webkitExitFullscreen) {
            document.webkitExitFullscreen();
        } else if (document.msExitFullscreen) {
            document.msExitFullscreen();
        }
    }
}

// Presentation utilities
class PresentationUtilities {
    static formatTime(date = new Date()) {
        return date.toLocaleString('en-US', {
            year: 'numeric',
            month: 'long',
            day: 'numeric',
            hour: '2-digit',
            minute: '2-digit'
        });
    }
    
    static highlightCodeBlocks() {
        // Simple syntax highlighting for code blocks
        const codeBlocks = document.querySelectorAll('code');
        codeBlocks.forEach(block => {
            if (block.textContent.includes('powershell') || block.textContent.includes('ps1')) {
                block.classList.add('powershell');
            } else if (block.textContent.includes('bicep')) {
                block.classList.add('bicep');
            } else if (block.textContent.includes('json')) {
                block.classList.add('json');
            }
        });
    }
    
    static addInteractiveElements() {
        // Add click-to-copy functionality to code blocks
        const codeBlocks = document.querySelectorAll('.code-block code, .code-snippet');
        codeBlocks.forEach(block => {
            block.style.cursor = 'pointer';
            block.title = 'Click to copy';
            
            block.addEventListener('click', () => {
                navigator.clipboard.writeText(block.textContent).then(() => {
                    // Visual feedback
                    const originalText = block.textContent;
                    const originalBg = block.style.backgroundColor;
                    
                    block.style.backgroundColor = '#4a4a4a';
                    
                    setTimeout(() => {
                        block.style.backgroundColor = originalBg;
                    }, 200);
                    
                    console.log('Code copied to clipboard');
                });
            });
        });
    }
    
    static setupPrintMode() {
        // Add print-friendly styles when printing
        window.addEventListener('beforeprint', () => {
            document.body.classList.add('print-mode');
            
            // Show all slides for printing
            const slides = document.querySelectorAll('.slide');
            slides.forEach(slide => {
                slide.style.display = 'block';
                slide.style.pageBreakAfter = 'always';
            });
        });
        
        window.addEventListener('afterprint', () => {
            document.body.classList.remove('print-mode');
            
            // Restore normal slide display
            const slides = document.querySelectorAll('.slide');
            slides.forEach((slide, index) => {
                if (index === presentation.currentSlide) {
                    slide.style.display = 'block';
                } else {
                    slide.style.display = 'none';
                }
                slide.style.pageBreakAfter = 'auto';
            });
        });
    }
}

// Initialize presentation when DOM is loaded
let presentation;

document.addEventListener('DOMContentLoaded', () => {
    presentation = new Presentation();
    
    // Add current date to title slide if present
    const dateElement = document.querySelector('.date');
    if (dateElement && !dateElement.textContent.trim()) {
        dateElement.textContent = PresentationUtilities.formatTime();
    }
    
    // Setup additional utilities
    PresentationUtilities.highlightCodeBlocks();
    PresentationUtilities.addInteractiveElements();
    PresentationUtilities.setupPrintMode();
    
    // Add keyboard shortcut help (optional)
    console.log('Presentation loaded. Keyboard shortcuts:');
    console.log('← ↑ : Previous slide');
    console.log('→ ↓ Space: Next slide');
    console.log('Home: First slide');
    console.log('End: Last slide');
    console.log('F11: Fullscreen (browser dependent)');
});

// Global functions for external control
window.presentationAPI = {
    nextSlide: () => presentation?.nextSlide(),
    previousSlide: () => presentation?.previousSlide(),
    goToSlide: (index) => presentation?.goToSlide(index),
    getCurrentSlide: () => presentation?.getCurrentSlideNumber(),
    getTotalSlides: () => presentation?.getTotalSlides(),
    enterFullscreen: () => presentation?.enterFullscreen(),
    exitFullscreen: () => presentation?.exitFullscreen()
};
