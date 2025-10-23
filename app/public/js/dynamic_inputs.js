document.addEventListener('DOMContentLoaded', function() {
  document.querySelectorAll('.add-input').forEach(button => {
    button.addEventListener('click', function() {
      const questionId = this.getAttribute('data-question-id');
      const container = document.getElementById(`${questionId}_container`);
      const inputs = container.querySelectorAll('.text-input-row');
      const index = inputs.length + 1;
      const newRow = document.createElement('div');
      newRow.className = 'text-input-row';
      newRow.style.display = 'flex';
      newRow.style.alignItems = 'center';
      newRow.style.gap = '10px';
      newRow.style.marginBottom = '10px';
      newRow.innerHTML = `
        <input type="text" name="${questionId}[]" id="${questionId}_${index}_ANSWER" size="50" />
        <button type="button" class="add-input" data-question-id="${questionId}">+</button>
        <button type="button" class="remove-input" data-index="${index - 1}">−</button>
      `;
      container.insertBefore(newRow, this.parentElement);
    });
  });

  document.addEventListener('click', function(event) {
    if (event.target.classList.contains('remove-input')) {
      const container = event.target.closest('.inputtype').querySelector('div[id$="_container"]');
      if (container.querySelectorAll('.text-input-row').length > 1) {
        event.target.parentElement.remove();
      }
    }
  });
});