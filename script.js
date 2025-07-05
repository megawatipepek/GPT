document.getElementById('surpriseBtn').addEventListener('click', function() {
  const message = document.getElementById('hiddenMessage');
  message.classList.remove('hidden');
  
  // Animasi tambahan
  document.body.style.backgroundColor = "#ffe0f0";
  this.textContent = "I LOVE YOU! 💘";
});
